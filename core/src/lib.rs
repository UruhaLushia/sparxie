//! Proxy controller backend, exposed to Flutter via flutter_rust_bridge.

mod assets;
pub mod backend;
mod cache;
pub(crate) mod clash;
pub(crate) mod surge;
mod utils;

mod frb_generated;

pub use utils::error::MihomoError;
