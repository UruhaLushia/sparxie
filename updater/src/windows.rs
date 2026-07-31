use std::ffi::{OsStr, OsString};
use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::windows::ffi::OsStrExt;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use windows_sys::Win32::Foundation::{CloseHandle, ERROR_INVALID_PARAMETER, HANDLE, WAIT_FAILED};
use windows_sys::Win32::System::Threading::{
    CREATE_NO_WINDOW, CreateProcessW, GetExitCodeProcess, INFINITE, OpenProcess,
    PROCESS_INFORMATION, PROCESS_SYNCHRONIZE, STARTUPINFOW, WaitForSingleObject,
};
use zip::ZipArchive;

use crate::common::{mark_ready, parse_number, parse_sha256, verify_sha256};

#[derive(Clone, Copy)]
enum PackageKind {
    Installer,
    Portable,
}

impl PackageKind {
    fn from_path(path: &Path) -> Result<Self> {
        let extension = path.extension().and_then(OsStr::to_str).unwrap_or_default();
        if extension.eq_ignore_ascii_case("exe") {
            return Ok(Self::Installer);
        }
        if extension.eq_ignore_ascii_case("zip") {
            return Ok(Self::Portable);
        }
        bail!("unsupported Windows update package")
    }
}

pub fn run() -> Result<()> {
    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    if args.len() != 5 {
        bail!("invalid updater arguments");
    }
    let package = PathBuf::from(&args[0]);
    let app = PathBuf::from(&args[1]);
    let app_pid = parse_number::<u32>(&args[2], "app pid")?;
    let work_dir = PathBuf::from(&args[3]);
    let expected_sha256 = parse_sha256(&args[4])?;
    let kind = PackageKind::from_path(&package)?;
    validate_paths(&package, &app, &work_dir, kind)?;
    mark_ready(&work_dir)?;

    let install_result = install(&package, &app, app_pid, &work_dir, &expected_sha256, kind);
    let _ = remove_path(&package);
    let launch_result = launch(&app);
    install_result.and(launch_result)
}

fn install(
    package: &Path,
    app: &Path,
    app_pid: u32,
    work_dir: &Path,
    expected_sha256: &str,
    kind: PackageKind,
) -> Result<()> {
    wait_for_exit(app_pid)?;
    verify_sha256(package, expected_sha256)?;
    match kind {
        PackageKind::Installer => install_setup(package),
        PackageKind::Portable => install_portable(package, app, work_dir),
    }
}

fn install_setup(installer: &Path) -> Result<()> {
    let exit_code = create_process(
        installer,
        &[
            "/SP-",
            "/VERYSILENT",
            "/SUPPRESSMSGBOXES",
            "/NORESTART",
            "/CLOSEAPPLICATIONS",
        ],
        true,
    )?
    .context("Windows installer did not return an exit code")?;
    if exit_code != 0 {
        bail!("Windows installer exited with code {exit_code}");
    }
    Ok(())
}

fn install_portable(package: &Path, app: &Path, work_dir: &Path) -> Result<()> {
    let target = app
        .parent()
        .context("portable app has no parent directory")?;
    if !target.join(".portable").is_file() {
        bail!("current application is not portable");
    }

    let stage = sibling_work_path(target, work_dir, "update")?;
    let backup = sibling_work_path(target, work_dir, "backup")?;
    ensure_absent(&stage)?;
    ensure_absent(&backup)?;

    fs::create_dir(&stage).context("create portable update directory")?;
    if let Err(error) = extract_zip(package, &stage).and_then(|()| verify_portable_bundle(&stage)) {
        let _ = remove_path(&stage);
        return Err(error);
    }

    let user_data = target.join("userdata");
    let has_user_data = match fs::symlink_metadata(&user_data) {
        Ok(_) => true,
        Err(error) if error.kind() == io::ErrorKind::NotFound => false,
        Err(error) => return Err(error).context("inspect portable user data"),
    };

    fs::rename(target, &backup).context("move current portable app to backup")?;
    if let Err(error) = fs::rename(&stage, target) {
        fs::rename(&backup, target).context("restore current portable app")?;
        return Err(error).context("activate portable update");
    }

    if has_user_data
        && let Err(error) = fs::rename(backup.join("userdata"), target.join("userdata"))
    {
        rollback_portable(target, &backup, &stage)?;
        return Err(error).context("preserve portable user data");
    }

    let _ = remove_path(&backup);
    Ok(())
}

fn extract_zip(package: &Path, target: &Path) -> Result<()> {
    let file = File::open(package).context("open portable update package")?;
    let mut archive = ZipArchive::new(file).context("read portable update package")?;
    for index in 0..archive.len() {
        let mut entry = archive
            .by_index(index)
            .context("read portable update entry")?;
        if entry
            .unix_mode()
            .is_some_and(|mode| mode & 0o170000 == 0o120000)
        {
            bail!("portable update contains a symbolic link");
        }
        let relative = entry
            .enclosed_name()
            .context("portable update contains an unsafe path")?;
        let output = target.join(relative);
        if entry.is_dir() {
            fs::create_dir_all(&output).context("create portable update directory")?;
            continue;
        }
        if let Some(parent) = output.parent() {
            fs::create_dir_all(parent).context("create portable update parent")?;
        }
        let mut output_file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&output)
            .context("create portable update file")?;
        io::copy(&mut entry, &mut output_file).context("extract portable update file")?;
    }
    Ok(())
}

