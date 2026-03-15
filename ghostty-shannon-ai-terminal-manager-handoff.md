# Ghostty Shannon AI Terminal Manager Handoff

## Status

当前已完成 **macOS Phase 1 的 tab 管控能力**，可以在 Ghostty 内直接测试：

- 打开本地 shell tab
- 打开 workspace tab
- 打开 SSH host tab
- 选择当前 session
- 读取可见缓冲区文本
- 读取整屏缓冲区文本
- 发送命令
- 发送原始输入
- 关闭 tab
- 设置 session 的 `Observe / Manage / Return Manual`
- 在任务队列里切换 `Pause / Resume / Need Approval / Complete / Fail`

这部分不是假 UI，已经接到了 Ghostty 当前 surface/session 能力。

同时已补上 **扩展版 macOS 国际化**：

- `AI Terminal Manager` 主界面支持 English / 简体中文
- 命令面板中的 `Open: AI Terminal Manager` 已国际化
- `About` / `Settings` / `Update` / `Clipboard` / `Configuration Errors` 已国际化
- terminal overlays、context menus、部分系统弹窗已国际化
- `App Intents / AppEnum / Ghostty.Input` 通过 `.strings` 资源支持简体中文
- `Settings` 内已新增应用内语言选择器，可独立于系统语言切换
- 当前实现位于 `macos/Sources/Helpers/AppLocalization.swift` 与 `macos/Sources/zh-Hans.lproj/Localizable.strings`

当前可选：

- `System`
- `English`
- `简体中文`

当前切换方式：

- 打开 `Settings`
- 修改 `App Language`
- 点 `Restart Now`

## Entry Points

- app: `macos/build/Debug/Ghostty.app`
- 菜单入口：`Ghostty` → `AI Terminal Manager…`
- 命令面板入口：`Open: AI Terminal Manager`
- 国际化测试：切换 `Ghostty` → `Preferences…` → `App Language`

## Build Output Rule

- 标准构建产物目录只认：`macos/build`
- 不要在仓库根目录直接执行带 `SYMROOT=macos/build` 的 `xcodebuild`
- 如果确实要直接跑 `xcodebuild`，请先 `cd macos`，再使用 `SYMROOT=build`
- 默认统一使用：`nu macos/build.nu`

## How To Test

### 1. 打开 app

- 运行：`open -na /Users/leongong/Desktop/LeonProjects/ghostty/macos/build/Debug/Ghostty.app`

### 2. 打开 AI Terminal Manager

- 方式 A：菜单栏 `Ghostty` → `AI Terminal Manager…`
- 方式 B：按 `Cmd+Shift+P`
- 输入 `Open: AI Terminal Manager`
- 回车

### 3. 最短测试路径

- 在 `Hosts` 区点击 `Open Local Shell`
- 在 `Sessions` 区找到新 tab，点击 `Select`
- 在 `Selected Session Control` 区：
  - `Command` 输入 `pwd`
  - 点击 `Send Command`
  - 点击 `Refresh Snapshot`
  - 检查 `Visible Buffer` 和 `Screen Buffer`
- 再输入 `ls`
- 再点击一次 `Refresh Snapshot`
- 如需测试关闭，点击 `Close Tab`

### 4. SSH 测试路径

- 在 `Hosts` 区保存一个 SSH host
- 已保存的 SSH host 支持 `Edit / Remove`
- 从 `~/.ssh/config` 导入的 host 支持 `Edit`
- 编辑导入 host 后，会生成同 ID 的本地覆盖配置并持久化
- 点击该 host 的 `Connect`
- 在 `Sessions` 区 `Select`
- 继续用 `Send Command` / `Refresh Snapshot` 测试

## Verified Build And Test Status

以下步骤已在本机跑通：

- 安装工具：
  - `brew install zig nushell swiftlint`
- 安装 Metal Toolchain：
  - `xcodebuild -runFirstLaunch -checkForNewerComponents`
  - `xcodebuild -downloadComponent MetalToolchain -buildVersion 17C7003j`
- 生成底层 xcframework：
  - `zig build -Demit-macos-app=false`
- Swift lint：
  - `swiftlint lint 'macos/Sources/App/macOS/AppDelegate.swift' 'macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift' 'macos/Sources/Features/AI Terminal Manager/AITerminalManagerView.swift' 'macos/Tests/AITerminalManager/AITerminalManagerTests.swift'`
- macOS tests：
  - `nu macos/build.nu --scheme Ghostty --configuration Debug --action test`
  - 如需直跑：`cd macos && env -i HOME=\"$HOME\" PATH=\"/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin\" xcodebuild -project Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build -skip-testing GhosttyUITests test`

结果：

- lint 通过
- 当前这轮国际化改动下，`macos/build.nu --action test` 可完成构建与链接
- 测试运行阶段在当前环境会卡在启动的 `Ghostty.app` 进程，需本机交互式收尾

## Files Added Or Changed

- `macos/Sources/App/macOS/AppDelegate.swift`
- `macos/Sources/App/macOS/AppDelegate+AITerminalManager.swift`
- `macos/Sources/Helpers/AppLanguageSetting.swift`
- `macos/Sources/Helpers/AppLocalization.swift`
- `macos/Sources/zh-Hans.lproj/Localizable.strings`
- `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerModels.swift`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerView.swift`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerController.swift`
- `macos/Sources/Features/AI Terminal Manager/ShannonSupervisor.swift`
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`
- `macos/Sources/Features/App Intents/`
- `macos/Sources/Ghostty/Ghostty.Input.swift`
- `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`
- `macos/Tests/Localization/AppLocalizationTests.swift`
- `ghostty-shannon-ai-terminal-manager-spec.md`

## Important Implementation Notes

- `AITerminalManagerStore` 是 `@MainActor`
- `AppDelegate` 中 AI manager store / controller 已按主线程隔离初始化
- tab 文本读取复用了 `SurfaceView_AppKit.swift` 里的缓存文本能力
- 国际化当前采用混合模式：运行时代码表 + 原生 `.strings`
- `App Intents` 及 `AppEnum` 使用 `.strings`，避免编译期元数据提取报错
- 远程 tab 当前实现仍是 shell 启动后发送 `ssh ...` 初始输入
- Shannon 目前还是 supervisor scaffold，不是完整桥接

## Next Recommended Work

下一阶段建议按这个顺序继续：

- 把 `Task Queue` 接到真实 Shannon bridge
- 给 tab/session 建立结构化 observation event
- 增加 approval / pause / resume 的真实调度器
- 增加从主控页创建 worker tab 的能力
- 设计远程 host / workspace 的更强配置模型

## Resume Prompt

如果之后继续开发，可以直接从这里接：

> Continue implementing the Ghostty Shannon AI Terminal Manager after the completed macOS Phase 1 tab-control milestone. Keep the current tab/session control working, and build the real Shannon bridge and task scheduler next.
