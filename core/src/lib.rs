//! mihomo controller backend, exposed to Flutter via flutter_rust_bridge.

mod cache_db;
mod client;
mod connections_state;
mod error;
mod fonts;
mod icons;
mod logs_state;
mod process_icons;
mod regex_util;
mod stream_stop;
mod traffic;
mod utils;

pub mod api;

mod frb_generated;

pub use error::MihomoError;
