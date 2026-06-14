use std::path::PathBuf;

fn main() {
    // `flutter_rust_bridge`'s `#[frb(...)]` macro emits `cfg(frb_expand)` gates
    // that are only set when `flutter_rust_bridge_codegen` runs cargo expand.
    // Tell rustc that this cfg name is intentional so `unexpected_cfgs` stops
    // warning during normal builds.
    println!("cargo::rustc-check-cfg=cfg(frb_expand)");

    let protoc = protoc_bin_vendored::protoc_bin_path().expect("find vendored protoc");
    let protobuf_include =
        protoc_bin_vendored::include_path().expect("find vendored protobuf includes");
    let mut config = tonic_prost_build::Config::new();
    config.protoc_executable(protoc);

    tonic_prost_build::configure()
        .build_server(false)
        .compile_with_config(
            config,
            &[PathBuf::from("proto/daemon/started_service.proto")],
            &[PathBuf::from("proto/daemon"), protobuf_include],
        )
        .expect("compile sing-box service api proto");
}
