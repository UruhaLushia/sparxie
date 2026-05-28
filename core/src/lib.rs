//! mihomo controller backend, exposed to Flutter via flutter_rust_bridge.

mod client;
mod connections_state;
mod error;
mod icons;
mod logs_state;
mod regex_util;
mod traffic;

pub mod api;

mod frb_generated;

pub use error::MihomoError;
