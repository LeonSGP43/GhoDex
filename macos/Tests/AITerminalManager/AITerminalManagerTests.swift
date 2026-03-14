import Testing
import Foundation
import AppKit
@testable import Ghostty

final class MockSSHConnectionCredentialStore: SSHConnectionCredentialStore {
    var passwords: [String: String] = [:]

    func password(for hostID: String) throws -> String? {
        passwords[hostID]
    }

    func setPassword(_ password: String, for hostID: String) throws {
        passwords[hostID] = password
    }

    func removePassword(for hostID: String) throws {
        passwords.removeValue(forKey: hostID)
    }
}

struct AITerminalManagerTests {
    @Test @MainActor func sshConnectionsWindowsWithoutTabGroupsAreNotTreatedAsSameGroup() {
        let lhs = NSWindow()
        let rhs = NSWindow()

        #expect(SSHConnectionsController.windowsAreInSameTabGroup(lhs, rhs) == false)
    }

    @Test func decodesLegacyHostConfigurationIntoSavedHosts() throws {
        let data = Data(#"{"hosts":[{"id":"ssh:buildbox","name":"Buildbox","transport":"ssh","sshAlias":"buildbox","hostname":"10.0.0.5","user":"deploy","port":2222,"defaultDirectory":"/srv/app","source":"configuration_file"}],"workspaces":[],"supervisor":{"arguments":[],"autoStart":false,"environment":{}}}"#.utf8)
        let configuration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)

        #expect(configuration.savedHosts.count == 1)
        #expect(configuration.savedHosts.first?.id == "ssh:buildbox")
        #expect(configuration.savedHosts.first?.authMode == .system)
        #expect(configuration.importedHostOverrides.isEmpty)
    }

    @Test func decodesLegacyConfigurationWithoutFavorites() throws {
        let data = Data(#"{"schemaVersion":1,"savedHosts":[{"id":"ssh:buildbox","name":"Buildbox","transport":"ssh","sshAlias":"buildbox","hostname":"10.0.0.5","user":"deploy","port":2222,"defaultDirectory":"/srv/app","source":"configuration_file"}],"importedHostOverrides":[],"recentHosts":[],"workspaces":[],"supervisor":{"arguments":[],"autoStart":false,"environment":{}}}"#.utf8)
        let configuration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)

        #expect(configuration.favoriteHostIDs.isEmpty)
        #expect(configuration.savedHosts.map(\.id) == ["ssh:buildbox"])
    }

    @Test func decodesLegacyConfigurationWithDefaultLearningSettings() throws {
        let data = Data(#"{"schemaVersion":2,"savedHosts":[],"importedHostOverrides":[],"favoriteHostIDs":[],"recentHosts":[],"workspaces":[]}"#.utf8)
        let configuration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)

        #expect(configuration.learningSettings.enabled)
        #expect(configuration.learningSettings.preferTabWorkingDirectory)
        #expect(configuration.learningSettings.notesRelativePath == AITerminalLearningSettings.defaultNotesRelativePath)
        #expect(configuration.learningSettings.commandTemplate == AITerminalLearningSettings.defaultCommandTemplate)
        #expect(configuration.learningSettings.fastModel == AITerminalLearningSettings.defaultFastModel)
        #expect(configuration.learningSettings.promptTemplate == AITerminalLearningSettings.defaultPromptTemplate)
        #expect(configuration.learningLogs.isEmpty)
    }

    @Test func decodesLegacyLearningKeysIntoCommandTemplate() throws {
        let data = Data(#"{"schemaVersion":3,"savedHosts":[],"importedHostOverrides":[],"favoriteHostIDs":[],"recentHosts":[],"workspaces":[],"learningSettings":{"enabled":true,"preferTabWorkingDirectory":false,"defaultProjectPath":"/tmp/project","notesRelativePath":".agents/memory/custom.md","codexCommand":"c codex -m \"$MODEL\" \"$PROMPT\"","codexModel":"grokcodex41fast"}}"#.utf8)
        let configuration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)

        #expect(configuration.learningSettings.commandTemplate == #"c codex -m "$MODEL" "$PROMPT""#)
        #expect(configuration.learningSettings.fastModel == "grokcodex41fast")
        #expect(configuration.learningSettings.promptTemplate == AITerminalLearningSettings.defaultPromptTemplate)
    }

    @Test func normalizesCodex1mExecCommandTemplateWithSkipGitRepoCheck() {
        let settings = AITerminalLearningSettings(
            enabled: true,
            preferTabWorkingDirectory: false,
            defaultProjectPath: "/tmp/project",
            notesRelativePath: "knowledges/inbox.md",
            commandTemplate: #"/Users/leongong/.local/bin/codex1m exec -C "$LEARN_WORKSPACE" "$PROMPT""#,
            fastModel: "gpt-5-codex",
            promptTemplate: "ignored"
        )

        #expect(settings.commandTemplate.contains("--skip-git-repo-check"))
        #expect(settings.commandTemplate.contains("/Users/leongong/.local/bin/codex1m exec"))

        let context = settings.resolvedContext(selection: "test", tabWorkingDirectory: "/tmp/project")
        #expect(context.commandTemplate.contains("--skip-git-repo-check"))
    }

