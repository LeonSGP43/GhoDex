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
        "command_palette.ai_manager.description": "Show the Phase 1 GhoDex + Shannon control center scaffold.",
        "command_palette.ssh_connections.title": "Open: Settings Panel",
        "command_palette.ssh_connections.description": "Open the settings panel for connection center and learning workflow.",
        "command_palette.update.restart": "Update GhoDex and Restart",
        "command_palette.update.cancel": "Cancel or Skip Update",
        "command_palette.update.cancel.description": "Dismiss the current update process",
        "command_palette.focus": "Focus: %@",
        "ai.manager.window.title": "AI Terminal Manager",
        "ai.manager.title": "AI Terminal Manager",
        "ai.manager.subtitle": "GhoDex hosts the terminals; Shannon is prepared as the local orchestration supervisor.",
        "ai.manager.launch": "Launch",
        "ai.manager.supervisor": "Supervisor",
        "ai.manager.supervisor.hint": "GhoDex now treats Shannon as an embedded local brain by default. An external runtime bridge remains optional when `GHOSTTY_SHANNON_PATH` is set.",
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
        "ai.manager.workspaces.save_action": "Save Workspace...",
        "ai.manager.workspaces.save_prompt": "Save the current top-level tab layout so it can be reopened from the New Tab picker.",
        "ai.manager.workspaces.saved_section": "Saved Workspaces",
        "ai.manager.workspaces.saved_item": "Saved Workspace",
        "ai.manager.workspaces.replace_title": "Workspace Already Exists",
        "ai.manager.workspaces.replace_message": "A workspace named \"%@\" already exists. Do you want to replace it?",
        "ai.manager.workspaces.replace": "Replace",
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
        "ai.manager.error.workspace_empty": "Workspace is empty.",
        "ai.manager.error.workspace_duplicate_name": "A workspace with this name already exists.",
        "ai.manager.error.saved_workspace_empty_pane": "Saved workspace contains an empty pane.",
        "ai.manager.error.saved_workspace_unknown_host": "Saved workspace references an unknown host.",
        "ai.manager.error.could_not_save_workspace": "Could Not Save Workspace",
        "ai.manager.error.session_unavailable": "The selected terminal session is no longer available.",
        "ai.manager.error.input_empty": "Input cannot be empty.",
        "ai.manager.error.command_empty": "Command cannot be empty.",
        "ai.manager.error.select_session_first": "Select a terminal session first.",
        "ai.manager.error.app_delegate_unavailable": "GhoDex app delegate is unavailable.",
        "ai.manager.error.create_session_failed": "GhoDex failed to create a new terminal session.",
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
        "ssh.connections.window.title": "Settings Panel",
        "ssh.connections.title": "Settings Panel",
        "ssh.connections.subtitle": "Switch between connection center and learning settings in one place.",
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
        "ssh.connections.tab.connections": "Connection Center",
        "ssh.connections.tab.todo": "Todo",
        "ssh.connections.tab.learning": "Learning Settings",
        "ssh.connections.tab.task_queue": "Task Queue",
        "ssh.connections.page.connections.title": "Connection Center",
        "ssh.connections.page.connections.subtitle": "Manage saved SSH connections, reuse Keychain passwords, and jump back into active remote sessions.",
        "ssh.connections.task_queue.title": "Task Queue",
        "ssh.connections.task_queue.subtitle": "Schedule and run terminal commands through the GhoDex heartbeat queue.",
        "ssh.connections.task_queue.enable": "Enable queue",
        "ssh.connections.task_queue.heartbeat_interval": "Heartbeat Interval (seconds)",
        "ssh.connections.task_queue.max_concurrent": "Max Concurrent: %d",
        "ssh.connections.task_queue.save_settings": "Save Queue Settings",
        "ssh.connections.task_queue.cancel_all": "Cancel All Queued",
        "ssh.connections.task_queue.cancelled_all_message": "Queued tasks cancelled.",
        "ssh.connections.task_queue.clear_finished": "Clear Finished",
        "ssh.connections.task_queue.cleared_finished_message": "Finished tasks cleared.",
        "ssh.connections.task_queue.enqueue_title": "Enqueue Command",
        "ssh.connections.task_queue.schedule_execution": "Schedule execution time",
        "ssh.connections.task_queue.execute_at": "Execute At",
        "ssh.connections.task_queue.enqueue": "Enqueue",
        "ssh.connections.task_queue.task_accepted": "Task accepted: %@",
        "ssh.connections.task_queue.counts": "Counts · queued %d · running %d · done %d · failed %d",
        "ssh.connections.task_queue.empty": "No queue tasks.",
        "ssh.connections.task_queue.saved": "Queue settings saved.",
        "ssh.connections.task_queue.status.queued": "Queued",
        "ssh.connections.task_queue.status.running": "Running",
        "ssh.connections.task_queue.status.done": "Done",
        "ssh.connections.task_queue.status.failed": "Failed",
        "ssh.connections.task_queue.status.cancelled": "Cancelled",
        "ssh.connections.todo.title": "Todo Workspace",
        "ssh.connections.todo.subtitle": "Track today's tasks in a manual-first flow with local daily files.",
        "ssh.connections.todo.enable": "Enable todo workflow",
        "ssh.connections.todo.workspace_root_path": "Todo workspace root path",
        "ssh.connections.todo.workspace_required": "Todo workspace root path is required.",
        "ssh.connections.todo.day_file_path": "Selected day file path",
        "ssh.connections.todo.show_completed_items": "Show completed items",
        "ssh.connections.todo.hide_completed_items": "Hide completed items",
        "ssh.connections.todo.presentation_title": "Presentation",
        "ssh.connections.todo.sidebar_placement": "Cmd+Shift+M panel side",
        "ssh.connections.todo.sidebar_placement_left": "Left",
        "ssh.connections.todo.sidebar_placement_right": "Right",
        "ssh.connections.todo.workspace_overlay_visible": "Show tab quick-look card",
        "ssh.connections.todo.workspace_overlay_placement": "Tab quick-look position",
        "ssh.connections.todo.overlay_top_left": "Top Left",
        "ssh.connections.todo.overlay_top_right": "Top Right",
        "ssh.connections.todo.overlay_bottom_left": "Bottom Left",
        "ssh.connections.todo.overlay_bottom_right": "Bottom Right",
        "ssh.connections.todo.initialize_workspace": "Initialize Todo Workspace",
        "ssh.connections.todo.initialize_workspace_hint": "Create the todo workspace root, creator note, README, and days directory.",
        "ssh.connections.todo.saved": "Todo settings saved.",
        "ssh.connections.todo.initialized_message": "Todo workspace initialized. Created %d file(s), reused %d existing file(s).",
        "ssh.connections.todo.initialize_failed_message": "Todo workspace initialization failed: %@",
        "ssh.connections.todo.add_title": "New task title",
        "ssh.connections.todo.add_notes": "Optional notes",
        "ssh.connections.todo.add_action": "Add Task",
        "ssh.connections.todo.empty": "No tasks for the selected day yet.",
        "ssh.connections.todo.date_yesterday": "Yesterday",
        "ssh.connections.todo.date_today": "Today",
        "ssh.connections.todo.date_tomorrow": "Tomorrow",
        "ssh.connections.todo.summary_title": "Day Summary",
        "ssh.connections.todo.summary_progress": "%d / %d complete · %d%%",
        "ssh.connections.todo.selected_day": "Selected day: %@",
        "ssh.connections.todo.focused_workspace_title": "Focused Tab",
        "ssh.connections.todo.focused_workspace_summary": "%d / %d complete · %d remaining",
        "ssh.connections.todo.focused_workspace_hint": "This summary tracks tasks assigned to the tab that opened the todo panel.",
        "ssh.connections.todo.quick_look_title": "Tab Tasks",
        "ssh.connections.todo.quick_look_empty": "No tasks are assigned to this tab for today.",
        "ssh.connections.todo.quick_look_manage": "Open Todo Panel",
        "ssh.connections.todo.quick_look_summary": "%d / %d complete · %d remaining",
        "ssh.connections.todo.quick_look_more": "%d more task(s)",
        "ssh.connections.todo.timeline_title": "Timeline",
        "ssh.connections.todo.timeline_created": "Created %@",
        "ssh.connections.todo.timeline_created_completed": "Created %@ · Completed %@",
        "ssh.connections.todo.save_settings": "Save Todo Settings",
        "ssh.connections.todo.panel_title": "Todo",
        "ssh.connections.todo.panel_subtitle": "Manage today's tasks without leaving the current tab.",
        "ssh.connections.todo.panel_open_settings": "Open Todo Settings",
        "ssh.connections.todo.panel_close": "Close",
        "ssh.connections.todo.action_save": "Save",
        "ssh.connections.todo.action_complete": "Complete",
        "ssh.connections.todo.action_edit": "Edit",
        "ssh.connections.todo.action_reset": "Reset",
        "ssh.connections.todo.assignment_clear": "Remove Tab Assignment",
        "ssh.connections.todo.assignment_no_tabs": "No live tabs available",
        "ssh.connections.todo.assignment_unassigned": "Unassigned",
        "ssh.connections.todo.assignment_unavailable": "Assigned Tab Unavailable",
        "ssh.connections.todo.title_required": "Enter a task title before saving notes.",
        "ssh.connections.todo.sync_stale_action": "Sync Unfinished",
        "ssh.connections.todo.sync_stale_empty": "No stale unfinished tasks need to be synced into today.",
        "ssh.connections.todo.sync_stale_success": "Synced %d stale unfinished task pointer(s) into today.",
        "ssh.connections.todo.stale_pointer": "Stale unfinished from %@",
        "ssh.connections.learning.title": "Learning Settings",
        "ssh.connections.learning.subtitle": "Configure how selected terminal text is summarized and written into your project knowledge files.",
        "ssh.connections.learning.enable": "Enable Learn action",
        "ssh.connections.learning.prefer_tab_working_directory": "Prefer current tab working directory as project path",
        "ssh.connections.learning.chat_workspace_path": "Chat workspace root path",
        "ssh.connections.learning.chat_workspace_required": "Chat workspace root path is required.",
        "ssh.connections.learning.learn_workspace_auto_path": "Learn workspace path (auto-derived)",
        "ssh.connections.learning.default_project_path": "Default project path",
        "ssh.connections.learning.notes_relative_path": "Knowledge file path (relative to project)",
        "ssh.connections.learning.command_template": "Execution command template",
        "ssh.connections.learning.fast_model": "Fast model",
        "ssh.connections.learning.prompt_template": "Summary prompt template",
        "ssh.connections.learning.supported_placeholders": "Supported placeholders",
        "ssh.connections.learning.context_action": "Learn Selection",
        "ssh.connections.learning.disabled_message": "Learn action is disabled in Learning settings.",
        "ssh.connections.learning.started_message": "Learning command started.",
        "ssh.connections.learning.succeeded_message": "Learning command completed.",
        "ssh.connections.learning.failed_message": "Learning command failed: %@",
        "ssh.connections.learning.permission_denied_message": "Learning command was canceled because execution permission was denied.",
        "ssh.connections.learning.persist_succeeded_message": "Learning completed and knowledge note saved: %@",
        "ssh.connections.learning.persist_failed_message": "Learning command completed, but writing knowledges failed: %@",
        "ssh.connections.learning.initialize_workspace": "Initialize Chat + Learn Workspace",
        "ssh.connections.learning.initialize_confirm_title": "Confirm initialization",
        "ssh.connections.learning.initialize_confirm_message": "Use this path as chat root?\n%@",
        "ssh.connections.learning.initialize_confirm_action": "Initialize now",
        "ssh.connections.learning.initialize_workspace_hint": "Create chat/learn bootstrap files (skills, scripts, and knowledges) under the chat root path.",
        "ssh.connections.learning.initializing": "Initializing workspace...",
        "ssh.connections.learning.initialized_message": "Workspace initialized. Created %d file(s), reused %d existing file(s).",
        "ssh.connections.learning.initialized_with_skill_sync_warning_message": "Workspace initialized. Created %d file(s), reused %d existing file(s), but %d skill repo(s) failed to sync.",
        "ssh.connections.learning.initialize_failed_message": "Workspace initialization failed: %@",
        "ssh.connections.learning.skill_repos.title": "Skill Repository Sync",
        "ssh.connections.learning.skill_repos.subtitle": "Private skill repositories for chat/learn workspaces.",
        "ssh.connections.learning.skill_repos.empty": "No repository status yet. Click Check Updates.",
        "ssh.connections.learning.skill_repos.check_updates": "Check Updates",
        "ssh.connections.learning.skill_repos.pull_updates": "Pull Skills",
        "ssh.connections.learning.skill_repos.checking": "Checking skill repository status...",
        "ssh.connections.learning.skill_repos.pulling": "Pulling skill repositories...",
        "ssh.connections.learning.skill_repos.checked_message": "Skill status checked. Latest %d, updates %d, errors %d.",
        "ssh.connections.learning.skill_repos.pulled_message": "Skill pull completed. Latest %d, updates %d, errors %d.",
        "ssh.connections.learning.skill_repos.status.latest": "Latest",
        "ssh.connections.learning.skill_repos.status.update_available": "Update Available",
        "ssh.connections.learning.skill_repos.status.not_installed": "Not Installed",
        "ssh.connections.learning.skill_repos.status.local_changes": "Local Changes",
        "ssh.connections.learning.skill_repos.status.error": "Error",
        "ssh.connections.learning.save": "Save Learning Settings",
        "ssh.connections.learning.saved": "Learning settings saved.",
        "ssh.connections.learning.log.title": "Learning Log Panel",
        "ssh.connections.learning.log.subtitle": "Recent right-click Learn runs with result status and output summary.",
        "ssh.connections.learning.log.clear": "Clear Logs",
        "ssh.connections.learning.log.empty": "No learning logs yet.",
        "ssh.connections.learning.log.status.success": "Success",
        "ssh.connections.learning.log.status.failure": "Failure",
        "ssh.connections.learning.log.show_details": "Show details",
        "ssh.connections.learning.log.hide_details": "Hide details",
        "ssh.connections.learning.log.exit_code": "Exit code: %d",
        "terminal.notification.bell.title": "Action Required",
        "terminal.notification.bell.body": "Task completed and waiting for your input.",
        "about.tagline": "Fast, native, feature-rich terminal \nemulator pushing modern features.",
        "about.version": "Version",
        "about.build": "Build",
        "about.configuration": "Configuration",
        "about.built_at": "Built At",
        "about.workspace": "Workspace",
        "about.branch": "Branch",
        "about.commit": "Commit",
        "about.fingerprint": "Fingerprint",
        "about.workspace.clean": "Clean",
        "about.workspace.dirty": "Dirty",
        "about.docs": "Docs",
        "about.github": "GitHub",
        "settings.title": "Settings",
        "settings.body": "Language can be configured here. For advanced terminal settings, edit $HOME/.config/ghodex/config.ghodex and restart GhoDex.",
        "settings.general.tab": "General",
        "settings.appearance.tab": "Appearance",
        "settings.gateway.tab": "Gateway",
        "settings.language.title": "App Language",
        "AI Terminal Manager…": "AI Terminal Manager…",
        "Settings Panel…": "Settings Panel…",
        "Connections…": "Connections…",
        "settings.language.description": "Choose a language override for GhoDex. Restart is required for menus, App Intents, and all localized resources to update consistently.",
        "settings.language.option.system": "System",
        "settings.language.option.english": "English",
        "settings.language.option.simplified_chinese": "简体中文",
        "settings.language.restart_required": "Restart GhoDex to apply the language change everywhere.",
        "settings.language.restart_now": "Restart Now",
        "settings.icon.quick_title": "App Logo",
        "settings.icon.quick_description": "Switch the Dock and app logo visually, save it into config, and apply it live after saving.",
        "settings.icon.open_editor": "Open Logo Settings",
        "settings.icon.title": "App Logo",
        "settings.icon.description": "Choose one of the built-in logos and apply it live without editing config by hand.",
        "settings.icon.preview": "Preview",
        "settings.icon.mode": "Logo Source",
        "settings.icon.mode.built_in": "Built-in",
        "settings.icon.mode.custom_file": "Custom File",
        "settings.icon.mode.custom_style": "Custom Style",
        "settings.icon.built_in.title": "Built-in Logos",
        "settings.icon.custom_path": "Custom Icon File",
        "settings.icon.custom_placeholder": "/Users/you/Pictures/GhoDex.icns",
        "settings.icon.custom_help": "Supports PNG, JPEG, ICNS, and any macOS-readable image format. ICNS is the safest choice for a crisp Dock icon.",
        "settings.icon.custom_browse": "Browse…",
        "settings.icon.custom_picker_message": "Choose the image file GhoDex should use as the app icon.",
        "settings.icon.invalid_custom_path": "Choose a valid image file before applying the custom logo.",
        "settings.icon.style.title": "Custom Style",
        "settings.icon.frame": "Frame",
        "settings.icon.frame.aluminum": "Aluminum",
        "settings.icon.frame.beige": "Beige",
        "settings.icon.frame.plastic": "Plastic",
        "settings.icon.frame.chrome": "Chrome",
        "settings.icon.ghost_color": "Ghost Color",
        "settings.icon.screen_colors": "Screen Gradient",
        "settings.icon.add_color": "Add Color Stop",
        "settings.icon.remove_color": "Remove",
        "settings.icon.apply": "Apply Logo",
        "settings.icon.reset": "Reset Draft",
        "settings.icon.pending_changes": "Unsaved logo changes are waiting to be applied.",
        "settings.icon.saved": "Logo settings saved to config.",
        "settings.icon.live_apply": "After saving, GhoDex reloads config and updates the app icon immediately.",
        "settings.icon.option.official": "Official",
        "settings.icon.option.ghodex": "GhoDex",
        "settings.icon.option.banana": "Banana",
        "settings.icon.option.blueprint": "Blueprint",
        "settings.icon.option.chalkboard": "Chalkboard",
        "settings.icon.option.glass": "Glass",
        "settings.icon.option.holographic": "Holographic",
        "settings.icon.option.microchip": "Microchip",
        "settings.icon.option.paper": "Paper",
        "settings.icon.option.retro": "Retro",
        "settings.icon.option.xray": "X-Ray",
        "welcome_setup.window_title": "Welcome Setup",
        "welcome_setup.menu_title": "Welcome Setup...",
        "welcome_setup.title": "Set up GhoDex for your first run",
        "welcome_setup.subtitle": "Configure the paths, browser runtime, and remote control basics that are easiest to miss on a fresh install. You can reopen this assistant anytime from the app menu.",
        "welcome_setup.section.app.title": "App Basics",
        "welcome_setup.section.app.body": "Choose your interface language, built-in icon, and default mouse behavior before you settle into daily use.",
        "welcome_setup.section.learning.title": "Learning Workspace",
        "welcome_setup.section.learning.body": "Point GhoDex at your chat workspace and notes path so learning and scaffolded workspaces land in the right place from day one.",
        "welcome_setup.section.learning.chat_workspace": "Chat Workspace Path",
        "welcome_setup.section.learning.chat_workspace_help": "The learn workspace is derived beside this chat workspace directory.",
        "welcome_setup.section.learning.notes_relative_path": "Notes Relative Path",
        "welcome_setup.section.learning.notes_relative_path_help": "Relative notes paths resolve from the learn workspace. Absolute paths are also supported.",
        "welcome_setup.section.todo.title": "Todo Workspace",
        "welcome_setup.section.todo.body": "Choose where daily todo documents and workspace overlays should be created.",
        "welcome_setup.section.todo.workspace_root_help": "GhoDex writes todo day files and workspace metadata under this root.",
        "welcome_setup.section.browser.title": "Browser Runtime",
        "welcome_setup.section.browser.body": "Browser tabs need a Chromium runtime. Managed paths are the safest default; custom paths are for advanced setups.",
        "welcome_setup.section.browser.runtime.ready": "Browser runtime is ready in this app session.",
        "welcome_setup.section.browser.runtime.unavailable": "No compatible browser runtime is active yet.",
        "welcome_setup.section.browser.runtime.initializing": "Chromium is still initializing for this app session.",
        "welcome_setup.section.browser.runtime.failed": "A runtime was found, but Chromium could not be activated yet. Retry activation or reinstall the managed runtime.",
        "welcome_setup.section.browser.runtime.unsupported": "This build does not support managed CEF runtime activation.",
        "welcome_setup.section.browser.install_runtime": "Install Managed Runtime",
        "welcome_setup.section.browser.retry_activation": "Retry Activation",
        "welcome_setup.section.browser.activation_failed": "Browser runtime installed, but Chromium could not be activated in this app session.",
        "welcome_setup.section.gateway.title": "Remote Control Gateway",
        "welcome_setup.section.gateway.body": "These settings control how GhoDex exposes its harness gateway to local or remote clients.",
        "welcome_setup.footer_note": "This assistant edits the same settings used elsewhere in GhoDex. It does not introduce a second configuration source.",
        "welcome_setup.open_settings": "Open Settings Panel",
        "welcome_setup.apply": "Apply",
        "welcome_setup.finish": "Finish Setup",
        "welcome_setup.saved": "Setup saved.",
        "welcome_setup.saved_restart_required": "Setup saved. Restart GhoDex to fully apply the language change.",
        "welcome_setup.finished": "Setup saved. You can reopen this assistant later from the app menu.",
        "welcome_setup.finished_restart_required": "Setup saved. Restart GhoDex to fully apply the language change; this assistant remains available from the app menu.",
        "settings.browser.title": "Browser Profile",
        "settings.browser.description": "Choose which Chromium profile GhoDex should use for Browser tabs. Leave it on the managed default to keep browser data isolated from Chrome.",
        "settings.browser.profile_section": "Browser Profile",
        "settings.browser.use_managed": "Use GhoDex managed browser profile",
        "settings.browser.managed_path": "Managed profile path",
        "settings.browser.custom_path": "Custom profile path",
        "settings.browser.custom_placeholder": "/Users/you/Library/Application Support/Google/Chrome/Profile 1",
        "settings.browser.custom_hint": "Point this at a dedicated Chromium/Chrome profile directory if you want to reuse cookies and local storage.",
        "settings.browser.runtime_section": "CEF Runtime",
        "settings.browser.runtime_description": "By default GhoDex downloads and manages its own Chromium runtime automatically. Switch to a custom runtime path only if you want to reuse an existing compatible CEF runtime directory.",
        "settings.browser.use_managed_runtime": "Use GhoDex managed Chromium runtime",
        "settings.browser.managed_runtime_path": "Managed runtime path",
        "settings.browser.custom_runtime_path": "Custom runtime path",
        "settings.browser.custom_runtime_placeholder": "/Users/you/Library/Application Support/GhoDex/CEF/current",
        "settings.browser.custom_runtime_hint": "Point this at a compatible CEF runtime root directory that already contains Frameworks/Chromium Embedded Framework.framework.",
        "settings.browser.runtime_media_title": "Media Capability",
        "settings.browser.runtime_media_managed_warning": "The managed CEF runtime is a Chromium-branded distribution and does not provide H.264/AAC playback. Use a custom codec-enabled CEF runtime if you need normal Chrome-like MP4 media parity.",
        "settings.browser.runtime_media_codec_enabled_hint": "This runtime declares H.264/AAC support in its managed descriptor or manifest. Verify it with the browser media acceptance probe before claiming full Chrome-like parity.",
        "settings.browser.runtime_media_chromium_warning": "This runtime appears to be a standard Chromium-branded CEF distribution (%@). H.264/AAC playback is likely unavailable here as well.",
        "settings.browser.runtime_media_custom_hint": "Custom runtime selected. GhoDex cannot verify H.264/AAC support from the path alone. If you need normal Chrome-like media parity, this runtime must come from a codec-enabled CEF build rather than the default Chromium-branded binaries.",
        "settings.browser.browse": "Browse…",
        "settings.browser.save": "Save Browser Settings",
        "settings.browser.saved": "Browser settings saved to config.",
        "settings.browser.restart_required": "Restart GhoDex after changing the browser profile path if Chromium has already been activated in this app session.",
        "settings.browser.invalid_path": "Choose an existing profile directory before saving.",
        "settings.browser.picker_message": "Choose the browser profile directory that Browser tabs should reuse.",
        "settings.browser.invalid_runtime_path": "Choose an existing CEF runtime directory before saving.",
        "settings.browser.runtime_picker_message": "Choose the CEF runtime directory that Browser tabs should use.",
        "settings.mouse_navigation.title": "Mouse Navigation",
        "settings.mouse_navigation.switch_tabs": "Use mouse back/forward buttons to switch top-level tabs",
        "settings.mouse_navigation.description": "When enabled, side buttons on the mouse cycle native macOS top-level tabs in Terminal, Browser, and Workspace Map windows. Leave this off if you want Browser tabs to keep page back/forward behavior.",
        "settings.mouse_navigation.saved": "Mouse navigation setting saved to config.",
        "settings.permissions.title": "macOS Privacy Settings",
        "settings.permissions.description": "Use these shortcuts when GhoDex needs Files and Folders or Full Disk Access. They open the two privacy pages most commonly needed during local development and automation setup.",
        "settings.permissions.signing": "Signing Status",
        "settings.permissions.bundle_identifier": "Bundle ID",
        "settings.permissions.team_identifier": "Team ID",
        "settings.permissions.signer_summary": "Signer",
        "settings.permissions.open_files_and_folders": "Open Files & Folders",
        "settings.permissions.open_full_disk_access": "Open Full Disk Access",
        "settings.permissions.open_settings_failed": "GhoDex could not open the requested macOS privacy settings page.",
        "settings.permissions.signing.unavailable": "Signing details unavailable",
        "settings.permissions.signing.unavailable_detail": "GhoDex could not inspect the current app signature: %@",
        "settings.permissions.signing.adhoc": "Ad hoc / local debug signature",
        "settings.permissions.signing.adhoc_detail": "macOS may treat rebuilt copies of this app as a new binary, so Files and Folders or Full Disk Access approvals can disappear after local rebuilds.",
        "settings.permissions.signing.stable": "Stable signed app",
        "settings.permissions.signing.stable_detail": "This app has a stable signing identity, so macOS privacy grants are more likely to survive relaunches and app updates.",
        "settings.gateway.title": "Control Gateway",
        "settings.gateway.description": "Run the mobile pairing gateway directly inside GhoDex. Changes apply immediately and persist across launches.",
        "settings.gateway.enabled": "Enable gateway on app launch",
        "settings.gateway.show_qr_on_launch": "Show pairing QR when GhoDex launches",
        "settings.gateway.listen_host": "Listen Host",
        "settings.gateway.listen_host.help": "Use 127.0.0.1 for USB plus adb reverse, or 0.0.0.0 / a reachable LAN IP for direct phone access.",
        "settings.gateway.port": "Port",
        "settings.gateway.port.help": "The fixed port keeps one active gateway per machine. If another instance already owns it, this instance stays passive.",
        "settings.gateway.port.invalid": "Enter a valid TCP port between 1 and 65535 before applying gateway settings.",
        "settings.gateway.pairing_host": "Pairing QR Host",
        "settings.gateway.pairing_host.placeholder": "Auto-detect from current LAN address",
        "settings.gateway.pairing_host.help": "Optional override for the host embedded in the pairing QR. Leave blank to auto-detect.",
        "settings.gateway.semantic_profile": "Semantic Extraction Profile",
        "settings.gateway.semantic_profile.help": "Choose how terminal semantic lines are projected for automation and AI reads. Generic is the safest default.",
        "settings.gateway.semantic_profile.generic": "Generic",
        "settings.gateway.semantic_profile.codex": "Codex",
        "settings.gateway.semantic_profile.claude_code": "Claude Code",
        "settings.gateway.status": "Status",
        "settings.gateway.status.disabled": "Disabled",
        "settings.gateway.status.pending": "Applying settings...",
        "settings.gateway.status.listening": "Listening on %@:%d",
        "settings.gateway.status.failed": "Failed to start: %@",
        "settings.gateway.apply": "Apply Gateway Settings",
        "settings.gateway.show_qr": "Show Pairing QR",
        "settings.gateway.pending_changes": "Unsaved gateway changes are waiting to be applied.",
        "app.allow_execute": "Allow GhoDex to execute \"%@\"?",
        "app.undo_action": "Undo %@",
        "app.redo_action": "Redo %@",
        "app.set_default_terminal_failure": "GhoDex could not be set as the default terminal application.\n\nError: %@",
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
        "command_palette.ai_manager.description": "打开 GhoDex + Shannon Phase 1 控制中心原型。",
        "command_palette.ssh_connections.title": "打开：设置面板",
        "command_palette.ssh_connections.description": "打开设置面板，统一管理连接中心与学习设置。",
        "command_palette.update.restart": "更新 GhoDex 并重启",
        "command_palette.update.cancel": "取消或跳过更新",
        "command_palette.update.cancel.description": "关闭当前更新流程",
        "command_palette.focus": "聚焦：%@",
        "ai.manager.window.title": "AI 终端管理器",
        "ai.manager.title": "AI 终端管理器",
        "ai.manager.subtitle": "GhoDex 负责终端宿主；Shannon 作为本地主控编排器预留接入。",
        "ai.manager.launch": "启动方式",
        "ai.manager.supervisor": "主控进程",
        "ai.manager.supervisor.hint": "GhoDex 现在默认把 Shannon 作为内嵌本地主脑运行。只有在设置 `GHOSTTY_SHANNON_PATH` 时，才会启用可选的外部 runtime bridge。",
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
        "ai.manager.workspaces.save_action": "保存工作区...",
        "ai.manager.workspaces.save_prompt": "保存当前顶层标签页布局，以便后续从新建标签选择器中重新打开。",
        "ai.manager.workspaces.saved_section": "已保存工作区",
        "ai.manager.workspaces.saved_item": "已保存工作区",
        "ai.manager.workspaces.replace_title": "工作区已存在",
        "ai.manager.workspaces.replace_message": "名为“%@”的工作区已存在。要替换它吗？",
        "ai.manager.workspaces.replace": "替换",
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
        "ai.manager.error.workspace_empty": "工作区为空。",
        "ai.manager.error.workspace_duplicate_name": "已存在同名工作区。",
        "ai.manager.error.saved_workspace_empty_pane": "已保存工作区包含空面板。",
        "ai.manager.error.saved_workspace_unknown_host": "已保存工作区引用了未知主机。",
        "ai.manager.error.could_not_save_workspace": "无法保存工作区",
        "ai.manager.error.session_unavailable": "选中的终端会话已不可用。",
        "ai.manager.error.input_empty": "输入不能为空。",
        "ai.manager.error.command_empty": "命令不能为空。",
        "ai.manager.error.select_session_first": "请先选择一个终端会话。",
        "ai.manager.error.app_delegate_unavailable": "GhoDex app delegate 不可用。",
        "ai.manager.error.create_session_failed": "GhoDex 创建终端会话失败。",
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
        "ssh.connections.window.title": "设置面板",
        "ssh.connections.title": "设置面板",
        "ssh.connections.subtitle": "在一个面板里快速切换连接中心与学习设置。",
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
        "ssh.connections.tab.connections": "连接中心",
        "ssh.connections.tab.todo": "待办",
        "ssh.connections.tab.learning": "学习设置",
        "ssh.connections.tab.task_queue": "任务队列",
        "ssh.connections.page.connections.title": "连接中心",
        "ssh.connections.page.connections.subtitle": "管理已保存 SSH 连接、复用 Keychain 密码，并快速回到活动中的远程会话。",
        "ssh.connections.task_queue.title": "任务队列",
        "ssh.connections.task_queue.subtitle": "通过 GhoDex 心跳队列调度并运行终端命令。",
        "ssh.connections.task_queue.enable": "启用队列",
        "ssh.connections.task_queue.heartbeat_interval": "心跳间隔（秒）",
        "ssh.connections.task_queue.max_concurrent": "最大并发：%d",
        "ssh.connections.task_queue.save_settings": "保存队列设置",
        "ssh.connections.task_queue.cancel_all": "取消所有排队任务",
        "ssh.connections.task_queue.cancelled_all_message": "已取消所有排队任务。",
        "ssh.connections.task_queue.clear_finished": "清理已完成任务",
        "ssh.connections.task_queue.cleared_finished_message": "已清理已完成任务。",
        "ssh.connections.task_queue.enqueue_title": "添加队列命令",
        "ssh.connections.task_queue.schedule_execution": "设置执行时间",
        "ssh.connections.task_queue.execute_at": "执行时间",
        "ssh.connections.task_queue.enqueue": "加入队列",
        "ssh.connections.task_queue.task_accepted": "任务已接受：%@",
        "ssh.connections.task_queue.counts": "统计 · 排队 %d · 运行中 %d · 完成 %d · 失败 %d",
        "ssh.connections.task_queue.empty": "当前没有队列任务。",
        "ssh.connections.task_queue.saved": "队列设置已保存。",
        "ssh.connections.task_queue.status.queued": "排队中",
        "ssh.connections.task_queue.status.running": "运行中",
        "ssh.connections.task_queue.status.done": "已完成",
        "ssh.connections.task_queue.status.failed": "失败",
        "ssh.connections.task_queue.status.cancelled": "已取消",
        "ssh.connections.todo.title": "待办工作区",
        "ssh.connections.todo.subtitle": "用手动优先的方式管理今日任务，并把每日任务文件保存在本地。",
        "ssh.connections.todo.enable": "启用待办工作流",
        "ssh.connections.todo.workspace_root_path": "待办根目录",
        "ssh.connections.todo.workspace_required": "必须先填写待办根目录。",
        "ssh.connections.todo.day_file_path": "当前日期文件路径",
        "ssh.connections.todo.show_completed_items": "显示已完成任务",
        "ssh.connections.todo.presentation_title": "展示方式",
        "ssh.connections.todo.sidebar_placement": "Cmd+Shift+M 面板位置",
        "ssh.connections.todo.sidebar_placement_left": "左侧",
        "ssh.connections.todo.sidebar_placement_right": "右侧",
        "ssh.connections.todo.workspace_overlay_visible": "显示标签页快速卡片",
        "ssh.connections.todo.workspace_overlay_placement": "标签页快速卡片位置",
        "ssh.connections.todo.overlay_top_left": "左上角",
        "ssh.connections.todo.overlay_top_right": "右上角",
        "ssh.connections.todo.overlay_bottom_left": "左下角",
        "ssh.connections.todo.overlay_bottom_right": "右下角",
        "ssh.connections.todo.initialize_workspace": "初始化待办工作区",
        "ssh.connections.todo.initialize_workspace_hint": "创建 todo 根目录、creator 说明、README 和 days 目录。",
        "ssh.connections.todo.saved": "待办设置已保存。",
        "ssh.connections.todo.initialized_message": "待办工作区初始化完成：新建 %d 个文件，复用 %d 个已存在文件。",
        "ssh.connections.todo.initialize_failed_message": "待办工作区初始化失败：%@",
        "ssh.connections.todo.add_title": "新任务标题",
        "ssh.connections.todo.add_notes": "可选备注",
        "ssh.connections.todo.add_action": "添加任务",
        "ssh.connections.todo.empty": "当前选择日期还没有任务。",
        "ssh.connections.todo.date_yesterday": "昨天",
        "ssh.connections.todo.date_today": "今天",
        "ssh.connections.todo.date_tomorrow": "明天",
        "ssh.connections.todo.summary_title": "日期汇总",
        "ssh.connections.todo.summary_progress": "%d / %d 已完成 · %d%%",
        "ssh.connections.todo.selected_day": "当前日期：%@",
        "ssh.connections.todo.focused_workspace_title": "当前标签页",
        "ssh.connections.todo.focused_workspace_summary": "%d / %d 已完成 · 剩余 %d",
        "ssh.connections.todo.focused_workspace_hint": "这里显示唤起当前待办面板的标签页所分配任务的完成情况。",
        "ssh.connections.todo.quick_look_title": "标签页任务",
        "ssh.connections.todo.quick_look_empty": "这个标签页今天还没有分配任务。",
        "ssh.connections.todo.quick_look_manage": "打开待办面板",
        "ssh.connections.todo.quick_look_summary": "已完成 %d / %d · 剩余 %d",
        "ssh.connections.todo.quick_look_more": "还有 %d 个任务",
        "ssh.connections.todo.timeline_title": "时间轴",
        "ssh.connections.todo.timeline_created": "创建于 %@",
        "ssh.connections.todo.timeline_created_completed": "创建于 %@ · 完成于 %@",
        "ssh.connections.todo.save_settings": "保存待办设置",
        "ssh.connections.todo.panel_title": "待办",
        "ssh.connections.todo.panel_subtitle": "不离开当前标签页就能查看和管理今日任务。",
        "ssh.connections.todo.panel_open_settings": "打开待办设置",
        "ssh.connections.todo.panel_close": "关闭",
        "ssh.connections.todo.action_save": "保存",
        "ssh.connections.todo.action_complete": "完成",
        "ssh.connections.todo.action_edit": "编辑",
        "ssh.connections.todo.action_reset": "重置",
        "ssh.connections.todo.assignment_clear": "移除标签页分配",
        "ssh.connections.todo.assignment_no_tabs": "当前没有可分配的活动标签页",
        "ssh.connections.todo.assignment_unassigned": "未分配",
        "ssh.connections.todo.assignment_unavailable": "已分配标签页不可用",
        "ssh.connections.todo.title_required": "请先填写任务标题，再保存备注。",
        "ssh.connections.todo.sync_stale_action": "同步未完成",
        "ssh.connections.todo.sync_stale_empty": "没有需要同步到今天的陈旧未完成任务。",
        "ssh.connections.todo.sync_stale_success": "已将 %d 个陈旧未完成任务指针同步到今天。",
        "ssh.connections.todo.stale_pointer": "陈旧未完成任务，来自 %@",
        "ssh.connections.learning.title": "学习参数",
        "ssh.connections.learning.subtitle": "配置如何把终端选中文本总结并写入项目知识文件。",
        "ssh.connections.learning.enable": "启用学习动作",
        "ssh.connections.learning.prefer_tab_working_directory": "优先使用当前 tab 工作目录作为项目路径",
        "ssh.connections.learning.chat_workspace_path": "Chat 项目根目录",
        "ssh.connections.learning.chat_workspace_required": "必须先填写 Chat 项目根目录。",
        "ssh.connections.learning.learn_workspace_auto_path": "Learn 项目路径（自动解析）",
        "ssh.connections.learning.default_project_path": "默认项目路径",
        "ssh.connections.learning.notes_relative_path": "知识文件路径（相对项目）",
        "ssh.connections.learning.command_template": "执行命令模板",
        "ssh.connections.learning.fast_model": "快速模型",
        "ssh.connections.learning.prompt_template": "总结提示模板",
        "ssh.connections.learning.supported_placeholders": "可用占位符",
        "ssh.connections.learning.context_action": "学习选中文本",
        "ssh.connections.learning.disabled_message": "学习动作在学习设置中已禁用。",
        "ssh.connections.learning.started_message": "学习命令已开始执行。",
        "ssh.connections.learning.succeeded_message": "学习命令已完成。",
        "ssh.connections.learning.failed_message": "学习命令失败：%@",
        "ssh.connections.learning.permission_denied_message": "学习命令已取消：执行权限被拒绝。",
        "ssh.connections.learning.persist_succeeded_message": "学习已完成，知识笔记已写入：%@",
        "ssh.connections.learning.persist_failed_message": "学习命令已完成，但写入 knowledges 失败：%@",
        "ssh.connections.learning.initialize_workspace": "初始化 Chat + Learn 目录",
        "ssh.connections.learning.initialize_confirm_title": "确认初始化",
        "ssh.connections.learning.initialize_confirm_message": "确认使用以下路径作为 Chat 根目录？\n%@",
        "ssh.connections.learning.initialize_confirm_action": "立即初始化",
        "ssh.connections.learning.initialize_workspace_hint": "在 Chat 根目录下创建 chat/learn 初始化文件（skills、scripts、knowledges）。",
        "ssh.connections.learning.initializing": "正在初始化目录...",
        "ssh.connections.learning.initialized_message": "目录初始化完成：新建 %d 个文件，复用 %d 个已存在文件。",
        "ssh.connections.learning.initialized_with_skill_sync_warning_message": "目录初始化完成：新建 %d 个文件，复用 %d 个已存在文件，但有 %d 个 skill 仓库同步失败。",
        "ssh.connections.learning.initialize_failed_message": "目录初始化失败：%@",
        "ssh.connections.learning.skill_repos.title": "Skill 仓库同步",
        "ssh.connections.learning.skill_repos.subtitle": "用于 chat/learn 的私有 skill 仓库。",
        "ssh.connections.learning.skill_repos.empty": "还没有仓库状态，请先点“检查更新”。",
        "ssh.connections.learning.skill_repos.check_updates": "检查更新",
        "ssh.connections.learning.skill_repos.pull_updates": "拉取 Skills",
        "ssh.connections.learning.skill_repos.checking": "正在检查 skill 仓库状态...",
        "ssh.connections.learning.skill_repos.pulling": "正在拉取 skill 仓库...",
        "ssh.connections.learning.skill_repos.checked_message": "已检查 skill 状态：最新 %d，待更新 %d，错误 %d。",
        "ssh.connections.learning.skill_repos.pulled_message": "已完成 skill 拉取：最新 %d，待更新 %d，错误 %d。",
        "ssh.connections.learning.skill_repos.status.latest": "已最新",
        "ssh.connections.learning.skill_repos.status.update_available": "有更新",
        "ssh.connections.learning.skill_repos.status.not_installed": "未安装",
        "ssh.connections.learning.skill_repos.status.local_changes": "本地有改动",
        "ssh.connections.learning.skill_repos.status.error": "错误",
        "ssh.connections.learning.save": "保存学习设置",
        "ssh.connections.learning.saved": "学习设置已保存。",
        "ssh.connections.learning.log.title": "学习日志面板",
        "ssh.connections.learning.log.subtitle": "记录每次右键学习的成功/失败与输出摘要。",
        "ssh.connections.learning.log.clear": "清空日志",
        "ssh.connections.learning.log.empty": "暂时还没有学习日志。",
        "ssh.connections.learning.log.status.success": "成功",
        "ssh.connections.learning.log.status.failure": "失败",
        "ssh.connections.learning.log.show_details": "展开详情",
        "ssh.connections.learning.log.hide_details": "收起详情",
        "ssh.connections.learning.log.exit_code": "退出码：%d",
        "terminal.notification.bell.title": "等待操作",
        "terminal.notification.bell.body": "任务已完成，等待你的操作。",
        "about.tagline": "快速、原生、功能丰富的终端模拟器，持续推进现代终端体验。",
        "about.version": "版本",
        "about.build": "构建号",
        "about.configuration": "构建配置",
        "about.built_at": "构建时间",
        "about.workspace": "工作区状态",
        "about.branch": "分支",
        "about.commit": "提交",
        "about.fingerprint": "构建指纹",
        "about.workspace.clean": "干净",
        "about.workspace.dirty": "未提交变更",
        "about.docs": "文档",
        "about.github": "GitHub",
        "settings.title": "设置",
        "settings.body": "这里目前可配置应用语言。若要修改高级终端配置，请编辑 $HOME/.config/ghodex/config.ghodex，然后重启 GhoDex。",
        "settings.general.tab": "通用",
        "settings.appearance.tab": "外观",
        "settings.gateway.tab": "网关",
        "settings.language.title": "应用语言",
        "AI Terminal Manager…": "AI 终端管理器…",
        "Settings Panel…": "设置面板…",
        "Connections…": "连接中心…",
        "settings.language.description": "为 GhoDex 选择语言覆盖设置。为了让菜单、App Intents 和所有本地化资源一致更新，需要重启应用。",
        "settings.language.option.system": "跟随系统",
        "settings.language.option.english": "English",
        "settings.language.option.simplified_chinese": "简体中文",
        "settings.language.restart_required": "需要重启 GhoDex，语言变更才会完整应用到所有界面。",
        "settings.language.restart_now": "立即重启",
        "settings.icon.quick_title": "应用 Logo",
        "settings.icon.quick_description": "可视化切换 Dock 和应用 Logo，保存后会写回配置文件并立即生效。",
        "settings.icon.open_editor": "打开 Logo 设置",
        "settings.icon.title": "应用 Logo",
        "settings.icon.description": "直接选择一个内置 Logo，保存后会立即生效，不需要手动改配置。",
        "settings.icon.preview": "预览",
        "settings.icon.mode": "Logo 来源",
        "settings.icon.mode.built_in": "内置",
        "settings.icon.mode.custom_file": "自定义文件",
        "settings.icon.mode.custom_style": "自定义风格",
        "settings.icon.built_in.title": "内置 Logo",
        "settings.icon.custom_path": "自定义图标文件",
        "settings.icon.custom_placeholder": "/Users/you/Pictures/GhoDex.icns",
        "settings.icon.custom_help": "支持 PNG、JPEG、ICNS 以及 macOS 可读取的图片格式。想要 Dock 图标最稳定、最清晰，优先用 ICNS。",
        "settings.icon.custom_browse": "选择…",
        "settings.icon.custom_picker_message": "选择 GhoDex 要使用的应用图标文件。",
        "settings.icon.invalid_custom_path": "应用自定义 Logo 前，请先选择一个有效的图片文件。",
        "settings.icon.style.title": "自定义风格",
        "settings.icon.frame": "边框",
        "settings.icon.frame.aluminum": "铝合金",
        "settings.icon.frame.beige": "米色",
        "settings.icon.frame.plastic": "塑料",
        "settings.icon.frame.chrome": "铬面",
        "settings.icon.ghost_color": "幽灵颜色",
        "settings.icon.screen_colors": "屏幕渐变",
        "settings.icon.add_color": "添加颜色节点",
        "settings.icon.remove_color": "移除",
        "settings.icon.apply": "应用 Logo",
        "settings.icon.reset": "重置草稿",
        "settings.icon.pending_changes": "还有未应用的 Logo 变更。",
        "settings.icon.saved": "Logo 设置已写入配置文件。",
        "settings.icon.live_apply": "保存后 GhoDex 会重载配置，并立即更新应用图标。",
        "settings.icon.option.official": "官方",
        "settings.icon.option.ghodex": "GhoDex",
        "settings.icon.option.banana": "香蕉",
        "settings.icon.option.blueprint": "蓝图",
        "settings.icon.option.chalkboard": "黑板",
        "settings.icon.option.glass": "玻璃",
        "settings.icon.option.holographic": "全息",
        "settings.icon.option.microchip": "芯片",
        "settings.icon.option.paper": "纸质",
        "settings.icon.option.retro": "复古",
        "settings.icon.option.xray": "X 光",
        "welcome_setup.window_title": "欢迎设置",
        "welcome_setup.menu_title": "欢迎设置...",
        "welcome_setup.title": "首次启动时先把 GhoDex 配好",
        "welcome_setup.subtitle": "把最容易遗漏的路径、Browser 运行时和远程控制基础项先配置清楚。后续你也可以随时从应用菜单重新打开这个助手。",
        "welcome_setup.section.app.title": "应用基础",
        "welcome_setup.section.app.body": "先选好界面语言、内置图标和默认鼠标行为，后续日常使用会更顺手。",
        "welcome_setup.section.learning.title": "学习工作区",
        "welcome_setup.section.learning.body": "把聊天工作区和笔记路径先设好，这样学习能力和脚手架工作区会从第一天起就落到正确位置。",
        "welcome_setup.section.learning.chat_workspace": "聊天工作区路径",
        "welcome_setup.section.learning.chat_workspace_help": "learn 工作区会自动生成在这个聊天工作区目录旁边。",
        "welcome_setup.section.learning.notes_relative_path": "笔记相对路径",
        "welcome_setup.section.learning.notes_relative_path_help": "相对路径会以 learn 工作区为基准解析；也支持直接填写绝对路径。",
        "welcome_setup.section.todo.title": "Todo 工作区",
        "welcome_setup.section.todo.body": "选择每天的 todo 文档和工作区覆盖层要写到哪里。",
        "welcome_setup.section.todo.workspace_root_help": "GhoDex 会在这个根目录下写入 todo 日文件和工作区元数据。",
        "welcome_setup.section.browser.title": "Browser 运行时",
        "welcome_setup.section.browser.body": "Browser 标签页需要 Chromium 运行时。托管路径是默认最稳的方式；自定义路径更适合高级场景。",
        "welcome_setup.section.browser.runtime.ready": "当前应用会话中的 Browser 运行时已经就绪。",
        "welcome_setup.section.browser.runtime.unavailable": "当前还没有可用的 Browser 运行时。",
        "welcome_setup.section.browser.runtime.initializing": "Chromium 仍在当前应用会话中初始化。",
        "welcome_setup.section.browser.runtime.failed": "已经找到运行时，但 Chromium 还没成功激活。你可以重试激活，或者重新安装托管运行时。",
        "welcome_setup.section.browser.runtime.unsupported": "当前构建不支持托管 CEF 运行时激活。",
        "welcome_setup.section.browser.install_runtime": "安装托管运行时",
        "welcome_setup.section.browser.retry_activation": "重试激活",
        "welcome_setup.section.browser.activation_failed": "Browser 运行时已经安装，但当前应用会话里还没能成功激活 Chromium。",
        "welcome_setup.section.gateway.title": "远程控制网关",
        "welcome_setup.section.gateway.body": "这些设置决定了 GhoDex 如何把 harness 网关暴露给本地或远程客户端。",
        "welcome_setup.footer_note": "这个助手编辑的是 GhoDex 现有设置本体，不会引入第二套配置来源。",
        "welcome_setup.open_settings": "打开设置面板",
        "welcome_setup.apply": "应用",
        "welcome_setup.finish": "完成设置",
        "welcome_setup.saved": "设置已保存。",
        "welcome_setup.saved_restart_required": "设置已保存。语言变更需要重启 GhoDex 才能完全生效。",
        "welcome_setup.finished": "设置已保存。后续你可以从应用菜单重新打开这个助手。",
        "welcome_setup.finished_restart_required": "设置已保存。语言变更需要重启 GhoDex 才能完全生效；这个助手后续仍可从应用菜单重新打开。",
        "settings.browser.title": "浏览器配置",
        "settings.browser.description": "选择 Browser 标签页使用哪个 Chromium 配置目录。保持为 GhoDex 管理的默认值时，浏览器数据会和 Chrome 隔离。",
        "settings.browser.profile_section": "浏览器配置",
        "settings.browser.use_managed": "使用 GhoDex 托管的浏览器配置",
        "settings.browser.managed_path": "托管配置路径",
        "settings.browser.custom_path": "自定义配置路径",
        "settings.browser.custom_placeholder": "/Users/you/Library/Application Support/Google/Chrome/Profile 1",
        "settings.browser.custom_hint": "如果你想复用 cookie 和本地存储，请指向一个专门给 GhoDex/CEF 使用的 Chromium/Chrome 配置目录。",
        "settings.browser.runtime_section": "CEF 内核",
        "settings.browser.runtime_description": "默认情况下 GhoDex 会自动下载并管理自己的 Chromium 运行时。只有当你想复用一个现成的兼容 CEF 运行时目录时，才切换到自定义路径。",
        "settings.browser.use_managed_runtime": "使用 GhoDex 管理的 Chromium 运行时",
        "settings.browser.managed_runtime_path": "托管运行时路径",
        "settings.browser.custom_runtime_path": "自定义运行时路径",
        "settings.browser.custom_runtime_placeholder": "/Users/you/Library/Application Support/GhoDex/CEF/current",
        "settings.browser.custom_runtime_hint": "请指向一个已经包含 Frameworks/Chromium Embedded Framework.framework 的兼容 CEF 运行时根目录。",
        "settings.browser.runtime_media_title": "媒体能力",
        "settings.browser.runtime_media_managed_warning": "当前托管 CEF 运行时属于 Chromium 品牌分发，不提供 H.264/AAC 播放能力。如果你需要接近正常 Chrome 的 MP4 媒体兼容性，请切换到一个启用了 codec 的自定义 CEF 运行时。",
        "settings.browser.runtime_media_codec_enabled_hint": "这个运行时会在托管描述或清单中声明 H.264/AAC 支持。真正对外宣称接近 Chrome 之前，仍应先跑 browser media acceptance probe 做实测确认。",
        "settings.browser.runtime_media_chromium_warning": "这个运行时看起来仍然是标准的 Chromium 品牌 CEF 分发（%@）。这里同样很可能不支持 H.264/AAC 播放。",
        "settings.browser.runtime_media_custom_hint": "当前选择的是自定义运行时。仅凭路径 GhoDex 无法直接验证它是否支持 H.264/AAC；如果你需要接近正常 Chrome 的媒体兼容性，这个运行时必须来自启用了 codec 的 CEF 构建，而不是默认的 Chromium 品牌二进制包。",
        "settings.browser.browse": "选择…",
        "settings.browser.save": "保存浏览器设置",
        "settings.browser.saved": "浏览器设置已写入配置文件。",
        "settings.browser.restart_required": "如果本次会话里 Chromium 已经启动过，修改浏览器配置目录后需要重启 GhoDex 才能完整生效。",
        "settings.browser.invalid_path": "保存前请选择一个已存在的配置目录。",
        "settings.browser.picker_message": "选择 Browser 标签页要复用的浏览器配置目录。",
        "settings.browser.invalid_runtime_path": "保存前请选择一个已存在的 CEF 运行时目录。",
        "settings.browser.runtime_picker_message": "选择 Browser 标签页要使用的 CEF 运行时根目录。",
        "settings.mouse_navigation.title": "鼠标导航",
        "settings.mouse_navigation.switch_tabs": "使用鼠标前进/回退按钮切换顶层标签页",
        "settings.mouse_navigation.description": "开启后，鼠标侧键会在 Terminal、Browser 和 Workspace Map 窗口的原生 macOS 顶层标签页之间循环切换。如果你希望 Browser 标签页继续保留网页前进/回退行为，请保持关闭。",
        "settings.mouse_navigation.saved": "鼠标导航设置已写入配置文件。",
        "settings.permissions.title": "macOS 隐私设置",
        "settings.permissions.description": "当 GhoDex 需要“文件与文件夹”或“完全磁盘访问权限”时，可用这里的快捷入口直接跳转。这两个入口覆盖了本地开发和自动化场景里最常用的权限页面。",
        "settings.permissions.signing": "签名状态",
        "settings.permissions.bundle_identifier": "Bundle ID",
        "settings.permissions.team_identifier": "Team ID",
        "settings.permissions.signer_summary": "签名者",
        "settings.permissions.open_files_and_folders": "打开“文件与文件夹”",
        "settings.permissions.open_full_disk_access": "打开“完全磁盘访问权限”",
        "settings.permissions.open_settings_failed": "GhoDex 无法打开目标 macOS 隐私设置页面。",
        "settings.permissions.signing.unavailable": "无法读取签名信息",
        "settings.permissions.signing.unavailable_detail": "GhoDex 无法检查当前应用的签名信息：%@",
        "settings.permissions.signing.adhoc": "Ad hoc / 本地调试签名",
        "settings.permissions.signing.adhoc_detail": "macOS 可能会把重编译后的这个应用视为新的二进制，因此“文件与文件夹”或“完全磁盘访问权限”的授权在本地重新构建后可能丢失。",
        "settings.permissions.signing.stable": "稳定签名应用",
        "settings.permissions.signing.stable_detail": "这个应用拥有稳定的签名身份，因此 macOS 隐私授权更有可能在重启和应用更新后继续保留。",
        "settings.gateway.title": "控制网关",
        "settings.gateway.description": "直接在 GhoDex 内运行移动端配对网关。修改会立即生效，并在下次启动时继续保留。",
        "settings.gateway.enabled": "启动应用时自动启用网关",
        "settings.gateway.show_qr_on_launch": "启动 GhoDex 时自动显示配对二维码",
        "settings.gateway.listen_host": "监听地址",
        "settings.gateway.listen_host.help": "USB 调试配合 adb reverse 时用 127.0.0.1；手机直连时用 0.0.0.0 或可达的局域网 IP。",
        "settings.gateway.port": "端口",
        "settings.gateway.port.help": "固定端口可以保证一台机器只保留一个活动网关。如果端口已被别的实例占用，这个实例会保持被动状态。",
        "settings.gateway.port.invalid": "应用网关设置前请输入 1 到 65535 之间的有效 TCP 端口。",
        "settings.gateway.pairing_host": "配对二维码主机地址",
        "settings.gateway.pairing_host.placeholder": "默认自动探测当前局域网地址",
        "settings.gateway.pairing_host.help": "可选。覆盖二维码里编码的主机地址；留空时自动探测。",
        "settings.gateway.semantic_profile": "语义提取模式",
        "settings.gateway.semantic_profile.help": "选择终端语义行的提取策略，供自动化与 AI 读取使用。Generic 兼容性最好。",
        "settings.gateway.semantic_profile.generic": "通用",
        "settings.gateway.semantic_profile.codex": "Codex",
        "settings.gateway.semantic_profile.claude_code": "Claude Code",
        "settings.gateway.status": "状态",
        "settings.gateway.status.disabled": "已禁用",
        "settings.gateway.status.pending": "正在应用设置...",
        "settings.gateway.status.listening": "正在监听 %@:%d",
        "settings.gateway.status.failed": "启动失败：%@",
        "settings.gateway.apply": "应用网关设置",
        "settings.gateway.show_qr": "显示配对二维码",
        "settings.gateway.pending_changes": "还有未应用的网关变更。",
        "app.allow_execute": "允许 GhoDex 执行“%@”吗？",
        "app.undo_action": "撤销 %@",
        "app.redo_action": "重做 %@",
        "app.set_default_terminal_failure": "无法将 GhoDex 设为默认终端应用。\n\n错误：%@",
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
        "About GhoDex": "关于 GhoDex",
        "Check for Updates...": "检查更新...",
        "Preferences…": "偏好设置…",
        "Open Config": "打开配置文件",
        "AI Terminal Manager…": "AI 终端管理器…",
        "Settings Panel…": "设置面板…",
        "Connections…": "连接中心…",
        "Reload Configuration": "重新加载配置",
        "Secure Keyboard Entry": "安全键盘输入",
        "Make GhoDex the Default Terminal": "将 GhoDex 设为默认终端",
        "Services": "服务",
        "Hide GhoDex": "隐藏 GhoDex",
        "Hide Others": "隐藏其他",
        "Show All": "显示全部",
        "Quit GhoDex": "退出 GhoDex",
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
        "GhoDex Help": "GhoDex 帮助",
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
        "Something went fatally wrong.\nCheck the logs and restart GhoDex.": "发生了严重错误。\n请检查日志并重新启动 GhoDex。",
        "Loading": "加载中",
        "You're running a debug build of GhoDex! Performance will be degraded.": "你正在运行 GhoDex 的调试构建版本，性能会下降。",
        "Debug builds of GhoDex are very slow and you may experience performance problems. Debug builds are only recommended during development.": "GhoDex 的调试构建非常慢，你可能会遇到性能问题。调试构建仅建议在开发期间使用。",
        "Debug build warning": "调试构建警告",
        "Enable automatic updates?": "启用自动更新？",
        "Enable Automatic Updates?": "启用自动更新？",
        "GhoDex can automatically check for updates in the background.": "GhoDex 可以在后台自动检查更新。",
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
        "GhoDex Application Icon": "GhoDex 应用图标",
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
        "Secure Input is active. Secure Input is a macOS security feature that prevents applications from reading keyboard events. This is enabled automatically whenever GhoDex detects a password prompt in the terminal, or at all times if `GhoDex > Secure Keyboard Entry` is active.": "安全输入已启用。安全输入是 macOS 的一项安全特性，可防止应用读取键盘事件。每当 GhoDex 检测到终端中的密码提示时会自动启用；如果 `GhoDex > 安全键盘输入` 处于启用状态，则会始终开启。",
        "Terminal pane": "终端面板",
        "Cannot Create New Tab": "无法新建标签页",
        "Tabs aren't supported in the Quick Terminal.": "快捷终端不支持标签页。",
        "Close Terminal?": "关闭终端？",
        "The terminal still has a running process. If you close the terminal the process will be killed.": "该终端仍有进程在运行。若关闭终端，该进程将被终止。",
        "Close All Windows?": "关闭所有窗口？",
        "Quit GhoDex?": "退出 GhoDex？",
        "All terminal sessions will be terminated.": "所有终端会话都将被终止。",
        "All open tabs and terminal sessions will be closed.": "所有打开的标签页和终端会话都将被关闭。",
        "Close GhoDex": "关闭 GhoDex",
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
        "The GhoDex app isn't properly initialized.": "GhoDex 应用未正确初始化。",
        "The terminal no longer exists.": "该终端已不存在。",
        "GhoDex doesn't allow Shortcuts.": "GhoDex 不允许快捷指令访问。",
        "Allow Shortcuts to interact with GhoDex?": "允许快捷指令与 GhoDex 交互吗？",
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
        nonisolated static var configuration: String { AppLocalization.localizedString("about.configuration") }
        nonisolated static var builtAt: String { AppLocalization.localizedString("about.built_at") }
        nonisolated static var workspace: String { AppLocalization.localizedString("about.workspace") }
        nonisolated static var branch: String { AppLocalization.localizedString("about.branch") }
        nonisolated static var commit: String { AppLocalization.localizedString("about.commit") }
        nonisolated static var fingerprint: String { AppLocalization.localizedString("about.fingerprint") }
        nonisolated static var workspaceClean: String { AppLocalization.localizedString("about.workspace.clean") }
        nonisolated static var workspaceDirty: String { AppLocalization.localizedString("about.workspace.dirty") }
        nonisolated static var docs: String { AppLocalization.localizedString("about.docs") }
        nonisolated static var github: String { AppLocalization.localizedString("about.github") }
    }

    enum Settings {
        nonisolated static var title: String { AppLocalization.localizedString("settings.title") }
        nonisolated static var body: String { AppLocalization.localizedString("settings.body") }
        nonisolated static var generalTab: String { AppLocalization.localizedString("settings.general.tab") }
        nonisolated static var appearanceTab: String { AppLocalization.localizedString("settings.appearance.tab") }
        nonisolated static var gatewayTab: String { AppLocalization.localizedString("settings.gateway.tab") }
        nonisolated static var languageTitle: String { AppLocalization.localizedString("settings.language.title") }
        nonisolated static var languageDescription: String { AppLocalization.localizedString("settings.language.description") }
        nonisolated static var languageOptionSystem: String { AppLocalization.localizedString("settings.language.option.system") }
        nonisolated static var languageOptionEnglish: String { AppLocalization.localizedString("settings.language.option.english") }
        nonisolated static var languageOptionSimplifiedChinese: String { AppLocalization.localizedString("settings.language.option.simplified_chinese") }
        nonisolated static var languageRestartRequired: String { AppLocalization.localizedString("settings.language.restart_required") }
        nonisolated static var restartNow: String { AppLocalization.localizedString("settings.language.restart_now") }
        nonisolated static var iconQuickTitle: String { AppLocalization.localizedString("settings.icon.quick_title") }
        nonisolated static var iconQuickDescription: String { AppLocalization.localizedString("settings.icon.quick_description") }
        nonisolated static var iconOpenEditor: String { AppLocalization.localizedString("settings.icon.open_editor") }
        nonisolated static var iconTitle: String { AppLocalization.localizedString("settings.icon.title") }
        nonisolated static var iconDescription: String { AppLocalization.localizedString("settings.icon.description") }
        nonisolated static var iconPreview: String { AppLocalization.localizedString("settings.icon.preview") }
        nonisolated static var iconModeTitle: String { AppLocalization.localizedString("settings.icon.mode") }
        nonisolated static var iconModeBuiltIn: String { AppLocalization.localizedString("settings.icon.mode.built_in") }
        nonisolated static var iconModeCustomFile: String { AppLocalization.localizedString("settings.icon.mode.custom_file") }
        nonisolated static var iconModeCustomStyle: String { AppLocalization.localizedString("settings.icon.mode.custom_style") }
        nonisolated static var iconBuiltInTitle: String { AppLocalization.localizedString("settings.icon.built_in.title") }
        nonisolated static var iconCustomPath: String { AppLocalization.localizedString("settings.icon.custom_path") }
        nonisolated static var iconCustomPlaceholder: String { AppLocalization.localizedString("settings.icon.custom_placeholder") }
        nonisolated static var iconCustomHelp: String { AppLocalization.localizedString("settings.icon.custom_help") }
        nonisolated static var iconCustomBrowse: String { AppLocalization.localizedString("settings.icon.custom_browse") }
        nonisolated static var iconCustomPickerMessage: String { AppLocalization.localizedString("settings.icon.custom_picker_message") }
        nonisolated static var iconInvalidCustomPath: String { AppLocalization.localizedString("settings.icon.invalid_custom_path") }
        nonisolated static var iconStyleTitle: String { AppLocalization.localizedString("settings.icon.style.title") }
        nonisolated static var iconFrame: String { AppLocalization.localizedString("settings.icon.frame") }
        nonisolated static var iconFrameAluminum: String { AppLocalization.localizedString("settings.icon.frame.aluminum") }
        nonisolated static var iconFrameBeige: String { AppLocalization.localizedString("settings.icon.frame.beige") }
        nonisolated static var iconFramePlastic: String { AppLocalization.localizedString("settings.icon.frame.plastic") }
        nonisolated static var iconFrameChrome: String { AppLocalization.localizedString("settings.icon.frame.chrome") }
        nonisolated static var iconGhostColor: String { AppLocalization.localizedString("settings.icon.ghost_color") }
        nonisolated static var iconScreenColors: String { AppLocalization.localizedString("settings.icon.screen_colors") }
        nonisolated static var iconAddColor: String { AppLocalization.localizedString("settings.icon.add_color") }
        nonisolated static var iconRemoveColor: String { AppLocalization.localizedString("settings.icon.remove_color") }
        nonisolated static var iconApply: String { AppLocalization.localizedString("settings.icon.apply") }
        nonisolated static var iconReset: String { AppLocalization.localizedString("settings.icon.reset") }
        nonisolated static var iconPendingChanges: String { AppLocalization.localizedString("settings.icon.pending_changes") }
        nonisolated static var iconSaved: String { AppLocalization.localizedString("settings.icon.saved") }
        nonisolated static var iconLiveApply: String { AppLocalization.localizedString("settings.icon.live_apply") }
        nonisolated static var iconOptionOfficial: String { AppLocalization.localizedString("settings.icon.option.official") }
        nonisolated static var iconOptionGhodex: String { AppLocalization.localizedString("settings.icon.option.ghodex") }
        nonisolated static var iconOptionBanana: String { AppLocalization.localizedString("settings.icon.option.banana") }
        nonisolated static var iconOptionBlueprint: String { AppLocalization.localizedString("settings.icon.option.blueprint") }
        nonisolated static var iconOptionChalkboard: String { AppLocalization.localizedString("settings.icon.option.chalkboard") }
        nonisolated static var iconOptionGlass: String { AppLocalization.localizedString("settings.icon.option.glass") }
        nonisolated static var iconOptionHolographic: String { AppLocalization.localizedString("settings.icon.option.holographic") }
        nonisolated static var iconOptionMicrochip: String { AppLocalization.localizedString("settings.icon.option.microchip") }
        nonisolated static var iconOptionPaper: String { AppLocalization.localizedString("settings.icon.option.paper") }
        nonisolated static var iconOptionRetro: String { AppLocalization.localizedString("settings.icon.option.retro") }
        nonisolated static var iconOptionXray: String { AppLocalization.localizedString("settings.icon.option.xray") }
        nonisolated static var browserTitle: String { AppLocalization.localizedString("settings.browser.title") }
        nonisolated static var browserDescription: String { AppLocalization.localizedString("settings.browser.description") }
        nonisolated static var browserProfileSectionTitle: String { AppLocalization.localizedString("settings.browser.profile_section") }
        nonisolated static var browserUseManagedProfile: String { AppLocalization.localizedString("settings.browser.use_managed") }
        nonisolated static var browserManagedPath: String { AppLocalization.localizedString("settings.browser.managed_path") }
        nonisolated static var browserCustomPath: String { AppLocalization.localizedString("settings.browser.custom_path") }
        nonisolated static var browserCustomPlaceholder: String { AppLocalization.localizedString("settings.browser.custom_placeholder") }
        nonisolated static var browserCustomHint: String { AppLocalization.localizedString("settings.browser.custom_hint") }
        nonisolated static var browserRuntimeSectionTitle: String { AppLocalization.localizedString("settings.browser.runtime_section") }
        nonisolated static var browserRuntimeDescription: String { AppLocalization.localizedString("settings.browser.runtime_description") }
        nonisolated static var browserUseManagedRuntime: String { AppLocalization.localizedString("settings.browser.use_managed_runtime") }
        nonisolated static var browserManagedRuntimePath: String { AppLocalization.localizedString("settings.browser.managed_runtime_path") }
        nonisolated static var browserCustomRuntimePath: String { AppLocalization.localizedString("settings.browser.custom_runtime_path") }
        nonisolated static var browserCustomRuntimePlaceholder: String { AppLocalization.localizedString("settings.browser.custom_runtime_placeholder") }
        nonisolated static var browserCustomRuntimeHint: String { AppLocalization.localizedString("settings.browser.custom_runtime_hint") }
        nonisolated static var browserRuntimeMediaTitle: String { AppLocalization.localizedString("settings.browser.runtime_media_title") }
        nonisolated static var browserRuntimeMediaManagedWarning: String { AppLocalization.localizedString("settings.browser.runtime_media_managed_warning") }
        nonisolated static var browserRuntimeMediaCodecEnabledHint: String { AppLocalization.localizedString("settings.browser.runtime_media_codec_enabled_hint") }
        nonisolated static func browserRuntimeMediaChromiumWarning(_ source: String) -> String {
            AppLocalization.localizedString("settings.browser.runtime_media_chromium_warning", source)
        }
        nonisolated static var browserRuntimeMediaCustomHint: String { AppLocalization.localizedString("settings.browser.runtime_media_custom_hint") }
        nonisolated static var browserBrowseButton: String { AppLocalization.localizedString("settings.browser.browse") }
        nonisolated static var browserSaveButton: String { AppLocalization.localizedString("settings.browser.save") }
        nonisolated static var browserSaved: String { AppLocalization.localizedString("settings.browser.saved") }
        nonisolated static var browserRestartRequired: String { AppLocalization.localizedString("settings.browser.restart_required") }
        nonisolated static var browserInvalidPath: String { AppLocalization.localizedString("settings.browser.invalid_path") }
        nonisolated static var browserPickerMessage: String { AppLocalization.localizedString("settings.browser.picker_message") }
        nonisolated static var browserInvalidRuntimePath: String { AppLocalization.localizedString("settings.browser.invalid_runtime_path") }
        nonisolated static var browserRuntimePickerMessage: String { AppLocalization.localizedString("settings.browser.runtime_picker_message") }
        nonisolated static var mouseNavigationTitle: String { AppLocalization.localizedString("settings.mouse_navigation.title") }
        nonisolated static var mouseNavigationSwitchTabs: String { AppLocalization.localizedString("settings.mouse_navigation.switch_tabs") }
        nonisolated static var mouseNavigationDescription: String { AppLocalization.localizedString("settings.mouse_navigation.description") }
        nonisolated static var mouseNavigationSaved: String { AppLocalization.localizedString("settings.mouse_navigation.saved") }
        nonisolated static var permissionsTitle: String { AppLocalization.localizedString("settings.permissions.title") }
        nonisolated static var permissionsDescription: String { AppLocalization.localizedString("settings.permissions.description") }
        nonisolated static var permissionsSigningTitle: String { AppLocalization.localizedString("settings.permissions.signing") }
        nonisolated static var permissionsBundleIdentifier: String { AppLocalization.localizedString("settings.permissions.bundle_identifier") }
        nonisolated static var permissionsTeamIdentifier: String { AppLocalization.localizedString("settings.permissions.team_identifier") }
        nonisolated static var permissionsSignerSummary: String { AppLocalization.localizedString("settings.permissions.signer_summary") }
        nonisolated static var permissionsOpenFilesAndFolders: String { AppLocalization.localizedString("settings.permissions.open_files_and_folders") }
        nonisolated static var permissionsOpenFullDiskAccess: String { AppLocalization.localizedString("settings.permissions.open_full_disk_access") }
        nonisolated static var permissionsOpenSettingsFailed: String { AppLocalization.localizedString("settings.permissions.open_settings_failed") }
        nonisolated static var permissionsSigningUnavailable: String { AppLocalization.localizedString("settings.permissions.signing.unavailable") }
        nonisolated static func permissionsUnavailableDetail(_ message: String) -> String {
            AppLocalization.localizedString("settings.permissions.signing.unavailable_detail", message)
        }
        nonisolated static var permissionsSigningAdhoc: String { AppLocalization.localizedString("settings.permissions.signing.adhoc") }
        nonisolated static var permissionsAdhocDetail: String { AppLocalization.localizedString("settings.permissions.signing.adhoc_detail") }
        nonisolated static var permissionsSigningStable: String { AppLocalization.localizedString("settings.permissions.signing.stable") }
        nonisolated static var permissionsStableDetail: String { AppLocalization.localizedString("settings.permissions.signing.stable_detail") }
        nonisolated static var gatewayTitle: String { AppLocalization.localizedString("settings.gateway.title") }
        nonisolated static var gatewayDescription: String { AppLocalization.localizedString("settings.gateway.description") }
        nonisolated static var gatewayEnabled: String { AppLocalization.localizedString("settings.gateway.enabled") }
        nonisolated static var gatewayShowQrOnLaunch: String { AppLocalization.localizedString("settings.gateway.show_qr_on_launch") }
        nonisolated static var gatewayListenHost: String { AppLocalization.localizedString("settings.gateway.listen_host") }
        nonisolated static var gatewayListenHostHelp: String { AppLocalization.localizedString("settings.gateway.listen_host.help") }
        nonisolated static var gatewayPort: String { AppLocalization.localizedString("settings.gateway.port") }
        nonisolated static var gatewayPortHelp: String { AppLocalization.localizedString("settings.gateway.port.help") }
        nonisolated static var gatewayPortInvalid: String { AppLocalization.localizedString("settings.gateway.port.invalid") }
        nonisolated static var gatewayPairingHost: String { AppLocalization.localizedString("settings.gateway.pairing_host") }
        nonisolated static var gatewayPairingHostPlaceholder: String { AppLocalization.localizedString("settings.gateway.pairing_host.placeholder") }
        nonisolated static var gatewayPairingHostHelp: String { AppLocalization.localizedString("settings.gateway.pairing_host.help") }
        nonisolated static var gatewaySemanticProfile: String { AppLocalization.localizedString("settings.gateway.semantic_profile") }
        nonisolated static var gatewaySemanticProfileHelp: String { AppLocalization.localizedString("settings.gateway.semantic_profile.help") }
        nonisolated static var gatewaySemanticProfileGeneric: String { AppLocalization.localizedString("settings.gateway.semantic_profile.generic") }
        nonisolated static var gatewaySemanticProfileCodex: String { AppLocalization.localizedString("settings.gateway.semantic_profile.codex") }
        nonisolated static var gatewaySemanticProfileClaudeCode: String { AppLocalization.localizedString("settings.gateway.semantic_profile.claude_code") }
        nonisolated static var gatewayStatus: String { AppLocalization.localizedString("settings.gateway.status") }
        nonisolated static var gatewayStatusDisabled: String { AppLocalization.localizedString("settings.gateway.status.disabled") }
        nonisolated static var gatewayStatusPending: String { AppLocalization.localizedString("settings.gateway.status.pending") }
        nonisolated static func gatewayStatusListening(_ host: String, _ port: Int) -> String { AppLocalization.localizedString("settings.gateway.status.listening", host, port) }
        nonisolated static func gatewayStatusFailed(_ error: String) -> String { AppLocalization.localizedString("settings.gateway.status.failed", error) }
        nonisolated static var gatewayApply: String { AppLocalization.localizedString("settings.gateway.apply") }
        nonisolated static var gatewayShowQr: String { AppLocalization.localizedString("settings.gateway.show_qr") }
        nonisolated static var gatewayPendingChanges: String { AppLocalization.localizedString("settings.gateway.pending_changes") }
    }

    enum WelcomeSetup {
        nonisolated static var windowTitle: String { AppLocalization.localizedString("welcome_setup.window_title") }
        nonisolated static var menuTitle: String { AppLocalization.localizedString("welcome_setup.menu_title") }
        nonisolated static var title: String { AppLocalization.localizedString("welcome_setup.title") }
        nonisolated static var subtitle: String { AppLocalization.localizedString("welcome_setup.subtitle") }
        nonisolated static var appSectionTitle: String { AppLocalization.localizedString("welcome_setup.section.app.title") }
        nonisolated static var appSectionBody: String { AppLocalization.localizedString("welcome_setup.section.app.body") }
        nonisolated static var learningSectionTitle: String { AppLocalization.localizedString("welcome_setup.section.learning.title") }
        nonisolated static var learningSectionBody: String { AppLocalization.localizedString("welcome_setup.section.learning.body") }
        nonisolated static var learningChatWorkspace: String { AppLocalization.localizedString("welcome_setup.section.learning.chat_workspace") }
        nonisolated static var learningChatWorkspaceHelp: String { AppLocalization.localizedString("welcome_setup.section.learning.chat_workspace_help") }
        nonisolated static var learningNotesRelativePath: String { AppLocalization.localizedString("welcome_setup.section.learning.notes_relative_path") }
        nonisolated static var learningNotesRelativePathHelp: String { AppLocalization.localizedString("welcome_setup.section.learning.notes_relative_path_help") }
        nonisolated static var todoSectionTitle: String { AppLocalization.localizedString("welcome_setup.section.todo.title") }
        nonisolated static var todoSectionBody: String { AppLocalization.localizedString("welcome_setup.section.todo.body") }
        nonisolated static var todoWorkspaceRootHelp: String { AppLocalization.localizedString("welcome_setup.section.todo.workspace_root_help") }
        nonisolated static var browserSectionTitle: String { AppLocalization.localizedString("welcome_setup.section.browser.title") }
        nonisolated static var browserSectionBody: String { AppLocalization.localizedString("welcome_setup.section.browser.body") }
        nonisolated static var browserRuntimeReady: String { AppLocalization.localizedString("welcome_setup.section.browser.runtime.ready") }
        nonisolated static var browserRuntimeUnavailable: String { AppLocalization.localizedString("welcome_setup.section.browser.runtime.unavailable") }
        nonisolated static var browserRuntimeInitializing: String { AppLocalization.localizedString("welcome_setup.section.browser.runtime.initializing") }
        nonisolated static var browserRuntimeFailed: String { AppLocalization.localizedString("welcome_setup.section.browser.runtime.failed") }
        nonisolated static var browserRuntimeUnsupported: String { AppLocalization.localizedString("welcome_setup.section.browser.runtime.unsupported") }
        nonisolated static var browserInstallRuntime: String { AppLocalization.localizedString("welcome_setup.section.browser.install_runtime") }
        nonisolated static var browserRetryActivation: String { AppLocalization.localizedString("welcome_setup.section.browser.retry_activation") }
        nonisolated static var browserRuntimeActivationFailed: String { AppLocalization.localizedString("welcome_setup.section.browser.activation_failed") }
        nonisolated static var gatewaySectionTitle: String { AppLocalization.localizedString("welcome_setup.section.gateway.title") }
        nonisolated static var gatewaySectionBody: String { AppLocalization.localizedString("welcome_setup.section.gateway.body") }
        nonisolated static var footerNote: String { AppLocalization.localizedString("welcome_setup.footer_note") }
        nonisolated static var openSettings: String { AppLocalization.localizedString("welcome_setup.open_settings") }
        nonisolated static var apply: String { AppLocalization.localizedString("welcome_setup.apply") }
        nonisolated static var finish: String { AppLocalization.localizedString("welcome_setup.finish") }
        nonisolated static var saved: String { AppLocalization.localizedString("welcome_setup.saved") }
        nonisolated static var savedRestartRequired: String { AppLocalization.localizedString("welcome_setup.saved_restart_required") }
        nonisolated static var finished: String { AppLocalization.localizedString("welcome_setup.finished") }
        nonisolated static var finishedRestartRequired: String { AppLocalization.localizedString("welcome_setup.finished_restart_required") }
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
        nonisolated static var closeGhostty: String { AppLocalization.localizedText("Close GhoDex") }
        nonisolated static var quitGhostty: String { AppLocalization.localizedText("Quit GhoDex?") }
        nonisolated static var closeAllWindows: String { AppLocalization.localizedText("Close All Windows") }
        nonisolated static var allSessionsTerminated: String { AppLocalization.localizedText("All terminal sessions will be terminated.") }
        nonisolated static var allTabsAndSessionsClosed: String { AppLocalization.localizedText("All open tabs and terminal sessions will be closed.") }
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
        nonisolated static var tabConnections: String { AppLocalization.localizedString("ssh.connections.tab.connections") }
        nonisolated static var tabTodo: String { AppLocalization.localizedString("ssh.connections.tab.todo") }
        nonisolated static var tabLearning: String { AppLocalization.localizedString("ssh.connections.tab.learning") }
        nonisolated static var tabTaskQueue: String { AppLocalization.localizedString("ssh.connections.tab.task_queue") }
        nonisolated static var connectionsPageTitle: String { AppLocalization.localizedString("ssh.connections.page.connections.title") }
        nonisolated static var connectionsPageSubtitle: String { AppLocalization.localizedString("ssh.connections.page.connections.subtitle") }
        nonisolated static var taskQueueTitle: String { AppLocalization.localizedString("ssh.connections.task_queue.title") }
        nonisolated static var taskQueueSubtitle: String { AppLocalization.localizedString("ssh.connections.task_queue.subtitle") }
        nonisolated static var taskQueueEnable: String { AppLocalization.localizedString("ssh.connections.task_queue.enable") }
        nonisolated static var taskQueueHeartbeatInterval: String { AppLocalization.localizedString("ssh.connections.task_queue.heartbeat_interval") }
        nonisolated static func taskQueueMaxConcurrent(_ value: Int) -> String {
            AppLocalization.localizedString("ssh.connections.task_queue.max_concurrent", value)
        }
        nonisolated static var taskQueueSaveSettings: String { AppLocalization.localizedString("ssh.connections.task_queue.save_settings") }
        nonisolated static var taskQueueCancelAll: String { AppLocalization.localizedString("ssh.connections.task_queue.cancel_all") }
        nonisolated static var taskQueueCancelledAllMessage: String { AppLocalization.localizedString("ssh.connections.task_queue.cancelled_all_message") }
        nonisolated static var taskQueueClearFinished: String { AppLocalization.localizedString("ssh.connections.task_queue.clear_finished") }
        nonisolated static var taskQueueClearedFinishedMessage: String { AppLocalization.localizedString("ssh.connections.task_queue.cleared_finished_message") }
        nonisolated static var taskQueueEnqueueTitle: String { AppLocalization.localizedString("ssh.connections.task_queue.enqueue_title") }
        nonisolated static var taskQueueScheduleExecution: String { AppLocalization.localizedString("ssh.connections.task_queue.schedule_execution") }
        nonisolated static var taskQueueExecuteAt: String { AppLocalization.localizedString("ssh.connections.task_queue.execute_at") }
        nonisolated static var taskQueueEnqueue: String { AppLocalization.localizedString("ssh.connections.task_queue.enqueue") }
        nonisolated static func taskQueueTaskAccepted(_ id: String) -> String {
            AppLocalization.localizedString("ssh.connections.task_queue.task_accepted", id)
        }
        nonisolated static func taskQueueCounts(_ queued: Int, _ running: Int, _ done: Int, _ failed: Int) -> String {
            AppLocalization.localizedString("ssh.connections.task_queue.counts", queued, running, done, failed)
        }
        nonisolated static var taskQueueEmpty: String { AppLocalization.localizedString("ssh.connections.task_queue.empty") }
        nonisolated static var taskQueueSaved: String { AppLocalization.localizedString("ssh.connections.task_queue.saved") }
        nonisolated static var taskQueueStatusQueued: String { AppLocalization.localizedString("ssh.connections.task_queue.status.queued") }
        nonisolated static var taskQueueStatusRunning: String { AppLocalization.localizedString("ssh.connections.task_queue.status.running") }
        nonisolated static var taskQueueStatusDone: String { AppLocalization.localizedString("ssh.connections.task_queue.status.done") }
        nonisolated static var taskQueueStatusFailed: String { AppLocalization.localizedString("ssh.connections.task_queue.status.failed") }
        nonisolated static var taskQueueStatusCancelled: String { AppLocalization.localizedString("ssh.connections.task_queue.status.cancelled") }
        nonisolated static var todoTitle: String { AppLocalization.localizedString("ssh.connections.todo.title") }
        nonisolated static var todoSubtitle: String { AppLocalization.localizedString("ssh.connections.todo.subtitle") }
        nonisolated static var todoEnable: String { AppLocalization.localizedString("ssh.connections.todo.enable") }
        nonisolated static var todoWorkspaceRootPath: String { AppLocalization.localizedString("ssh.connections.todo.workspace_root_path") }
        nonisolated static var todoWorkspaceRequired: String { AppLocalization.localizedString("ssh.connections.todo.workspace_required") }
        nonisolated static var todoDayFilePath: String { AppLocalization.localizedString("ssh.connections.todo.day_file_path") }
        nonisolated static var todoShowCompletedItems: String { AppLocalization.localizedString("ssh.connections.todo.show_completed_items") }
        nonisolated static var todoHideCompletedItems: String { AppLocalization.localizedString("ssh.connections.todo.hide_completed_items") }
        nonisolated static var todoPresentationTitle: String { AppLocalization.localizedString("ssh.connections.todo.presentation_title") }
        nonisolated static var todoSidebarPlacement: String { AppLocalization.localizedString("ssh.connections.todo.sidebar_placement") }
        nonisolated static var todoSidebarPlacementLeft: String { AppLocalization.localizedString("ssh.connections.todo.sidebar_placement_left") }
        nonisolated static var todoSidebarPlacementRight: String { AppLocalization.localizedString("ssh.connections.todo.sidebar_placement_right") }
        nonisolated static var todoWorkspaceOverlayVisible: String { AppLocalization.localizedString("ssh.connections.todo.workspace_overlay_visible") }
        nonisolated static var todoWorkspaceOverlayPlacement: String { AppLocalization.localizedString("ssh.connections.todo.workspace_overlay_placement") }
        nonisolated static var todoOverlayTopLeft: String { AppLocalization.localizedString("ssh.connections.todo.overlay_top_left") }
        nonisolated static var todoOverlayTopRight: String { AppLocalization.localizedString("ssh.connections.todo.overlay_top_right") }
        nonisolated static var todoOverlayBottomLeft: String { AppLocalization.localizedString("ssh.connections.todo.overlay_bottom_left") }
        nonisolated static var todoOverlayBottomRight: String { AppLocalization.localizedString("ssh.connections.todo.overlay_bottom_right") }
        nonisolated static var todoInitializeWorkspace: String { AppLocalization.localizedString("ssh.connections.todo.initialize_workspace") }
        nonisolated static var todoInitializeWorkspaceHint: String { AppLocalization.localizedString("ssh.connections.todo.initialize_workspace_hint") }
        nonisolated static var todoSaved: String { AppLocalization.localizedString("ssh.connections.todo.saved") }
        nonisolated static func todoInitializedMessage(_ createdCount: Int, _ reusedCount: Int) -> String {
            AppLocalization.localizedString("ssh.connections.todo.initialized_message", createdCount, reusedCount)
        }
        nonisolated static func todoInitializeFailedMessage(_ detail: String) -> String {
            AppLocalization.localizedString("ssh.connections.todo.initialize_failed_message", detail)
        }
        nonisolated static var todoAddTitle: String { AppLocalization.localizedString("ssh.connections.todo.add_title") }
        nonisolated static var todoAddNotes: String { AppLocalization.localizedString("ssh.connections.todo.add_notes") }
        nonisolated static var todoAddAction: String { AppLocalization.localizedString("ssh.connections.todo.add_action") }
        nonisolated static var todoEmpty: String { AppLocalization.localizedString("ssh.connections.todo.empty") }
        nonisolated static var todoDateYesterday: String { AppLocalization.localizedString("ssh.connections.todo.date_yesterday") }
        nonisolated static var todoDateToday: String { AppLocalization.localizedString("ssh.connections.todo.date_today") }
        nonisolated static var todoDateTomorrow: String { AppLocalization.localizedString("ssh.connections.todo.date_tomorrow") }
        nonisolated static var todoSummaryTitle: String { AppLocalization.localizedString("ssh.connections.todo.summary_title") }
        nonisolated static func todoSummaryProgress(_ completedCount: Int, _ totalCount: Int, _ percentage: Int) -> String {
            AppLocalization.localizedString("ssh.connections.todo.summary_progress", completedCount, totalCount, percentage)
        }
        nonisolated static func todoSelectedDay(_ value: String) -> String { AppLocalization.localizedString("ssh.connections.todo.selected_day", value) }
        nonisolated static var todoFocusedWorkspaceTitle: String { AppLocalization.localizedString("ssh.connections.todo.focused_workspace_title") }
        nonisolated static func todoFocusedWorkspaceSummary(_ completedCount: Int, _ totalCount: Int, _ remainingCount: Int) -> String {
            AppLocalization.localizedString("ssh.connections.todo.focused_workspace_summary", completedCount, totalCount, remainingCount)
        }
        nonisolated static var todoFocusedWorkspaceHint: String { AppLocalization.localizedString("ssh.connections.todo.focused_workspace_hint") }
        nonisolated static var todoQuickLookTitle: String { AppLocalization.localizedString("ssh.connections.todo.quick_look_title") }
        nonisolated static var todoQuickLookEmpty: String { AppLocalization.localizedString("ssh.connections.todo.quick_look_empty") }
        nonisolated static var todoQuickLookManage: String { AppLocalization.localizedString("ssh.connections.todo.quick_look_manage") }
        nonisolated static func todoQuickLookSummary(_ completedCount: Int, _ totalCount: Int, _ remainingCount: Int) -> String {
            AppLocalization.localizedString("ssh.connections.todo.quick_look_summary", completedCount, totalCount, remainingCount)
        }
        nonisolated static func todoQuickLookMore(_ count: Int) -> String {
            AppLocalization.localizedString("ssh.connections.todo.quick_look_more", count)
        }
        nonisolated static var todoTimelineTitle: String { AppLocalization.localizedString("ssh.connections.todo.timeline_title") }
        nonisolated static func todoTimelineCreated(_ created: String) -> String {
            AppLocalization.localizedString("ssh.connections.todo.timeline_created", created)
        }
        nonisolated static func todoTimelineCreatedCompleted(_ created: String, _ completed: String) -> String {
            AppLocalization.localizedString("ssh.connections.todo.timeline_created_completed", created, completed)
        }
        nonisolated static var todoSaveSettings: String { AppLocalization.localizedString("ssh.connections.todo.save_settings") }
        nonisolated static var todoPanelTitle: String { AppLocalization.localizedString("ssh.connections.todo.panel_title") }
        nonisolated static var todoPanelSubtitle: String { AppLocalization.localizedString("ssh.connections.todo.panel_subtitle") }
        nonisolated static var todoPanelOpenSettings: String { AppLocalization.localizedString("ssh.connections.todo.panel_open_settings") }
        nonisolated static var todoPanelClose: String { AppLocalization.localizedString("ssh.connections.todo.panel_close") }
        nonisolated static var todoActionSave: String { AppLocalization.localizedString("ssh.connections.todo.action_save") }
        nonisolated static var todoActionComplete: String { AppLocalization.localizedString("ssh.connections.todo.action_complete") }
        nonisolated static var todoActionEdit: String { AppLocalization.localizedString("ssh.connections.todo.action_edit") }
        nonisolated static var todoActionReset: String { AppLocalization.localizedString("ssh.connections.todo.action_reset") }
        nonisolated static var todoAssignmentClear: String { AppLocalization.localizedString("ssh.connections.todo.assignment_clear") }
        nonisolated static var todoAssignmentNoTabs: String { AppLocalization.localizedString("ssh.connections.todo.assignment_no_tabs") }
        nonisolated static var todoAssignmentUnassigned: String { AppLocalization.localizedString("ssh.connections.todo.assignment_unassigned") }
        nonisolated static var todoAssignmentUnavailable: String { AppLocalization.localizedString("ssh.connections.todo.assignment_unavailable") }
        nonisolated static var todoTitleRequired: String { AppLocalization.localizedString("ssh.connections.todo.title_required") }
        nonisolated static var todoSyncStaleAction: String { AppLocalization.localizedString("ssh.connections.todo.sync_stale_action") }
        nonisolated static var todoSyncStaleEmpty: String { AppLocalization.localizedString("ssh.connections.todo.sync_stale_empty") }
        nonisolated static func todoSyncStaleSuccess(_ count: Int) -> String {
            AppLocalization.localizedString("ssh.connections.todo.sync_stale_success", count)
        }
        nonisolated static func todoStalePointer(_ day: String) -> String {
            AppLocalization.localizedString("ssh.connections.todo.stale_pointer", day)
        }
        nonisolated static var learningTitle: String { AppLocalization.localizedString("ssh.connections.learning.title") }
        nonisolated static var learningSubtitle: String { AppLocalization.localizedString("ssh.connections.learning.subtitle") }
        nonisolated static var learningEnable: String { AppLocalization.localizedString("ssh.connections.learning.enable") }
        nonisolated static var learningPreferTabWorkingDirectory: String { AppLocalization.localizedString("ssh.connections.learning.prefer_tab_working_directory") }
        nonisolated static var learningChatWorkspacePath: String { AppLocalization.localizedString("ssh.connections.learning.chat_workspace_path") }
        nonisolated static var learningChatWorkspaceRequired: String { AppLocalization.localizedString("ssh.connections.learning.chat_workspace_required") }
        nonisolated static var learningLearnWorkspaceAutoPath: String { AppLocalization.localizedString("ssh.connections.learning.learn_workspace_auto_path") }
        nonisolated static var learningDefaultProjectPath: String { AppLocalization.localizedString("ssh.connections.learning.default_project_path") }
        nonisolated static var learningNotesRelativePath: String { AppLocalization.localizedString("ssh.connections.learning.notes_relative_path") }
        nonisolated static var learningCommandTemplate: String { AppLocalization.localizedString("ssh.connections.learning.command_template") }
        nonisolated static var learningFastModel: String { AppLocalization.localizedString("ssh.connections.learning.fast_model") }
        nonisolated static var learningPromptTemplate: String { AppLocalization.localizedString("ssh.connections.learning.prompt_template") }
        nonisolated static var learningSupportedPlaceholders: String { AppLocalization.localizedString("ssh.connections.learning.supported_placeholders") }
        nonisolated static var learningContextAction: String { AppLocalization.localizedString("ssh.connections.learning.context_action") }
        nonisolated static var learningDisabledMessage: String { AppLocalization.localizedString("ssh.connections.learning.disabled_message") }
        nonisolated static var learningStartedMessage: String { AppLocalization.localizedString("ssh.connections.learning.started_message") }
        nonisolated static var learningSucceededMessage: String { AppLocalization.localizedString("ssh.connections.learning.succeeded_message") }
        nonisolated static func learningFailedMessage(_ message: String) -> String { AppLocalization.localizedString("ssh.connections.learning.failed_message", message) }
        nonisolated static var learningPermissionDeniedMessage: String { AppLocalization.localizedString("ssh.connections.learning.permission_denied_message") }
        nonisolated static func learningPersistSucceededMessage(_ path: String) -> String { AppLocalization.localizedString("ssh.connections.learning.persist_succeeded_message", path) }
        nonisolated static func learningPersistFailedMessage(_ message: String) -> String { AppLocalization.localizedString("ssh.connections.learning.persist_failed_message", message) }
        nonisolated static var learningInitializeWorkspace: String { AppLocalization.localizedString("ssh.connections.learning.initialize_workspace") }
        nonisolated static var learningInitializeConfirmTitle: String { AppLocalization.localizedString("ssh.connections.learning.initialize_confirm_title") }
        nonisolated static func learningInitializeConfirmMessage(_ path: String) -> String {
            AppLocalization.localizedString("ssh.connections.learning.initialize_confirm_message", path)
        }
        nonisolated static var learningInitializeConfirmAction: String { AppLocalization.localizedString("ssh.connections.learning.initialize_confirm_action") }
        nonisolated static var learningInitializeWorkspaceHint: String { AppLocalization.localizedString("ssh.connections.learning.initialize_workspace_hint") }
        nonisolated static var learningInitializing: String { AppLocalization.localizedString("ssh.connections.learning.initializing") }
        nonisolated static func learningInitializedMessage(_ createdCount: Int, _ reusedCount: Int) -> String {
            AppLocalization.localizedString(
                "ssh.connections.learning.initialized_message",
                createdCount,
                reusedCount
            )
        }
        nonisolated static func learningInitializedWithSkillSyncWarningMessage(
            _ createdCount: Int,
            _ reusedCount: Int,
            _ failedSkillRepoCount: Int
        ) -> String {
            AppLocalization.localizedString(
                "ssh.connections.learning.initialized_with_skill_sync_warning_message",
                createdCount,
                reusedCount,
                failedSkillRepoCount
            )
        }
        nonisolated static func learningInitializeFailedMessage(_ message: String) -> String {
            AppLocalization.localizedString("ssh.connections.learning.initialize_failed_message", message)
        }
        nonisolated static var learningSkillReposTitle: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.title") }
        nonisolated static var learningSkillReposSubtitle: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.subtitle") }
        nonisolated static var learningSkillReposEmpty: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.empty") }
        nonisolated static var learningSkillReposCheckUpdates: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.check_updates") }
        nonisolated static var learningSkillReposPullUpdates: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.pull_updates") }
        nonisolated static var learningSkillReposChecking: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.checking") }
        nonisolated static var learningSkillReposPulling: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.pulling") }
        nonisolated static func learningSkillReposCheckedMessage(_ latest: Int, _ updates: Int, _ errors: Int) -> String {
            AppLocalization.localizedString(
                "ssh.connections.learning.skill_repos.checked_message",
                latest,
                updates,
                errors
            )
        }
        nonisolated static func learningSkillReposPulledMessage(_ latest: Int, _ updates: Int, _ errors: Int) -> String {
            AppLocalization.localizedString(
                "ssh.connections.learning.skill_repos.pulled_message",
                latest,
                updates,
                errors
            )
        }
        nonisolated static var learningSkillReposStatusLatest: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.status.latest") }
        nonisolated static var learningSkillReposStatusUpdateAvailable: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.status.update_available") }
        nonisolated static var learningSkillReposStatusNotInstalled: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.status.not_installed") }
        nonisolated static var learningSkillReposStatusLocalChanges: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.status.local_changes") }
        nonisolated static var learningSkillReposStatusError: String { AppLocalization.localizedString("ssh.connections.learning.skill_repos.status.error") }
        nonisolated static var learningSave: String { AppLocalization.localizedString("ssh.connections.learning.save") }
        nonisolated static var learningSaved: String { AppLocalization.localizedString("ssh.connections.learning.saved") }
        nonisolated static var learningLogPanelTitle: String { AppLocalization.localizedString("ssh.connections.learning.log.title") }
        nonisolated static var learningLogPanelSubtitle: String { AppLocalization.localizedString("ssh.connections.learning.log.subtitle") }
        nonisolated static var learningLogClear: String { AppLocalization.localizedString("ssh.connections.learning.log.clear") }
        nonisolated static var learningLogEmpty: String { AppLocalization.localizedString("ssh.connections.learning.log.empty") }
        nonisolated static var learningLogStatusSuccess: String { AppLocalization.localizedString("ssh.connections.learning.log.status.success") }
        nonisolated static var learningLogStatusFailure: String { AppLocalization.localizedString("ssh.connections.learning.log.status.failure") }
        nonisolated static var learningLogShowDetails: String { AppLocalization.localizedString("ssh.connections.learning.log.show_details") }
        nonisolated static var learningLogHideDetails: String { AppLocalization.localizedString("ssh.connections.learning.log.hide_details") }
        nonisolated static func learningLogExitCode(_ code: Int32) -> String {
            AppLocalization.localizedString("ssh.connections.learning.log.exit_code", Int(code))
        }
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
        nonisolated static var saveWorkspaceAction: String { AppLocalization.localizedString("ai.manager.workspaces.save_action") }
        nonisolated static var saveWorkspacePrompt: String { AppLocalization.localizedString("ai.manager.workspaces.save_prompt") }
        nonisolated static var savedWorkspacesSection: String { AppLocalization.localizedString("ai.manager.workspaces.saved_section") }
        nonisolated static var savedWorkspaceItem: String { AppLocalization.localizedString("ai.manager.workspaces.saved_item") }
        nonisolated static var replaceWorkspaceTitle: String { AppLocalization.localizedString("ai.manager.workspaces.replace_title") }
        nonisolated static func replaceWorkspaceMessage(_ name: String) -> String { AppLocalization.localizedString("ai.manager.workspaces.replace_message", name) }
        nonisolated static var replaceWorkspace: String { AppLocalization.localizedString("ai.manager.workspaces.replace") }
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
        nonisolated static var workspaceEmpty: String { AppLocalization.localizedString("ai.manager.error.workspace_empty") }
        nonisolated static var workspaceDuplicateName: String { AppLocalization.localizedString("ai.manager.error.workspace_duplicate_name") }
        nonisolated static var savedWorkspaceEmptyPane: String { AppLocalization.localizedString("ai.manager.error.saved_workspace_empty_pane") }
        nonisolated static var savedWorkspaceUnknownHost: String { AppLocalization.localizedString("ai.manager.error.saved_workspace_unknown_host") }
        nonisolated static var couldNotSaveWorkspace: String { AppLocalization.localizedString("ai.manager.error.could_not_save_workspace") }
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
