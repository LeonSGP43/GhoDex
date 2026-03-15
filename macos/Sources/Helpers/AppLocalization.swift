import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum AppLocalization {
    enum Language {
        case english
        case simplifiedChinese

        var localeIdentifier: String {
            switch self {
            case .english:
                "en"
            case .simplifiedChinese:
                "zh-Hans"
            }
        }
    }

    private static let englishTable: [String: String] = [
        "common.untitled": "Untitled",
        "command_palette.ai_manager.title": "Open: AI Terminal Manager",
        "command_palette.ai_manager.description": "Show the Phase 1 Ghostty + Shannon control center scaffold.",
        "command_palette.ssh_connections.title": "Open: Connections",
        "command_palette.ssh_connections.description": "Manage saved SSH connections and jump back to active remote tabs.",
        "command_palette.update.restart": "Update Ghostty and Restart",
        "command_palette.update.cancel": "Cancel or Skip Update",
        "command_palette.update.cancel.description": "Dismiss the current update process",
        "command_palette.focus": "Focus: %@",
        "ai.manager.window.title": "AI Terminal Manager",
        "ai.manager.title": "AI Terminal Manager",
        "ai.manager.subtitle": "Ghostty hosts the terminals; Shannon is prepared as the local orchestration supervisor.",
        "ai.manager.launch": "Launch",
        "ai.manager.supervisor": "Supervisor",
        "ai.manager.supervisor.hint": "Ghostty now treats Shannon as an embedded local brain by default. An external runtime bridge remains optional when `GHOSTTY_SHANNON_PATH` is set.",
        "ai.manager.supervisor.start": "Start Supervisor",
        "ai.manager.supervisor.stop": "Stop Supervisor",
        "ai.manager.runtime.endpoint": "Runtime Endpoint",
        "ai.manager.runtime.health": "Runtime Health",
        "ai.manager.runtime.version": "Runtime Version",
        "ai.manager.runtime.gateway": "Gateway Connection",
        "ai.manager.runtime.active_agent": "Active Agent",
        "ai.manager.runtime.uptime": "Uptime",
        "ai.manager.shannon.prompt": "Shannon Prompt",
        "ai.manager.shannon.prompt.empty": "Shannon prompt cannot be empty.",
        "ai.manager.shannon.ask": "Ask Shannon",
        "ai.manager.shannon.response": "Shannon Response",
        "ai.manager.shannon.response.empty": "No Shannon response yet.",
        "ai.manager.shannon.status.idle": "Idle",
        "ai.manager.shannon.status.running": "Running",
        "ai.manager.shannon.status.waiting_approval": "Waiting for approval",
        "ai.manager.shannon.status.completed": "Completed",
        "ai.manager.shannon.status.failed": "Failed: %@",
        "ai.manager.shannon.runtime_unavailable": "Shannon runtime is unavailable.",
        "ai.manager.shannon.request_submitted": "Submitted to Shannon runtime.",
        "ai.manager.shannon.approval_needed": "Shannon requested approval for %@.",
        "ai.manager.shannon.approval_card": "Approval Required",
        "ai.manager.shannon.approve": "Approve",
        "ai.manager.shannon.deny": "Deny",
        "ai.manager.hosts": "Hosts",
        "ai.manager.hosts.open_local_shell": "Open Local Shell",
        "ai.manager.hosts.reload_ssh_config": "Reload SSH Config",
        "ai.manager.hosts.add_ssh_host": "Add SSH Host",
        "ai.manager.hosts.new_ssh_host": "New Host",
        "ai.manager.hosts.edit_ssh_host": "Edit SSH Host",
        "ai.manager.hosts.display_name": "Display Name",
        "ai.manager.hosts.ssh_alias": "SSH Alias",
        "ai.manager.hosts.hostname": "Hostname (optional if alias works)",
        "ai.manager.hosts.user": "User",
        "ai.manager.hosts.port": "Port",
        "ai.manager.hosts.default_directory": "Default Directory",
        "ai.manager.hosts.save": "Save Host",
        "ai.manager.hosts.update": "Update Host",
        "ai.manager.hosts.details": "Host Details",
        "ai.manager.hosts.none_selected": "Select a host to inspect and act on it.",
        "ai.manager.hosts.no_recent_activity": "No recent connection activity.",
        "ai.manager.hosts.source_label": "Source",
        "ai.manager.hosts.target": "Target",
        "ai.manager.hosts.duplicate": "Duplicate",
        "ai.manager.hosts.copy_suffix": "Copy",
        "ai.manager.hosts.status.connected": "Connected",
        "ai.manager.hosts.status.failed": "Failed",
        "ai.manager.hosts.empty": "No hosts configured yet.",
        "ai.manager.hosts.search": "Search SSH Hosts",
        "ai.manager.hosts.favorite": "Favorite",
        "ai.manager.hosts.unfavorite": "Unfavorite",
        "ai.manager.hosts.favorites": "Favorites",
        "ai.manager.hosts.recent": "Recent",
        "ai.manager.hosts.saved": "Saved Hosts",
        "ai.manager.hosts.imported": "Imported from SSH Config",
        "ai.manager.hosts.source.saved": "Saved",
        "ai.manager.hosts.source.imported": "Imported",
        "ai.manager.hosts.source.imported_overridden": "Imported · Local Override",
        "ai.manager.hosts.connect": "Connect",
        "ai.manager.edit": "Edit",
        "ai.manager.cancel_edit": "Cancel",
        "ai.manager.remove": "Remove",
        "ai.manager.hosts.reset_override": "Reset Override",
        "ai.manager.workspaces": "Workspaces",
        "ai.manager.workspaces.add_local": "Add Local Workspace",
        "ai.manager.workspaces.register": "Register Workspace",
        "ai.manager.workspaces.name": "Workspace Name",
        "ai.manager.workspaces.host": "Host",
        "ai.manager.workspaces.directory": "Directory",
        "ai.manager.workspaces.save": "Save Workspace",
        "ai.manager.workspaces.empty": "No workspaces saved yet.",
        "ai.manager.open": "Open",
        "ai.manager.sessions": "Sessions",
        "ai.manager.sessions.empty": "No terminal sessions are currently open.",
        "ai.manager.selected": "Selected",
        "ai.manager.focused": "Focused",
        "ai.manager.select": "Select",
        "ai.manager.focus": "Focus",
        "ai.manager.create_task": "Create Task",
        "ai.manager.observe": "Observe",
        "ai.manager.manage": "Manage",
        "ai.manager.return_manual": "Return Manual",
        "ai.manager.selected_session_control": "Selected Session Control",
        "ai.manager.refresh_snapshot": "Refresh Snapshot",
        "ai.manager.close_tab": "Close Tab",
        "ai.manager.command": "Command",
        "ai.manager.command.placeholder": "pwd && ls",
        "ai.manager.send_command": "Send Command",
        "ai.manager.raw_input": "Raw Input",
        "ai.manager.send_input": "Send Input",
        "ai.manager.visible_buffer": "Visible Buffer",
        "ai.manager.visible_buffer.empty": "No visible text captured yet.",
        "ai.manager.screen_buffer": "Screen Buffer",
        "ai.manager.screen_buffer.empty": "No screen text captured yet.",
        "ai.manager.selected_session.empty": "Select a session to inspect its terminal text, send commands, or close the tab.",
        "ai.manager.task_queue": "Task Queue",
        "ai.manager.task_queue.empty": "No managed tasks yet.",
        "ai.manager.focus_session": "Focus Session",
        "ai.manager.pause": "Pause",
        "ai.manager.resume": "Resume",
        "ai.manager.need_approval": "Need Approval",
        "ai.manager.complete": "Complete",
        "ai.manager.fail": "Fail",
        "ai.manager.open_panel.add_workspace": "Add Workspace",
        "ai.manager.error.host_missing_ssh_details": "The selected host is missing SSH connection details.",
        "ai.manager.error.workspace_unknown_host": "Workspace %@ references an unknown host.",
        "ai.manager.error.workspace_invalid_plan": "Workspace %@ could not be converted into a launch plan.",
        "ai.manager.error.host_name_empty": "Host name cannot be empty.",
        "ai.manager.error.host_missing_alias_or_hostname": "Provide either an SSH alias or a hostname.",
        "ai.manager.error.host_invalid_port": "SSH port must be a number.",
        "ai.manager.error.local_mcd_commands_empty": "Provide at least one startup command.",
        "ai.manager.error.workspace_name_empty": "Workspace name cannot be empty.",
        "ai.manager.error.workspace_directory_empty": "Workspace directory cannot be empty.",
        "ai.manager.error.session_unavailable": "The selected terminal session is no longer available.",
        "ai.manager.error.input_empty": "Input cannot be empty.",
        "ai.manager.error.command_empty": "Command cannot be empty.",
        "ai.manager.error.select_session_first": "Select a terminal session first.",
        "ai.manager.error.app_delegate_unavailable": "Ghostty app delegate is unavailable.",
        "ai.manager.error.create_session_failed": "Ghostty failed to create a new terminal session.",
        "ai.manager.error.save_configuration_failed": "Failed to save AI terminal manager configuration: %@",
        "ai.manager.session.manual": "Manual",
        "ai.manager.session.observed": "Observed",
        "ai.manager.session.managed": "Managed",
        "ai.manager.session.awaiting_approval": "Awaiting Approval",
        "ai.manager.session.paused": "Paused",
        "ai.manager.session.completed": "Completed",
        "ai.manager.session.failed": "Failed",
        "ai.manager.launch_target.tab": "New Tab",
        "ai.manager.launch_target.window": "New Window",
        "ai.manager.host.local_name": "This Mac",
        "ai.manager.host.local_shell": "Local shell",
        "ai.manager.task.queued": "Queued",
        "ai.manager.task.active": "Active",
        "ai.manager.supervisor.unavailable": "Unavailable",
        "ai.manager.supervisor.stopped": "Stopped",
        "ai.manager.supervisor.starting": "Starting",
        "ai.manager.supervisor.running_embedded": "Running (embedded)",
        "ai.manager.supervisor.running": "Running (pid %@)",
        "ai.manager.supervisor.failed": "Failed: %@",
        "ai.manager.supervisor.exit_status": "Exited with status %@",
        "ai.manager.runtime.unavailable": "Unavailable",
        "ai.manager.runtime.probing": "Probing runtime...",
        "ai.manager.runtime.healthy": "Healthy",
        "ai.manager.runtime.unreachable": "Unreachable: %@",
        "ai.manager.runtime.gateway.connected": "Connected",
        "ai.manager.runtime.gateway.disconnected": "Disconnected",
        "ai.manager.session.manual_session": "Manual Session",
        "ai.manager.task.waiting_for_operator": "Waiting for operator approval.",
        "ai.manager.task.marked_complete": "Marked complete by operator.",
        "ai.manager.task.marked_failed": "Marked failed by operator.",
        "ai.manager.task.session_closed": "Session closed before task completed.",
        "ai.manager.task.manage_session": "Manage %@",
        "ai.manager.task.default_title": "Managed Terminal Task",
        "ssh.connections.window.title": "Connections",
        "ssh.connections.title": "Connections",
        "ssh.connections.subtitle": "Save SSH connections, reuse passwords from Keychain, and jump back into active remote sessions.",
        "ssh.connections.new": "New Connection",
        "ssh.connections.search": "Search Connections",
        "ssh.connections.connection_type": "Connection Type",
        "ssh.connections.connection_type.ssh": "SSH",
        "ssh.connections.connection_type.localmcd": "Local MCD",
        "ssh.connections.localmcd.commands": "Startup Commands",
        "ssh.connections.localmcd.commands.help": "Commands run line by line in a new tab.",
        "ssh.connections.localmcd.edit": "Edit Local MCD Connection",
        "ssh.connections.save": "Save Connection",
        "ssh.connections.update": "Update Connection",
        "ssh.connections.authentication": "Authentication",
        "ssh.connections.authentication.system": "System SSH",
        "ssh.connections.authentication.password": "Saved Password",
        "ssh.connections.password": "Password",
        "ssh.connections.password.stored": "A password is already stored in Keychain. Leave this blank to keep it.",
        "ssh.connections.password.not_stored": "No password is currently stored in Keychain for this connection.",
        "ssh.connections.active_sessions": "Active Remote Sessions",
        "ssh.connections.active_sessions.empty": "No active remote sessions yet.",
        "ssh.connections.reconnect": "Reconnect",
        "ssh.connections.error.password_required": "Password is required when using Saved Password authentication.",
        "ssh.connections.error.password_missing": "No saved password was found for this connection. Edit the connection and save the password again.",
        "ssh.connections.error.password_save_failed": "Failed to save the SSH password to Keychain: %@",
        "ssh.connections.error.password_read_failed": "Failed to read the SSH password from Keychain: %@",
        "ssh.connections.error.password_delete_failed": "Failed to remove the saved SSH password from Keychain: %@",
        "ssh.connections.error.authentication_failed": "SSH authentication failed.",
        "ssh.connections.session.auth.connecting": "Connecting",
        "ssh.connections.session.auth.awaiting_password": "Awaiting Password Prompt",
        "ssh.connections.session.auth.authenticating": "Authenticating",
        "ssh.connections.session.auth.connected": "Connected",
        "ssh.connections.session.auth.failed": "Failed",
        "ssh.connections.new_tab_picker.subtitle": "Choose a local shell or a ready SSH connection.",
        "ssh.connections.new_tab_picker.empty": "No saved SSH connections are ready yet.",
        "ssh.connections.new_tab_picker.search": "Search local and SSH connections",
        "ssh.connections.new_tab_picker.quick_connect": "⌘1-9 Quick Connect",
        "terminal.notification.bell.title": "Action Required",
        "terminal.notification.bell.body": "Task completed and waiting for your input.",
        "about.tagline": "Fast, native, feature-rich terminal \nemulator pushing modern features.",
        "about.version": "Version",
        "about.build": "Build",
        "about.commit": "Commit",
        "about.docs": "Docs",
        "about.github": "GitHub",
        "settings.title": "Settings",
        "settings.body": "Language can be configured here. For advanced terminal settings, edit $HOME/.config/ghostty/config.ghostty and restart Ghostty.",
        "settings.language.title": "App Language",
        "AI Terminal Manager…": "AI Terminal Manager…",
        "Connections…": "Connections…",
        "settings.language.description": "Choose a language override for Ghostty. Restart is required for menus, App Intents, and all localized resources to update consistently.",
        "settings.language.option.system": "System",
        "settings.language.option.english": "English",
        "settings.language.option.simplified_chinese": "简体中文",
        "settings.language.restart_required": "Restart Ghostty to apply the language change everywhere.",
        "settings.language.restart_now": "Restart Now",
        "app.allow_execute": "Allow Ghostty to execute \"%@\"?",
        "app.undo_action": "Undo %@",
        "app.redo_action": "Redo %@",
        "app.set_default_terminal_failure": "Ghostty could not be set as the default terminal application.\n\nError: %@",
        "app.configuration_errors.summary": "%d configuration error(s) were found while loading the configuration. Review the errors below, then reload your configuration or ignore the invalid lines.",
        "app.progress.percent": "%@ percent complete",
        "app.tabs_disabled": "Tabs are disabled",
        "app.enable_window_decorations_for_tabs": "Enable window decorations to use tabs",
        "app.new_tabs_unsupported_fullscreen": "New tabs are unsupported while in non-native fullscreen. Exit fullscreen and try again.",
        "permission.dont_allow": "Don't Allow",
        "permission.remember.seconds": "Remember my decision for %d seconds",
        "permission.remember.minute.one": "Remember my decision for %d minute",
        "permission.remember.minute.other": "Remember my decision for %d minutes",
        "permission.remember.hour.one": "Remember my decision for %d hour",
        "permission.remember.hour.other": "Remember my decision for %d hours",
        "permission.remember.one_day": "Remember my decision for one day",
        "permission.remember.day.one": "Remember my decision for %d day",
        "permission.remember.day.other": "Remember my decision for %d days"
    ]

    private static let simplifiedChineseTable: [String: String] = [
        "common.untitled": "未命名",
        "command_palette.ai_manager.title": "打开：AI Terminal Manager",
        "command_palette.ai_manager.description": "打开 Ghostty + Shannon Phase 1 控制中心原型。",
        "command_palette.ssh_connections.title": "打开：连接中心",
        "command_palette.ssh_connections.description": "管理已保存的 SSH 连接，并快速回到活动中的远程标签页。",
        "command_palette.update.restart": "更新 Ghostty 并重启",
        "command_palette.update.cancel": "取消或跳过更新",
        "command_palette.update.cancel.description": "关闭当前更新流程",
        "command_palette.focus": "聚焦：%@",
        "ai.manager.window.title": "AI 终端管理器",
        "ai.manager.title": "AI 终端管理器",
        "ai.manager.subtitle": "Ghostty 负责终端宿主；Shannon 作为本地主控编排器预留接入。",
        "ai.manager.launch": "启动方式",
        "ai.manager.supervisor": "主控进程",
        "ai.manager.supervisor.hint": "Ghostty 现在默认把 Shannon 作为内嵌本地主脑运行。只有在设置 `GHOSTTY_SHANNON_PATH` 时，才会启用可选的外部 runtime bridge。",
        "ai.manager.supervisor.start": "启动主控进程",
        "ai.manager.supervisor.stop": "停止主控进程",
        "ai.manager.runtime.endpoint": "运行时地址",
        "ai.manager.runtime.health": "运行时健康状态",
        "ai.manager.runtime.version": "运行时版本",
        "ai.manager.runtime.gateway": "网关连接",
        "ai.manager.runtime.active_agent": "当前 Agent",
        "ai.manager.runtime.uptime": "运行时长",
        "ai.manager.shannon.prompt": "Shannon 请求",
        "ai.manager.shannon.prompt.empty": "Shannon 请求不能为空。",
        "ai.manager.shannon.ask": "请求 Shannon",
        "ai.manager.shannon.response": "Shannon 回复",
        "ai.manager.shannon.response.empty": "还没有 Shannon 回复。",
        "ai.manager.shannon.status.idle": "空闲",
        "ai.manager.shannon.status.running": "运行中",
        "ai.manager.shannon.status.waiting_approval": "等待审批",
        "ai.manager.shannon.status.completed": "已完成",
        "ai.manager.shannon.status.failed": "失败：%@",
        "ai.manager.shannon.runtime_unavailable": "Shannon 运行时不可用。",
        "ai.manager.shannon.request_submitted": "已提交到 Shannon 运行时。",
        "ai.manager.shannon.approval_needed": "Shannon 请求对 %@ 进行审批。",
        "ai.manager.shannon.approval_card": "待审批动作",
        "ai.manager.shannon.approve": "批准",
        "ai.manager.shannon.deny": "拒绝",
        "ai.manager.hosts": "主机",
        "ai.manager.hosts.open_local_shell": "打开本地 Shell",
        "ai.manager.hosts.reload_ssh_config": "重新加载 SSH 配置",
        "ai.manager.hosts.add_ssh_host": "添加 SSH 主机",
        "ai.manager.hosts.new_ssh_host": "新建主机",
        "ai.manager.hosts.edit_ssh_host": "编辑 SSH 主机",
        "ai.manager.hosts.display_name": "显示名称",
        "ai.manager.hosts.ssh_alias": "SSH 别名",
        "ai.manager.hosts.hostname": "主机名（如果别名可用可不填）",
        "ai.manager.hosts.user": "用户",
        "ai.manager.hosts.port": "端口",
        "ai.manager.hosts.default_directory": "默认目录",
        "ai.manager.hosts.save": "保存主机",
        "ai.manager.hosts.update": "更新主机",
        "ai.manager.hosts.details": "主机详情",
        "ai.manager.hosts.none_selected": "选择一个主机以查看详情并执行操作。",
        "ai.manager.hosts.no_recent_activity": "暂无最近连接记录。",
        "ai.manager.hosts.source_label": "来源",
        "ai.manager.hosts.target": "目标",
        "ai.manager.hosts.duplicate": "复制",
        "ai.manager.hosts.copy_suffix": "副本",
        "ai.manager.hosts.status.connected": "已连接",
        "ai.manager.hosts.status.failed": "连接失败",
        "ai.manager.hosts.empty": "还没有配置任何主机。",
        "ai.manager.hosts.search": "搜索 SSH 主机",
        "ai.manager.hosts.favorite": "收藏",
        "ai.manager.hosts.unfavorite": "取消收藏",
        "ai.manager.hosts.favorites": "收藏连接",
        "ai.manager.hosts.recent": "最近连接",
        "ai.manager.hosts.saved": "已保存连接",
        "ai.manager.hosts.imported": "从 SSH 配置导入",
        "ai.manager.hosts.source.saved": "已保存",
        "ai.manager.hosts.source.imported": "已导入",
        "ai.manager.hosts.source.imported_overridden": "已导入 · 本地覆盖",
        "ai.manager.hosts.connect": "连接",
        "ai.manager.edit": "编辑",
        "ai.manager.cancel_edit": "取消编辑",
        "ai.manager.remove": "移除",
        "ai.manager.hosts.reset_override": "重置覆盖",
        "ai.manager.workspaces": "工作区",
        "ai.manager.workspaces.add_local": "添加本地工作区",
        "ai.manager.workspaces.register": "注册工作区",
        "ai.manager.workspaces.name": "工作区名称",
        "ai.manager.workspaces.host": "主机",
        "ai.manager.workspaces.directory": "目录",
        "ai.manager.workspaces.save": "保存工作区",
        "ai.manager.workspaces.empty": "还没有保存任何工作区。",
        "ai.manager.open": "打开",
        "ai.manager.sessions": "会话",
        "ai.manager.sessions.empty": "当前没有打开任何终端会话。",
        "ai.manager.selected": "已选中",
        "ai.manager.focused": "当前聚焦",
        "ai.manager.select": "选择",
        "ai.manager.focus": "聚焦",
        "ai.manager.create_task": "创建任务",
        "ai.manager.observe": "观察",
        "ai.manager.manage": "托管",
        "ai.manager.return_manual": "恢复手动",
        "ai.manager.selected_session_control": "当前选中会话控制",
        "ai.manager.refresh_snapshot": "刷新快照",
        "ai.manager.close_tab": "关闭标签页",
        "ai.manager.command": "命令",
        "ai.manager.command.placeholder": "pwd && ls",
        "ai.manager.send_command": "发送命令",
        "ai.manager.raw_input": "原始输入",
        "ai.manager.send_input": "发送输入",
        "ai.manager.visible_buffer": "可见缓冲区",
        "ai.manager.visible_buffer.empty": "还没有采集到可见文本。",
        "ai.manager.screen_buffer": "整屏缓冲区",
        "ai.manager.screen_buffer.empty": "还没有采集到整屏文本。",
        "ai.manager.selected_session.empty": "先选择一个会话，再查看文本、发送命令或关闭标签页。",
        "ai.manager.task_queue": "任务队列",
        "ai.manager.task_queue.empty": "还没有托管任务。",
        "ai.manager.focus_session": "聚焦会话",
        "ai.manager.pause": "暂停",
        "ai.manager.resume": "继续",
        "ai.manager.need_approval": "需要审批",
        "ai.manager.complete": "完成",
        "ai.manager.fail": "失败",
        "ai.manager.open_panel.add_workspace": "添加工作区",
        "ai.manager.error.host_missing_ssh_details": "选中的主机缺少 SSH 连接信息。",
        "ai.manager.error.workspace_unknown_host": "工作区 %@ 引用了未知主机。",
        "ai.manager.error.workspace_invalid_plan": "工作区 %@ 无法转换为启动计划。",
        "ai.manager.error.host_name_empty": "主机名称不能为空。",
        "ai.manager.error.host_missing_alias_or_hostname": "请至少提供 SSH 别名或主机名。",
        "ai.manager.error.host_invalid_port": "SSH 端口必须是数字。",
        "ai.manager.error.local_mcd_commands_empty": "请至少填写一条启动命令。",
        "ai.manager.error.workspace_name_empty": "工作区名称不能为空。",
        "ai.manager.error.workspace_directory_empty": "工作区目录不能为空。",
        "ai.manager.error.session_unavailable": "选中的终端会话已不可用。",
        "ai.manager.error.input_empty": "输入不能为空。",
        "ai.manager.error.command_empty": "命令不能为空。",
        "ai.manager.error.select_session_first": "请先选择一个终端会话。",
        "ai.manager.error.app_delegate_unavailable": "Ghostty app delegate 不可用。",
        "ai.manager.error.create_session_failed": "Ghostty 创建终端会话失败。",
        "ai.manager.error.save_configuration_failed": "保存 AI 终端管理器配置失败：%@",
        "ai.manager.session.manual": "手动",
        "ai.manager.session.observed": "观察中",
        "ai.manager.session.managed": "托管中",
        "ai.manager.session.awaiting_approval": "等待审批",
        "ai.manager.session.paused": "已暂停",
        "ai.manager.session.completed": "已完成",
        "ai.manager.session.failed": "失败",
        "ai.manager.launch_target.tab": "新标签页",
        "ai.manager.launch_target.window": "新窗口",
        "ai.manager.host.local_name": "当前 Mac",
        "ai.manager.host.local_shell": "本地 Shell",
        "ai.manager.task.queued": "排队中",
        "ai.manager.task.active": "进行中",
        "ai.manager.supervisor.unavailable": "不可用",
        "ai.manager.supervisor.stopped": "已停止",
        "ai.manager.supervisor.starting": "启动中",
        "ai.manager.supervisor.running_embedded": "运行中（内嵌）",
        "ai.manager.supervisor.running": "运行中（pid %@）",
        "ai.manager.supervisor.failed": "失败：%@",
        "ai.manager.supervisor.exit_status": "进程退出，状态码 %@",
        "ai.manager.runtime.unavailable": "不可用",
        "ai.manager.runtime.probing": "正在探测运行时……",
        "ai.manager.runtime.healthy": "健康",
        "ai.manager.runtime.unreachable": "无法访问：%@",
        "ai.manager.runtime.gateway.connected": "已连接",
        "ai.manager.runtime.gateway.disconnected": "未连接",
        "ai.manager.session.manual_session": "手动会话",
        "ai.manager.task.waiting_for_operator": "等待操作员审批。",
        "ai.manager.task.marked_complete": "操作员已标记完成。",
        "ai.manager.task.marked_failed": "操作员已标记失败。",
        "ai.manager.task.session_closed": "会话在任务完成前已关闭。",
        "ai.manager.task.manage_session": "托管 %@",
        "ai.manager.task.default_title": "托管终端任务",
        "ssh.connections.window.title": "连接中心",
        "ssh.connections.title": "连接中心",
        "ssh.connections.subtitle": "保存 SSH 连接、复用 Keychain 密码，并快速回到活动中的远程会话。",
        "ssh.connections.new": "新建连接",
        "ssh.connections.search": "搜索连接",
        "ssh.connections.connection_type": "连接类型",
        "ssh.connections.connection_type.ssh": "SSH",
        "ssh.connections.connection_type.localmcd": "Local MCD",
        "ssh.connections.localmcd.commands": "启动命令",
        "ssh.connections.localmcd.commands.help": "打开新标签页时将按行顺序执行这些命令。",
        "ssh.connections.localmcd.edit": "编辑 Local MCD 连接",
        "ssh.connections.save": "保存连接",
        "ssh.connections.update": "更新连接",
        "ssh.connections.authentication": "认证方式",
        "ssh.connections.authentication.system": "系统 SSH",
        "ssh.connections.authentication.password": "保存密码",
        "ssh.connections.password": "密码",
        "ssh.connections.password.stored": "Keychain 中已保存密码。留空即可保留现有密码。",
        "ssh.connections.password.not_stored": "当前连接在 Keychain 中还没有保存密码。",
        "ssh.connections.active_sessions": "活动远程会话",
        "ssh.connections.active_sessions.empty": "当前还没有活动中的远程会话。",
        "ssh.connections.reconnect": "重新连接",
        "ssh.connections.error.password_required": "使用“保存密码”认证时必须填写密码。",
        "ssh.connections.error.password_missing": "当前连接没有已保存密码。请编辑该连接并重新保存密码。",
        "ssh.connections.error.password_save_failed": "保存 SSH 密码到 Keychain 失败：%@",
        "ssh.connections.error.password_read_failed": "从 Keychain 读取 SSH 密码失败：%@",
        "ssh.connections.error.password_delete_failed": "从 Keychain 删除已保存 SSH 密码失败：%@",
        "ssh.connections.error.authentication_failed": "SSH 认证失败。",
        "ssh.connections.session.auth.connecting": "连接中",
        "ssh.connections.session.auth.awaiting_password": "等待密码提示",
        "ssh.connections.session.auth.authenticating": "认证中",
        "ssh.connections.session.auth.connected": "已连接",
        "ssh.connections.session.auth.failed": "失败",
        "ssh.connections.new_tab_picker.subtitle": "选择本地终端或一个已就绪的 SSH 连接。",
        "ssh.connections.new_tab_picker.empty": "当前还没有可直接连接的已保存 SSH 连接。",
        "ssh.connections.new_tab_picker.search": "搜索本地和 SSH 连接",
        "ssh.connections.new_tab_picker.quick_connect": "⌘1-9 快速连接",
        "terminal.notification.bell.title": "等待操作",
        "terminal.notification.bell.body": "任务已完成，等待你的操作。",
        "about.tagline": "快速、原生、功能丰富的终端模拟器，持续推进现代终端体验。",
        "about.version": "版本",
        "about.build": "构建号",
        "about.commit": "提交",
        "about.docs": "文档",
        "about.github": "GitHub",
        "settings.title": "设置",
        "settings.body": "这里目前可配置应用语言。若要修改高级终端配置，请编辑 $HOME/.config/ghostty/config.ghostty，然后重启 Ghostty。",
        "settings.language.title": "应用语言",
        "AI Terminal Manager…": "AI 终端管理器…",
        "Connections…": "连接中心…",
        "settings.language.description": "为 Ghostty 选择语言覆盖设置。为了让菜单、App Intents 和所有本地化资源一致更新，需要重启应用。",
        "settings.language.option.system": "跟随系统",
        "settings.language.option.english": "English",
        "settings.language.option.simplified_chinese": "简体中文",
        "settings.language.restart_required": "需要重启 Ghostty，语言变更才会完整应用到所有界面。",
        "settings.language.restart_now": "立即重启",
        "app.allow_execute": "允许 Ghostty 执行“%@”吗？",
        "app.undo_action": "撤销 %@",
        "app.redo_action": "重做 %@",
        "app.set_default_terminal_failure": "无法将 Ghostty 设为默认终端应用。\n\n错误：%@",
        "app.configuration_errors.summary": "加载配置时发现 %d 个错误。请查看下方错误，然后重新加载配置或忽略无效行。",
        "app.progress.percent": "已完成 %@",
        "app.tabs_disabled": "标签页已禁用",
        "app.enable_window_decorations_for_tabs": "启用窗口装饰后才能使用标签页",
        "app.new_tabs_unsupported_fullscreen": "非原生全屏模式下不支持新建标签页。请先退出全屏后再试。",
        "permission.dont_allow": "不允许",
        "permission.remember.seconds": "记住我的决定 %d 秒",
        "permission.remember.minute.one": "记住我的决定 %d 分钟",
        "permission.remember.minute.other": "记住我的决定 %d 分钟",
        "permission.remember.hour.one": "记住我的决定 %d 小时",
        "permission.remember.hour.other": "记住我的决定 %d 小时",
        "permission.remember.one_day": "记住我的决定一天",
        "permission.remember.day.one": "记住我的决定 %d 天",
        "permission.remember.day.other": "记住我的决定 %d 天"
    ]

    private static let simplifiedChineseSourceTable: [String: String] = [
        "About Ghostty": "关于 Ghostty",
        "Check for Updates...": "检查更新...",
        "Preferences…": "偏好设置…",
        "Open Config": "打开配置文件",
        "AI Terminal Manager…": "AI 终端管理器…",
        "Connections…": "连接中心…",
        "Reload Configuration": "重新加载配置",
        "Secure Keyboard Entry": "安全键盘输入",
        "Make Ghostty the Default Terminal": "将 Ghostty 设为默认终端",
        "Services": "服务",
        "Hide Ghostty": "隐藏 Ghostty",
        "Hide Others": "隐藏其他",
        "Show All": "显示全部",
        "Quit Ghostty": "退出 Ghostty",
        "File": "文件",
        "New Window": "新建窗口",
        "New Tab": "新建标签页",
        "Split Right": "向右分屏",
        "Split Left": "向左分屏",
        "Split Down": "向下分屏",
        "Split Up": "向上分屏",
        "Close": "关闭",
        "Close Tab": "关闭标签页",
        "Close Window": "关闭窗口",
        "Close All Windows": "关闭所有窗口",
        "Edit": "编辑",
        "Undo": "撤销",
        "Redo": "重做",
        "Copy": "复制",
        "Paste": "粘贴",
        "Paste Selection": "粘贴选中内容",
        "Select All": "全选",
        "Find": "查找",
        "Find...": "查找...",
        "Find Next": "查找下一个",
        "Find Previous": "查找上一个",
        "Hide Find Bar": "隐藏查找栏",
        "Use Selection for Find": "使用所选内容查找",
        "Jump to Selection": "跳转到所选内容",
        "View": "显示",
        "Reset Font Size": "重置字体大小",
        "Increase Font Size": "增大字体",
        "Decrease Font Size": "减小字体",
        "Command Palette": "命令面板",
        "Change Tab Title...": "修改标签页标题...",
        "Change Terminal Title...": "修改终端标题...",
        "Terminal Read-only": "终端只读",
        "Quick Terminal": "快捷终端",
        "Terminal Inspector": "终端检查器",
        "Window": "窗口",
        "Minimize": "最小化",
        "Zoom": "缩放",
        "Toggle Full Screen": "切换全屏",
        "Show/Hide All Terminals": "显示/隐藏所有终端",
        "Zoom Split": "聚焦分屏",
        "Select Previous Split": "选择上一个分屏",
        "Select Next Split": "选择下一个分屏",
        "Select Split": "选择分屏",
        "Select Split Above": "选择上方分屏",
        "Select Split Below": "选择下方分屏",
        "Select Split Left": "选择左侧分屏",
        "Select Split Right": "选择右侧分屏",
        "Resize Split": "调整分屏",
        "Equalize Splits": "平均分配分屏",
        "Move Divider Up": "向上移动分隔线",
        "Move Divider Down": "向下移动分隔线",
        "Move Divider Left": "向左移动分隔线",
        "Move Divider Right": "向右移动分隔线",
        "Return To Default Size": "恢复默认大小",
        "Float on Top": "置顶显示",
        "Use as Default": "设为默认",
        "Bring All to Front": "全部移到前台",
        "Help": "帮助",
        "Ghostty Help": "Ghostty 帮助",
        "Execute a command…": "执行命令…",
        "No matches": "无匹配项",
        "Search": "搜索",
        "Key Table": "按键表",
        "A key table is a named set of keybindings, activated by some other key. Keys are interpreted using this table until it is deactivated.": "按键表是一组有名称的按键绑定，由其他按键触发激活。在停用前，按键都会按此表解释。",
        "Key Sequence": "按键序列",
        "A key sequence is a series of key presses that trigger an action. A pending key sequence is currently active.": "按键序列是一串按键输入，用于触发某个动作。当前存在一个待完成的按键序列。",
        "Read-only": "只读",
        "Read-only terminal": "只读终端",
        "Read-Only Mode": "只读模式",
        "This terminal is in read-only mode. You can still view, select, and scroll through the content, but no input events will be sent to the running application.": "此终端当前处于只读模式。你仍可查看、选择和滚动内容，但不会向正在运行的应用发送任何输入事件。",
        "Disable": "关闭只读",
        "Oh, no. 😭": "出错了 😭",
        "The renderer has failed. This is usually due to exhausting available GPU memory. Please free up available resources.": "渲染器已失败。这通常是由于 GPU 可用内存耗尽导致的。请释放一些可用资源。",
        "The terminal failed to initialize. Please check the logs for more information. This is usually a bug.": "终端初始化失败。请查看日志以获取更多信息。这通常是一个程序缺陷。",
        "Something went fatally wrong.\nCheck the logs and restart Ghostty.": "发生了严重错误。\n请检查日志并重新启动 Ghostty。",
        "Loading": "加载中",
        "You're running a debug build of Ghostty! Performance will be degraded.": "你正在运行 Ghostty 的调试构建版本，性能会下降。",
        "Debug builds of Ghostty are very slow and you may experience performance problems. Debug builds are only recommended during development.": "Ghostty 的调试构建非常慢，你可能会遇到性能问题。调试构建仅建议在开发期间使用。",
        "Debug build warning": "调试构建警告",
        "Enable automatic updates?": "启用自动更新？",
        "Enable Automatic Updates?": "启用自动更新？",
        "Ghostty can automatically check for updates in the background.": "Ghostty 可以在后台自动检查更新。",
        "Not Now": "暂不",
        "Allow": "允许",
        "Checking for updates…": "正在检查更新…",
        "Checking for Updates…": "正在检查更新…",
        "Cancel": "取消",
        "Update Available": "发现可用更新",
        "Update Available: %@": "发现可用更新：%@",
        "Version:": "版本：",
        "Size:": "大小：",
        "Released:": "发布日期：",
        "Skip": "跳过",
        "Later": "稍后",
        "Install and Relaunch": "安装并重新启动",
        "Downloading Update": "正在下载更新",
        "Downloading: %.0f%%": "下载中：%.0f%%",
        "Downloading…": "下载中…",
        "Preparing Update": "正在准备更新",
        "Preparing: %.0f%%": "准备中：%.0f%%",
        "Restart Required": "需要重新启动",
        "The update is ready. Please restart the application to complete the installation.": "更新已就绪。请重新启动应用以完成安装。",
        "Restart to Complete Update": "重启以完成更新",
        "Installing…": "安装中…",
        "Restart Later": "稍后重启",
        "Restart Now": "立即重启",
        "No Updates Found": "未发现更新",
        "No Updates Available": "没有可用更新",
        "You're already running the latest version.": "你当前已是最新版本。",
        "OK": "确定",
        "Update Failed": "更新失败",
        "Retry": "重试",
        "Configure automatic update preferences": "配置自动更新偏好",
        "Please wait while we check for available updates": "正在检查可用更新，请稍候",
        "Download and install the latest version": "下载并安装最新版本",
        "Downloading the update package": "正在下载更新包",
        "Extracting and preparing the update": "正在解压并准备更新",
        "Installing update and preparing to restart": "正在安装更新并准备重启",
        "You are running the latest version": "你当前运行的是最新版本",
        "An error occurred during the update process": "更新过程中发生错误",
        "Copy Icon Config": "复制图标配置",
        "Ghostty Application Icon": "Ghostty 应用图标",
        "Click to cycle through icon variants": "点击切换图标变体",
        "None": "无",
        "Blue": "蓝色",
        "Purple": "紫色",
        "Pink": "粉色",
        "Red": "红色",
        "Orange": "橙色",
        "Yellow": "黄色",
        "Green": "绿色",
        "Teal": "青色",
        "Graphite": "石墨色",
        "Tab Color": "标签页颜色",
        "Secure Input is active. Secure Input is a macOS security feature that prevents applications from reading keyboard events. This is enabled automatically whenever Ghostty detects a password prompt in the terminal, or at all times if `Ghostty > Secure Keyboard Entry` is active.": "安全输入已启用。安全输入是 macOS 的一项安全特性，可防止应用读取键盘事件。每当 Ghostty 检测到终端中的密码提示时会自动启用；如果 `Ghostty > 安全键盘输入` 处于启用状态，则会始终开启。",
        "Terminal pane": "终端面板",
        "Cannot Create New Tab": "无法新建标签页",
        "Tabs aren't supported in the Quick Terminal.": "快捷终端不支持标签页。",
        "Close Terminal?": "关闭终端？",
        "The terminal still has a running process. If you close the terminal the process will be killed.": "该终端仍有进程在运行。若关闭终端，该进程将被终止。",
        "Close All Windows?": "关闭所有窗口？",
        "Quit Ghostty?": "退出 Ghostty？",
        "All terminal sessions will be terminated.": "所有终端会话都将被终止。",
        "Close Ghostty": "关闭 Ghostty",
        "Failed to Set Default Terminal": "设置默认终端失败",
        "Warning: Potentially Unsafe Paste": "警告：可能存在风险的粘贴",
        "Authorize Clipboard Access": "授权访问剪贴板",
        "Pasting this text to the terminal may be dangerous as it looks like some commands may be executed.": "将这段文本粘贴到终端可能存在风险，因为它看起来可能会执行某些命令。",
        "An application is attempting to read from the clipboard.\nThe current clipboard contents are shown below.": "某个应用正尝试读取剪贴板。\n当前剪贴板内容如下所示。",
        "An application is attempting to write to the clipboard.\nThe content to write is shown below.": "某个应用正尝试写入剪贴板。\n将要写入的内容如下所示。",
        "Deny": "拒绝",
        "Ignore": "忽略",
        "Configuration Errors": "配置错误",
        "Horizontal split divider": "水平分屏分隔线",
        "Horizontal split view": "水平分屏视图",
        "Vertical split view": "垂直分屏视图",
        "Left pane": "左侧面板",
        "Right pane": "右侧面板",
        "Top pane": "上方面板",
        "Bottom pane": "下方面板",
        "Vertical split divider": "垂直分屏分隔线",
        "Drag to resize the left and right panes": "拖动以调整左右面板大小",
        "Drag to resize the top and bottom panes": "拖动以调整上下分屏大小",
        "Terminal progress - Error": "终端进度 - 错误",
        "Terminal progress - Paused": "终端进度 - 已暂停",
        "Terminal progress - In progress": "终端进度 - 进行中",
        "Terminal progress": "终端进度",
        "Operation failed": "操作失败",
        "Operation paused at completion": "操作在完成时已暂停",
        "Operation in progress": "操作进行中",
        "Indeterminate progress": "不确定进度",
        "Reset Terminal": "重置终端",
        "Toggle Terminal Inspector": "切换终端检查器",
        "Show": "显示",
        "Close Tabs to the Right": "关闭右侧标签页",
        "Terminal content area": "终端内容区域",
        "Could not load any text from the clipboard.": "无法从剪贴板读取任何文本。",
        "Tabs are disabled": "标签页已禁用",
        "Enable window decorations to use tabs": "启用窗口装饰后才能使用标签页",
        "New tabs are unsupported while in non-native fullscreen. Exit fullscreen and try again.": "非原生全屏模式下不支持新建标签页。请先退出全屏后再试。",
        "Rename Tab...": "重命名标签页...",
        "Get Details of Terminal": "获取终端详情",
        "Detail": "详情",
        "The detail to extract about a terminal.": "要从终端中提取的详情。",
        "The terminal to extract information about.": "要提取信息的终端。",
        "Terminal Detail": "终端详情",
        "Title": "标题",
        "Working Directory": "工作目录",
        "Full Contents": "完整内容",
        "Selected Text": "选中文本",
        "Visible Text": "可见文本",
        "Close Terminal": "关闭终端",
        "Close an existing terminal.": "关闭一个已有终端。",
        "The terminal to close.": "要关闭的终端。",
        "Invoke Command Palette Action": "执行命令面板操作",
        "The terminal to base available commands from.": "用于提供可用命令来源的终端。",
        "Command": "命令",
        "The command to invoke.": "要执行的命令。",
        "Focus Terminal": "聚焦终端",
        "Move focus to an existing terminal.": "将焦点移动到已有终端。",
        "The terminal to focus.": "要聚焦的终端。",
        "Input Text to Terminal": "向终端输入文本",
        "Text": "文本",
        "The text to input to the terminal. The text will be inputted as if it was pasted.": "要输入到终端的文本。文本会以粘贴方式输入。",
        "The terminal to scope this action to.": "此操作要作用到的终端。",
        "Send Keyboard Event to Terminal": "向终端发送键盘事件",
        "Simulate a keyboard event. This will not handle text encoding; use the 'Input Text' action for that.": "模拟键盘事件。该操作不会处理文本编码；文本输入请使用“输入文本”操作。",
        "Key": "按键",
        "The key to send to the terminal.": "要发送到终端的按键。",
        "Modifier(s)": "修饰键",
        "The modifiers to send with the key event.": "随按键事件一起发送的修饰键。",
        "Event Type": "事件类型",
        "A key press or release.": "按键按下或释放。",
        "Send Mouse Button Event to Terminal": "向终端发送鼠标按键事件",
        "Button": "按钮",
        "The mouse button to press or release.": "要按下或释放的鼠标按钮。",
        "Action": "动作",
        "Whether to press or release the button.": "按下还是释放该按钮。",
        "The modifiers to send with the mouse event.": "随鼠标事件一起发送的修饰键。",
        "Send Mouse Position Event to Terminal": "向终端发送鼠标位置事件",
        "Send a mouse position event to the terminal. This reports the cursor position for mouse tracking.": "向终端发送鼠标位置事件。该事件用于报告鼠标跟踪所需的光标位置。",
        "X Position": "X 坐标",
        "The horizontal position of the mouse cursor in pixels.": "鼠标光标的横向像素位置。",
        "Y Position": "Y 坐标",
        "The vertical position of the mouse cursor in pixels.": "鼠标光标的纵向像素位置。",
        "The modifiers to send with the mouse position event.": "随鼠标位置事件一起发送的修饰键。",
        "Send Mouse Scroll Event to Terminal": "向终端发送鼠标滚动事件",
        "Send a mouse scroll event to the terminal with configurable precision and momentum.": "向终端发送鼠标滚动事件，并可配置精度和惯性阶段。",
        "X Scroll Delta": "X 滚动增量",
        "The horizontal scroll amount.": "横向滚动量。",
        "Y Scroll Delta": "Y 滚动增量",
        "The vertical scroll amount.": "纵向滚动量。",
        "High Precision": "高精度",
        "Whether this is a high-precision scroll event (e.g., from trackpad).": "该滚动事件是否为高精度事件（例如来自触控板）。",
        "Momentum Phase": "惯性阶段",
        "The momentum phase of the scroll event.": "滚动事件的惯性阶段。",
        "The momentum phase for inertial scrolling.": "惯性滚动的阶段。",
        "Modifier Key": "修饰键",
        "Shift": "Shift",
        "Control": "Control",
        "Option": "Option",
        "Command Palette Command": "命令面板命令",
        "Description": "描述",
        "Terminal": "终端",
        "Kind": "类型",
        "Terminal Kind": "终端类型",
        "Normal": "普通",
        "Quick": "快捷",
        "Invoke a Keybind Action": "执行按键绑定动作",
        "The terminal to invoke the action on.": "要执行动作的终端。",
        "The keybind action to invoke. This can be any valid keybind action you could put in a configuration file.": "要执行的按键绑定动作。可以是任意可写入配置文件的有效 keybind action。",
        "New Terminal": "新建终端",
        "Create a new terminal.": "创建一个新终端。",
        "Location": "位置",
        "The location that the terminal should be created.": "应创建终端的位置。",
        "Command to execute within your configured shell.": "在已配置 Shell 中执行的命令。",
        "Environment Variables": "环境变量",
        "Environment variables in `KEY=VALUE` format.": "采用 `KEY=VALUE` 格式的环境变量。",
        "Parent Terminal": "父终端",
        "The terminal to inherit the base configuration from.": "要继承基础配置的终端。",
        "Terminal Location": "终端位置",
        "Tab": "标签页",
        "Open the Quick Terminal": "打开快捷终端",
        "Open the Quick Terminal. If it is already open, then do nothing.": "打开快捷终端。如果已经打开，则不执行任何操作。",
        "The Ghostty app isn't properly initialized.": "Ghostty 应用未正确初始化。",
        "The terminal no longer exists.": "该终端已不存在。",
        "Ghostty doesn't allow Shortcuts.": "Ghostty 不允许快捷指令访问。",
        "Allow Shortcuts to interact with Ghostty?": "允许快捷指令与 Ghostty 交互吗？",
        "Key Action": "按键动作",
        "Release": "释放",
        "Press": "按下",
        "Repeat": "重复",
        "Mouse State": "鼠标状态",
        "Mouse Button": "鼠标按钮",
        "Unknown": "未知",
        "Left": "左键",
        "Right": "右键",
        "Middle": "中键",
        "Scroll Momentum": "滚动惯性",
        "Began": "开始",
        "Stationary": "静止",
        "Changed": "变化中",
        "Ended": "结束",
        "Cancelled": "已取消",
        "May Begin": "可能开始",
        "Up Arrow": "上箭头",
        "Down Arrow": "下箭头",
        "Left Arrow": "左箭头",
        "Right Arrow": "右箭头",
        "Space": "空格",
        "Enter": "回车",
        "Backspace": "退格",
        "Escape": "Esc",
        "Delete": "删除",
        "Home": "Home",
        "End": "End",
        "Page Up": "Page Up",
        "Page Down": "Page Down",
        "Insert": "Insert",
        "Left Shift": "左 Shift",
        "Right Shift": "右 Shift",
        "Left Control": "左 Control",
        "Right Control": "右 Control",
        "Left Alt": "左 Alt",
        "Right Alt": "右 Alt",
        "Left Command": "左 Command",
        "Right Command": "右 Command",
        "Caps Lock": "Caps Lock",
        "Minus (-)": "减号 (-)",
        "Equal (=)": "等号 (=)",
        "Backtick (`)": "反引号 (`)",
        "Left Bracket ([)": "左方括号 ([)",
        "Right Bracket (])": "右方括号 (])",
        "Backslash (\\)": "反斜杠 (\\)",
        "Semicolon (;)": "分号 (;)",
        "Quote (')": "引号 (')",
        "Comma (,)": "逗号 (,)",
        "Period (.)": "句点 (.)",
        "Slash (/)": "斜杠 (/)",
        "Num Lock": "Num Lock",
        "Numpad 0": "小键盘 0",
        "Numpad 1": "小键盘 1",
        "Numpad 2": "小键盘 2",
        "Numpad 3": "小键盘 3",
        "Numpad 4": "小键盘 4",
        "Numpad 5": "小键盘 5",
        "Numpad 6": "小键盘 6",
        "Numpad 7": "小键盘 7",
        "Numpad 8": "小键盘 8",
        "Numpad 9": "小键盘 9",
        "Numpad Add (+)": "小键盘加号 (+)",
        "Numpad Subtract (-)": "小键盘减号 (-)",
        "Numpad Multiply (×)": "小键盘乘号 (×)",
        "Numpad Divide (÷)": "小键盘除号 (÷)",
        "Numpad Decimal": "小键盘小数点",
        "Numpad Equal": "小键盘等号",
        "Numpad Enter": "小键盘回车",
        "Numpad Comma": "小键盘逗号",
        "Volume Up": "音量增大",
        "Volume Down": "音量减小",
        "Volume Mute": "静音",
        "International Backslash": "国际反斜杠",
        "International Ro": "国际 Ro",
        "International Yen": "国际 Yen",
        "Context Menu": "上下文菜单",
        "View GitHub Commit": "查看 GitHub 提交",
        "Changes Since This Tip Release": "查看自当前 Tip 版本以来的变更",
        "View Release Notes": "查看发布说明"
    ]

    nonisolated static func language(for preferredLanguages: [String]) -> Language {
        for identifier in preferredLanguages {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if normalized.hasPrefix("en") {
                return .english
            }
        }

        return .english
    }

    nonisolated static func localizedString(
        _ key: String,
        preferredLanguages: [String] = AppLanguageSetting.preferredLanguages(),
        _ arguments: CVarArg...
    ) -> String {
        localizedString(key, preferredLanguages: preferredLanguages, arguments: arguments)
    }

    nonisolated static func localizedString(
        _ key: String,
        preferredLanguages: [String],
        arguments: [CVarArg]
    ) -> String {
        let language = language(for: preferredLanguages)
        let format = table(for: language)[key]
            ?? englishTable[key]
            ?? key

        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }

    nonisolated static func localizedText(
        _ text: String,
        preferredLanguages: [String] = AppLanguageSetting.preferredLanguages()
    ) -> String {
        if let localized = localizedBundleText(
            text,
            preferredLanguages: preferredLanguages
        ) {
            return localized
        }

        let language = language(for: preferredLanguages)
        switch language {
        case .english:
            return text
        case .simplifiedChinese:
            return simplifiedChineseSourceTable[text] ?? text
        }
    }

    nonisolated static func resource(
        _ text: String,
        preferredLanguages: [String] = AppLanguageSetting.preferredLanguages()
    ) -> LocalizedStringResource {
        LocalizedStringResource(
            stringLiteral: localizedText(
                text,
                preferredLanguages: preferredLanguages
            )
        )
    }

    private nonisolated static func localizedBundleText(
        _ text: String,
        preferredLanguages: [String],
        bundle: Bundle = .main
    ) -> String? {
        let language = language(for: preferredLanguages)
        guard language != .english,
              let path = bundle.path(forResource: language.localeIdentifier, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else { return nil }

        let localized = localizedBundle.localizedString(forKey: text, value: nil, table: nil)
        return localized == text ? nil : localized
    }

    private nonisolated static func table(for language: Language) -> [String: String] {
        switch language {
        case .english:
            englishTable
        case .simplifiedChinese:
            simplifiedChineseTable
        }
    }

#if canImport(AppKit)
    static func localize(menu: NSMenu?) {
        guard let menu else { return }
        menu.title = localizedText(menu.title)
        for item in menu.items {
            if !item.title.isEmpty {
                item.title = localizedText(item.title)
            }
            if let submenu = item.submenu {
                localize(menu: submenu)
            }
        }
    }
#endif
}

enum L10n {
    enum Common {
        nonisolated static var cancel: String { AppLocalization.localizedText("Cancel") }
        nonisolated static var untitled: String { AppLocalization.localizedString("common.untitled") }
    }

    enum CommandPalette {
        nonisolated static var aiManagerTitle: String { AppLocalization.localizedString("command_palette.ai_manager.title") }
        nonisolated static var aiManagerDescription: String { AppLocalization.localizedString("command_palette.ai_manager.description") }
        nonisolated static var sshConnectionsTitle: String { AppLocalization.localizedString("command_palette.ssh_connections.title") }
        nonisolated static var sshConnectionsDescription: String { AppLocalization.localizedString("command_palette.ssh_connections.description") }
        nonisolated static var updateRestart: String { AppLocalization.localizedString("command_palette.update.restart") }
        nonisolated static var updateCancel: String { AppLocalization.localizedString("command_palette.update.cancel") }
        nonisolated static var updateCancelDescription: String { AppLocalization.localizedString("command_palette.update.cancel.description") }
        nonisolated static func focus(_ title: String) -> String { AppLocalization.localizedString("command_palette.focus", title) }
    }

    enum About {
        nonisolated static var tagline: String { AppLocalization.localizedString("about.tagline") }
        nonisolated static var version: String { AppLocalization.localizedString("about.version") }
        nonisolated static var build: String { AppLocalization.localizedString("about.build") }
        nonisolated static var commit: String { AppLocalization.localizedString("about.commit") }
        nonisolated static var docs: String { AppLocalization.localizedString("about.docs") }
        nonisolated static var github: String { AppLocalization.localizedString("about.github") }
    }

    enum Settings {
        nonisolated static var title: String { AppLocalization.localizedString("settings.title") }
        nonisolated static var body: String { AppLocalization.localizedString("settings.body") }
        nonisolated static var languageTitle: String { AppLocalization.localizedString("settings.language.title") }
        nonisolated static var languageDescription: String { AppLocalization.localizedString("settings.language.description") }
        nonisolated static var languageOptionSystem: String { AppLocalization.localizedString("settings.language.option.system") }
        nonisolated static var languageOptionEnglish: String { AppLocalization.localizedString("settings.language.option.english") }
        nonisolated static var languageOptionSimplifiedChinese: String { AppLocalization.localizedString("settings.language.option.simplified_chinese") }
        nonisolated static var languageRestartRequired: String { AppLocalization.localizedString("settings.language.restart_required") }
        nonisolated static var restartNow: String { AppLocalization.localizedString("settings.language.restart_now") }
    }

    enum App {
        nonisolated static var ok: String { AppLocalization.localizedText("OK") }
        nonisolated static var cancel: String { AppLocalization.localizedText("Cancel") }
        nonisolated static var close: String { AppLocalization.localizedText("Close") }
        nonisolated static var allow: String { AppLocalization.localizedText("Allow") }
        nonisolated static var paste: String { AppLocalization.localizedText("Paste") }
        nonisolated static var deny: String { AppLocalization.localizedText("Deny") }
        nonisolated static var ignore: String { AppLocalization.localizedText("Ignore") }
        nonisolated static var reloadConfiguration: String { AppLocalization.localizedText("Reload Configuration") }
        nonisolated static var closeGhostty: String { AppLocalization.localizedText("Close Ghostty") }
        nonisolated static var quitGhostty: String { AppLocalization.localizedText("Quit Ghostty?") }
        nonisolated static var closeAllWindows: String { AppLocalization.localizedText("Close All Windows") }
        nonisolated static var allSessionsTerminated: String { AppLocalization.localizedText("All terminal sessions will be terminated.") }
        nonisolated static var leaveBlankRestoreDefault: String { AppLocalization.localizedText("Leave blank to restore the default.") }
        nonisolated static var cannotCreateNewTab: String { AppLocalization.localizedText("Cannot Create New Tab") }
        nonisolated static var closeTerminal: String { AppLocalization.localizedText("Close Terminal?") }
        nonisolated static var closeAllWindowsQuestion: String { AppLocalization.localizedText("Close All Windows?") }
        nonisolated static var failedSetDefaultTerminal: String { AppLocalization.localizedText("Failed to Set Default Terminal") }
        nonisolated static var pasteWarningTitle: String { AppLocalization.localizedText("Warning: Potentially Unsafe Paste") }
        nonisolated static var authorizeClipboardAccess: String { AppLocalization.localizedText("Authorize Clipboard Access") }
        nonisolated static func allowExecute(_ filename: String) -> String { AppLocalization.localizedString("app.allow_execute", filename) }
        nonisolated static func undo(_ action: String) -> String { AppLocalization.localizedString("app.undo_action", action) }
        nonisolated static func redo(_ action: String) -> String { AppLocalization.localizedString("app.redo_action", action) }
        nonisolated static func setDefaultTerminalFailure(_ message: String) -> String { AppLocalization.localizedString("app.set_default_terminal_failure", message) }
        nonisolated static func configurationErrorsSummary(_ count: Int) -> String { AppLocalization.localizedString("app.configuration_errors.summary", count) }
        nonisolated static func progressPercent(_ percent: UInt8) -> String { AppLocalization.localizedString("app.progress.percent", String(percent)) }
        nonisolated static var tabsDisabled: String { AppLocalization.localizedString("app.tabs_disabled") }
        nonisolated static var enableWindowDecorationsForTabs: String { AppLocalization.localizedString("app.enable_window_decorations_for_tabs") }
        nonisolated static var newTabsUnsupportedFullscreen: String { AppLocalization.localizedString("app.new_tabs_unsupported_fullscreen") }
    }

    enum Permission {
        nonisolated static var dontAllow: String { AppLocalization.localizedString("permission.dont_allow") }
        nonisolated static func rememberSeconds(_ value: Int) -> String { AppLocalization.localizedString("permission.remember.seconds", value) }
        nonisolated static func rememberMinute(_ value: Int) -> String { AppLocalization.localizedString("permission.remember.minute.one", value) }
        nonisolated static func rememberMinutes(_ value: Int) -> String { AppLocalization.localizedString("permission.remember.minute.other", value) }
        nonisolated static func rememberHour(_ value: Int) -> String { AppLocalization.localizedString("permission.remember.hour.one", value) }
        nonisolated static func rememberHours(_ value: Int) -> String { AppLocalization.localizedString("permission.remember.hour.other", value) }
        nonisolated static var rememberOneDay: String { AppLocalization.localizedString("permission.remember.one_day") }
        nonisolated static func rememberDay(_ value: Int) -> String { AppLocalization.localizedString("permission.remember.day.one", value) }
        nonisolated static func rememberDays(_ value: Int) -> String { AppLocalization.localizedString("permission.remember.day.other", value) }
    }

    enum SSHConnections {
        nonisolated static var windowTitle: String { AppLocalization.localizedString("ssh.connections.window.title") }
        nonisolated static var title: String { AppLocalization.localizedString("ssh.connections.title") }
        nonisolated static var subtitle: String { AppLocalization.localizedString("ssh.connections.subtitle") }
        nonisolated static var newConnection: String { AppLocalization.localizedString("ssh.connections.new") }
        nonisolated static var searchConnections: String { AppLocalization.localizedString("ssh.connections.search") }
        nonisolated static var connectionType: String { AppLocalization.localizedString("ssh.connections.connection_type") }
        nonisolated static var connectionTypeSSH: String { AppLocalization.localizedString("ssh.connections.connection_type.ssh") }
        nonisolated static var connectionTypeLocalMCD: String { AppLocalization.localizedString("ssh.connections.connection_type.localmcd") }
        nonisolated static var localMCDStartupCommands: String { AppLocalization.localizedString("ssh.connections.localmcd.commands") }
        nonisolated static var localMCDStartupCommandsHelp: String { AppLocalization.localizedString("ssh.connections.localmcd.commands.help") }
        nonisolated static var editLocalMCDConnection: String { AppLocalization.localizedString("ssh.connections.localmcd.edit") }
        nonisolated static var saveConnection: String { AppLocalization.localizedString("ssh.connections.save") }
        nonisolated static var updateConnection: String { AppLocalization.localizedString("ssh.connections.update") }
        nonisolated static var authentication: String { AppLocalization.localizedString("ssh.connections.authentication") }
        nonisolated static var authModeSystem: String { AppLocalization.localizedString("ssh.connections.authentication.system") }
        nonisolated static var authModePassword: String { AppLocalization.localizedString("ssh.connections.authentication.password") }
        nonisolated static var password: String { AppLocalization.localizedString("ssh.connections.password") }
        nonisolated static var passwordStored: String { AppLocalization.localizedString("ssh.connections.password.stored") }
        nonisolated static var passwordNotStored: String { AppLocalization.localizedString("ssh.connections.password.not_stored") }
        nonisolated static var activeSessions: String { AppLocalization.localizedString("ssh.connections.active_sessions") }
        nonisolated static var activeSessionsEmpty: String { AppLocalization.localizedString("ssh.connections.active_sessions.empty") }
        nonisolated static var reconnect: String { AppLocalization.localizedString("ssh.connections.reconnect") }
        nonisolated static var passwordRequired: String { AppLocalization.localizedString("ssh.connections.error.password_required") }
        nonisolated static var passwordMissing: String { AppLocalization.localizedString("ssh.connections.error.password_missing") }
        nonisolated static func passwordSaveFailed(_ message: String) -> String { AppLocalization.localizedString("ssh.connections.error.password_save_failed", message) }
        nonisolated static func passwordReadFailed(_ message: String) -> String { AppLocalization.localizedString("ssh.connections.error.password_read_failed", message) }
        nonisolated static func passwordDeleteFailed(_ message: String) -> String { AppLocalization.localizedString("ssh.connections.error.password_delete_failed", message) }
        nonisolated static var authenticationFailed: String { AppLocalization.localizedString("ssh.connections.error.authentication_failed") }
        nonisolated static var authStateConnecting: String { AppLocalization.localizedString("ssh.connections.session.auth.connecting") }
        nonisolated static var authStateAwaitingPassword: String { AppLocalization.localizedString("ssh.connections.session.auth.awaiting_password") }
        nonisolated static var authStateAuthenticating: String { AppLocalization.localizedString("ssh.connections.session.auth.authenticating") }
        nonisolated static var authStateConnected: String { AppLocalization.localizedString("ssh.connections.session.auth.connected") }
        nonisolated static var authStateFailed: String { AppLocalization.localizedString("ssh.connections.session.auth.failed") }
        nonisolated static var newTabPickerSubtitle: String { AppLocalization.localizedString("ssh.connections.new_tab_picker.subtitle") }
        nonisolated static var newTabPickerEmpty: String { AppLocalization.localizedString("ssh.connections.new_tab_picker.empty") }
        nonisolated static var newTabPickerSearch: String { AppLocalization.localizedString("ssh.connections.new_tab_picker.search") }
        nonisolated static var newTabPickerQuickConnect: String { AppLocalization.localizedString("ssh.connections.new_tab_picker.quick_connect") }
    }

    enum AITerminalManager {
        nonisolated static var windowTitle: String { AppLocalization.localizedString("ai.manager.window.title") }
        nonisolated static var title: String { AppLocalization.localizedString("ai.manager.title") }
        nonisolated static var subtitle: String { AppLocalization.localizedString("ai.manager.subtitle") }
        nonisolated static var launch: String { AppLocalization.localizedString("ai.manager.launch") }
        nonisolated static var supervisor: String { AppLocalization.localizedString("ai.manager.supervisor") }
        nonisolated static var supervisorHint: String { AppLocalization.localizedString("ai.manager.supervisor.hint") }
        nonisolated static var startSupervisor: String { AppLocalization.localizedString("ai.manager.supervisor.start") }
        nonisolated static var stopSupervisor: String { AppLocalization.localizedString("ai.manager.supervisor.stop") }
        nonisolated static var runtimeEndpoint: String { AppLocalization.localizedString("ai.manager.runtime.endpoint") }
        nonisolated static var runtimeHealth: String { AppLocalization.localizedString("ai.manager.runtime.health") }
        nonisolated static var runtimeVersion: String { AppLocalization.localizedString("ai.manager.runtime.version") }
        nonisolated static var runtimeGateway: String { AppLocalization.localizedString("ai.manager.runtime.gateway") }
        nonisolated static var runtimeActiveAgent: String { AppLocalization.localizedString("ai.manager.runtime.active_agent") }
        nonisolated static var runtimeUptime: String { AppLocalization.localizedString("ai.manager.runtime.uptime") }
        nonisolated static var shannonPrompt: String { AppLocalization.localizedString("ai.manager.shannon.prompt") }
        nonisolated static var shannonPromptEmpty: String { AppLocalization.localizedString("ai.manager.shannon.prompt.empty") }
        nonisolated static var askShannon: String { AppLocalization.localizedString("ai.manager.shannon.ask") }
        nonisolated static var shannonResponse: String { AppLocalization.localizedString("ai.manager.shannon.response") }
        nonisolated static var shannonResponseEmpty: String { AppLocalization.localizedString("ai.manager.shannon.response.empty") }
        nonisolated static var shannonIdle: String { AppLocalization.localizedString("ai.manager.shannon.status.idle") }
        nonisolated static var shannonRunning: String { AppLocalization.localizedString("ai.manager.shannon.status.running") }
        nonisolated static var shannonWaitingApproval: String { AppLocalization.localizedString("ai.manager.shannon.status.waiting_approval") }
        nonisolated static var shannonCompleted: String { AppLocalization.localizedString("ai.manager.shannon.status.completed") }
        nonisolated static func shannonFailed(_ message: String) -> String { AppLocalization.localizedString("ai.manager.shannon.status.failed", message) }
        nonisolated static var shannonRuntimeUnavailable: String { AppLocalization.localizedString("ai.manager.shannon.runtime_unavailable") }
        nonisolated static var shannonRequestSubmitted: String { AppLocalization.localizedString("ai.manager.shannon.request_submitted") }
        nonisolated static func shannonApprovalNeeded(_ tool: String) -> String { AppLocalization.localizedString("ai.manager.shannon.approval_needed", tool) }
        nonisolated static var shannonApprovalCard: String { AppLocalization.localizedString("ai.manager.shannon.approval_card") }
        nonisolated static var approveAction: String { AppLocalization.localizedString("ai.manager.shannon.approve") }
        nonisolated static var denyAction: String { AppLocalization.localizedString("ai.manager.shannon.deny") }
        nonisolated static var hosts: String { AppLocalization.localizedString("ai.manager.hosts") }
        nonisolated static var openLocalShell: String { AppLocalization.localizedString("ai.manager.hosts.open_local_shell") }
        nonisolated static var reloadSSHConfig: String { AppLocalization.localizedString("ai.manager.hosts.reload_ssh_config") }
        nonisolated static var addSSHHost: String { AppLocalization.localizedString("ai.manager.hosts.add_ssh_host") }
        nonisolated static var newSSHHost: String { AppLocalization.localizedString("ai.manager.hosts.new_ssh_host") }
        nonisolated static var editSSHHost: String { AppLocalization.localizedString("ai.manager.hosts.edit_ssh_host") }
        nonisolated static var displayName: String { AppLocalization.localizedString("ai.manager.hosts.display_name") }
        nonisolated static var sshAlias: String { AppLocalization.localizedString("ai.manager.hosts.ssh_alias") }
        nonisolated static var hostname: String { AppLocalization.localizedString("ai.manager.hosts.hostname") }
        nonisolated static var user: String { AppLocalization.localizedString("ai.manager.hosts.user") }
        nonisolated static var port: String { AppLocalization.localizedString("ai.manager.hosts.port") }
        nonisolated static var defaultDirectory: String { AppLocalization.localizedString("ai.manager.hosts.default_directory") }
        nonisolated static var saveHost: String { AppLocalization.localizedString("ai.manager.hosts.save") }
        nonisolated static var updateHost: String { AppLocalization.localizedString("ai.manager.hosts.update") }
        nonisolated static var hostDetails: String { AppLocalization.localizedString("ai.manager.hosts.details") }
        nonisolated static var noHostSelected: String { AppLocalization.localizedString("ai.manager.hosts.none_selected") }
        nonisolated static var noRecentHostActivity: String { AppLocalization.localizedString("ai.manager.hosts.no_recent_activity") }
        nonisolated static var hostSource: String { AppLocalization.localizedString("ai.manager.hosts.source_label") }
        nonisolated static var hostTarget: String { AppLocalization.localizedString("ai.manager.hosts.target") }
        nonisolated static var duplicateHost: String { AppLocalization.localizedString("ai.manager.hosts.duplicate") }
        nonisolated static var copySuffix: String { AppLocalization.localizedString("ai.manager.hosts.copy_suffix") }
        nonisolated static var hostStatusConnected: String { AppLocalization.localizedString("ai.manager.hosts.status.connected") }
        nonisolated static var hostStatusFailed: String { AppLocalization.localizedString("ai.manager.hosts.status.failed") }
        nonisolated static var hostsEmpty: String { AppLocalization.localizedString("ai.manager.hosts.empty") }
        nonisolated static var searchHosts: String { AppLocalization.localizedString("ai.manager.hosts.search") }
        nonisolated static var favoriteHost: String { AppLocalization.localizedString("ai.manager.hosts.favorite") }
        nonisolated static var removeFavoriteHost: String { AppLocalization.localizedString("ai.manager.hosts.unfavorite") }
        nonisolated static var favoriteHosts: String { AppLocalization.localizedString("ai.manager.hosts.favorites") }
        nonisolated static var recentHosts: String { AppLocalization.localizedString("ai.manager.hosts.recent") }
        nonisolated static var savedHosts: String { AppLocalization.localizedString("ai.manager.hosts.saved") }
        nonisolated static var importedHosts: String { AppLocalization.localizedString("ai.manager.hosts.imported") }
        nonisolated static var savedHostSource: String { AppLocalization.localizedString("ai.manager.hosts.source.saved") }
        nonisolated static var importedHostSource: String { AppLocalization.localizedString("ai.manager.hosts.source.imported") }
        nonisolated static var importedHostOverriddenSource: String { AppLocalization.localizedString("ai.manager.hosts.source.imported_overridden") }
        nonisolated static var connect: String { AppLocalization.localizedString("ai.manager.hosts.connect") }
        nonisolated static var edit: String { AppLocalization.localizedString("ai.manager.edit") }
        nonisolated static var cancelEdit: String { AppLocalization.localizedString("ai.manager.cancel_edit") }
        nonisolated static var remove: String { AppLocalization.localizedString("ai.manager.remove") }
        nonisolated static var resetOverride: String { AppLocalization.localizedString("ai.manager.hosts.reset_override") }
        nonisolated static var workspaces: String { AppLocalization.localizedString("ai.manager.workspaces") }
        nonisolated static var addLocalWorkspace: String { AppLocalization.localizedString("ai.manager.workspaces.add_local") }
        nonisolated static var registerWorkspace: String { AppLocalization.localizedString("ai.manager.workspaces.register") }
        nonisolated static var workspaceName: String { AppLocalization.localizedString("ai.manager.workspaces.name") }
        nonisolated static var host: String { AppLocalization.localizedString("ai.manager.workspaces.host") }
        nonisolated static var directory: String { AppLocalization.localizedString("ai.manager.workspaces.directory") }
        nonisolated static var saveWorkspace: String { AppLocalization.localizedString("ai.manager.workspaces.save") }
        nonisolated static var workspacesEmpty: String { AppLocalization.localizedString("ai.manager.workspaces.empty") }
        nonisolated static var open: String { AppLocalization.localizedString("ai.manager.open") }
        nonisolated static var sessions: String { AppLocalization.localizedString("ai.manager.sessions") }
        nonisolated static var sessionsEmpty: String { AppLocalization.localizedString("ai.manager.sessions.empty") }
        nonisolated static var selected: String { AppLocalization.localizedString("ai.manager.selected") }
        nonisolated static var focused: String { AppLocalization.localizedString("ai.manager.focused") }
        nonisolated static var select: String { AppLocalization.localizedString("ai.manager.select") }
        nonisolated static var focus: String { AppLocalization.localizedString("ai.manager.focus") }
        nonisolated static var createTask: String { AppLocalization.localizedString("ai.manager.create_task") }
        nonisolated static var observe: String { AppLocalization.localizedString("ai.manager.observe") }
        nonisolated static var manage: String { AppLocalization.localizedString("ai.manager.manage") }
        nonisolated static var returnManual: String { AppLocalization.localizedString("ai.manager.return_manual") }
        nonisolated static var selectedSessionControl: String { AppLocalization.localizedString("ai.manager.selected_session_control") }
        nonisolated static var refreshSnapshot: String { AppLocalization.localizedString("ai.manager.refresh_snapshot") }
        nonisolated static var closeTab: String { AppLocalization.localizedString("ai.manager.close_tab") }
        nonisolated static var command: String { AppLocalization.localizedString("ai.manager.command") }
        nonisolated static var commandPlaceholder: String { AppLocalization.localizedString("ai.manager.command.placeholder") }
        nonisolated static var sendCommand: String { AppLocalization.localizedString("ai.manager.send_command") }
        nonisolated static var rawInput: String { AppLocalization.localizedString("ai.manager.raw_input") }
        nonisolated static var sendInput: String { AppLocalization.localizedString("ai.manager.send_input") }
        nonisolated static var visibleBuffer: String { AppLocalization.localizedString("ai.manager.visible_buffer") }
        nonisolated static var visibleBufferEmpty: String { AppLocalization.localizedString("ai.manager.visible_buffer.empty") }
        nonisolated static var screenBuffer: String { AppLocalization.localizedString("ai.manager.screen_buffer") }
        nonisolated static var screenBufferEmpty: String { AppLocalization.localizedString("ai.manager.screen_buffer.empty") }
        nonisolated static var selectedSessionEmpty: String { AppLocalization.localizedString("ai.manager.selected_session.empty") }
        nonisolated static var taskQueue: String { AppLocalization.localizedString("ai.manager.task_queue") }
        nonisolated static var taskQueueEmpty: String { AppLocalization.localizedString("ai.manager.task_queue.empty") }
        nonisolated static var focusSession: String { AppLocalization.localizedString("ai.manager.focus_session") }
        nonisolated static var pause: String { AppLocalization.localizedString("ai.manager.pause") }
        nonisolated static var resume: String { AppLocalization.localizedString("ai.manager.resume") }
        nonisolated static var needApproval: String { AppLocalization.localizedString("ai.manager.need_approval") }
        nonisolated static var complete: String { AppLocalization.localizedString("ai.manager.complete") }
        nonisolated static var fail: String { AppLocalization.localizedString("ai.manager.fail") }
        nonisolated static var addWorkspacePrompt: String { AppLocalization.localizedString("ai.manager.open_panel.add_workspace") }
        nonisolated static var hostMissingSSHDetails: String { AppLocalization.localizedString("ai.manager.error.host_missing_ssh_details") }
        nonisolated static func workspaceUnknownHost(_ name: String) -> String { AppLocalization.localizedString("ai.manager.error.workspace_unknown_host", name) }
        nonisolated static func workspaceInvalidPlan(_ name: String) -> String { AppLocalization.localizedString("ai.manager.error.workspace_invalid_plan", name) }
        nonisolated static var hostNameEmpty: String { AppLocalization.localizedString("ai.manager.error.host_name_empty") }
        nonisolated static var hostMissingAliasOrHostname: String { AppLocalization.localizedString("ai.manager.error.host_missing_alias_or_hostname") }
        nonisolated static var hostInvalidPort: String { AppLocalization.localizedString("ai.manager.error.host_invalid_port") }
        nonisolated static var localMCDCommandsEmpty: String { AppLocalization.localizedString("ai.manager.error.local_mcd_commands_empty") }
        nonisolated static var workspaceNameEmpty: String { AppLocalization.localizedString("ai.manager.error.workspace_name_empty") }
        nonisolated static var workspaceDirectoryEmpty: String { AppLocalization.localizedString("ai.manager.error.workspace_directory_empty") }
        nonisolated static var sessionUnavailable: String { AppLocalization.localizedString("ai.manager.error.session_unavailable") }
        nonisolated static var inputEmpty: String { AppLocalization.localizedString("ai.manager.error.input_empty") }
        nonisolated static var commandEmpty: String { AppLocalization.localizedString("ai.manager.error.command_empty") }
        nonisolated static var selectSessionFirst: String { AppLocalization.localizedString("ai.manager.error.select_session_first") }
        nonisolated static var appDelegateUnavailable: String { AppLocalization.localizedString("ai.manager.error.app_delegate_unavailable") }
        nonisolated static var createSessionFailed: String { AppLocalization.localizedString("ai.manager.error.create_session_failed") }
        nonisolated static func saveConfigurationFailed(_ message: String) -> String { AppLocalization.localizedString("ai.manager.error.save_configuration_failed", message) }
        nonisolated static var manual: String { AppLocalization.localizedString("ai.manager.session.manual") }
        nonisolated static var observed: String { AppLocalization.localizedString("ai.manager.session.observed") }
        nonisolated static var managed: String { AppLocalization.localizedString("ai.manager.session.managed") }
        nonisolated static var awaitingApproval: String { AppLocalization.localizedString("ai.manager.session.awaiting_approval") }
        nonisolated static var paused: String { AppLocalization.localizedString("ai.manager.session.paused") }
        nonisolated static var completed: String { AppLocalization.localizedString("ai.manager.session.completed") }
        nonisolated static var failed: String { AppLocalization.localizedString("ai.manager.session.failed") }
        nonisolated static var newTab: String { AppLocalization.localizedString("ai.manager.launch_target.tab") }
        nonisolated static var newWindow: String { AppLocalization.localizedString("ai.manager.launch_target.window") }
        nonisolated static var thisMac: String { AppLocalization.localizedString("ai.manager.host.local_name") }
        nonisolated static var localShell: String { AppLocalization.localizedString("ai.manager.host.local_shell") }
        nonisolated static var queued: String { AppLocalization.localizedString("ai.manager.task.queued") }
        nonisolated static var active: String { AppLocalization.localizedString("ai.manager.task.active") }
        nonisolated static var supervisorUnavailable: String { AppLocalization.localizedString("ai.manager.supervisor.unavailable") }
        nonisolated static var supervisorStopped: String { AppLocalization.localizedString("ai.manager.supervisor.stopped") }
        nonisolated static var supervisorStarting: String { AppLocalization.localizedString("ai.manager.supervisor.starting") }
        nonisolated static var supervisorRunningEmbedded: String { AppLocalization.localizedString("ai.manager.supervisor.running_embedded") }
        nonisolated static func supervisorRunning(pid: Int32) -> String { AppLocalization.localizedString("ai.manager.supervisor.running", String(pid)) }
        nonisolated static func supervisorFailed(_ message: String) -> String { AppLocalization.localizedString("ai.manager.supervisor.failed", message) }
        nonisolated static func supervisorExitStatus(_ status: Int32) -> String { AppLocalization.localizedString("ai.manager.supervisor.exit_status", String(status)) }
        nonisolated static var runtimeUnavailable: String { AppLocalization.localizedString("ai.manager.runtime.unavailable") }
        nonisolated static var runtimeProbing: String { AppLocalization.localizedString("ai.manager.runtime.probing") }
        nonisolated static var runtimeHealthy: String { AppLocalization.localizedString("ai.manager.runtime.healthy") }
        nonisolated static func runtimeUnreachable(_ message: String) -> String { AppLocalization.localizedString("ai.manager.runtime.unreachable", message) }
        nonisolated static var runtimeGatewayConnected: String { AppLocalization.localizedString("ai.manager.runtime.gateway.connected") }
        nonisolated static var runtimeGatewayDisconnected: String { AppLocalization.localizedString("ai.manager.runtime.gateway.disconnected") }
        nonisolated static var manualSession: String { AppLocalization.localizedString("ai.manager.session.manual_session") }
        nonisolated static var waitingForOperator: String { AppLocalization.localizedString("ai.manager.task.waiting_for_operator") }
        nonisolated static var markedComplete: String { AppLocalization.localizedString("ai.manager.task.marked_complete") }
        nonisolated static var markedFailed: String { AppLocalization.localizedString("ai.manager.task.marked_failed") }
        nonisolated static var sessionClosed: String { AppLocalization.localizedString("ai.manager.task.session_closed") }
        nonisolated static func manageSession(_ title: String) -> String { AppLocalization.localizedString("ai.manager.task.manage_session", title) }
        nonisolated static var defaultTaskTitle: String { AppLocalization.localizedString("ai.manager.task.default_title") }
    }
}
