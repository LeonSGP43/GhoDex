# Ghostty SSH V1 Connection Workspace Spec

## Summary

- 目标：先把 Ghostty 的 SSH 体验收敛到 **“像 Termius 一样保存连接并快速连接”**。
- 范围：只做 `SSH Host 保存 / 编辑 / 删除 / 搜索 / 最近连接 / ~/.ssh/config 导入 / 导入覆盖 / 一键连接`。
- 不做：`SFTP`、`Vault`、`团队协作`、`端口转发`、`Known Hosts 审批 UI`、`Snippets`、`自研 SSH transport`。
- 技术边界：继续复用系统 `ssh`，但连接参数必须来自结构化模型，不再只依赖手写字符串。
- 合并策略：优先只改 `macos/`，不碰 `src/` Zig 核心，减少未来跟 Ghostty 主线合并冲突。

## Product Goal

用户在 Ghostty 里应该能获得下面这套最小完整体验：

1. 打开连接工作台。
2. 看到 `Recent / Saved / Imported` 三类 SSH 连接。
3. 搜索连接。
4. 新建连接。
5. 编辑连接。
6. 删除自己保存的连接。
7. 覆盖从 `~/.ssh/config` 导入的连接，而不回写用户原始配置。
8. 点击连接后直接新开 tab 并进入远程 shell。

## Non-Goals

以下能力明确不进入 SSH V1：

- SFTP 面板
- 端口转发
- Jump/Proxy 的完整可视化编排（仅保留后续扩展位）
- 密钥托管 / 密码保存 / Vault
- Known Hosts 首次信任审批 UI
- Snippets
- 多端同步 / 团队共享
- 自定义 SSH transport / libssh

## Architecture

### 1. Storage Model

在 `AITerminalManagerConfiguration` 中引入明确的 SSH 工作台存储结构：

- `schemaVersion`
- `savedHosts`
  - 用户手动创建的 SSH 连接
- `importedHostOverrides`
  - 对 `~/.ssh/config` 导入连接的本地覆盖
- `recentHosts`
  - 最近连接记录
- `workspaces`
- `supervisor`

### 2. Host Categories

工作台中 Host 分成三类：

- `Local`
  - 固定内建项
- `Saved`
  - 用户显式创建或复制的连接
- `Imported`
  - 从 `~/.ssh/config` 导入

对 Imported Host 的编辑行为：

- 不改写导入源
- 写入 `importedHostOverrides`
- 最终 UI 显示使用“导入配置 + 本地覆盖”合并结果

### 3. Stable Identity

每个 SSH Host 需要稳定 ID：

- 优先：`ssh:<alias>`
- 否则：`configured:<user@hostname>`

覆盖与最近连接一律基于稳定 ID 运作。

### 4. Launch Model

SSH 连接底层仍使用系统 `ssh`，但参数生成必须来自结构化字段：

- `name`
- `sshAlias`
- `hostname`
- `user`
- `port`
- `defaultDirectory`

V1 只支持这些字段。

命令组装规则：

- 若存在 `sshAlias`，优先直接使用 alias
- 否则使用 `user@hostname`
- `port` 在无 alias 直连时带上 `-p`
- `defaultDirectory` 存在时附带远端 `cd ... && exec ${SHELL:-/bin/sh} -l`

## UI Spec

### 1. Information Architecture

SSH 工作台 UI 先保留在当前 AI Terminal Manager 内，但主机区域改成连接工作台式结构：

- Host Actions
- Search
- Recent
- Saved Hosts
- Imported SSH Config Hosts
- Host Details
- Host Editor

`Host Actions` 包含：

- Open Local Shell
- Reload SSH Config
- New Host（编辑中时可快速退出编辑）

### 2. Interactions

#### Saved Host

- `Connect`
- `Edit`
- `Duplicate`
- `Remove`

#### Imported Host

- `Connect`
- `Edit`
- `Duplicate`
- `Reset Override`（仅当存在本地覆盖时出现）

编辑 Imported Host 后：

- 创建或更新本地 override
- UI 中仍归类在 Imported 区
- 来源显示为 imported + override

### 3. Search

搜索需匹配：

- display name
- ssh alias
- hostname
- user

### 4. Recent

Recent 列表最多展示最近 8 个 SSH 连接，按时间倒序。

每条 Recent 记录保存：

- `hostID`
- `connectedAt`
- `status`
- `errorSummary`

V1 状态枚举：

- `connected`
- `failed`

## Import Rules

### Supported `~/.ssh/config` fields in V1

- `Host`
- `HostName`
- `User`
- `Port`

### Deferred fields

下列字段明确延后：

- `Include`
- `IdentityFile`
- `ProxyJump`
- `ProxyCommand`
- `ForwardAgent`
- `LocalForward`
- `RemoteForward`
- `DynamicForward`
- `Compression`
- `ServerAliveInterval`
- `Match`

## Validation Rules

连接前只做本地轻量校验：

- 别名与主机名至少一个存在
- 端口必须可解析为整数
- `defaultDirectory` 可为空

V1 不做：

- key 文件存在性检查
- host key 状态检查
- 认证可用性预检查

## Development Plan

### Phase 1

- 引入 SSH V1 存储模型
- 增加 recent records
- 增加 search state
- 将 imported override 语义从“直接变 saved host”改成显式覆盖模型

### Phase 2

- 重构 Hosts UI 为 `Recent / Saved / Imported`
- 支持搜索
- 支持编辑 imported host 并持久化 override

### Phase 3

- 连接后记录 recent 状态
- 保存最近一次失败摘要预留字段

## Test Plan

### Unit Tests

- 保存 saved host
- 更新 saved host
- imported host override 合并
- 删除 saved host
- 删除 imported override 后恢复原导入项
- recent host 更新与排序
- search 过滤逻辑
- launch command 生成

### Manual Verification

- 新建 SSH host 后可直接连接
- 编辑 Saved host 后连接参数更新
- 编辑 Imported host 后 UI 仍保留在 Imported 分组
- 删除 Saved host 后从列表消失
- 覆盖 Imported host 后删除 override，原导入项恢复
- 连接成功后出现在 Recent

## Merge Strategy

为减少后续与 Ghostty 主线冲突，提交必须按下列原子粒度拆分：

1. `docs: add ssh v1 connection workspace spec`
2. `macos: split ssh workspace storage model`
3. `macos: add recent ssh host tracking`
4. `macos: add ssh host search and grouped lists`
5. `macos: support imported ssh host overrides`
6. `tests: cover ssh workspace storage and recent hosts`
