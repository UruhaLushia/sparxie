use std::ffi::{CStr, CString, OsStr, OsString};
use std::fs::{self, File};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use core_foundation::url::CFURL;
use flate2::read::GzDecoder;
use objc2::rc::autoreleasepool;
use objc2_app_kit::NSWorkspace;
use objc2_foundation::{NSString, NSURL};
use security_framework::authorization::{
    Authorization, AuthorizationItemSetBuilder, Flags as AuthorizationFlags,
};
use security_framework::os::macos::code_signing::{
    Flags as CodeSigningFlags, SecRequirement, SecStaticCode,
};
use tar::Archive;

use crate::common::{mark_failed, mark_ready, parse_number, parse_sha256, verify_sha256};

const SIGNING_REQUIREMENT: &str = "identifier \"zip.atri.sparxie\"";

struct Update {
    archive: PathBuf,
    target: PathBuf,
    app_pid: i32,
    work_dir: PathBuf,
    expected_sha256: String,
    user_id: u32,
    user_name: OsString,
}

impl Update {
    fn parse(args: &[OsString], authorized: bool) -> Result<Self> {
        let expected_len = if authorized { 7 } else { 5 };
        if args.len() != expected_len {
            bail!("invalid updater arguments");
        }
        let user_id = if authorized {
            parse_number::<u32>(&args[5], "user id")?
        } else {
            unsafe { libc::getuid() }
        };
        let user_name = if authorized {
            args[6].clone()
        } else {
            username_for(user_id)?
        };
        Ok(Self {
            archive: PathBuf::from(&args[0]),
            target: PathBuf::from(&args[1]),
            app_pid: parse_number::<i32>(&args[2], "app pid")?,
            work_dir: PathBuf::from(&args[3]),
            expected_sha256: parse_sha256(&args[4])?,
            user_id,
            user_name,
        })
    }
}

pub fn run() -> Result<()> {
    let current_exe = std::env::current_exe().context("locate updater executable")?;
    let current_bundle = app_bundle_for(&current_exe).context("locate current app bundle")?;
    let mut args: Vec<OsString> = std::env::args_os().skip(1).collect();
    let authorized = args.first().is_some_and(|arg| arg == "--authorized");
    if authorized {
        args.remove(0);
    }

    let update = Update::parse(&args, authorized)?;
    if let Err(error) = validate_paths(&update) {
        let _ = mark_failed(&update.work_dir);
        return Err(error);
    }

    let target_parent = update.target.parent().context("target app has no parent")?;
    if !authorized && !is_writable(target_parent) {
        if let Err(error) = elevate(&current_exe, &update) {
            let _ = mark_failed(&update.work_dir);
            return Err(error).context("request administrator authorization");
        }
        return Ok(());
    }

    if let Err(error) = mark_ready(&update.work_dir) {
        let _ = mark_failed(&update.work_dir);
        return Err(error);
    }
    wait_for_exit(update.app_pid);
    let install_result = install(&update);
    let relaunch_result = relaunch(
        &update.target,
        &current_bundle,
        authorized,
        update.user_id,
        &update.user_name,
    );
    let cleanup_result = remove_path(&update.work_dir);
    install_result.and(relaunch_result).and(cleanup_result)
}

fn validate_paths(update: &Update) -> Result<()> {
    let archive = update
        .archive
        .canonicalize()
        .context("resolve macOS update archive")?;
    let work_dir = update
        .work_dir
        .canonicalize()
        .context("resolve update directory")?;
    if archive.parent() != Some(work_dir.as_path()) {
        bail!("update archive is outside the update directory");
    }
    if !update.target.is_absolute()
        || update.target.extension() != Some(OsStr::new("app"))
        || !update.target.parent().is_some_and(|parent| parent.is_dir())
    {
        bail!("invalid target app path");
    }
    if update.target.exists() && !update.target.is_dir() {
        bail!("target app is not a directory");
    }
    Ok(())
}

fn install(update: &Update) -> Result<()> {
    verify_sha256(&update.archive, &update.expected_sha256)?;
    let extract_dir = update.work_dir.join("extracted");
    remove_path(&extract_dir)?;
    fs::create_dir_all(&extract_dir).context("create extraction directory")?;

    let file = File::open(&update.archive).context("open update archive")?;
    Archive::new(GzDecoder::new(file))
        .unpack(&extract_dir)
        .context("extract update archive")?;
    let source = find_app_bundle(&extract_dir)?;
    verify_bundle(&source)?;

    let parent = update.target.parent().context("target app has no parent")?;
    let name = update
        .target
        .file_name()
        .context("target app has no file name")?
        .to_string_lossy();
    let stage = parent.join(format!(".{name}.update-{}", update.app_pid));
    let backup = parent.join(format!(".{name}.backup-{}", update.app_pid));
    remove_path(&stage)?;
    remove_path(&backup)?;
    copy_tree(&source, &stage).context("stage new app")?;
    verify_bundle(&stage)?;

    let had_target = update.target.exists();
    if had_target {
        fs::rename(&update.target, &backup).context("move current app to backup")?;
    }
    if let Err(error) = fs::rename(&stage, &update.target) {
        if had_target {
            let _ = fs::rename(&backup, &update.target);
        }
        let _ = remove_path(&stage);
        return Err(error).context("activate new app");
    }
    let _ = remove_path(&backup);
    Ok(())
}

fn find_app_bundle(directory: &Path) -> Result<PathBuf> {
    let mut apps = fs::read_dir(directory)
        .context("read extraction directory")?
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| path.is_dir() && path.extension() == Some(OsStr::new("app")));
    let app = apps
        .next()
        .context("update archive contains no app bundle")?;
    if apps.next().is_some() {
        bail!("update archive contains multiple app bundles");
    }
    Ok(app)
}