fn verify_portable_bundle(directory: &Path) -> Result<()> {
    for name in ["sparxie.exe", "sparxie-updater.exe", ".portable"] {
        if !directory.join(name).is_file() {
            bail!("portable update is missing {name}");
        }
    }
    if directory.join("userdata").exists() {
        bail!("portable update unexpectedly contains user data");
    }
    Ok(())
}

fn rollback_portable(target: &Path, backup: &Path, stage: &Path) -> Result<()> {
    fs::rename(target, stage).context("move failed portable update aside")?;
    fs::rename(backup, target).context("restore portable app after failed update")?;
    let _ = remove_path(stage);
    Ok(())
}

fn sibling_work_path(target: &Path, work_dir: &Path, label: &str) -> Result<PathBuf> {
    let parent = target
        .parent()
        .context("portable app directory has no parent")?;
    let mut name = OsString::from(".");
    name.push(
        target
            .file_name()
            .context("portable app directory has no name")?,
    );
    name.push(format!(".{label}-"));
    name.push(
        work_dir
            .file_name()
            .context("update directory has no name")?,
    );
    Ok(parent.join(name))
}

fn ensure_absent(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).context("inspect portable update path"),
        Ok(_) => bail!("portable update path already exists"),
    }
}

fn validate_paths(package: &Path, app: &Path, work_dir: &Path, kind: PackageKind) -> Result<()> {
    let helper = std::env::current_exe()
        .context("locate updater executable")?
        .canonicalize()
        .context("resolve updater executable")?;
    let package = package
        .canonicalize()
        .context("resolve Windows update package")?;
    let work_dir = work_dir
        .canonicalize()
        .context("resolve update directory")?;
    if helper.parent() != Some(work_dir.as_path()) || package.parent() != Some(work_dir.as_path()) {
        bail!("updater files are outside the update directory");
    }
    if !app.is_file() {
        bail!("current application executable is missing");
    }
    if matches!(kind, PackageKind::Portable)
        && !app
            .parent()
            .is_some_and(|directory| directory.join(".portable").is_file())
    {
        bail!("portable marker is missing");
    }
    Ok(())
}

fn wait_for_exit(pid: u32) -> Result<()> {
    let process = unsafe { OpenProcess(PROCESS_SYNCHRONIZE, 0, pid) };
    if process.is_null() {
        let error = std::io::Error::last_os_error();
        if error.raw_os_error() == Some(ERROR_INVALID_PARAMETER as i32) {
            return Ok(());
        }
        return Err(error).context("open application process");
    }
    let process = OwnedHandle(process);
    let wait = unsafe { WaitForSingleObject(process.0, INFINITE) };
    if wait == WAIT_FAILED {
        return Err(std::io::Error::last_os_error()).context("wait for application exit");
    }
    Ok(())
}

fn launch(app: &Path) -> Result<()> {
    create_process(app, &[], false).map(|_| ())
}

fn create_process(executable: &Path, arguments: &[&str], wait: bool) -> Result<Option<u32>> {
    let application_name = wide_null(executable.as_os_str());
    let mut command_line = command_line(executable.as_os_str(), arguments);
    let startup = STARTUPINFOW {
        cb: size_of::<STARTUPINFOW>() as u32,
        ..Default::default()
    };
    let mut process_info = PROCESS_INFORMATION::default();
    let created = unsafe {
        CreateProcessW(
            application_name.as_ptr(),
            command_line.as_mut_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            CREATE_NO_WINDOW,
            std::ptr::null(),
            std::ptr::null(),
            &startup,
            &mut process_info,
        )
    };
    if created == 0 {
        return Err(std::io::Error::last_os_error()).context("start process");
    }

    let process = OwnedHandle(process_info.hProcess);
    let _thread = OwnedHandle(process_info.hThread);
    if !wait {
        return Ok(None);
    }
    let wait_result = unsafe { WaitForSingleObject(process.0, INFINITE) };
    if wait_result == WAIT_FAILED {
        return Err(std::io::Error::last_os_error()).context("wait for process");
    }
    let mut exit_code = 0;
    if unsafe { GetExitCodeProcess(process.0, &mut exit_code) } == 0 {
        return Err(std::io::Error::last_os_error()).context("read process exit code");
    }
    Ok(Some(exit_code))
}

fn command_line(executable: &OsStr, arguments: &[&str]) -> Vec<u16> {
    let mut value = Vec::new();
    value.push(b'"' as u16);
    value.extend(executable.encode_wide());
    value.push(b'"' as u16);
    for argument in arguments {
        value.push(b' ' as u16);
        value.extend(argument.encode_utf16());
    }
    value.push(0);
    value
}

fn wide_null(value: &OsStr) -> Vec<u16> {
    value.encode_wide().chain([0]).collect()
}

fn remove_path(path: &Path) -> Result<()> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error).context("read cleanup target"),
    };
    if metadata.is_dir() {
        fs::remove_dir_all(path).context("remove directory")
    } else {
        fs::remove_file(path).context("remove file")
    }
}

struct OwnedHandle(HANDLE);

impl Drop for OwnedHandle {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }
}
