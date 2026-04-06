import Testing
import Combine
import Foundation
import AppKit
@testable import GhoDex

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

private struct HeartbeatPressureResult: Codable {
    var mode: String
    var maxConcurrentTasks: Int
    var taskCount: Int
    var taskSleepSeconds: Double
    var elapsedSeconds: Double
    var sequentialSeconds: Double
    var speedupVsSequential: Double
    var peakRunningCount: Int
}

private enum AITerminalManagerTestSupport {
    static let managedConfigStartMarker = "# >>> GhoDex managed settings >>>"
    static let managedConfigEndMarker = "# <<< GhoDex managed settings <<<"

    static func configStringLiteral(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [])
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "AITerminalManagerTests", code: 1)
        }
        return String(encoded.dropFirst().dropLast())
    }

    static func encodedConfigStringLiteral(_ value: String) throws -> String {
        try configStringLiteral(Data(value.utf8).base64EncodedString())
    }

    static func encodedPayload<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value).base64EncodedString()
    }

    static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
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
        #expect(configuration.heartbeatQueueSettings.enabled)
        #expect(configuration.heartbeatQueueSettings.heartbeatIntervalSeconds == 5)
        #expect(configuration.heartbeatQueueSettings.maxConcurrentTasks == 4)
        #expect(configuration.heartbeatQueueSettings.allowExternalInboxMutations == false)
        #expect(configuration.heartbeatTasks.isEmpty)
    }

    @Test func decodesLegacyConfigurationWithDefaultLearningSettings() throws {
        let data = Data(#"{"schemaVersion":2,"savedHosts":[],"importedHostOverrides":[],"favoriteHostIDs":[],"recentHosts":[],"workspaces":[]}"#.utf8)
        let configuration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)

        #expect(configuration.todoSettings.enabled)
        #expect(configuration.todoSettings.workspaceRootPath == AITerminalTodoSettings.defaultWorkspaceRootPath)
        #expect(configuration.todoSettings.showCompletedItems)
        #expect(configuration.todoSettings.sidebarEdge == .leading)
        #expect(configuration.todoSettings.workspaceOverlayVisible == false)
        #expect(configuration.todoSettings.workspaceOverlayCorner == .topLeading)
        #expect(configuration.learningSettings.enabled)
        #expect(configuration.learningSettings.preferTabWorkingDirectory)
        #expect(configuration.learningSettings.notesRelativePath == AITerminalLearningSettings.defaultNotesRelativePath)
        #expect(configuration.learningSettings.commandTemplate == AITerminalLearningSettings.defaultCommandTemplate)
        #expect(configuration.learningSettings.fastModel == AITerminalLearningSettings.defaultFastModel)
        #expect(configuration.learningSettings.promptTemplate == AITerminalLearningSettings.defaultPromptTemplate)
        #expect(configuration.learningLogs.isEmpty)
        #expect(configuration.agentRuntimeSettings.enabled)
        #expect(configuration.agentRuntimeSettings.defaultLeaseDurationSeconds == 30)
        #expect(configuration.agentRuntimeSettings.staleTaskPolicy == .requeueClaimedWork)
        #expect(configuration.agentRuntimeSessions.isEmpty)
        #expect(configuration.agentRuntimeTasks.isEmpty)
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
            name: "GhoDex",
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

    @Test @MainActor func storeClampsHeartbeatIntervalSettings() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveHeartbeatQueueSettings(.init(enabled: true, heartbeatIntervalSeconds: 0.1, maxConcurrentTasks: 0))
        #expect(store.heartbeatQueueSettings.heartbeatIntervalSeconds == 0.5)
        #expect(store.heartbeatQueueSettings.maxConcurrentTasks == 1)

        store.saveHeartbeatQueueSettings(.init(enabled: true, heartbeatIntervalSeconds: 120, maxConcurrentTasks: 999))
        #expect(store.heartbeatQueueSettings.heartbeatIntervalSeconds == 60)
        #expect(store.heartbeatQueueSettings.maxConcurrentTasks == 16)
    }

    @Test @MainActor func storeManagesHeartbeatQueueLifecycle() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        store.saveHeartbeatQueueSettings(.init(enabled: false, heartbeatIntervalSeconds: 5, maxConcurrentTasks: 4))

        let queuedID = store.enqueueHeartbeatTask(command: "codex exec \"status\"")
        #expect(queuedID != nil)
        #expect(store.heartbeatQueuedCount == 1)

        if let queuedID {
            store.cancelHeartbeatTask(queuedID)
        }
        #expect(store.heartbeatQueuedCount == 0)
        #expect(store.heartbeatQueueTasks.first?.status == .cancelled)

        store.clearFinishedHeartbeatTasks()
        #expect(store.heartbeatQueueTasks.isEmpty)
    }

    @Test @MainActor func storeBlocksExternalHeartbeatInboxMutationsByDefault() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let configURL = baseDirectory.appendingPathComponent("config.ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: configURL
        )
        store.saveHeartbeatQueueSettings(.init(
            enabled: true,
            heartbeatIntervalSeconds: 0.5,
            maxConcurrentTasks: 1,
            allowExternalInboxMutations: false
        ))

        let inboxURL = URL(fileURLWithPath: store.heartbeatInboxDirectoryPath, isDirectory: true)
        let payload: [String: Any] = [
            "action": "enqueue",
            "command": "echo blocked",
            "type": "exec",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let requestURL = inboxURL.appendingPathComponent("blocked-request.json")
        try data.write(to: requestURL, options: .atomic)

        let timeout = Date().addingTimeInterval(3)
        var blockedFiles: [URL] = []
        while Date() < timeout {
            blockedFiles = try FileManager.default.contentsOfDirectory(
                at: inboxURL,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "blocked" }
            if !blockedFiles.isEmpty {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(store.heartbeatQueueTasks.isEmpty)
        #expect(store.heartbeatQueuedCount == 0)
        #expect(store.heartbeatDoneCount == 0)
        #expect(blockedFiles.count == 1)
    }

    @Test @MainActor func storeRunsDueHeartbeatTasksWithBoundedConcurrencyUnderLoad() async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let maxConcurrentTasks = 4
        let taskCount = 64
        let taskSleepSeconds = 0.2
        store.saveHeartbeatQueueSettings(.init(
            enabled: true,
            heartbeatIntervalSeconds: 0.5,
            maxConcurrentTasks: maxConcurrentTasks
        ))

        for _ in 0..<taskCount {
            let id = store.enqueueHeartbeatTask(
                command: "sleep \(taskSleepSeconds)"
            )
            #expect(id != nil)
        }

        let timeout = Date().addingTimeInterval(max(Double(taskCount) * taskSleepSeconds * 3, 30))
        var peakRunningCount = 0

        while Date() < timeout {
            peakRunningCount = max(peakRunningCount, store.heartbeatRunningCount)
            if store.heartbeatDoneCount == taskCount {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(
            store.heartbeatDoneCount == taskCount,
            "done=\(store.heartbeatDoneCount) running=\(store.heartbeatRunningCount) queued=\(store.heartbeatQueuedCount) failed=\(store.heartbeatFailedCount)"
        )
        #expect(store.heartbeatFailedCount == 0)
        #expect(store.heartbeatQueuedCount == 0)
        #expect(store.heartbeatRunningCount == 0)
        #expect(peakRunningCount <= maxConcurrentTasks)
        // The benchmark test below measures speedup separately; keep this test focused
        // on correctness because full-suite load makes real-time thresholds noisy.
        #expect(peakRunningCount > 1)
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

        let configuration = try AITerminalManagerStore.loadConfiguration(at: tempURL)

        #expect(configuration.learningSettings.enabled)
        #expect(!configuration.learningSettings.preferTabWorkingDirectory)
        #expect(configuration.learningSettings.defaultProjectPath == "/Users/leongong/Desktop/LeonProjects/codex_chat_workspace")
        #expect(configuration.learningSettings.notesRelativePath == ".agents/memory/custom.md")
        #expect(configuration.learningSettings.commandTemplate == #"c codex -m "$MODEL" "$PROMPT""#)
        #expect(configuration.learningSettings.fastModel == AITerminalLearningSettings.defaultFastModel)
        #expect(configuration.learningSettings.promptTemplate == AITerminalLearningSettings.defaultPromptTemplate)
    }

    @Test @MainActor func storeSavesTodoSettings() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveTodoSettings(.init(
            enabled: true,
            workspaceRootPath: "/tmp/ghodex-todo-tests",
            showCompletedItems: false,
            selectedDateAnchor: "2026-03-20",
            sidebarEdge: .trailing,
            workspaceOverlayVisible: false,
            workspaceOverlayCorner: .bottomTrailing
        ))

        let configuration = try AITerminalManagerStore.loadConfiguration(at: tempURL)
        #expect(configuration.todoSettings.enabled)
        #expect(configuration.todoSettings.workspaceRootPath == "/tmp/ghodex-todo-tests")
        #expect(configuration.todoSettings.showCompletedItems == false)
        #expect(configuration.todoSettings.selectedDateAnchor == "2026-03-20")
        #expect(configuration.todoSettings.sidebarEdge == .trailing)
        #expect(configuration.todoSettings.workspaceOverlayVisible == false)
        #expect(configuration.todoSettings.workspaceOverlayCorner == .bottomTrailing)
    }

    @Test @MainActor func storeClearsTodoErrorsWhenSavingSettings() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        #expect(store.addTodoItem(title: "   ", notes: "", for: .now) == nil)
        #expect(store.lastError == "Todo title cannot be empty.")

        store.saveTodoSettings(.init(
            enabled: true,
            workspaceRootPath: "/tmp/ghodex-todo-tests",
            showCompletedItems: true,
            selectedDateAnchor: "2026-03-21",
            sidebarEdge: .leading,
            workspaceOverlayVisible: true,
            workspaceOverlayCorner: .topLeading
        ))

        #expect(store.lastError == nil)
        #expect(store.todoSettings.workspaceRootPath == "/tmp/ghodex-todo-tests")
    }

    @Test @MainActor func newTabPickerControllerUsesExpandedWindowSizing() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        let controller = NewTabPickerController(store: store)

        #expect(controller.window?.frame.size.width == 860)
        #expect(controller.window?.frame.size.height == 640)
        #expect(controller.window?.minSize.width == 760)
        #expect(controller.window?.minSize.height == 560)
    }

    @Test func newTabPickerEntriesPreserveOrderingAndFilteringBehavior() {
        let favorite = AITerminalHost(
            id: "ssh:fav",
            name: "Favorite Box",
            transport: .ssh,
            sshAlias: "fav",
            hostname: "10.0.0.2",
            user: "deploy",
            port: 22,
            defaultDirectory: "/srv/fav",
            source: .configurationFile
        )
        let duplicateRecent = favorite
        let saved = AITerminalHost(
            id: "ssh:saved",
            name: "Saved Box",
            transport: .ssh,
            sshAlias: "saved",
            hostname: "10.0.0.3",
            user: "deploy",
            port: 22,
            defaultDirectory: "/srv/saved",
            source: .configurationFile
        )
        let imported = AITerminalHost(
            id: "ssh:imported",
            name: "Imported Box",
            transport: .ssh,
            sshAlias: "imported",
            hostname: "10.0.0.4",
            user: "deploy",
            port: 22,
            defaultDirectory: "/srv/imported",
            source: .sshConfig
        )
        let passwordHost = AITerminalHost(
            id: "ssh:password",
            name: "Password Box",
            transport: .ssh,
            sshAlias: "password",
            hostname: "10.0.0.5",
            user: "deploy",
            port: 22,
            defaultDirectory: "/srv/password",
            source: .configurationFile,
            authMode: .password
        )
        let workspace = AITerminalSavedWorkspaceTemplate(
            name: "Research Workspace",
            root: .pane(.init(
                tabs: [.init(hostID: favorite.id, directory: "/tmp/research")],
                activeTabIndex: 0
            ))
        )

        let entries = NewTabPickerModel.entries(
            favoriteHosts: [favorite],
            recentHosts: [duplicateRecent],
            savedHosts: [saved, passwordHost],
            importedHosts: [imported],
            savedWorkspaceTemplates: [workspace],
            mode: .topLevel
        ) { host in
            host.id != passwordHost.id
        }

        #expect(entries.map(\.id) == [
            AITerminalHost.local.id,
            favorite.id,
            saved.id,
            imported.id,
            workspace.id,
        ])
        #expect(entries.map(\.shortcutIndex) == [1, 2, 3, 4, 5])

        let filtered = NewTabPickerModel.filteredEntries(entries, query: "research")
        #expect(filtered.map(\.id) == [workspace.id])

        let paneChildEntries = NewTabPickerModel.entries(
            favoriteHosts: [favorite],
            recentHosts: [],
            savedHosts: [],
            importedHosts: [],
            savedWorkspaceTemplates: [workspace],
            mode: .paneChild
        ) { _ in true }
        #expect(!paneChildEntries.contains(where: { entry in
            if case .savedWorkspace = entry.kind {
                return true
            }
            return false
        }))
    }

    @Test @MainActor func storeLoadsConfigurationFromManagedGhoDexConfigBlock() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let savedHost = AITerminalHost(
            id: "ssh:buildbox",
            name: "Buildbox",
            transport: .ssh,
            sshAlias: "buildbox",
            hostname: "10.0.0.5",
            user: "deploy",
            port: 2222,
            defaultDirectory: "/srv/app",
            source: .configurationFile
        )
        let payload = try AITerminalManagerTestSupport.encodedPayload(savedHost)
        let favorite = try AITerminalManagerTestSupport.configStringLiteral("ssh:buildbox")

        let text = """
        font-size = 14

        \(AITerminalManagerTestSupport.managedConfigStartMarker)
        ghodex-saved-host = \(try AITerminalManagerTestSupport.configStringLiteral(payload))
        ghodex-favorite-host = \(favorite)
        ghodex-learning-enabled = false
        ghodex-heartbeat-interval-seconds = 7
        \(AITerminalManagerTestSupport.managedConfigEndMarker)
        """
        try text.write(to: tempURL, atomically: true, encoding: .utf8)

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        #expect(store.configuration.savedHosts.count == 1)
        #expect(store.configuration.savedHosts.first?.id == "ssh:buildbox")
        #expect(store.configuration.favoriteHostIDs == ["ssh:buildbox"])
        #expect(store.configuration.learningSettings.enabled == false)
        #expect(store.configuration.heartbeatQueueSettings.heartbeatIntervalSeconds == 7)
    }

    @Test @MainActor func storePersistsConfigurationIntoManagedGhoDexConfigBlock() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        try "font-size = 14\n".write(to: tempURL, atomically: true, encoding: .utf8)

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

        let text = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(text.contains("font-size = 14"))
        #expect(text.contains(AITerminalManagerTestSupport.managedConfigStartMarker))
        #expect(text.contains(AITerminalManagerTestSupport.managedConfigEndMarker))
        #expect(text.contains("ghodex-saved-host = "))
        #expect(!text.contains("\"savedHosts\""))
        #expect(AITerminalManagerTestSupport.occurrences(of: AITerminalManagerTestSupport.managedConfigStartMarker, in: text) == 1)
        #expect(AITerminalManagerTestSupport.occurrences(of: AITerminalManagerTestSupport.managedConfigEndMarker, in: text) == 1)
    }

    @Test @MainActor func storeReloadsPersistedConfigurationFromGhoDexConfig() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let storeA = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        storeA.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "2222",
            defaultDirectory: "/srv/app"
        )
        storeA.saveLearningSettings(.init(
            enabled: true,
            preferTabWorkingDirectory: false,
            defaultProjectPath: "/tmp/learn-workspace",
            notesRelativePath: ".agents/memory/custom.md",
            commandTemplate: #"c codex -m "$MODEL" "$PROMPT""#,
            fastModel: "ignored-fast-model",
            promptTemplate: "ignored prompt"
        ))
        storeA.saveHeartbeatQueueSettings(.init(
            enabled: true,
            heartbeatIntervalSeconds: 7,
            maxConcurrentTasks: 3,
            allowExternalInboxMutations: true
        ))

        let storeB = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        #expect(storeB.configuration.savedHosts.map(\.id) == ["ssh:buildbox"])
        #expect(storeB.configuration.learningSettings.preferTabWorkingDirectory == false)
        #expect(storeB.configuration.learningSettings.defaultProjectPath == "/tmp/learn-workspace")
        #expect(storeB.configuration.learningSettings.notesRelativePath == ".agents/memory/custom.md")
        #expect(storeB.configuration.learningSettings.commandTemplate == #"c codex -m "$MODEL" "$PROMPT""#)
        #expect(storeB.configuration.heartbeatQueueSettings.enabled)
        #expect(storeB.configuration.heartbeatQueueSettings.heartbeatIntervalSeconds == 7)
        #expect(storeB.configuration.heartbeatQueueSettings.maxConcurrentTasks == 3)
        #expect(storeB.configuration.heartbeatQueueSettings.allowExternalInboxMutations)
    }

    @Test @MainActor func storeRefreshReloadsTodoSettingsFromManagedConfigBlock() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        try """
        font-size = 14
        """.write(to: tempURL, atomically: true, encoding: .utf8)

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let text = """
        font-size = 14

        \(AITerminalManagerTestSupport.managedConfigStartMarker)
        ghodex-todo-enabled = false
        ghodex-todo-workspace-root-path = \(try AITerminalManagerTestSupport.encodedConfigStringLiteral("/tmp/refreshed-todo-root"))
        ghodex-todo-show-completed-items = false
        ghodex-todo-selected-date-anchor = \(try AITerminalManagerTestSupport.encodedConfigStringLiteral("2026-03-19"))
        ghodex-todo-sidebar-edge = \(try AITerminalManagerTestSupport.encodedConfigStringLiteral("trailing"))
        ghodex-todo-workspace-overlay-visible = false
        ghodex-todo-workspace-overlay-corner = \(try AITerminalManagerTestSupport.encodedConfigStringLiteral("bottom-trailing"))
        \(AITerminalManagerTestSupport.managedConfigEndMarker)
        """
        try text.write(to: tempURL, atomically: true, encoding: .utf8)

        store.refresh()

        #expect(store.todoSettings.enabled == false)
        #expect(store.todoSettings.workspaceRootPath == "/tmp/refreshed-todo-root")
        #expect(store.todoSettings.showCompletedItems == false)
        #expect(store.todoSettings.selectedDateAnchor == "2026-03-19")
        #expect(store.todoSettings.sidebarEdge == .trailing)
        #expect(store.todoSettings.workspaceOverlayVisible == false)
        #expect(store.todoSettings.workspaceOverlayCorner == .bottomTrailing)
    }

    @Test @MainActor func storePersistsAgentRuntimeStateIntoManagedGhoDexConfigBlock() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        try "font-size = 14\n".write(to: tempURL, atomically: true, encoding: .utf8)

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveAgentRuntimeSettings(.init(
            enabled: true,
            defaultLeaseDurationSeconds: 42,
            staleTaskPolicy: .pauseClaimedWork
        ))
        let session = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            tabID: UUID(),
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"]
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            priority: 2,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd")
        )
        let schedule = try store.enqueueAgentRuntimeSchedule(
            taskKind: .terminalCommand,
            priority: 4,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "echo scheduled"),
            startAt: Date().addingTimeInterval(60),
            recurrence: .init(mode: .once)
        )

        let text = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(text.contains("ghodex-agent-runtime-enabled = true"))
        #expect(text.contains("ghodex-agent-runtime-default-lease-seconds = 42"))
        #expect(text.contains("ghodex-agent-runtime-stale-task-policy = "))
        #expect(text.contains("ghodex-agent-runtime-session = "))
        #expect(text.contains("ghodex-agent-runtime-task = "))
        #expect(text.contains("ghodex-agent-runtime-schedule = "))

        let reloaded = try AITerminalManagerStore.loadConfiguration(at: tempURL)
        #expect(reloaded.agentRuntimeSettings.defaultLeaseDurationSeconds == 42)
        #expect(reloaded.agentRuntimeSettings.staleTaskPolicy == .pauseClaimedWork)
        #expect(reloaded.agentRuntimeSessions.contains(where: { $0.id == session.id }))
        #expect(reloaded.agentRuntimeTasks.contains(where: { $0.id == task.id }))
        #expect(reloaded.agentRuntimeSchedules.contains(where: { $0.id == schedule.id }))
    }

    @Test @MainActor func storeAutoAddsCanonicalExecutorCapabilitiesForBrowserAndVisionWork() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let browserTask = try store.enqueueAgentRuntimeTask(
            kind: .browserNavigation,
            capabilityRequirements: ["browser", "task-runtime"],
            payload: .init(metadata: ["url": "https://example.com"])
        )
        let visionSchedule = try store.enqueueAgentRuntimeSchedule(
            taskKind: .visionAutomation,
            capabilityRequirements: ["vision", "task-claim"],
            payload: .init(metadata: ["instruction": "click submit"]),
            startAt: Date().addingTimeInterval(60),
            recurrence: .init(mode: .once)
        )

        #expect(browserTask.capabilityRequirements == [
            AgentRuntimeCapability.runtimeExecutorBrowser.rawValue,
            AgentRuntimeCapability.runtimeTaskManage.rawValue,
        ])
        #expect(visionSchedule.capabilityRequirements == [
            AgentRuntimeCapability.runtimeExecutorVision.rawValue,
            AgentRuntimeCapability.runtimeTaskClaim.rawValue,
        ])

        let persistedTask = try #require(store.agentRuntimeTasks.first(where: { $0.id == browserTask.id }))
        let persistedSchedule = try #require(store.agentRuntimeSchedules.first(where: { $0.id == visionSchedule.id }))
        #expect(persistedTask.capabilityRequirements == browserTask.capabilityRequirements)
        #expect(persistedSchedule.capabilityRequirements == visionSchedule.capabilityRequirements)
    }

    @Test @MainActor func storeMaterializesOneShotAgentRuntimeScheduleIntoQueuedTask() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = try store.enqueueAgentRuntimeSchedule(
            taskKind: .terminalCommand,
            priority: 3,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "echo once"),
            startAt: now.addingTimeInterval(-1),
            recurrence: .init(mode: .once),
            maxRetryCount: 2,
            now: now
        )

        let persistedSchedule = try #require(store.agentRuntimeSchedules.first(where: { $0.id == schedule.id }))
        let task = try #require(store.agentRuntimeTasks.first(where: {
            $0.payload.metadata["ghodex_schedule_id"] == schedule.id.uuidString.lowercased()
        }))

        #expect(persistedSchedule.state == .completed)
        #expect(persistedSchedule.nextRunAt == nil)
        #expect(task.state == .queued)
        #expect(task.priority == 3)
        #expect(task.maxRetryCount == 2)
        #expect(task.payload.command == "echo once")
    }

    @Test @MainActor func storeKeepsFutureAgentRuntimeSchedulePendingUntilDue() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let futureStart = now.addingTimeInterval(300)
        let schedule = try store.enqueueAgentRuntimeSchedule(
            taskKind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "echo future"),
            startAt: futureStart,
            recurrence: .init(mode: .once),
            now: now
        )

        #expect(store.agentRuntimeTasks.isEmpty)
        let persistedSchedule = store.agentRuntimeSchedules.first(where: { $0.id == schedule.id })
        #expect(persistedSchedule?.state == .active)
        #expect(persistedSchedule?.lastTaskID == nil)
        #expect(persistedSchedule?.nextRunAt == futureStart)
    }

    @Test @MainActor func storeMaterializesIntervalAgentRuntimeScheduleWithoutDuplicatingActiveWork() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let schedule = try store.enqueueAgentRuntimeSchedule(
            taskKind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "echo interval"),
            startAt: start,
            recurrence: .init(mode: .interval, intervalSeconds: 10),
            now: start
        )

        let firstTask = try #require(store.agentRuntimeTasks.first(where: {
            $0.payload.metadata["ghodex_schedule_id"] == schedule.id.uuidString.lowercased()
        }))
        let firstSnapshot = try #require(store.agentRuntimeSchedules.first(where: { $0.id == schedule.id }))
        #expect(firstSnapshot.state == .active)
        #expect(firstSnapshot.nextRunAt == start.addingTimeInterval(10))

        store.refresh()
        #expect(store.agentRuntimeTasks.filter {
            $0.payload.metadata["ghodex_schedule_id"] == schedule.id.uuidString.lowercased()
        }.count == 1)

        _ = try store.cancelAgentRuntimeTask(
            taskID: firstTask.id,
            reason: "done",
            force: true,
            now: start.addingTimeInterval(5)
        )

        _ = try store.updateAgentRuntimeSchedule(
            scheduleID: schedule.id,
            startAt: start.addingTimeInterval(-20),
            recurrence: .init(mode: .interval, intervalSeconds: 10),
            now: start.addingTimeInterval(20)
        )

        let materializedTasks = store.agentRuntimeTasks.filter {
            $0.payload.metadata["ghodex_schedule_id"] == schedule.id.uuidString.lowercased()
        }
        #expect(materializedTasks.count == 2)
        let updatedSchedule = try #require(store.agentRuntimeSchedules.first(where: { $0.id == schedule.id }))
        #expect(updatedSchedule.state == .active)
        #expect(updatedSchedule.nextRunAt != nil)
    }

    @Test @MainActor func storeResumesIntervalAgentRuntimeScheduleAfterRestart() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let start = Date().addingTimeInterval(0.3)
        let storeA = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        let schedule = try storeA.enqueueAgentRuntimeSchedule(
            taskKind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "echo restart-loop"),
            startAt: start,
            recurrence: .init(mode: .interval, intervalSeconds: 1),
            now: Date()
        )
        #expect(storeA.agentRuntimeTasks.isEmpty)

        let storeB = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        #expect(storeB.agentRuntimeSchedules.contains(where: { $0.id == schedule.id }))
        #expect(storeB.agentRuntimeTasks.isEmpty)

        try? await Task.sleep(nanoseconds: 500_000_000)
        storeB.refresh()

        let firstTask = try #require(storeB.agentRuntimeTasks.first(where: {
            $0.payload.metadata["ghodex_schedule_id"] == schedule.id.uuidString.lowercased()
        }))
        let firstSnapshot = try #require(storeB.agentRuntimeSchedules.first(where: { $0.id == schedule.id }))
        #expect(firstSnapshot.lastTaskID == firstTask.id)

        _ = try storeB.cancelAgentRuntimeTask(
            taskID: firstTask.id,
            reason: "advance-loop",
            force: true
        )

        try? await Task.sleep(nanoseconds: 1_100_000_000)
        storeB.refresh()

        let materializedTasks = storeB.agentRuntimeTasks.filter {
            $0.payload.metadata["ghodex_schedule_id"] == schedule.id.uuidString.lowercased()
        }
        #expect(materializedTasks.count == 2)
        let resumedSchedule = try #require(storeB.agentRuntimeSchedules.first(where: { $0.id == schedule.id }))
        #expect(resumedSchedule.state == .active)
        #expect(resumedSchedule.lastTaskID != firstTask.id)
        #expect(resumedSchedule.nextRunAt != nil)
    }

    @Test @MainActor func storeAllowsMultipleRuntimeSessionsForSameWorkspaceAcrossDifferentTabs() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let workspaceID = UUID()
        let first = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            tabID: UUID(),
            terminalID: UUID(),
            hostWorkspaceID: workspaceID,
            capabilities: ["terminal"]
        )
        let second = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            tabID: UUID(),
            terminalID: UUID(),
            hostWorkspaceID: workspaceID,
            capabilities: ["terminal"]
        )

        let firstSession = try #require(store.agentRuntimeSessions.first(where: { $0.id == first.id }))
        let secondSession = try #require(store.agentRuntimeSessions.first(where: { $0.id == second.id }))
        #expect(firstSession.state == .active)
        #expect(secondSession.state == .active)
        #expect(firstSession.lastError == nil)
        #expect(secondSession.lastError == nil)
    }

    @Test @MainActor func storeSupersedesWorkspaceOnlyRuntimeSessionsWhenNoTabOrTerminalIdentityExists() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let workspaceID = UUID()
        let first = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            hostWorkspaceID: workspaceID,
            capabilities: ["terminal"]
        )
        let second = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            hostWorkspaceID: workspaceID,
            capabilities: ["terminal"]
        )

        let firstSession = try #require(store.agentRuntimeSessions.first(where: { $0.id == first.id }))
        let secondSession = try #require(store.agentRuntimeSessions.first(where: { $0.id == second.id }))
        #expect(firstSession.state == .expired)
        #expect(firstSession.lastError == "superseded_by_new_registration")
        #expect(secondSession.state == .active)
    }

    @Test @MainActor func storeCanClaimRuntimeTasksForSpecificKindsOnly() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let now = Date(timeIntervalSince1970: 1_710_000_100)
        let session = try store.registerAgentRuntimeSession(
            clientKind: .hostExecutor,
            capabilities: [AgentRuntimeCapability.runtimeExecutorBrowser.rawValue],
            now: now
        )
        let hostWorkflow = try store.enqueueAgentRuntimeTask(
            kind: .hostWorkflow,
            payload: .init(text: "noop"),
            now: now
        )
        let browserTask = try store.enqueueAgentRuntimeTask(
            kind: .browserNavigation,
            payload: .init(metadata: ["url": "https://example.com"]),
            now: now
        )

        let claimedTask = try #require(try store.claimNextAgentRuntimeTask(
            sessionID: session.id,
            allowedKinds: [.browserNavigation, .browserInteraction],
            now: now
        ))

        #expect(claimedTask.id == browserTask.id)
        #expect(store.agentRuntimeTasks.first(where: { $0.id == hostWorkflow.id })?.state == .queued)
    }

    @Test @MainActor func storeRejectsRuntimeMutationsWhenRuntimeIsDisabled() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let session = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"]
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd")
        )
        let claimedTask = try #require(try store.claimNextAgentRuntimeTask(sessionID: session.id))
        #expect(claimedTask.id == task.id)

        store.saveAgentRuntimeSettings(.init(
            enabled: false,
            defaultLeaseDurationSeconds: 30,
            staleTaskPolicy: .requeueClaimedWork
        ))

        do {
            _ = try store.enqueueAgentRuntimeTask(
                kind: .terminalCommand,
                capabilityRequirements: ["terminal"],
                payload: .init(command: "echo blocked")
            )
            Issue.record("Expected enqueueAgentRuntimeTask to reject while runtime is disabled")
        } catch let error as AgentRuntimeStoreError {
            #expect(error == .runtimeDisabled)
        }

        do {
            _ = try store.enqueueAgentRuntimeSchedule(
                taskKind: .terminalCommand,
                capabilityRequirements: ["terminal"],
                payload: .init(command: "echo blocked schedule")
            )
            Issue.record("Expected enqueueAgentRuntimeSchedule to reject while runtime is disabled")
        } catch let error as AgentRuntimeStoreError {
            #expect(error == .runtimeDisabled)
        }

        do {
            _ = try store.updateAgentRuntimeTask(
                sessionID: session.id,
                taskID: claimedTask.id,
                state: .running
            )
            Issue.record("Expected updateAgentRuntimeTask to reject while runtime is disabled")
        } catch let error as AgentRuntimeStoreError {
            #expect(error == .runtimeDisabled)
        }
    }

    @Test @MainActor func heartbeatTickDoesNotExpireSessionsWhenRuntimeDisabled() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        store.saveAgentRuntimeSettings(.init(
            enabled: true,
            defaultLeaseDurationSeconds: 30,
            staleTaskPolicy: .requeueClaimedWork
        ))
        store.saveHeartbeatQueueSettings(.init(
            enabled: true,
            heartbeatIntervalSeconds: 0.5,
            maxConcurrentTasks: 1,
            allowExternalInboxMutations: false
        ))

        let registeredAt = Date(timeIntervalSince1970: 1_710_000_000)
        let session = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"],
            leaseDurationSeconds: 5,
            now: registeredAt
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd"),
            now: registeredAt
        )
        let claimedTask = try #require(try store.claimNextAgentRuntimeTask(
            sessionID: session.id,
            now: registeredAt
        ))
        #expect(claimedTask.id == task.id)

        store.saveAgentRuntimeSettings(.init(
            enabled: false,
            defaultLeaseDurationSeconds: 30,
            staleTaskPolicy: .requeueClaimedWork
        ))

        store.processHeartbeatTick(now: registeredAt.addingTimeInterval(10))

        let persistedSession = try #require(store.agentRuntimeSessions.first(where: { $0.id == session.id }))
        let persistedTask = try #require(store.agentRuntimeTasks.first(where: { $0.id == task.id }))
        #expect(persistedSession.state == .active)
        #expect(persistedSession.currentTaskID == task.id)
        #expect(persistedTask.state == .claimed)
        #expect(persistedTask.sessionID == session.id)
    }

    @Test @MainActor func storeRuntimeSnapshotProjectsLeaseExpiryWithoutPersistingMutation() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        store.saveAgentRuntimeSettings(.init(
            enabled: true,
            defaultLeaseDurationSeconds: 30,
            staleTaskPolicy: .requeueClaimedWork
        ))

        let registeredAt = Date(timeIntervalSince1970: 1_710_000_000)
        let session = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"],
            leaseDurationSeconds: 5,
            now: registeredAt
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd"),
            now: registeredAt
        )
        let claimedTask = try #require(try store.claimNextAgentRuntimeTask(
            sessionID: session.id,
            now: registeredAt
        ))
        #expect(claimedTask.id == task.id)

        let snapshot = store.agentRuntimeSnapshot(now: registeredAt.addingTimeInterval(10))
        let snapshotSession = try #require(snapshot.sessions.first(where: { $0.id == session.id }))
        let snapshotTask = try #require(snapshot.tasks.first(where: { $0.id == task.id }))

        #expect(snapshotSession.state == .expired)
        #expect(snapshotSession.currentTaskID == nil)
        #expect(snapshotTask.state == .queued)
        #expect(snapshotTask.sessionID == nil)
        #expect(snapshotTask.claimedAt == nil)
        #expect(snapshotTask.errorSummary == "lease_expired")

        let persistedSession = try #require(store.agentRuntimeSessions.first(where: { $0.id == session.id }))
        let persistedTask = try #require(store.agentRuntimeTasks.first(where: { $0.id == task.id }))
        #expect(persistedSession.state == .active)
        #expect(persistedSession.currentTaskID == task.id)
        #expect(persistedTask.state == .claimed)
        #expect(persistedTask.sessionID == session.id)
    }

    @Test @MainActor func storeExpiresLeasedSessionAndRequeuesClaimedTask() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveAgentRuntimeSettings(.init(
            enabled: true,
            defaultLeaseDurationSeconds: 30,
            staleTaskPolicy: .requeueClaimedWork
        ))
        let startedAt = Date()
        let session = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"],
            leaseDurationSeconds: 5,
            now: startedAt
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd"),
            now: startedAt
        )
        let claimed = try store.claimNextAgentRuntimeTask(
            sessionID: session.id,
            now: startedAt
        )

        #expect(claimed?.id == task.id)

        let expiredIDs = store.expireStaleAgentRuntimeSessions(
            now: startedAt.addingTimeInterval(6)
        )

        #expect(expiredIDs == [session.id])
        #expect(store.agentRuntimeSessions.first?.state == .expired)
        #expect(store.agentRuntimeTasks.first?.state == .queued)
        #expect(store.agentRuntimeTasks.first?.sessionID == nil)
    }

    @Test @MainActor func storeExpiresLeasedSessionAndPausesClaimedTaskWhenPolicyRequiresPause() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveAgentRuntimeSettings(.init(
            enabled: true,
            defaultLeaseDurationSeconds: 30,
            staleTaskPolicy: .pauseClaimedWork
        ))
        let startedAt = Date()
        let session = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"],
            leaseDurationSeconds: 5,
            now: startedAt
        )
        _ = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd"),
            now: startedAt
        )
        let claimed = try #require(try store.claimNextAgentRuntimeTask(
            sessionID: session.id,
            now: startedAt
        ))

        let expiredIDs = store.expireStaleAgentRuntimeSessions(
            now: startedAt.addingTimeInterval(6)
        )

        #expect(expiredIDs == [session.id])
        #expect(store.agentRuntimeSessions.first?.state == .expired)
        #expect(store.agentRuntimeSessions.first?.currentTaskID == nil)
        #expect(store.agentRuntimeTasks.first?.id == claimed.id)
        #expect(store.agentRuntimeTasks.first?.state == .paused)
        #expect(store.agentRuntimeTasks.first?.sessionID == session.id)
        #expect(store.agentRuntimeTasks.first?.errorSummary == "lease_expired")
    }

    @Test @MainActor func storeRefreshExpiresWaitingApprovalTaskOnStartup() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let startedAt = Date().addingTimeInterval(-60)

        let writer = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )
        writer.saveAgentRuntimeSettings(.init(
            enabled: true,
            defaultLeaseDurationSeconds: 30,
            staleTaskPolicy: .requeueClaimedWork
        ))
        let session = try writer.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"],
            leaseDurationSeconds: 5,
            now: startedAt
        )
        _ = try writer.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd"),
            now: startedAt
        )
        let claimed = try #require(try writer.claimNextAgentRuntimeTask(
            sessionID: session.id,
            now: startedAt
        ))
        _ = try writer.updateAgentRuntimeTask(
            sessionID: session.id,
            taskID: claimed.id,
            state: .waitingApproval,
            now: startedAt.addingTimeInterval(1)
        )

        let reloaded = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        #expect(reloaded.agentRuntimeSessions.first?.id == session.id)
        #expect(reloaded.agentRuntimeSessions.first?.state == .expired)
        #expect(reloaded.agentRuntimeSessions.first?.currentTaskID == nil)
        #expect(reloaded.agentRuntimeTasks.first?.id == claimed.id)
        #expect(reloaded.agentRuntimeTasks.first?.state == .paused)
        #expect(reloaded.agentRuntimeTasks.first?.errorSummary == "lease_expired")
    }

    @Test @MainActor func storeRejectsWrongOwnerAgentRuntimeTaskUpdate() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let owner = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"]
        )
        let outsider = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"]
        )
        _ = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd")
        )
        let claimed = try #require(try store.claimNextAgentRuntimeTask(sessionID: owner.id))

        do {
            _ = try store.updateAgentRuntimeTask(
                sessionID: outsider.id,
                taskID: claimed.id,
                state: .running
            )
            Issue.record("Expected wrong-owner update to fail")
        } catch let error as AgentRuntimeStoreError {
            #expect(error == .taskOwnershipMismatch(taskID: claimed.id, sessionID: outsider.id))
        }
    }

    @Test @MainActor func storeRequeuesAgentRuntimeTaskAndClearsSessionBinding() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let session = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"]
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd")
        )
        let claimed = try #require(try store.claimNextAgentRuntimeTask(sessionID: session.id))
        #expect(claimed.id == task.id)

        let requeued = try store.updateAgentRuntimeTask(
            sessionID: session.id,
            taskID: claimed.id,
            state: .queued
        )

        #expect(requeued.state == .queued)
        #expect(requeued.sessionID == nil)
        #expect(requeued.claimedAt == nil)
        #expect(store.agentRuntimeSessions.first?.currentTaskID == nil)
        #expect(store.agentRuntimeSessions.first?.state == .active)

        let reclaimed = try store.claimNextAgentRuntimeTask(sessionID: session.id)
        #expect(reclaimed?.id == task.id)
    }

    @Test @MainActor func storeReleaseRecoversActiveAgentRuntimeTask() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveAgentRuntimeSettings(.init(
            enabled: true,
            defaultLeaseDurationSeconds: 30,
            staleTaskPolicy: .requeueClaimedWork
        ))
        let session = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: UUID(),
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"]
        )
        let task = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd")
        )
        let claimed = try #require(try store.claimNextAgentRuntimeTask(sessionID: session.id))
        #expect(claimed.id == task.id)

        let released = try store.releaseAgentRuntimeSession(
            session.id,
            reason: "operator_stop"
        )

        #expect(released.state == .released)
        #expect(released.currentTaskID == nil)
        #expect(store.agentRuntimeTasks.first?.state == .queued)
        #expect(store.agentRuntimeTasks.first?.sessionID == nil)
        #expect(store.agentRuntimeTasks.first?.claimedAt == nil)
        #expect(store.agentRuntimeTasks.first?.errorSummary == "lease_expired")
    }

    @Test @MainActor func projectedManagedStatePrefersRuntimeSessionStateOverLegacyRegistration() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let terminalID = UUID()
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.setManagedState(.manual, for: terminalID)
        _ = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: terminalID,
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"]
        )

        #expect(store.projectedManagedState(for: terminalID) == .managedActive)
    }

    @Test @MainActor func projectedSessionTaskSummaryUsesRuntimeTaskProjection() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let terminalID = UUID()
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let session = try store.registerAgentRuntimeSession(
            clientKind: .codexTab,
            terminalID: terminalID,
            hostWorkspaceID: UUID(),
            capabilities: ["terminal"]
        )
        _ = try store.enqueueAgentRuntimeTask(
            kind: .terminalCommand,
            capabilityRequirements: ["terminal"],
            payload: .init(command: "pwd")
        )
        let claimed = try #require(try store.claimNextAgentRuntimeTask(sessionID: session.id))
        let waitingApproval = try store.updateAgentRuntimeTask(
            sessionID: session.id,
            taskID: claimed.id,
            state: .waitingApproval
        )

        let summary = store.projectedSessionTaskSummary(for: terminalID)
        #expect(store.projectedManagedState(for: terminalID) == .managedWaitingApproval)
        #expect(summary.taskID == waitingApproval.id)
        #expect(summary.taskState == .waitingApproval)
        #expect(summary.taskTitle == "pwd")
    }

    @Test @MainActor func projectedManagedStateDefaultsToManualWithoutRuntimeProjection() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let terminalID = UUID()
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        #expect(store.projectedManagedState(for: terminalID) == .manual)
        #expect(store.projectedSessionTaskSummary(for: terminalID).taskID == nil)
    }

    @Test @MainActor func storeUsesConfigDirectoryForHeartbeatInbox() {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = baseDirectory.appendingPathComponent("config.ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: configURL
        )

        #expect(
            store.heartbeatInboxDirectoryPath ==
            baseDirectory.appendingPathComponent("ai-task-queue-inbox", isDirectory: true).path
        )
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
        let generatedScript = try String(contentsOf: expectedScriptURL, encoding: .utf8)

        #expect(result.createdFileCount > 0)
        #expect(FileManager.default.fileExists(atPath: expectedSkillURL.path))
        #expect(FileManager.default.fileExists(atPath: expectedScriptURL.path))
        #expect(FileManager.default.fileExists(atPath: expectedKnowledgeURL.path))
        #expect(store.learningSettings.defaultProjectPath == result.learnWorkspacePath)
        #expect(store.learningSettings.notesRelativePath == AITerminalLearningSettings.defaultNotesRelativePath)
        #expect(generatedScript.contains("agent.runtime.session.register"))
        #expect(generatedScript.contains("agent.runtime.session.heartbeat"))
        #expect(generatedScript.contains("agent.runtime.session.release"))
        #expect(generatedScript.contains("GHODEX_AGENT_RUNTIME_SOCKET"))
        #expect(generatedScript.contains("GHODEX_AGENT_RUNTIME_CLIENT_ID"))
    }

    @Test @MainActor func storeInitializesTodoWorkspaceAndMutatesDailyFiles() throws {
        let tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let tempTodoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghodex-todo-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempConfigURL)
            try? FileManager.default.removeItem(at: tempTodoRootURL)
        }

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempConfigURL
        )

        let result = try #require(store.initializeTodoWorkspace(rootPath: tempTodoRootURL.path))
        let creatorURL = tempTodoRootURL.appendingPathComponent("creator.md", isDirectory: false)
        let readmeURL = tempTodoRootURL.appendingPathComponent("README.md", isDirectory: false)
        let day = Date(timeIntervalSince1970: 1_710_892_800)

        #expect(result.workspaceRootPath == tempTodoRootURL.path)
        #expect(FileManager.default.fileExists(atPath: creatorURL.path))
        #expect(FileManager.default.fileExists(atPath: readmeURL.path))

        let added = try #require(store.addTodoItem(
            title: "Ship todo phase 1",
            notes: "manual-first",
            for: day
        ))
        #expect(added.items.count == 1)

        let itemID = try #require(added.items.first?.id)
        let completed = try #require(store.setTodoItemCompleted(
            id: itemID,
            isCompleted: true,
            for: day
        ))
        #expect(completed.items.first?.isCompleted == true)

        let updated = try #require(store.updateTodoItem(
            id: itemID,
            title: "Ship todo phase 1.1",
            notes: "picker included",
            for: day
        ))
        #expect(updated.items.first?.title == "Ship todo phase 1.1")
        #expect(updated.items.first?.notes == "picker included")

        let reloaded = store.todoDocument(for: day)
        #expect(reloaded.items.count == 1)
        #expect(reloaded.items.first?.title == "Ship todo phase 1.1")
        #expect(reloaded.items.first?.isCompleted == true)
        #expect(reloaded.completionRate == 1)
    }

    @Test @MainActor func todoDocumentLoadsMissingDayDeterministically() throws {
        let tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let tempTodoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghodex-empty-day-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempConfigURL)
            try? FileManager.default.removeItem(at: tempTodoRootURL)
        }

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempConfigURL
        )

        _ = try #require(store.initializeTodoWorkspace(rootPath: tempTodoRootURL.path))
        let day = Date(timeIntervalSince1970: 1_710_979_200)
        let expectedDayString = AITerminalTodoSettings.dayString(from: day)
        let expectedPath = tempTodoRootURL
            .appendingPathComponent("days", isDirectory: true)
            .appendingPathComponent("\(expectedDayString).json", isDirectory: false)

        let firstLoad = store.todoDocument(for: day)
        let secondLoad = store.todoDocument(for: day)

        #expect(firstLoad.date == expectedDayString)
        #expect(firstLoad.items.isEmpty)
        #expect(firstLoad.completionRate == 0)
        #expect(secondLoad.date == expectedDayString)
        #expect(secondLoad.items.isEmpty)
        #expect(secondLoad.completionRate == 0)
        #expect(secondLoad.updatedAt >= firstLoad.updatedAt)
        #expect(FileManager.default.fileExists(atPath: expectedPath.path) == false)
    }

    @Test @MainActor func storeResetsTodoCompletionWithoutLosingItem() throws {
        let tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let tempTodoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghodex-reset-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempConfigURL)
            try? FileManager.default.removeItem(at: tempTodoRootURL)
        }

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempConfigURL
        )

        _ = try #require(store.initializeTodoWorkspace(rootPath: tempTodoRootURL.path))
        let day = Date(timeIntervalSince1970: 1_710_892_800)
        let added = try #require(store.addTodoItem(
            title: "Reset me",
            notes: "todo",
            for: day
        ))
        let itemID = try #require(added.items.first?.id)

        _ = try #require(store.setTodoItemCompleted(
            id: itemID,
            isCompleted: true,
            for: day
        ))
        let reset = try #require(store.setTodoItemCompleted(
            id: itemID,
            isCompleted: false,
            for: day
        ))

        #expect(reset.items.count == 1)
        #expect(reset.items.first?.isCompleted == false)
        #expect(reset.items.first?.completedAt == nil)
        #expect(reset.completionRate == 0)
    }

    @Test @MainActor func storeAssignsTodoItemsToWorkspaceAndSummarizesProgress() throws {
        let tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let tempTodoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghodex-assignment-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempConfigURL)
            try? FileManager.default.removeItem(at: tempTodoRootURL)
        }

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempConfigURL
        )

        _ = try #require(store.initializeTodoWorkspace(rootPath: tempTodoRootURL.path))
        let day = Date(timeIntervalSince1970: 1_710_892_800)
        let workspaceID = UUID()
        let otherWorkspaceID = UUID()

        let first = try #require(store.addTodoItem(
            title: "Ship tab quick look",
            notes: "today",
            for: day
        ))
        let second = try #require(store.addTodoItem(
            title: "Refine picker layout",
            notes: "",
            for: day
        ))

        let firstID = try #require(first.items.first?.id)
        let secondID = try #require(second.items.last?.id)

        _ = try #require(store.assignTodoItem(id: firstID, to: workspaceID, for: day))
        _ = try #require(store.assignTodoItem(id: secondID, to: workspaceID, for: day))
        _ = try #require(store.setTodoItemCompleted(id: firstID, isCompleted: true, for: day))

        let unrelated = try #require(store.addTodoItem(
            title: "Other tab",
            notes: "",
            for: day
        ))
        let unrelatedID = try #require(unrelated.items.last?.id)
        _ = try #require(store.assignTodoItem(id: unrelatedID, to: otherWorkspaceID, for: day))

        let assignedItems = store.todoItems(assignedTo: workspaceID, on: day)
        #expect(assignedItems.count == 2)
        #expect(assignedItems.map(\.id) == [firstID, secondID])
        #expect(assignedItems.first?.isCompleted == true)
        #expect(store.todoItems(assignedTo: workspaceID, on: day, includeCompleted: false).map(\.id) == [secondID])

        let summary = store.todoWorkspaceSummary(for: workspaceID, on: day)
        #expect(summary.completedCount == 1)
        #expect(summary.totalCount == 2)
        #expect(summary.remainingCount == 1)
        #expect(store.todoWorkspaceSummary(for: otherWorkspaceID, on: day).totalCount == 1)

        _ = try #require(store.assignTodoItem(id: secondID, to: nil, for: day))
        let clearedSummary = store.todoWorkspaceSummary(for: workspaceID, on: day)
        #expect(clearedSummary.completedCount == 1)
        #expect(clearedSummary.totalCount == 1)
        #expect(clearedSummary.remainingCount == 0)

        let reloaded = store.todoDocument(for: day)
        #expect(reloaded.items.first(where: { $0.id == firstID })?.assignedWorkspaceID == workspaceID)
        #expect(reloaded.items.first(where: { $0.id == secondID })?.assignedWorkspaceID == nil)
        #expect(reloaded.items.first(where: { $0.id == unrelatedID })?.assignedWorkspaceID == otherWorkspaceID)
    }

    @Test @MainActor func todoWorkspaceReadsDoNotPublishStoreChanges() throws {
        let tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let tempTodoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghodex-todo-read-snapshot-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempConfigURL)
            try? FileManager.default.removeItem(at: tempTodoRootURL)
        }

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempConfigURL
        )

        _ = try #require(store.initializeTodoWorkspace(rootPath: tempTodoRootURL.path))
        let day = Date(timeIntervalSince1970: 1_710_892_800)
        let workspaceID = UUID()
        let document = try #require(store.addTodoItem(
            title: "Inspect quick look",
            notes: "",
            for: day
        ))
        let todoID = try #require(document.items.first?.id)
        _ = try #require(store.assignTodoItem(id: todoID, to: workspaceID, for: day))

        store.lastError = "sticky"

        var changeCount = 0
        let cancellable = store.objectWillChange.sink {
            changeCount += 1
        }
        defer { cancellable.cancel() }

        let snapshot = store.todoWorkspaceSnapshot(for: workspaceID, on: day)
        let items = store.todoItems(assignedTo: workspaceID, on: day)
        let summary = store.todoWorkspaceSummary(for: workspaceID, on: day)

        #expect(snapshot.items.map(\.id) == [todoID])
        #expect(snapshot.summary.totalCount == 1)
        #expect(snapshot.summary.completedCount == 0)
        #expect(items.map(\.id) == [todoID])
        #expect(summary.totalCount == 1)
        #expect(summary.completedCount == 0)
        #expect(changeCount == 0)
        #expect(store.lastError == "sticky")
    }

    @Test @MainActor func storeSyncsIncompleteTodoItemsIntoTodayAsPointers() throws {
        let tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let tempTodoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghodex-stale-sync-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempConfigURL)
            try? FileManager.default.removeItem(at: tempTodoRootURL)
        }

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempConfigURL
        )

        _ = try #require(store.initializeTodoWorkspace(rootPath: tempTodoRootURL.path))
        let staleDay = Date(timeIntervalSince1970: 1_710_892_800)
        let today = Date(timeIntervalSince1970: 1_711_152_000)
        let staleDayString = AITerminalTodoSettings.dayString(from: staleDay)

        let staleAdded = try #require(store.addTodoItem(
            title: "Carry me forward",
            notes: "still open",
            for: staleDay
        ))
        let completedAdded = try #require(store.addTodoItem(
            title: "Already done",
            notes: "",
            for: staleDay
        ))
        let staleID = try #require(staleAdded.items.first?.id)
        let completedID = try #require(completedAdded.items.last?.id)
        _ = try #require(store.setTodoItemCompleted(id: completedID, isCompleted: true, for: staleDay))

        #expect(store.syncableStaleTodoPointerCount(into: today) == 1)
        #expect(try #require(store.syncIncompleteTodoPointers(into: today)) == 1)
        #expect(store.syncableStaleTodoPointerCount(into: today) == 0)

        let todayDocument = store.todoDocument(for: today)
        #expect(todayDocument.items.count == 1)

        let pointer = try #require(todayDocument.items.first)
        #expect(pointer.id != staleID)
        #expect(pointer.isCarryForwardPointer)
        #expect(pointer.sourceItem == .init(day: staleDayString, itemID: staleID))
        #expect(pointer.title == "Carry me forward")
        #expect(pointer.notes == "still open")
        #expect(pointer.createdAt == staleAdded.items.first?.createdAt)

        #expect(try #require(store.syncIncompleteTodoPointers(into: today)) == 0)
        #expect(store.todoDocument(for: today).items.count == 1)
    }

    @Test @MainActor func pointerMutationsUpdateTheOriginalTodoItem() throws {
        let tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")
        let tempTodoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghodex-stale-pointer-mutation-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempConfigURL)
            try? FileManager.default.removeItem(at: tempTodoRootURL)
        }

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempConfigURL
        )

        _ = try #require(store.initializeTodoWorkspace(rootPath: tempTodoRootURL.path))
        let staleDay = Date(timeIntervalSince1970: 1_710_892_800)
        let today = Date(timeIntervalSince1970: 1_711_152_000)

        let staleAdded = try #require(store.addTodoItem(
            title: "Old title",
            notes: "old notes",
            for: staleDay
        ))
        let staleID = try #require(staleAdded.items.first?.id)

        _ = try #require(store.syncIncompleteTodoPointers(into: today))
        let pointerID = try #require(store.todoDocument(for: today).items.first?.id)

        _ = try #require(store.updateTodoItem(
            id: pointerID,
            title: "Updated from today",
            notes: "notes from today",
            for: today
        ))
        _ = try #require(store.setTodoItemCompleted(
            id: pointerID,
            isCompleted: true,
            for: today
        ))

        let staleDocument = store.todoDocument(for: staleDay)
        let todayDocument = store.todoDocument(for: today)

        #expect(staleDocument.items.first(where: { $0.id == staleID })?.title == "Updated from today")
        #expect(staleDocument.items.first(where: { $0.id == staleID })?.notes == "notes from today")
        #expect(staleDocument.items.first(where: { $0.id == staleID })?.isCompleted == true)
        #expect(todayDocument.items.first(where: { $0.id == pointerID })?.title == "Updated from today")
        #expect(todayDocument.items.first(where: { $0.id == pointerID })?.isCompleted == true)
        #expect(todayDocument.items.first(where: { $0.id == pointerID })?.sourceItem?.itemID == staleID)
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
        set -euo pipefail
        read_selection() {
          if [[ -n "${SELECTION:-}" ]]; then
            printf '%s' "$SELECTION"
            return
          fi
          return 1
        }
        selection="$(read_selection "$@" || true)"
        LEARN_WORKSPACE="${LEARN_WORKSPACE:-$PWD}"
        PROJECT_PATH="${PROJECT_PATH:-${TAB_WORKING_DIRECTORY:-$LEARN_WORKSPACE}}"
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
        #expect(migratedScript.contains("agent.runtime.session.register"))
        #expect(migratedScript.contains("agent.runtime.session.heartbeat"))
        #expect(migratedScript.contains("agent.runtime.session.release"))
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

        let savedConfiguration = try AITerminalManagerStore.loadConfiguration(at: tempURL)
        #expect(savedConfiguration.learningLogs.count == 2)

        store.clearLearningLogs()
        #expect(store.configuration.learningLogs.isEmpty)

        let clearedConfiguration = try AITerminalManagerStore.loadConfiguration(at: tempURL)
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

    @Test func newTabPickerEntriesIncludeSavedWorkspacesOnlyForTopLevelMode() {
        let workspace = AITerminalSavedWorkspaceTemplate(
            name: "Full Stack",
            root: .split(.init(
                direction: .horizontal,
                ratio: 0.5,
                left: .pane(.init(tabs: [
                    .init(hostID: "local", directory: "/tmp/app"),
                ])),
                right: .pane(.init(tabs: [
                    .init(hostID: "ssh:buildbox", directory: "/srv/app"),
                ]))
            ))
        )

        let topLevelEntries = NewTabPickerModel.entries(
            favoriteHosts: [],
            recentHosts: [],
            savedHosts: [],
            importedHosts: [],
            savedWorkspaceTemplates: [workspace],
            mode: .topLevel
        ) { _ in true }

        let paneEntries = NewTabPickerModel.entries(
            favoriteHosts: [],
            recentHosts: [],
            savedHosts: [],
            importedHosts: [],
            savedWorkspaceTemplates: [workspace],
            mode: .paneChild
        ) { _ in true }

        #expect(topLevelEntries.map(\.id) == ["local", workspace.id])
        #expect(topLevelEntries.map(\.section) == [.local, .savedWorkspaces])
        #expect(paneEntries.map(\.id) == ["local"])
    }

    @Test func configurationRoundTripsSavedWorkspaceTemplates() throws {
        let workspace = AITerminalSavedWorkspaceTemplate(
            name: "Infra",
            root: .pane(.init(tabs: [
                .init(hostID: "local", directory: "/Users/leongong/Desktop/LeonProjects/GhoDex"),
                .init(hostID: "ssh:buildbox", directory: "/srv/app"),
            ], activeTabIndex: 1))
        )

        let configuration = AITerminalManagerConfiguration(
            savedWorkspaceTemplates: [workspace]
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)

        #expect(decoded.savedWorkspaceTemplates == [workspace])
        #expect(decoded.schemaVersion == 9)
    }

    @Test func configurationRoundTripsAgentRuntimeState() throws {
        let sessionID = UUID()
        let taskID = UUID()
        let configuration = AITerminalManagerConfiguration(
            agentRuntimeSettings: .init(
                enabled: true,
                defaultLeaseDurationSeconds: 45,
                staleTaskPolicy: .pauseClaimedWork
            ),
            agentRuntimeSessions: [
                .init(
                    id: sessionID,
                    clientKind: .codexTab,
                    tabID: UUID(),
                    terminalID: UUID(),
                    hostWorkspaceID: UUID(),
                    state: .active,
                    capabilities: ["terminal", "task-runtime"],
                    createdAt: .now,
                    updatedAt: .now,
                    lastHeartbeatAt: .now,
                    leaseDurationSeconds: 45,
                    leaseExpiresAt: Date().addingTimeInterval(45),
                    currentTaskID: taskID
                ),
            ],
            agentRuntimeTasks: [
                .init(
                    id: taskID,
                    kind: .terminalCommand,
                    state: .claimed,
                    priority: 10,
                    sessionID: sessionID,
                    capabilityRequirements: ["terminal"],
                    payload: .init(command: "pwd"),
                    createdAt: .now,
                    scheduledAt: .now,
                    claimedAt: .now
                ),
            ]
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)

        #expect(decoded.agentRuntimeSettings.defaultLeaseDurationSeconds == 45)
        #expect(decoded.agentRuntimeSettings.staleTaskPolicy == .pauseClaimedWork)
        #expect(decoded.agentRuntimeSessions.count == 1)
        #expect(decoded.agentRuntimeSessions.first?.id == sessionID)
        #expect(decoded.agentRuntimeTasks.count == 1)
        #expect(decoded.agentRuntimeTasks.first?.id == taskID)
    }

    @Test @MainActor func storeLoadsSavedWorkspaceTemplatesFromGhoDexConfigWithoutDiagnostics() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let workspace = AITerminalSavedWorkspaceTemplate(
            name: "Infra",
            root: .split(.init(
                direction: .horizontal,
                ratio: 0.5,
                left: .pane(.init(tabs: [
                    .init(hostID: "local", directory: "/tmp/app"),
                    .init(hostID: "ssh:buildbox", directory: "/srv/app"),
                ], activeTabIndex: 1)),
                right: .pane(.init(tabs: [
                    .init(hostID: "local", directory: "/tmp/logs"),
                ]))
            ))
        )

        let payload = try AITerminalManagerTestSupport.encodedPayload(workspace)
        let text = """
        font-size = 14

        \(AITerminalManagerTestSupport.managedConfigStartMarker)
        ghodex-saved-workspace-template = \(try AITerminalManagerTestSupport.configStringLiteral(payload))
        \(AITerminalManagerTestSupport.managedConfigEndMarker)
        """
        try text.write(to: tempURL, atomically: true, encoding: .utf8)

        let ghosttyConfig = Ghostty.Config(at: tempURL.path(percentEncoded: false))
        #expect(ghosttyConfig.errors.isEmpty)

        let configuration = try AITerminalManagerStore.loadConfiguration(at: tempURL)
        #expect(configuration.savedWorkspaceTemplates == [workspace])
    }

    @Test @MainActor func saveWorkspaceTemplateRejectsDuplicateNamesWithoutReplace() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let root = AITerminalSavedWorkspaceNode.pane(.init(tabs: [
            .init(hostID: "local", directory: "/tmp/app"),
        ]))

        #expect(store.saveWorkspaceTemplate(name: "Infra", root: root))
        #expect(store.saveWorkspaceTemplate(name: "infra", root: root) == false)
        #expect(store.configuration.savedWorkspaceTemplates.count == 1)
        #expect(store.existingSavedWorkspaceTemplate(named: "INFRA")?.name == "Infra")
    }

    @Test @MainActor func saveWorkspaceTemplateReplacesExistingTemplateWhenRequested() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let originalRoot = AITerminalSavedWorkspaceNode.pane(.init(tabs: [
            .init(hostID: "local", directory: "/tmp/app"),
        ]))
        let replacementRoot = AITerminalSavedWorkspaceNode.split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .pane(.init(tabs: [
                .init(hostID: "local", directory: "/tmp/app"),
            ])),
            right: .pane(.init(tabs: [
                .init(hostID: "ssh:buildbox", directory: "/srv/app"),
            ]))
        ))

        #expect(store.saveWorkspaceTemplate(name: "Infra", root: originalRoot))
        guard let original = store.existingSavedWorkspaceTemplate(named: "Infra") else {
            Issue.record("Expected original saved workspace to exist")
            return
        }

        #expect(store.saveWorkspaceTemplate(name: "Infra", root: replacementRoot, replacingID: original.id))
        guard let replaced = store.existingSavedWorkspaceTemplate(named: "Infra") else {
            Issue.record("Expected replaced saved workspace to exist")
            return
        }
        #expect(store.configuration.savedWorkspaceTemplates.count == 1)
        #expect(replaced.id == original.id)
        #expect(replaced.root == replacementRoot)
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

