use flutter_rust_bridge::frb;

#[path = "connections.rs"]
pub mod connections;
#[path = "control.rs"]
pub mod control;
#[path = "convert.rs"]
mod convert;
#[path = "providers.rs"]
pub mod providers;
#[path = "proxies.rs"]
pub mod proxies;
#[path = "proxy_delay.rs"]
pub mod proxy_delay;
#[path = "resources.rs"]
pub mod resources;
#[path = "rules.rs"]
pub mod rules;
#[path = "streams.rs"]
pub mod streams;
#[path = "target.rs"]
pub mod target;
#[path = "types.rs"]
pub mod types;

pub(in crate::backend::api) use convert::{
    clash_conn_sort, clash_group_sort, clash_list_kind, clash_member_sort,
};
pub use target::{BackendTarget, BackendType};
pub use types::*;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
