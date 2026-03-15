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
                "Connections…",
                preferredLanguages: ["zh-Hans"]
            ) == "连接中心…"
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
            ) == "Open: Connections"
        )
        #expect(
            AppLocalization.localizedString(
                "command_palette.ssh_connections.title",
                preferredLanguages: ["zh-Hans"]
            ) == "打开：连接中心"
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