@Suite(
    "AITerminalManager Benchmarks",
    .enabled(if: false),
    .tags(.benchmark)
)
struct AITerminalManagerBenchmarkTests {
    @Test @MainActor func storeBenchmarksHeartbeatConcurrencyCurve() async throws {
        let taskCount = 64
        let taskSleepSeconds = 0.2
        let maxConcurrentValues = [1, 2, 4, 8]
        let intervalSeconds = 0.5
        var results: [HeartbeatPressureResult] = []

        for maxConcurrent in maxConcurrentValues {
            let baseDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            let configURL = baseDirectory.appendingPathComponent("config.ghodex")

            let store = AITerminalManagerStore(
                appDelegateProvider: { nil },
                configurationURL: configURL
            )
            store.saveHeartbeatQueueSettings(.init(
                enabled: true,
                heartbeatIntervalSeconds: intervalSeconds,
                maxConcurrentTasks: maxConcurrent,
                allowExternalInboxMutations: true
            ))

            for _ in 0..<taskCount {
                let id = store.enqueueHeartbeatTask(command: "sleep \(taskSleepSeconds)")
                #expect(id != nil)
            }

            let startedAt = Date()
            let timeout = startedAt.addingTimeInterval(30)
            var peakRunningCount = 0

            while Date() < timeout {
                peakRunningCount = max(peakRunningCount, store.heartbeatRunningCount)
                if store.heartbeatDoneCount == taskCount {
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            let sequentialSeconds = Double(taskCount) * taskSleepSeconds
            let speedup = sequentialSeconds / max(elapsed, 0.000_1)

            #expect(
                store.heartbeatDoneCount == taskCount,
                "maxConcurrent=\(maxConcurrent) done=\(store.heartbeatDoneCount) running=\(store.heartbeatRunningCount) queued=\(store.heartbeatQueuedCount) failed=\(store.heartbeatFailedCount)"
            )
            #expect(store.heartbeatFailedCount == 0)
            #expect(store.heartbeatQueuedCount == 0)
            #expect(store.heartbeatRunningCount == 0)
            #expect(peakRunningCount <= maxConcurrent)
            #expect(peakRunningCount > 0)

            results.append(.init(
                mode: "direct_api",
                maxConcurrentTasks: maxConcurrent,
                taskCount: taskCount,
                taskSleepSeconds: taskSleepSeconds,
                elapsedSeconds: elapsed,
                sequentialSeconds: sequentialSeconds,
                speedupVsSequential: speedup,
                peakRunningCount: peakRunningCount
            ))
        }

        for index in 1..<results.count {
            let previous = results[index - 1]
            let current = results[index]
            #expect(
                current.elapsedSeconds < previous.elapsedSeconds * 0.95,
                "expected faster runtime when maxConcurrent increases: prev=\(previous.maxConcurrentTasks):\(previous.elapsedSeconds)s, current=\(current.maxConcurrentTasks):\(current.elapsedSeconds)s"
            )
        }

        let outputURL = URL(fileURLWithPath: "/tmp/ghostty-heartbeat-curve-direct.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(results)
        try data.write(to: outputURL, options: .atomic)
    }

    @Test @MainActor func storeBenchmarksHeartbeatInboxEndToEndCurve() async throws {
        let taskCount = 64
        let taskSleepSeconds = 0.2
        let maxConcurrentValues = [1, 2, 4, 8]
        let intervalSeconds = 0.5
        var results: [HeartbeatPressureResult] = []

        for maxConcurrent in maxConcurrentValues {
            let baseDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            let configURL = baseDirectory.appendingPathComponent("config.ghodex")

            let store = AITerminalManagerStore(
                appDelegateProvider: { nil },
                configurationURL: configURL
            )
            store.saveHeartbeatQueueSettings(.init(
                enabled: true,
                heartbeatIntervalSeconds: intervalSeconds,
                maxConcurrentTasks: maxConcurrent,
                allowExternalInboxMutations: true
            ))

            let inboxURL = URL(fileURLWithPath: store.heartbeatInboxDirectoryPath, isDirectory: true)
            let startedAt = Date()
            for index in 0..<taskCount {
                let payload: [String: Any] = [
                    "action": "enqueue",
                    "command": "sleep \(taskSleepSeconds)",
                    "type": "exec",
                ]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                let filename = String(format: "enqueue-%03d.json", index)
                try data.write(to: inboxURL.appendingPathComponent(filename), options: .atomic)
            }

            let timeout = startedAt.addingTimeInterval(40)
            var peakRunningCount = 0
            while Date() < timeout {
                peakRunningCount = max(peakRunningCount, store.heartbeatRunningCount)
                if store.heartbeatDoneCount == taskCount {
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            let sequentialSeconds = Double(taskCount) * taskSleepSeconds
            let speedup = sequentialSeconds / max(elapsed, 0.000_1)

            let remainingFiles = try FileManager.default.contentsOfDirectory(
                at: inboxURL,
                includingPropertiesForKeys: nil
            )
            let failedInboxFiles = remainingFiles.filter { $0.pathExtension.lowercased() == "failed" }

            #expect(
                store.heartbeatDoneCount == taskCount,
                "maxConcurrent=\(maxConcurrent) done=\(store.heartbeatDoneCount) running=\(store.heartbeatRunningCount) queued=\(store.heartbeatQueuedCount) failed=\(store.heartbeatFailedCount)"
            )
            #expect(store.heartbeatFailedCount == 0)
            #expect(store.heartbeatQueuedCount == 0)
            #expect(store.heartbeatRunningCount == 0)
            #expect(peakRunningCount <= maxConcurrent)
            #expect(peakRunningCount > 0)
            #expect(failedInboxFiles.isEmpty)

            results.append(.init(
                mode: "inbox_e2e",
                maxConcurrentTasks: maxConcurrent,
                taskCount: taskCount,
                taskSleepSeconds: taskSleepSeconds,
                elapsedSeconds: elapsed,
                sequentialSeconds: sequentialSeconds,
                speedupVsSequential: speedup,
                peakRunningCount: peakRunningCount
            ))
        }

        for index in 1..<results.count {
            let previous = results[index - 1]
            let current = results[index]
            #expect(
                current.elapsedSeconds < previous.elapsedSeconds * 0.95,
                "expected faster runtime when maxConcurrent increases (inbox): prev=\(previous.maxConcurrentTasks):\(previous.elapsedSeconds)s, current=\(current.maxConcurrentTasks):\(current.elapsedSeconds)s"
            )
        }

        let outputURL = URL(fileURLWithPath: "/tmp/ghostty-heartbeat-curve-inbox.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(results)
        try data.write(to: outputURL, options: .atomic)
    }
}
