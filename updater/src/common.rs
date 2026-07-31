use std::ffi::OsStr;
use std::fs::File;
use std::io::Read;
use std::path::Path;

use anyhow::{Context, Result, bail};
use sha2::{Digest, Sha256};

const READY_MARKER: &str = ".helper-ready";
#[cfg(target_os = "macos")]
const FAILED_MARKER: &str = ".helper-failed";

pub fn parse_number<T>(value: &OsStr, name: &str) -> Result<T>
where
    T: std::str::FromStr,
    T::Err: std::error::Error + Send + Sync + 'static,
{
    value
        .to_string_lossy()
        .parse()
        .with_context(|| format!("parse {name}"))
}

pub fn parse_sha256(value: &OsStr) -> Result<String> {
    let value = value.to_str().context("SHA-256 is not valid UTF-8")?;
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("invalid SHA-256 argument");
    }
    Ok(value.to_ascii_lowercase())
}

pub fn verify_sha256(path: &Path, expected: &str) -> Result<()> {
    let mut file = File::open(path).context("open update package for verification")?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = file.read(&mut buffer).context("read update package")?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    let actual = format!("{:x}", hasher.finalize());
    if actual != expected {
        bail!("update package SHA-256 mismatch");
    }
    Ok(())
}

pub fn mark_ready(work_dir: &Path) -> Result<()> {
    File::create(work_dir.join(READY_MARKER)).context("create updater ready marker")?;
    Ok(())
}

#[cfg(target_os = "macos")]
pub fn mark_failed(work_dir: &Path) -> Result<()> {
    File::create(work_dir.join(FAILED_MARKER)).context("create updater failed marker")?;
    Ok(())
}
