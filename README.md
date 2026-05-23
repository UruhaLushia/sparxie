# Sparxie

跨平台 mihomo 控制器。Flutter UI + Rust 后端，通过 flutter_rust_bridge 在进程内直连。

## 平台

| 平台 | 状态 |
|---|---|
| Android(arm64-v8a / x86_64 / universal) | ✅ |
| Linux(x86_64 / arm64) | ✅ |
| Windows(x86_64 / arm64) | ✅ |
| macOS(Apple Silicon / Intel) | ✅ |
| iOS | 暂未配置签名，需自行 build |
| Web | 不支持 (依赖 dart:ffi) |

## 架构

```
┌──────────────┐    FFI    ┌────────────────┐    HTTP/WS   ┌────────┐
│  Flutter UI  │ ────────→ │  Rust (cdylib) │ ───────────→ │ mihomo │
└──────────────┘           └────────────────┘              └────────┘
```

所有 mihomo 通信、连接排序/分页、图标缓存都在 Rust 端;Dart 只做渲染。

## 开发

```bash
rustup default stable
cargo install flutter_rust_bridge_codegen --version 2.12.0
flutter pub get

# 改 Rust API 后
flutter_rust_bridge_codegen generate
# 改 freezed 类后
dart run build_runner build --delete-conflicting-outputs

flutter run -d <device>
```

Android 还需 `cargo install cargo-ndk` + `./scripts/build-android.sh` 编 cdylib 到 jniLibs。
