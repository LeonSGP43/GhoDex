# GhoDex 操作文档（中文）

## 文档目标

本文档用于日常运行、构建、测试、基础维护和问题排查。

## 语言切换

- 中文首页：[`../README.md`](../README.md)
- English home: [`README.en.md`](./README.en.md)
- English operations: [`OPERATIONS.en.md`](./OPERATIONS.en.md)

## 1. 日常使用

### 1.1 启动方式

- Release 安装版：从 GitHub Releases 安装后直接启动。
- 源码构建版：完成构建后在产物目录启动应用。

### 1.2 推荐配置

在 `config.ghodex` 中加入以下配置，降低误操作概率：

```ini
keybind = ctrl+u=ignore
```

## 2. 构建流程（macOS）

### 2.1 前置依赖

- Zig
- Xcode / xcodebuild
- Nushell（建议，用于统一构建脚本）

### 2.2 拉取与进入仓库

```bash
git clone https://github.com/LeonSGP43/GhoDex.git
cd GhoDex
```

### 2.3 构建核心（仅核心）

```bash
zig build -Demit-macos-app=false
```

### 2.4 构建 macOS App（Debug）

```bash
nu macos/build.nu --configuration Debug --action build
```

### 2.5 构建 macOS App（ReleaseLocal）

```bash
nu macos/build.nu --configuration ReleaseLocal --action build
```

### 2.6 无 Nushell 备用命令

```bash
xcodebuild \
  -project macos/GhoDex.xcodeproj \
  -scheme GhoDex \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

## 3. 测试与验证

### 3.1 运行 Zig 测试（建议按过滤器执行）

```bash
zig build test -Dtest-filter=<test_name>
```

### 3.2 变更质量快速检查

```bash
git diff --check
```

## 4. 常用维护命令

### 4.1 清理构建产物（预览）

```bash
make prune-build-artifacts-dry-run
```

### 4.2 清理构建产物（执行）

```bash
make prune-build-artifacts
```

### 4.3 完整清理（谨慎）

```bash
make clean
```

## 5. 文档与版本治理

- 版本号文件：[`../VERSION`](../VERSION)
- 变更历史：[`../CHANGELOG.md`](../CHANGELOG.md)
- 开发说明：[`../HACKING.md`](../HACKING.md)
- 贡献说明：[`../CONTRIBUTING.md`](../CONTRIBUTING.md)

## 6. 常见问题排查

### 6.1 构建失败

- 先检查 Zig 与 Xcode 命令是否可用。
- 先跑 `git diff --check`，排除格式或冲突问题。
- 优先使用 `nu macos/build.nu` 统一构建路径。

### 6.2 ReleaseLocal 与 Debug 行为不一致

- 确认是否混用了旧产物。
- 使用 `make clean` 后重新构建对应配置。

### 6.3 文档入口不一致

- 中文入口以 [`../README.md`](../README.md) 为主。
- 英文入口以 [`README.en.md`](./README.en.md) 为主。
