import Testing
@testable import Ghostty

struct AppLocalizationTests {
    @Test func detectsPreferredLanguage() {
        #expect(AppLocalization.language(for: ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(AppLocalization.language(for: ["en-US"]) == .english)
        #expect(AppLocalization.language(for: ["fr-FR"]) == .english)
    }

    @Test func formatsLocalizedStrings() {
        #expect(
            AppLocalization.localizedString(
                "command_palette.focus",
                preferredLanguages: ["en-US"],
                arguments: ["Buildbox"]
            ) == "Focus: Buildbox"
        )
        #expect(
            AppLocalization.localizedString(
                "command_palette.focus",
                preferredLanguages: ["zh-Hans"],
                arguments: ["构建机"]
            ) == "聚焦：构建机"
        )
    }

    @Test func fallsBackToEnglishAndKey() {
        #expect(
            AppLocalization.localizedString(
                "about.docs",
                preferredLanguages: ["fr-FR"]
            ) == "Docs"
        )
        #expect(
            AppLocalization.localizedString(
                "missing.localization.key",
                preferredLanguages: ["en-US"]
            ) == "missing.localization.key"
        )
    }

    @Test func localizesRawAppTextAndFormatsDynamicStrings() {
        #expect(
            AppLocalization.localizedText(
                "Close Window",
                preferredLanguages: ["zh-Hans"]
            ) == "关闭窗口"
        )
        #expect(
            AppLocalization.localizedString(
                "app.allow_execute",
                preferredLanguages: ["zh-Hans"],
                arguments: ["/tmp/demo.sh"]
            ) == "允许 Ghostty 执行“/tmp/demo.sh”吗？"
        )
        #expect(
            AppLocalization.localizedText(
                "View Release Notes",
                preferredLanguages: ["zh-Hans"]
            ) == "查看发布说明"
        )
        #expect(
            AppLocalization.localizedText(
                "Allow Shortcuts to interact with Ghostty?",
                preferredLanguages: ["zh-Hans"]
            ) == "允许快捷指令与 Ghostty 交互吗？"
        )
        #expect(
            AppLocalization.localizedText(
                "The momentum phase for inertial scrolling.",
                preferredLanguages: ["zh-Hans"]
            ) == "惯性滚动的阶段。"
        )
        #expect(
            AppLocalization.localizedString(
                "app.tabs_disabled",
                preferredLanguages: ["zh-Hans"]
            ) == "标签页已禁用"
        )
        #expect(
            AppLocalization.localizedText(
                "Tabs are disabled",
                preferredLanguages: ["zh-Hans"]
            ) == "标签页已禁用"
        )
        #expect(
            AppLocalization.localizedText(
                "AI Terminal Manager…",
                preferredLanguages: ["zh-Hans"]
            ) == "AI 终端管理器…"
        )
        #expect(
            AppLocalization.localizedText(
                "Settings Panel…",
                preferredLanguages: ["zh-Hans"]
            ) == "设置面板…"
        )
        #expect(
            AppLocalization.localizedText(
                "Enable window decorations to use tabs",
                preferredLanguages: ["zh-Hans"]
            ) == "启用窗口装饰后才能使用标签页"
        )
        #expect(
            AppLocalization.localizedString(
                "permission.remember.hour.other",
                preferredLanguages: ["zh-Hans"],
                arguments: [4]
            ) == "记住我的决定 4 小时"
        )
    }

    @Test func sshConnectionsCommandPaletteStringsAreLocalized() {
        #expect(
            AppLocalization.localizedString(
                "command_palette.ssh_connections.title",
                preferredLanguages: ["en-US"]
            ) == "Open: Settings Panel"
        )
        #expect(
            AppLocalization.localizedString(
                "command_palette.ssh_connections.title",
                preferredLanguages: ["zh-Hans"]
            ) == "打开：设置面板"
        )
    }

    @Test func sshConnectionsPanelAndLearningLogStringsAreLocalized() {
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.window.title",
                preferredLanguages: ["en-US"]
            ) == "Settings Panel"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.window.title",
                preferredLanguages: ["zh-Hans"]
            ) == "设置面板"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.log.status.success",
                preferredLanguages: ["en-US"]
            ) == "Success"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.log.status.failure",
                preferredLanguages: ["zh-Hans"]
            ) == "失败"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.started_message",
                preferredLanguages: ["en-US"]
            ) == "Learning command started."
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.initialize_workspace",
                preferredLanguages: ["en-US"]
            ) == "Initialize Chat + Learn Workspace"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.skill_repos.check_updates",
                preferredLanguages: ["en-US"]
            ) == "Check Updates"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.permission_denied_message",
                preferredLanguages: ["zh-Hans"]
            ) == "学习命令已取消：执行权限被拒绝。"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.chat_workspace_path",
                preferredLanguages: ["zh-Hans"]
            ) == "Chat 项目根目录"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.chat_workspace_required",
                preferredLanguages: ["en-US"]
            ) == "Chat workspace root path is required."
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.learn_workspace_auto_path",
                preferredLanguages: ["zh-Hans"]
            ) == "Learn 项目路径（自动解析）"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.initialize_confirm_title",
                preferredLanguages: ["en-US"]
            ) == "Confirm initialization"
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.skill_repos.checking",
                preferredLanguages: ["zh-Hans"]
            ) == "正在检查 skill 仓库状态..."
        )
        #expect(
            AppLocalization.localizedString(
                "ssh.connections.learning.skill_repos.status.latest",
                preferredLanguages: ["zh-Hans"]
            ) == "已最新"
        )
    }

    @Test func bellNotificationStringsAreLocalized() {
        #expect(
            AppLocalization.localizedString(
                "terminal.notification.bell.title",
                preferredLanguages: ["en-US"]
            ) == "Action Required"
        )
        #expect(
            AppLocalization.localizedString(
                "terminal.notification.bell.body",
                preferredLanguages: ["en-US"]
            ) == "Task completed and waiting for your input."
        )
        #expect(
            AppLocalization.localizedString(
                "terminal.notification.bell.title",
                preferredLanguages: ["zh-Hans"]
            ) == "等待操作"
        )
        #expect(
            AppLocalization.localizedString(
                "terminal.notification.bell.body",
                preferredLanguages: ["zh-Hans"]
            ) == "任务已完成，等待你的操作。"
        )
    }

    @Test func appLanguageSettingUsesStoredOverride() {
        let suiteName = "AppLocalizationTests.\(#function)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(
            AppLanguageSetting.preferredLanguages(
                userDefaults: userDefaults,
                systemPreferredLanguages: ["fr-FR"]
            ) == ["fr-FR"]
        )

        AppLanguageSetting.english.apply(userDefaults: userDefaults)
        #expect(AppLanguageSetting.storedSelection(userDefaults: userDefaults) == .english)
        #expect(
            AppLanguageSetting.preferredLanguages(
                userDefaults: userDefaults,
                systemPreferredLanguages: ["zh-Hans"]
            ) == ["en"]
        )
        #expect((userDefaults.array(forKey: AppLanguageSetting.appleLanguagesKey) as? [String]) == ["en"])

        AppLanguageSetting.simplifiedChinese.apply(userDefaults: userDefaults)
        #expect(AppLanguageSetting.storedSelection(userDefaults: userDefaults) == .simplifiedChinese)
        #expect((userDefaults.array(forKey: AppLanguageSetting.appleLanguagesKey) as? [String]) == ["zh-Hans"])

        AppLanguageSetting.system.apply(userDefaults: userDefaults)
        #expect(AppLanguageSetting.storedSelection(userDefaults: userDefaults) == .system)
        #expect(userDefaults.array(forKey: AppLanguageSetting.appleLanguagesKey) == nil)
    }
}
