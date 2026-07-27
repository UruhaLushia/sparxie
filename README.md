# Sparxie

跨平台代理控制器。Flutter UI + Rust 后端，通过 flutter_rust_bridge 在进程内直连

## 下载

### 正式版

<h1 align="left">
<a href="https://stikstore.app/altdirect/?url=https://raw.githubusercontent.com/UruhaLushia/sparxie/altstore/release.json" target="_blank"><img src="https://github.com/StikStore/altdirect/blob/main/assets/png/AltSource_Blue.png?raw=true" alt="Add AltSource" width="200"></a>
<a href="https://github.com/UruhaLushia/sparxie/releases/latest/download/sparxie-ios.ipa" target="_blank"><img src="https://github.com/StikStore/altdirect/blob/main/assets/png/Download_Blue.png?raw=true" alt="Download .ipa" width="200"></a>
</h1>

### 预发布版

<h1 align="left">
<a href="https://stikstore.app/altdirect/?url=https://raw.githubusercontent.com/UruhaLushia/sparxie/altstore/pre-release.json" target="_blank"><img src="https://github.com/StikStore/altdirect/blob/main/assets/png/AltSource_Blue.png?raw=true" alt="Add AltSource" width="200"></a>
<a href="https://github.com/UruhaLushia/sparxie/releases/download/pre-release/sparxie-ios.ipa" target="_blank"><img src="https://github.com/StikStore/altdirect/blob/main/assets/png/Download_Blue.png?raw=true" alt="Download .ipa" width="200"></a>
</h1>

## 支持的后端类型

| 类型 | 应用 / 后端 | 支持内容 |
|---|---|---|
| Clash | mihomo | 代理组、节点、规则、连接、日志、流量、配置、缓存、内存、升级 / 重启 |
| Clash | CMFA | 代理组、连接、日志、流量可用；核心管理和部分配置操作不可用 |
| Clash | Stash | 代理组、Provider 节点、连接、日志、流量、基础配置可用；内存、缓存、核心管理不可用 |
| Surge | Surge | 策略组、策略选择、连接、规则、流量、出站模式、DNS 刷新可用；核心管理、Provider 管理、内存流不可用 |
| sing-box | sing-box | 状态信息 (协程/内存)、代理组、节点、连接、日志、tailscale 状态 (基于 1.14.0-alpha.31) |

## 平台

| 平台 | 状态 |
|---|---|
| Android(arm64-v8a / x86_64 / universal) | ✅ |
| Linux(x86_64 / arm64) | ✅ |
| Windows(x86_64 / arm64) | ✅ |
| macOS(Apple Silicon) | ✅ |
| macOS(Intel) | ✅ 仅 Release 构建；非 Release 不编译 |
| iOS(arm64) | ✅ 未签名 IPA，供 SideStore 等工具自签 |
| Web | 暂不支持 |

## 架构

```
┌──────────────┐    FFI    ┌────────────────┐    HTTP/WS   ┌────────┐
│  Flutter UI  │ ────────→ │  Rust (cdylib) │ ───────────→ │ Backend│
└──────────────┘           └────────────────┘              └────────┘
```

所有后端通信、代理组解析、连接排序 / 分页、图标缓存都在 Rust 端；Dart 只做渲染。

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

## iOS unsigned IPA

项目不配置开发者证书，也不用于 App Store 分发。iOS 产物是未签名 IPA，适合交给 SideStore 等工具重新签名后安装。

```bash
./scripts/build-ios-ipa.sh
```

产物输出到 `build/ios/ipa/sparxie-ios.ipa`。脚本会用命令行构建 Rust iOS staticlib 和 Flutter iOS app，并用 `--no-codesign` 打包。
