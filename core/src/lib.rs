//! mihomo controller backend, exposed to Flutter via flutter_rust_bridge.

mod assets;
mod cache;
mod client;
mod state;
mod utils;

pub mod api;

mod frb_generated;

pub use utils::error::MihomoError;
