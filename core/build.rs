fn main() {
    // `flutter_rust_bridge`'s `#[frb(...)]` macro emits `cfg(frb_expand)` gates
    // that are only set when `flutter_rust_bridge_codegen` runs cargo expand.
    // Tell rustc that this cfg name is intentional so `unexpected_cfgs` stops
    // warning during normal builds.
    println!("cargo::rustc-check-cfg=cfg(frb_expand)");
}