    @Test func learningSettingsResolveContextWithTabWorkingDirectory() {
        let settings = AITerminalLearningSettings(
            enabled: true,
            preferTabWorkingDirectory: true,
            defaultProjectPath: "/tmp/default",
            notesRelativePath: "knowledges/inbox.md",
            commandTemplate: #"c codex -m "$MODEL" "$PROMPT""#,
            fastModel: "grokcodex41fast",
            promptTemplate: "Project=$PROJECT_PATH\nNotes=$NOTES_ABSOLUTE_PATH\nSelection=$SELECTION"
        )

        let context = settings.resolvedContext(
            selection: "  hello world  ",
            tabWorkingDirectory: "/tmp/current-tab"
        )
        let expectedPrompt = AITerminalLearningSettings.defaultPromptTemplate.replacingOccurrences(
            of: "$SELECTION",
            with: "hello world"
        )

        #expect(context.projectPath == "/tmp/default")
        #expect(context.notesAbsolutePath == "/tmp/default/knowledges/inbox.md")
        #expect(context.prompt == expectedPrompt)
        #expect(context.environmentVariables["MODEL"] == "grokcodex41fast")
    }

    @Test func learningSettingsResolveContextFallsBackToDefaultProjectPath() {
        let settings = AITerminalLearningSettings(
            enabled: true,
            preferTabWorkingDirectory: true,
            defaultProjectPath: "/tmp/default-project",
            notesRelativePath: "knowledges/inbox.md",
            commandTemplate: #"c codex -m "$MODEL" "$PROMPT""#,
            fastModel: "gpt-5-codex",
            promptTemplate: "Path=$PROJECT_PATH"
        )

        let context = settings.resolvedContext(
            selection: "selection",
            tabWorkingDirectory: nil
        )
        let expectedPrompt = AITerminalLearningSettings.defaultPromptTemplate.replacingOccurrences(
            of: "$SELECTION",
            with: "selection"
        )

        #expect(context.projectPath == "/tmp/default-project")
        #expect(context.notesAbsolutePath == "/tmp/default-project/knowledges/inbox.md")
        #expect(context.prompt == expectedPrompt)
    }

