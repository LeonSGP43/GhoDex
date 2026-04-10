# GhoDex

<p align="center">
  <img src="./images/readme/welcome-hero.jpg" alt="GhoDex Welcome Banner" width="960">
</p>

<p align="center">
  面向高频开发场景的终端工作台：在原生性能基础上，强化 AI 管理、任务编排与远程控制能力。
</p>

<p align="center">
  <strong>Language / 语言</strong>:
  <a href="./README.md">中文</a>
  ·
  <a href="./docs/README.en.md">English</a>
</p>

<p align="center">
  <a href="#功能总览">功能总览</a>
  ·
  <a href="#优化总结">优化总结</a>
  ·
  <a href="#部署方法">部署方法</a>
  ·
  <a href="#操作文档">操作文档</a>
  ·
  <a href="#开发与贡献">开发与贡献</a>
  ·
  <a href="#声明">声明</a>
</p>

## 功能总览

- AI Terminal Manager：终端学习与知识沉淀流程，可把终端操作沉淀到可追踪的任务/知识上下文。
- Heartbeat Task Queue：内置心跳任务队列，支持间隔、并发等运行参数控制。
- Markdown 原生工作流：在 GhoDex 内直接打开 Markdown，支持预览/源码切换与编辑保存。
- 本地控制通道：支持终端自动化控制与面向 Agent 的命令执行链路。
- Desktop ↔ Android 远程配对：支持二维码配对与基础远程交互流程。

## 优化总结

- 稳定性优化：增强多实例控制场景下的命令路由与归属识别。
- 可维护性优化：完善 `VERSION` + `CHANGELOG.md` 的版本治理流程。
- 测试与验证优化：强化本地验证路径，提升升级回归与文档可追溯性。
- 使用体验优化：提供更贴近日常开发的内置文档阅读与任务管理能力。

## 部署方法

### 1. 快速使用（Release）

1. 打开发布页：<https://github.com/LeonSGP43/GhoDex/releases>
2. 下载对应平台的发布包。
3. 安装并启动 GhoDex。

### 2. 从源码部署（macOS 推荐）

#### 环境准备

- Zig（用于核心构建）
- Xcode / xcodebuild（用于 macOS App 构建）
- Nushell（可选，用于统一构建脚本 `macos/build.nu`）

#### 拉取源码

```bash
git clone https://github.com/LeonSGP43/GhoDex.git
cd GhoDex
```

#### 构建核心（不打包 macOS App）

```bash
zig build -Demit-macos-app=false
```

#### Browser / CEF 默认构建说明

- `nu macos/build.nu` 在 `--scheme GhoDex` 下默认按 `CEF required` 处理。
- 默认 runtime 根目录是：
  `~/Library/Application Support/GhoDex/CEF/current`
- 该目录至少要包含：
  - `Frameworks/Chromium Embedded Framework.framework`
  - `lib/Debug/libcef_dll_wrapper.a` 或 `lib/Release/libcef_dll_wrapper.a`
- Browser host bridge 会直接调用 SQLite API 处理 runtime profile 数据，因此
  CEF-enabled build 还必须链接系统 `libsqlite3`。
- `nu macos/build.nu` 现在会自动注入
  `GHODEX_CEF_OTHER_LDFLAGS=-lsqlite3`；如果当前 runtime 是单架构
  （例如当前 codec-enabled lane 常见的 `macosarm64`），它也会自动把 app
  build 收窄到匹配架构，避免 CEF wrapper 和 app slice 发生链接不匹配。
- 如果 runtime 缺失，`macos/build.nu` 现在会直接失败并给出明确提示，而不是静默编出一个 Browser 处于 `unsupportedBuild` 的 app。
- 如果你明确就是要构建一个禁用 Browser/CEF 的 app，需要显式传：
  `--cef-mode disabled`
- Browser 激活模型与 codec runtime 供给说明见：
  [`browser-tab-runtime-activation.md`](./browser-tab-runtime-activation.md)
  和 [`browser-tab-codec-runtime-playbook.md`](./browser-tab-codec-runtime-playbook.md)

#### 构建 macOS App（Debug）

```bash
nu macos/build.nu --configuration Debug --action build
```

#### 构建 macOS App（ReleaseLocal）

```bash
nu macos/build.nu --configuration ReleaseLocal --action build
```

#### 无 Nushell 时的替代构建

如果你要构建带 Browser/CEF 能力的主 app，优先使用上面的
`nu macos/build.nu`。它会统一处理 CEF runtime 检查和构建参数注入。

下面这个裸 `xcodebuild` 示例更适合作为低层调试入口；如果你直接用它来构建
Browser-enabled app，需要自己传对 CEF 相关参数，并让 app 架构和当前 runtime
架构一致。对于当前 arm64-only runtime，至少应像下面这样传：

```bash
GHODEX_CEF_ROOT="$HOME/Library/Application Support/GhoDex/CEF/current"

xcodebuild \
  -project macos/GhoDex.xcodeproj \
  -scheme GhoDex \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  EXCLUDED_ARCHS=x86_64 \
  GHODEX_CEF_ENABLED=1 \
  GHODEX_CEF_ROOT="$GHODEX_CEF_ROOT" \
  GHODEX_CEF_OTHER_LDFLAGS=-lsqlite3 \
  GHODEX_CEF_WRAPPER_LIB="$GHODEX_CEF_ROOT/lib/Debug/libcef_dll_wrapper.a" \
  build
```

## 操作文档

- 中文操作文档：[`docs/OPERATIONS.zh-CN.md`](./docs/OPERATIONS.zh-CN.md)
- English operations doc: [`docs/OPERATIONS.en.md`](./docs/OPERATIONS.en.md)
- Control Harness 协议参考：[`docs/control-harness-protocol.md`](./docs/control-harness-protocol.md)

## 推荐配置

为避免在 shell 中误触整行清空，建议在 `config.ghodex` 中加入：

```ini
keybind = ctrl+u=ignore
```

## 开发与贡献

- 开发文档：[`HACKING.md`](./HACKING.md)
- 贡献指南：[`CONTRIBUTING.md`](./CONTRIBUTING.md)
- 版本历史：[`CHANGELOG.md`](./CHANGELOG.md)
- 当前版本：[`VERSION`](./VERSION)

## 声明

GhoDex 在 [Ghostty](https://github.com/ghostty-org/ghostty) 基础之上开发，
沿用上游许可与归属要求，感谢 Ghostty 社区与贡献者的基础能力支持。
