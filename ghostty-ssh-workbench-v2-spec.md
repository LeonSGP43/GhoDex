# Ghostty SSH Workbench V2 Spec

## Summary

- 目标：在现有 `Connections` 与 `New Tab` picker 基础上，补齐更接近真实 SSH 工作台的高频能力：`收藏连接 / 更清晰的分组 / 更快的检索 / 更少的重复项`。
- 范围：本轮只增强连接选择与导航效率，不扩展 SSH transport 能力，不新增跳板、端口转发、SFTP、known-hosts 审批。
- 合并原则：继续只改 `macos/` 与顶层文档，不碰 Zig 核心，尽量保持未来 upstream merge 的低冲突面。

## Product Goals

用户应当可以在 Ghostty 内完成以下更高频的连接流：

1. 在 `Connections` 中把最常用的 SSH 连接标记为收藏。
2. 在侧边栏中优先看到收藏连接，而不是混在最近/已保存列表里。
3. 在 `Cmd+N` 与 tab bar `+` 打开的 `New Tab` picker 里，直接搜索并快速选择本地或 SSH 连接。
4. 同一个连接只在一个最优分组里出现，避免最近/已保存/导入重复展示。
5. 收藏状态持久化保存，重启 Ghostty 后仍然存在。

## Non-Goals

- 不实现密码保存流程的重构
- 不实现 Quick Add 新表单
- 不实现 host detail 新布局重构
- 不实现会话内端口转发、SFTP、代理与跳板
- 不实现云同步或团队共享

## UX Changes

### Connections Sidebar

- 新增 `收藏连接` 分组，显示用户手动标记的 SSH host。
- `最近连接` 不再重复显示已收藏 host。
- `已保存连接` 不再重复显示已收藏或最近连接里的 host。
- `从 SSH 配置导入` 不再重复显示已收藏、最近或已保存中已出现的 host。

### Host Detail Actions

- 在连接详情主操作区新增 `收藏 / 取消收藏` 按钮。
- 在侧边栏行项目中使用星标展示当前 host 是否已收藏。

### New Tab Picker

- 顶部新增搜索框，支持按以下字段模糊匹配：
  - 连接名称
  - subtitle
  - SSH alias
  - hostname
  - user
- 分组顺序固定为：
  1. Local
  2. Favorites
  3. Recent
  4. Saved
  5. Imported
- 快捷键序号继续按最终展示顺序重新分配，最多显示 `1...9`。

## Data Model

在 `AITerminalManagerConfiguration` 中新增：

- `favoriteHostIDs: [String]`

规则：

- 仅保存 host ID，不复制 host 数据。
- 配置 reconciliation 时自动移除无效 host ID。
- 删除 saved host 或重置 imported override 时，同步移除对应收藏 ID。

## Implementation Notes

### Store

- `AITerminalManagerStore` 新增：
  - `favoriteHosts`
  - `isFavorite(_:)`
  - `toggleFavorite(_:)`
- `newTabPickerEntries()` 改为把收藏 host 作为最高优先级 SSH 分组输入。

### Picker Model

- `NewTabPickerEntry.Section` 新增 `.favorites`
- `entries(...)` 先 append 收藏，再 append 最近/保存/导入
- 新增 `filteredEntries(_:, query:)`

### Localization

新增中英文文案：

- `ai.manager.hosts.favorite`
- `ai.manager.hosts.unfavorite`
- `ai.manager.hosts.favorites`
- `ssh.connections.new_tab_picker.search`

## Validation

- 本地 shell 不能被收藏
- 无效收藏 ID 在启动或重载配置后必须自动清理
- 搜索结果为空时，picker 只显示空态，不显示旧分组残影
- 收藏 host 在 sidebar 与 picker 中都必须优先于普通连接展示

## Test Plan

### Unit Tests

- 旧版配置解码时 `favoriteHostIDs` 默认为空
- `reconciledConfiguration` 会移除不存在的 favorite IDs
- `NewTabPickerModel.entries(...)` 的顺序为 `local -> favorites -> recent -> saved -> imported`
- 收藏 host 不会在 recent/saved/imported 分组中重复出现

### Build Verification

- `macos/build.nu --scheme Ghostty --configuration Debug --action build`
- `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=$PWD/macos/build -only-testing:GhosttyTests/AITerminalManagerTests test`

