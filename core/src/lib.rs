//! Proxy controller backend, exposed to Flutter via flutter_rust_bridge.

mod assets;
pub mod backend;
mod cache;
pub(crate) mod clash;
pub(crate) mod sing_box;
pub(crate) mod surge;
pub(crate) mod surge_controller;
mod utils;

mod frb_generated;

pub use utils::error::MihomoError;