    @Test func learningSettingsDeriveChatAndLearnWorkspacePaths() {
        let chatWorkspacePath = "/tmp/my-chat-workspace"
        let learnWorkspacePath = AITerminalLearningSettings.learnWorkspacePath(
            fromChatWorkspacePath: chatWorkspacePath
        )

        #expect(learnWorkspacePath == "/tmp/my-chat-workspace/codex_learn_workspace")
        #expect(
            AITerminalLearningSettings.chatWorkspacePath(
                fromLearnWorkspacePath: learnWorkspacePath
            ) == chatWorkspacePath
        )
    }

    @Test func parsesSSHConfigHosts() {
        let config = #"""
        Host *
          AddKeysToAgent yes

        Host buildbox staging
          HostName 10.0.0.5
          User deploy
          Port 2222

        Host prod-*
          HostName ignored.example.com
        """#

        let hosts = AITerminalSSHConfigParser.parse(config)
        #expect(hosts.map(\.id) == ["ssh:buildbox", "ssh:staging"])
        #expect(hosts.first?.hostname == "10.0.0.5")
        #expect(hosts.first?.user == "deploy")
        #expect(hosts.first?.port == 2222)
    }

    @Test func buildsRemoteCommandWithDirectory() {
        let host = AITerminalHost(
            id: "ssh:buildbox",
            name: "buildbox",
            transport: .ssh,
            sshAlias: "buildbox",
            hostname: "10.0.0.5",
            user: "deploy",
            port: 2222,
            defaultDirectory: "/srv/app",
            source: .sshConfig
        )

        let command = AITerminalLaunchPlan.remoteCommand(host: host)
        #expect(command == "ssh buildbox -t 'export TERM=xterm-256color && export COLORTERM=truecolor && unset LC_ALL && cd /srv/app && exec ${SHELL:-/bin/sh} -l'")
    }

    @Test func buildsRemoteCommandWithoutDirectorySetsColorTerm() {
        let host = AITerminalHost(
            id: "ssh:buildbox",
            name: "buildbox",
            transport: .ssh,
            sshAlias: "buildbox",
            hostname: "10.0.0.5",
            user: "deploy",
            port: 2222,
            defaultDirectory: nil,
            source: .sshConfig
        )

        let command = AITerminalLaunchPlan.remoteCommand(host: host)
        #expect(command == "ssh buildbox -t 'export TERM=xterm-256color && export COLORTERM=truecolor && unset LC_ALL && exec ${SHELL:-/bin/sh} -l'")
    }

    @Test func buildsLocalMCDPlanWithSequentialCommands() throws {
        let host = AITerminalHost(
            id: "localmcd:grokmcp",
            name: "grokmcp",
            transport: .localmcd,
            startupCommands: [
                "cd /tmp/grokmcp",
                "c codex",
            ],
            sshAlias: nil,
            hostname: nil,
            user: nil,
            port: nil,
            defaultDirectory: nil,
            source: .configurationFile
        )

        let plan = try #require(AITerminalLaunchPlan.localCommand(host: host))
        #expect(plan.surfaceConfiguration.initialInput == "cd /tmp/grokmcp\nc codex\n")
        #expect(plan.registration.hostID == "localmcd:grokmcp")
    }

    @Test func mergesImportedHostOverrides() {
        let imported = [
            AITerminalHost(
                id: "ssh:buildbox",
                name: "buildbox",
                transport: .ssh,
                sshAlias: "buildbox",
                hostname: "10.0.0.5",
                user: "deploy",
                port: 22,
                defaultDirectory: nil,
                source: .sshConfig
            ),
        ]
        let overrides = [
            AITerminalHost(
                id: "ssh:buildbox",
                name: "Buildbox Prod",
                transport: .ssh,
                sshAlias: "buildbox",
                hostname: "10.0.0.5",
                user: "deploy",
                port: 2200,
                defaultDirectory: "/srv/prod",
                source: .configurationFile,
                authMode: .password
            ),
        ]

        let merged = AITerminalManagerStore.mergedImportedHosts(imported: imported, overrides: overrides)
        #expect(merged.count == 1)
        #expect(merged.first?.name == "Buildbox Prod")
        #expect(merged.first?.port == 2200)
        #expect(merged.first?.defaultDirectory == "/srv/prod")
        #expect(merged.first?.authMode == .password)
    }

    @Test func localWorkspacePlanUsesWorkingDirectory() throws {
        let workspace = AITerminalWorkspaceTemplate(
            id: "workspace:test",
            name: "Ghostty",
            hostID: AITerminalHost.local.id,
            directory: "/tmp/ghostty"
        )

        let plan = try #require(AITerminalLaunchPlan.workspace(workspace, host: .local))
        #expect(plan.surfaceConfiguration.workingDirectory == "/tmp/ghostty")
        #expect(plan.registration.workspaceID == "workspace:test")
    }

    @Test @MainActor func storeSavesConfiguredHost() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "2222",
            defaultDirectory: "/srv/app"
        )

        #expect(store.configuration.savedHosts.count == 1)
        #expect(store.configuration.savedHosts.first?.sshAlias == "buildbox")
        #expect(store.configuration.savedHosts.first?.port == 2222)
        #expect(store.configuration.savedHosts.first?.id == "ssh:buildbox")
        #expect(store.configuration.savedHosts.first?.authMode == .system)
    }

    @Test @MainActor func storeSavesLocalMCDHost() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveLocalMCDHost(
            name: "grokmcp",
            defaultDirectory: "/tmp/grokmcp",
            startupCommands: """
            cd /tmp/grokmcp
            c codex
            """
        )

        #expect(store.lastError == nil)
        #expect(store.configuration.savedHosts.count == 1)
        #expect(store.configuration.savedHosts.first?.transport == .localmcd)
        #expect(store.configuration.savedHosts.first?.defaultDirectory == "/tmp/grokmcp")
        #expect(store.configuration.savedHosts.first?.startupCommands == ["cd /tmp/grokmcp", "c codex"])
    }

    @Test @MainActor func storeSavesLearningSettings() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveLearningSettings(.init(
            enabled: true,
            preferTabWorkingDirectory: false,
            defaultProjectPath: "/Users/leongong/Desktop/LeonProjects/codex_chat_workspace",
            notesRelativePath: ".agents/memory/custom.md",
            commandTemplate: #"c codex -m "$MODEL" "$PROMPT""#,
            fastModel: "grokcodex41fast",
            promptTemplate: "Summarize:\n$SELECTION"
        ))

        let data = try Data(contentsOf: tempURL)
        let configuration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)

        #expect(configuration.learningSettings.enabled)
        #expect(!configuration.learningSettings.preferTabWorkingDirectory)
        #expect(configuration.learningSettings.defaultProjectPath == "/Users/leongong/Desktop/LeonProjects/codex_chat_workspace")
        #expect(configuration.learningSettings.notesRelativePath == ".agents/memory/custom.md")
        #expect(configuration.learningSettings.commandTemplate == #"c codex -m "$MODEL" "$PROMPT""#)
        #expect(configuration.learningSettings.fastModel == AITerminalLearningSettings.defaultFastModel)
        #expect(configuration.learningSettings.promptTemplate == AITerminalLearningSettings.defaultPromptTemplate)
    }

    @Test @MainActor func storeInitializesChatAndLearnWorkspaceScaffold() throws {
        let tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let tempChatWorkspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-learning-bootstrap-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempChatWorkspaceURL)
            try? FileManager.default.removeItem(at: tempConfigURL)
        }

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempConfigURL
        )

        let result = try #require(
            store.initializeChatAndLearnWorkspace(
                chatWorkspacePath: tempChatWorkspaceURL.path,
                commandTemplate: AITerminalLearningSettings.defaultCommandTemplate
            )
        )

        let learnWorkspaceURL = URL(fileURLWithPath: result.learnWorkspacePath, isDirectory: true)
        let expectedSkillURL = learnWorkspaceURL
            .appendingPathComponent(".codex/skills/terminal-learning-notes/SKILL.md")
        let expectedScriptURL = learnWorkspaceURL
            .appendingPathComponent(".codex/skills/terminal-learning-notes/scripts/run_learn_capture.sh")
        let expectedKnowledgeURL = URL(fileURLWithPath: result.chatWorkspacePath, isDirectory: true)
            .appendingPathComponent("knowledges/inbox.md")

        #expect(result.createdFileCount > 0)
        #expect(FileManager.default.fileExists(atPath: expectedSkillURL.path))
        #expect(FileManager.default.fileExists(atPath: expectedScriptURL.path))
        #expect(FileManager.default.fileExists(atPath: expectedKnowledgeURL.path))
        #expect(store.learningSettings.defaultProjectPath == result.learnWorkspacePath)
        #expect(store.learningSettings.notesRelativePath == AITerminalLearningSettings.defaultNotesRelativePath)
    }

    @Test @MainActor func initializeWorkspaceMigratesLegacyLearnScriptCommandTemplate() throws {
        let tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let tempChatWorkspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-learning-bootstrap-\(UUID().uuidString)", isDirectory: true)
        let learnWorkspaceURL = tempChatWorkspaceURL
            .appendingPathComponent("codex_learn_workspace", isDirectory: true)
        let legacyScriptURL = learnWorkspaceURL
            .appendingPathComponent(".codex/skills/terminal-learning-notes/scripts/run_learn_capture.sh")

        defer {
            try? FileManager.default.removeItem(at: tempChatWorkspaceURL)
            try? FileManager.default.removeItem(at: tempConfigURL)
        }

        try FileManager.default.createDirectory(
            at: legacyScriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        #!/usr/bin/env bash
        LEARN_EXEC_COMMAND_TEMPLATE="${LEARN_EXEC_COMMAND_TEMPLATE:-/Users/leongong/.local/bin/codex1m exec -c 'mcp_servers.gemini.enabled=false' -c 'mcp_servers.grok-research.enabled=false' -c 'mcp_servers.opus-planning.enabled=false' -C \"$LEARN_WORKSPACE\" \"$PROMPT\"}"
        """.write(to: legacyScriptURL, atomically: true, encoding: .utf8)

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempConfigURL
        )
        _ = try #require(store.initializeChatAndLearnWorkspace(
            chatWorkspacePath: tempChatWorkspaceURL.path,
            commandTemplate: AITerminalLearningSettings.defaultCommandTemplate
        ))

        let migratedScript = try String(contentsOf: legacyScriptURL, encoding: .utf8)
        #expect(migratedScript.contains("codex1m exec --skip-git-repo-check"))
        #expect(!migratedScript.contains("codex1m exec -c"))
    }

    @Test @MainActor func storeAppendsAndClearsLearningLogs() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.appendLearningLog(
            status: .success,
            outputSummary: "summary one",
            commandTemplate: #"c codex exec -m "$MODEL" "$PROMPT""#,
            projectPath: "/tmp/project-a",
            notesAbsolutePath: "/tmp/project-a/.agents/memory/inbox.md"
        )
        store.appendLearningLog(
            status: .failure,
            outputSummary: "   ",
            commandTemplate: #"c codex exec -m "$MODEL" "$PROMPT""#,
            projectPath: "/tmp/project-b",
            notesAbsolutePath: "/tmp/project-b/.agents/memory/inbox.md"
        )

        #expect(store.configuration.learningLogs.count == 2)
        #expect(store.configuration.learningLogs[0].status == .success)
        #expect(store.configuration.learningLogs[0].outputSummary == "summary one")
        #expect(store.configuration.learningLogs[1].status == .failure)
        #expect(store.configuration.learningLogs[1].outputSummary == "(no output)")

        let savedData = try Data(contentsOf: tempURL)
        let savedConfiguration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: savedData)
        #expect(savedConfiguration.learningLogs.count == 2)

        store.clearLearningLogs()
        #expect(store.configuration.learningLogs.isEmpty)

        let clearedData = try Data(contentsOf: tempURL)
        let clearedConfiguration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: clearedData)
        #expect(clearedConfiguration.learningLogs.isEmpty)
    }

    @Test func derivesHostNameFromAliasOrHostname() {
        #expect(
            AITerminalManagerStore.resolvedHostName(
                explicitName: "",
                sshAlias: "buildbox",
                hostname: "10.0.0.5",
                user: "deploy"
            ) == "buildbox"
        )
        #expect(
            AITerminalManagerStore.resolvedHostName(
                explicitName: "",
                sshAlias: "",
                hostname: "10.0.0.5",
                user: "deploy"
            ) == "deploy@10.0.0.5"
        )
    }

    @Test func sshConnectionsSidebarGroupsDoNotDuplicateHosts() {
        let recent = [
            AITerminalHost(
                id: "ssh:recent",
                name: "Recent",
                transport: .ssh,
                sshAlias: "recent",
                hostname: "10.0.0.1",
                user: "leon",
                port: 22,
                defaultDirectory: nil,
                source: .configurationFile
            ),
        ]
        let saved = [
            recent[0],
            AITerminalHost(
                id: "ssh:saved",
                name: "Saved",
                transport: .ssh,
                sshAlias: "saved",
                hostname: "10.0.0.2",
                user: "leon",
                port: 22,
                defaultDirectory: nil,
                source: .configurationFile
            ),
        ]
        let imported = [
            recent[0],
            saved[1],
            AITerminalHost(
                id: "ssh:imported",
                name: "Imported",
                transport: .ssh,
                sshAlias: "imported",
                hostname: "10.0.0.3",
                user: "leon",
                port: 22,
                defaultDirectory: nil,
                source: .sshConfig
            ),
        ]

        let displayRecent = SSHConnectionsView.deduplicatedRecentHosts(recent)
        let displaySaved = SSHConnectionsView.sidebarSavedHosts(
            savedHosts: saved,
            favoriteHosts: [],
            recentHosts: displayRecent
        )
        let displayImported = SSHConnectionsView.sidebarImportedHosts(
            importedHosts: imported,
            favoriteHosts: [],
            savedHosts: saved,
            recentHosts: displayRecent
        )

        #expect(displayRecent.map(\.id) == ["ssh:recent"])
        #expect(displaySaved.map(\.id) == ["ssh:saved"])
        #expect(displayImported.map(\.id) == ["ssh:imported"])
    }

    @Test func newTabPickerEntriesKeepLocalFirstAndSectionOrder() {
        let recent = [
            AITerminalHost(
                id: "ssh:recent",
                name: "Recent",
                transport: .ssh,
                sshAlias: "recent",
                hostname: "10.0.0.1",
                user: "leon",
                port: 22,
                defaultDirectory: nil,
                source: .configurationFile
            ),
        ]
        let saved = [
            recent[0],
            AITerminalHost(
                id: "ssh:saved",
                name: "Saved",
                transport: .ssh,
                sshAlias: "saved",
                hostname: "10.0.0.2",
                user: "leon",
                port: 22,
                defaultDirectory: nil,
                source: .configurationFile
            ),
        ]
        let imported = [
            saved[1],
            AITerminalHost(
                id: "ssh:imported",
                name: "Imported",
                transport: .ssh,
                sshAlias: "imported",
                hostname: "10.0.0.3",
                user: "leon",
                port: 22,
                defaultDirectory: nil,
                source: .sshConfig
            ),
        ]

        let entries = NewTabPickerModel.entries(
            favoriteHosts: [],
            recentHosts: recent,
            savedHosts: saved,
            importedHosts: imported
        ) { _ in false }

        #expect(entries.map(\.id) == ["local", "ssh:recent", "ssh:saved", "ssh:imported"])
        #expect(entries.map(\.shortcutIndex) == [1, 2, 3, 4])
    }

    @Test func newTabPickerEntriesExcludePasswordHostsWithoutStoredSecret() {
        let missingPasswordHost = AITerminalHost(
            id: "ssh:password",
            name: "Password",
            transport: .ssh,
            sshAlias: nil,
            hostname: "10.0.0.4",
            user: "leon",
            port: 22,
            defaultDirectory: nil,
            source: .configurationFile,
            authMode: .password
        )

        let entries = NewTabPickerModel.entries(
            favoriteHosts: [],
            recentHosts: [],
            savedHosts: [missingPasswordHost],
            importedHosts: []
        ) { _ in false }

        #expect(entries.map(\.id) == ["local"])
    }

    @Test func newTabPickerEntriesIncludeLocalMCDHost() {
        let localMCDHost = AITerminalHost(
            id: "localmcd:grokmcp",
            name: "grokmcp",
            transport: .localmcd,
            startupCommands: ["cd /tmp/grokmcp", "c codex"],
            sshAlias: nil,
            hostname: nil,
            user: nil,
            port: nil,
            defaultDirectory: nil,
            source: .configurationFile
        )

        let entries = NewTabPickerModel.entries(
            favoriteHosts: [],
            recentHosts: [],
            savedHosts: [localMCDHost],
            importedHosts: []
        ) { _ in false }

        #expect(entries.map(\.id) == ["local", "localmcd:grokmcp"])
    }

    @Test func newTabPickerEntriesExcludeLocalMCDHostWithoutStartupCommands() {
        let localMCDHost = AITerminalHost(
            id: "localmcd:grokmcp",
            name: "grokmcp",
            transport: .localmcd,
            startupCommands: [],
            sshAlias: nil,
            hostname: nil,
            user: nil,
            port: nil,
            defaultDirectory: nil,
            source: .configurationFile
        )

        let entries = NewTabPickerModel.entries(
            favoriteHosts: [],
            recentHosts: [],
            savedHosts: [localMCDHost],
            importedHosts: []
        ) { _ in false }

        #expect(entries.map(\.id) == ["local"])
    }
    @Test @MainActor func storeSavesHostWithoutExplicitName() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveHost(
            name: "",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "2222",
            defaultDirectory: "/srv/app"
        )

        #expect(store.lastError == nil)
        #expect(store.configuration.savedHosts.first?.name == "buildbox")
    }

    @Test @MainActor func storeUpdatesExistingHostByStableID() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "2222",
            defaultDirectory: "/srv/app"
        )

        store.saveHost(
            existingHostID: "ssh:buildbox",
            name: "Buildbox Prod",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "2200",
            defaultDirectory: "/srv/prod"
        )

        #expect(store.configuration.savedHosts.count == 1)
        #expect(store.configuration.savedHosts.first?.name == "Buildbox Prod")
        #expect(store.configuration.savedHosts.first?.port == 2200)
        #expect(store.configuration.savedHosts.first?.defaultDirectory == "/srv/prod")
    }

    @Test @MainActor func storeSavesPasswordHostIntoCredentialStore() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let credentialStore = MockSSHConnectionCredentialStore()

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL,
            credentialStore: credentialStore
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "/srv/app",
            authMode: .password,
            password: "secret"
        )

        #expect(store.configuration.savedHosts.first?.authMode == .password)
        #expect(credentialStore.passwords["ssh:buildbox"] == "secret")
    }

    @Test @MainActor func storeSwitchingBackToSystemAuthRemovesSavedPassword() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let credentialStore = MockSSHConnectionCredentialStore()

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL,
            credentialStore: credentialStore
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "",
            authMode: .password,
            password: "secret"
        )
        store.saveHost(
            existingHostID: "ssh:buildbox",
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "",
            authMode: .system
        )

        #expect(store.configuration.savedHosts.first?.authMode == .system)
        #expect(credentialStore.passwords["ssh:buildbox"] == nil)
    }

    @Test @MainActor func storeKeepsExistingPasswordWhenEditingWithoutNewPassword() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let credentialStore = MockSSHConnectionCredentialStore()

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL,
            credentialStore: credentialStore
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "",
            authMode: .password,
            password: "secret"
        )
        store.saveHost(
            existingHostID: "ssh:buildbox",
            name: "Buildbox Prod",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "/srv/prod",
            authMode: .password,
            password: ""
        )

        #expect(store.configuration.savedHosts.first?.name == "Buildbox Prod")
        #expect(credentialStore.passwords["ssh:buildbox"] == "secret")
    }

    @Test func taskStateLocalizationSupportsEnglishAndChinese() {
        #expect(
            AppLocalization.localizedString(
                "ai.manager.session.awaiting_approval",
                preferredLanguages: ["en-US"]
            ) == "Awaiting Approval"
        )
        #expect(
            AppLocalization.localizedString(
                "ai.manager.session.awaiting_approval",
                preferredLanguages: ["zh-Hans-CN"]
            ) == "等待审批"
        )
    }

    @Test func commandPayloadAppendsTrailingNewline() {
        #expect(AITerminalManagerStore.commandPayload(for: "ls -la") == "ls -la\n")
        #expect(AITerminalManagerStore.commandPayload(for: "ls -la\n") == "ls -la\n")
        #expect(AITerminalManagerStore.commandPayload(for: "   \n") == nil)
    }

    @Test func textPayloadPreservesRawInput() {
        #expect(AITerminalManagerStore.textPayload(for: "y") == "y")
        #expect(AITerminalManagerStore.textPayload(for: "line1\nline2") == "line1\nline2")
        #expect(AITerminalManagerStore.textPayload(for: "") == nil)
    }

    @Test func detectsCommonSSHAuthenticationPromptsAndFailures() {
        #expect(AITerminalManagerStore.containsSSHPasswordPrompt(in: "deploy@10.0.0.5's password:"))
        #expect(AITerminalManagerStore.containsSSHPasswordPrompt(in: "Password:"))
        #expect(!AITerminalManagerStore.containsSSHPasswordPrompt(in: "deploy@buildbox:~$"))
        #expect(AITerminalManagerStore.containsSSHAuthenticationFailure(in: "Permission denied, please try again."))
        #expect(AITerminalManagerStore.containsSSHAuthenticationFailure(in: "ssh: connect to host 10.0.0.5 port 22: Connection refused"))
    }

    @Test func recentHostRecordsAreUpdatedAndTrimmed() {
        let baseDate = Date(timeIntervalSince1970: 1_000)
        var records: [AITerminalRecentHostRecord] = []

        for offset in 0..<10 {
            records = AITerminalManagerStore.upsertRecentHostRecord(
                records,
                hostID: "ssh:host\(offset)",
                status: .connected,
                now: baseDate.addingTimeInterval(TimeInterval(offset))
            )
        }

        #expect(records.count == 8)
        #expect(records.first?.id == "ssh:host9")

        records = AITerminalManagerStore.upsertRecentHostRecord(
            records,
            hostID: "ssh:host4",
            status: .failed,
            errorSummary: "Permission denied",
            now: baseDate.addingTimeInterval(100)
        )
        #expect(records.first?.id == "ssh:host4")
        #expect(records.first?.status == .failed)
        #expect(records.first?.errorSummary == "Permission denied")
    }

    @Test func reconcilesImportedOverridesAndRecentRecords() {
        let configuration = AITerminalManagerConfiguration(
            savedHosts: [
                AITerminalHost(
                    id: "ssh:saved",
                    name: "Saved",
                    transport: .ssh,
                    sshAlias: "saved",
                    hostname: nil,
                    user: nil,
                    port: nil,
                    defaultDirectory: nil,
                    source: .configurationFile
                ),
            ],
            importedHostOverrides: [
                AITerminalHost(
                    id: "ssh:keep",
                    name: "Keep Override",
                    transport: .ssh,
                    sshAlias: "keep",
                    hostname: nil,
                    user: nil,
                    port: nil,
                    defaultDirectory: nil,
                    source: .configurationFile
                ),
                AITerminalHost(
                    id: "ssh:stale",
                    name: "Stale Override",
                    transport: .ssh,
                    sshAlias: "stale",
                    hostname: nil,
                    user: nil,
                    port: nil,
                    defaultDirectory: nil,
                    source: .configurationFile
                ),
            ],
            recentHosts: [
                .init(id: "ssh:keep", status: .connected),
                .init(id: "ssh:saved", status: .connected),
                .init(id: "ssh:stale", status: .failed),
            ]
        )

        let importedHosts = [
            AITerminalHost(
                id: "ssh:keep",
                name: "Keep",
                transport: .ssh,
                sshAlias: "keep",
                hostname: nil,
                user: nil,
                port: nil,
                defaultDirectory: nil,
                source: .sshConfig
            ),
        ]

        let reconciled = AITerminalManagerStore.reconciledConfiguration(
            configuration,
            importedHosts: importedHosts
        )

        #expect(reconciled.importedHostOverrides.map(\.id) == ["ssh:keep"])
        #expect(reconciled.recentHosts.map(\.id) == ["ssh:keep", "ssh:saved"])
    }

    @Test func reconcilesFavoriteHostsAndDropsInvalidIDs() {
        let configuration = AITerminalManagerConfiguration(
            savedHosts: [
                AITerminalHost(
                    id: "ssh:saved",
                    name: "Saved",
                    transport: .ssh,
                    sshAlias: "saved",
                    hostname: nil,
                    user: nil,
                    port: nil,
                    defaultDirectory: nil,
                    source: .configurationFile
                ),
            ],
            importedHostOverrides: [
                AITerminalHost(
                    id: "ssh:keep",
                    name: "Keep Override",
                    transport: .ssh,
                    sshAlias: "keep",
                    hostname: nil,
                    user: nil,
                    port: nil,
                    defaultDirectory: nil,
                    source: .configurationFile
                ),
            ],
            favoriteHostIDs: ["ssh:keep", "ssh:saved", "ssh:stale"],
            recentHosts: []
        )

        let importedHosts = [
            AITerminalHost(
                id: "ssh:keep",
                name: "Keep",
                transport: .ssh,
                sshAlias: "keep",
                hostname: nil,
                user: nil,
                port: nil,
                defaultDirectory: nil,
                source: .sshConfig
            ),
        ]

        let reconciled = AITerminalManagerStore.reconciledConfiguration(
            configuration,
            importedHosts: importedHosts
        )

        #expect(reconciled.favoriteHostIDs == ["ssh:keep", "ssh:saved"])
    }

    @Test func newTabPickerFavoritesPrecedeOtherSectionsAndDeduplicateHosts() {
        let favorite = AITerminalHost(
            id: "ssh:favorite",
            name: "Favorite",
            transport: .ssh,
            sshAlias: "favorite",
            hostname: "10.0.0.10",
            user: "leon",
            port: 22,
            defaultDirectory: nil,
            source: .configurationFile
        )
        let recent = [
            favorite,
            AITerminalHost(
                id: "ssh:recent",
                name: "Recent",
                transport: .ssh,
                sshAlias: "recent",
                hostname: "10.0.0.11",
                user: "leon",
                port: 22,
                defaultDirectory: nil,
                source: .configurationFile
            ),
        ]
        let saved = [
            favorite,
            recent[1],
            AITerminalHost(
                id: "ssh:saved",
                name: "Saved",
                transport: .ssh,
                sshAlias: "saved",
                hostname: "10.0.0.12",
                user: "leon",
                port: 22,
                defaultDirectory: nil,
                source: .configurationFile
            ),
        ]
        let imported = [
            saved[2],
            AITerminalHost(
                id: "ssh:imported",
                name: "Imported",
                transport: .ssh,
                sshAlias: "imported",
                hostname: "10.0.0.13",
                user: "leon",
                port: 22,
                defaultDirectory: nil,
                source: .sshConfig
            ),
        ]

        let entries = NewTabPickerModel.entries(
            favoriteHosts: [favorite],
            recentHosts: recent,
            savedHosts: saved,
            importedHosts: imported
        ) { _ in true }

        #expect(entries.map(\.id) == ["local", "ssh:favorite", "ssh:recent", "ssh:saved", "ssh:imported"])
        #expect(entries.map(\.section) == [.local, .favorites, .recent, .saved, .imported])
        #expect(entries.map(\.shortcutIndex) == [1, 2, 3, 4, 5])
    }

    @Test func sidebarGroupingHidesFavoritesFromRecentSavedAndImported() {
        let favorite = AITerminalHost(
            id: "ssh:favorite",
            name: "Favorite",
            transport: .ssh,
            sshAlias: "favorite",
            hostname: "10.0.0.10",
            user: "leon",
            port: 22,
            defaultDirectory: nil,
            source: .configurationFile
        )
        let recentOnly = AITerminalHost(
            id: "ssh:recent",
            name: "Recent",
            transport: .ssh,
            sshAlias: "recent",
            hostname: "10.0.0.11",
            user: "leon",
            port: 22,
            defaultDirectory: nil,
            source: .configurationFile
        )
        let savedOnly = AITerminalHost(
            id: "ssh:saved",
            name: "Saved",
            transport: .ssh,
            sshAlias: "saved",
            hostname: "10.0.0.12",
            user: "leon",
            port: 22,
            defaultDirectory: nil,
            source: .configurationFile
        )
        let importedOnly = AITerminalHost(
            id: "ssh:imported",
            name: "Imported",
            transport: .ssh,
            sshAlias: "imported",
            hostname: "10.0.0.13",
            user: "leon",
            port: 22,
            defaultDirectory: nil,
            source: .sshConfig
        )

        let favorites = SSHConnectionsView.sidebarFavoriteHosts(
            favoriteHosts: [favorite, favorite]
        )
        let recent = SSHConnectionsView.sidebarRecentHosts(
            recentHosts: [favorite, recentOnly, recentOnly],
            favoriteHosts: favorites
        )
        let saved = SSHConnectionsView.sidebarSavedHosts(
            savedHosts: [favorite, recentOnly, savedOnly],
            favoriteHosts: favorites,
            recentHosts: recent
        )
        let imported = SSHConnectionsView.sidebarImportedHosts(
            importedHosts: [favorite, recentOnly, savedOnly, importedOnly],
            favoriteHosts: favorites,
            savedHosts: [favorite, recentOnly, savedOnly],
            recentHosts: recent
        )

        #expect(favorites.map(\.id) == ["ssh:favorite"])
        #expect(recent.map(\.id) == ["ssh:recent"])
        #expect(saved.map(\.id) == ["ssh:saved"])
        #expect(imported.map(\.id) == ["ssh:imported"])
    }

    @Test func duplicateAliasAvoidsCollisions() {
        let host = AITerminalHost(
            id: "configured:deploy@10.0.0.5",
            name: "Buildbox Prod",
            transport: .ssh,
            sshAlias: nil,
            hostname: "10.0.0.5",
            user: "deploy",
            port: 22,
            defaultDirectory: nil,
            source: .configurationFile
        )
        let existingHosts = [
            AITerminalHost(
                id: "ssh:10-0-0-5-copy",
                name: "Buildbox Prod Copy",
                transport: .ssh,
                sshAlias: "10-0-0-5-copy",
                hostname: "10.0.0.5",
                user: "deploy",
                port: 22,
                defaultDirectory: nil,
                source: .configurationFile
            ),
        ]

        let alias = AITerminalManagerStore.duplicateAlias(for: host, existingHosts: existingHosts)
        #expect(alias == "10-0-0-5-copy-2")
    }

    @Test @MainActor func reloadImportedSSHHostsUsesInjectedLoader() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL,
            sshConfigHostLoader: {
                [
                    AITerminalHost(
                        id: "ssh:buildbox",
                        name: "Buildbox",
                        transport: .ssh,
                        sshAlias: "buildbox",
                        hostname: "10.0.0.5",
                        user: "deploy",
                        port: 2222,
                        defaultDirectory: nil,
                        source: .sshConfig
                    ),
                ]
            }
        )

        store.reloadImportedSSHHosts()

        #expect(store.importedSSHHosts.map(\.id) == ["ssh:buildbox"])
        #expect(store.mergedImportedHosts.map(\.id) == ["ssh:buildbox"])
    }

    @Test @MainActor func recentRecordReturnsLatestStatusForHost() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let host = AITerminalHost(
            id: "ssh:buildbox",
            name: "Buildbox",
            transport: .ssh,
            sshAlias: "buildbox",
            hostname: "10.0.0.5",
            user: "deploy",
            port: 22,
            defaultDirectory: nil,
            source: .configurationFile
        )
        let configuration = AITerminalManagerConfiguration(
            savedHosts: [host],
            recentHosts: [
                .init(id: host.id, connectedAt: Date(timeIntervalSince1970: 1), status: .connected),
                .init(id: host.id, connectedAt: Date(timeIntervalSince1970: 2), status: .failed, errorSummary: "Permission denied"),
            ]
        )
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: tempURL, options: .atomic)

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let record = store.recentRecord(for: host)
        #expect(record?.status == .failed)
        #expect(record?.errorSummary == "Permission denied")
    }

    @Test @MainActor func sendCommandRequiresSessionSelection() {
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )

        store.sendCommand("pwd")

        #expect(store.lastError == L10n.AITerminalManager.selectSessionFirst)
    }
}
