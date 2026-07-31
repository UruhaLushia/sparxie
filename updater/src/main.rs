#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

use std::process::ExitCode;

#[cfg(any(target_os = "macos", target_os = "windows"))]
mod common;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "macos")]
use macos as platform;
#[cfg(target_os = "windows")]
use windows as platform;

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
mod platform {
    use anyhow::{Result, bail};

    pub fn run() -> Result<()> {
        bail!("the updater helper is only supported on macOS and Windows")
    }
}

fn main() -> ExitCode {
    match platform::run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error:#}");
            ExitCode::FAILURE
        }
    }
}