fn verify_bundle(bundle: &Path) -> Result<()> {
    let url = CFURL::from_path(bundle, true).context("create app bundle URL")?;
    let code = SecStaticCode::from_path(&url, CodeSigningFlags::NONE)
        .context("read app bundle signature")?;
    let requirement: SecRequirement = SIGNING_REQUIREMENT
        .parse()
        .context("create app signing requirement")?;
    code.check_validity(
        CodeSigningFlags::CHECK_ALL_ARCHITECTURES
            | CodeSigningFlags::CHECK_NESTED_CODE
            | CodeSigningFlags::STRICT_VALIDATE
            | CodeSigningFlags::NO_NETWORK_ACCESS,
        &requirement,
    )
    .context("verify app bundle signature")
}

fn copy_tree(source: &Path, target: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(source).context("read source metadata")?;
    if metadata.file_type().is_symlink() {
        let link = fs::read_link(source).context("read symbolic link")?;
        std::os::unix::fs::symlink(link, target).context("copy symbolic link")?;
        return Ok(());
    }
    if metadata.is_file() {
        fs::copy(source, target).context("copy file")?;
        fs::set_permissions(target, metadata.permissions()).context("copy file permissions")?;
        return Ok(());
    }
    fs::create_dir(target).context("create directory")?;
    for entry in fs::read_dir(source).context("read source directory")? {
        let entry = entry.context("read source entry")?;
        copy_tree(&entry.path(), &target.join(entry.file_name()))?;
    }
    fs::set_permissions(target, metadata.permissions()).context("copy directory permissions")?;
    Ok(())
}

fn remove_path(path: &Path) -> Result<()> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error).context("read cleanup target"),
    };
    if metadata.is_dir() && !metadata.file_type().is_symlink() {
        fs::remove_dir_all(path).context("remove directory")
    } else {
        fs::remove_file(path).context("remove file")
    }
}

fn app_bundle_for(path: &Path) -> Option<PathBuf> {
    path.ancestors()
        .find(|ancestor| ancestor.extension() == Some(OsStr::new("app")))
        .map(Path::to_path_buf)
}

fn wait_for_exit(pid: i32) {
    while unsafe { libc::kill(pid, 0) } == 0 {
        thread::sleep(Duration::from_millis(200));
    }
}

fn is_writable(path: &Path) -> bool {
    CString::new(path.as_os_str().as_bytes())
        .is_ok_and(|path| unsafe { libc::access(path.as_ptr(), libc::W_OK) } == 0)
}

fn username_for(user_id: u32) -> Result<OsString> {
    let user = unsafe { libc::getpwuid(user_id) };
    if user.is_null() {
        bail!("resolve current user");
    }
    let name = unsafe { CStr::from_ptr((*user).pw_name) };
    Ok(OsString::from_vec(name.to_bytes().to_vec()))
}

fn elevate(helper: &Path, update: &Update) -> Result<()> {
    let rights = AuthorizationItemSetBuilder::new()
        .add_right("system.privilege.admin")?
        .build();
    let authorization = Authorization::new(
        Some(rights),
        None,
        AuthorizationFlags::DEFAULTS
            | AuthorizationFlags::INTERACTION_ALLOWED
            | AuthorizationFlags::PREAUTHORIZE
            | AuthorizationFlags::EXTEND_RIGHTS,
    )?;
    authorization.execute_with_privileges(
        helper,
        [
            OsString::from("--authorized"),
            update.archive.as_os_str().to_owned(),
            update.target.as_os_str().to_owned(),
            OsString::from(update.app_pid.to_string()),
            update.work_dir.as_os_str().to_owned(),
            OsString::from(&update.expected_sha256),
            OsString::from(update.user_id.to_string()),
            update.user_name.clone(),
        ],
        AuthorizationFlags::DEFAULTS,
    )?;
    authorization.destroy_rights();
    Ok(())
}

fn relaunch(
    target: &Path,
    current_bundle: &Path,
    authorized: bool,
    user_id: u32,
    user_name: &OsStr,
) -> Result<()> {
    let app = if target.exists() {
        target
    } else {
        current_bundle
    };
    if authorized {
        drop_privileges(user_id, user_name)?;
    }
    let path = app.to_str().context("app path is not valid UTF-8")?;
    let launched = autoreleasepool(|_| {
        let path = NSString::from_str(path);
        let url = NSURL::fileURLWithPath_isDirectory(&path, true);
        NSWorkspace::sharedWorkspace().openURL(&url)
    });
    if !launched {
        bail!("relaunch updated application");
    }
    Ok(())
}

fn drop_privileges(user_id: u32, user_name: &OsStr) -> Result<()> {
    let name = CString::new(user_name.as_bytes()).context("validate user name")?;
    let user = unsafe { libc::getpwnam(name.as_ptr()) };
    if user.is_null() || unsafe { (*user).pw_uid } != user_id {
        bail!("resolve original user");
    }
    let group_id = unsafe { (*user).pw_gid };
    let init_group_id = i32::try_from(group_id).context("validate user group")?;
    if unsafe { libc::initgroups(name.as_ptr(), init_group_id) } != 0 {
        return Err(std::io::Error::last_os_error()).context("restore user groups");
    }
    if unsafe { libc::setgid(group_id) } != 0 {
        return Err(std::io::Error::last_os_error()).context("restore user group");
    }
    if unsafe { libc::setuid(user_id) } != 0 {
        return Err(std::io::Error::last_os_error()).context("restore user identity");
    }
    Ok(())
}
