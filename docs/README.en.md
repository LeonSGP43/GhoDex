# GhoDex

<p align="center">
  <img src="../images/readme/welcome-hero.jpg" alt="GhoDex Welcome Banner" width="960">
</p>

<p align="center">
  A developer-first terminal workspace focused on AI-assisted workflows,
  task orchestration, and local control automation.
</p>

<p align="center">
  <strong>Language / 语言</strong>:
  <a href="../README.md">中文</a>
  ·
  <a href="./README.en.md">English</a>
</p>

## Core Capabilities

- AI Terminal Manager for terminal-to-knowledge capture and workflow learning.
- Heartbeat Task Queue with configurable interval and concurrency.
- Native Markdown workflow with preview/source modes and in-app editing.
- Local control channel for automation and agent-oriented command flows.
- Desktop-to-Android remote pairing with QR bootstrap support.

## Optimization Summary

- Stability: improved command routing in multi-instance control scenarios.
- Maintainability: strengthened governance with `VERSION` and `CHANGELOG.md`.
- Verification: clearer local validation paths for upgrades and regressions.
- Usability: stronger built-in docs and task-management workflow support.

## Deployment

### 1. Release Install

1. Open releases: <https://github.com/LeonSGP43/GhoDex/releases>
2. Download your platform package.
3. Install and launch GhoDex.

### 2. Build From Source (Recommended on macOS)

#### Prerequisites

- Zig (core build)
- Xcode / xcodebuild (macOS app build)
- Nushell (optional, for `macos/build.nu`)

#### Clone

```bash
git clone https://github.com/LeonSGP43/GhoDex.git
cd GhoDex
```

#### Build Core (without packaging macOS app)

```bash
zig build -Demit-macos-app=false
```

#### Build macOS App (Debug)

```bash
nu macos/build.nu --configuration Debug --action build
```

#### Build macOS App (ReleaseLocal)

```bash
nu macos/build.nu --configuration ReleaseLocal --action build
```

#### Fallback Build Without Nushell

```bash
xcodebuild \
  -project macos/GhoDex.xcodeproj \
  -scheme GhoDex \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

## Operations Docs

- Chinese: [`OPERATIONS.zh-CN.md`](./OPERATIONS.zh-CN.md)
- English: [`OPERATIONS.en.md`](./OPERATIONS.en.md)

## Recommended Config

To avoid accidental whole-line clearing in shell input:

```ini
keybind = ctrl+u=ignore
```

## Development

- Development guide: [`../HACKING.md`](../HACKING.md)
- Contribution guide: [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
- Changelog: [`../CHANGELOG.md`](../CHANGELOG.md)
- Current version: [`../VERSION`](../VERSION)

## Attribution

GhoDex is developed on top of [Ghostty](https://github.com/ghostty-org/ghostty),
while preserving upstream licensing and attribution requirements.
