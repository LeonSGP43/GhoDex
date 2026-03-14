import AppKit
import Foundation
import SwiftUI

@MainActor
final class AITerminalManagerStore: ObservableObject {
    private struct PendingSSHPasswordAutomation {
        var hostID: String
        var password: String
        var hasSentPassword: Bool
    }

    struct LearningWorkspaceBootstrapResult {
        var chatWorkspacePath: String
        var learnWorkspacePath: String
        var createdFileCount: Int
        var reusedFileCount: Int
    }

    enum ManagedSkillRepositoryState: Sendable {
        case latest
        case updateAvailable
        case notInstalled
        case localChanges
        case error
    }

    struct ManagedSkillRepositoryStatus: Identifiable, Hashable, Sendable {
        var id: String
        var skillName: String
        var repositoryURL: String
        var branch: String
        var destinationPath: String
        var localCommit: String?
        var remoteCommit: String?
        var expectedTag: String?
        var expectedCommit: String?
        var state: ManagedSkillRepositoryState
        var message: String?
    }

    private enum ManagedSkillWorkspaceScope: Sendable {
        case chat
        case learn
    }

    private struct ManagedSkillRepositorySpec: Hashable, Sendable {
        var id: String
        var skillName: String
        var repositoryURL: String
        var branch: String
        var expectedTag: String?
        var expectedCommit: String?
        var scope: ManagedSkillWorkspaceScope
    }

    @Published private(set) var configuration: AITerminalManagerConfiguration
    @Published private(set) var importedSSHHosts: [AITerminalHost] = []
    @Published private(set) var remoteSessions: [AITerminalRemoteSessionSummary] = []
    @Published private(set) var sessions: [AITerminalSessionSummary] = []
    @Published private(set) var tasks: [AITerminalTaskRecord] = []
    @Published private(set) var selectedSessionID: UUID?
    @Published private(set) var selectedSessionVisibleText = ""
    @Published private(set) var selectedSessionScreenText = ""
    @Published private(set) var managedSkillRepositoryStatuses: [ManagedSkillRepositoryStatus] = []
    @Published var launchTarget: AITerminalLaunchTarget = .tab
    @Published var lastError: String?

    private let appDelegateProvider: () -> AppDelegate?
    private let configurationURL: URL
    private let sshConfigHostLoader: () -> [AITerminalHost]
    private let credentialStore: SSHConnectionCredentialStore
    private var registrations: [UUID: AITerminalLaunchRegistration] = [:]
    private var sshSessionAuthStates: [UUID: AITerminalSSHSessionAuthState] = [:]
    private var pendingSSHPasswordAutomations: [UUID: PendingSSHPasswordAutomation] = [:]
    private var taskBindings: [UUID: UUID] = [:]
    private var sshPasswordAutomationTimer: Timer?
    private static let maxLearningLogEntries = 200
    private static let maxLearningLogSummaryCharacters = 400
    private static let maxLearningLogDetailCharacters = 8_000
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    nonisolated private static let managedSkillRepositorySpecs: [ManagedSkillRepositorySpec] = [
        .init(
            id: "gho_chat_skill_daily-qa-copilot",
            skillName: "daily-qa-copilot",
            repositoryURL: "https://github.com/LeonSGP43/gho_chat_skill_daily-qa-copilot",
            branch: "main",
            expectedTag: "v0.1.0",
            expectedCommit: "4389201",
            scope: .chat
        ),
        .init(
            id: "gho_chat_skill_desktop-ops-orchestrator",
            skillName: "desktop-ops-orchestrator",
            repositoryURL: "https://github.com/LeonSGP43/gho_chat_skill_desktop-ops-orchestrator",
            branch: "main",
            expectedTag: "v0.1.0",
            expectedCommit: "aee6d15",
            scope: .chat
        ),
        .init(
            id: "gho_chat_skill_ghostty-task-queue-manager",
            skillName: "ghostty-task-queue-manager",
            repositoryURL: "https://github.com/LeonSGP43/gho_chat_skill_ghostty-task-queue-manager",
            branch: "main",
            expectedTag: "v0.1.0",
            expectedCommit: "77cdf1d",
            scope: .chat
        ),
        .init(
            id: "gho_chat_skill_system-safety-guardian",
            skillName: "system-safety-guardian",
            repositoryURL: "https://github.com/LeonSGP43/gho_chat_skill_system-safety-guardian",
            branch: "main",
            expectedTag: "v0.1.0",
            expectedCommit: "0387be7",
            scope: .chat
        ),
        .init(
            id: "gho_chat_learn_skill_terminal-learning-notes",
            skillName: "terminal-learning-notes",
            repositoryURL: "https://github.com/LeonSGP43/gho_chat_learn_skill_terminal-learning-notes",
            branch: "main",
            expectedTag: "v0.1.0",
            expectedCommit: "7199eec",
            scope: .learn
        ),
    ]

    init(
        appDelegateProvider: @escaping () -> AppDelegate?,
        configurationURL: URL? = nil,
        sshConfigHostLoader: @escaping () -> [AITerminalHost] = { AITerminalManagerStore.loadSSHConfigHostsFromDefaultPath() },
        credentialStore: SSHConnectionCredentialStore = KeychainSSHConnectionCredentialStore()
    ) {
        self.appDelegateProvider = appDelegateProvider
        self.configurationURL = configurationURL ?? Self.defaultConfigurationURL()
        self.sshConfigHostLoader = sshConfigHostLoader
        self.credentialStore = credentialStore
        self.configuration = (try? Self.loadConfiguration(from: self.configurationURL)) ?? .empty
        refresh()
    }

    deinit {
        sshPasswordAutomationTimer?.invalidate()
        sshPasswordAutomationTimer = nil
    }

    var availableHosts: [AITerminalHost] {
        var result: [AITerminalHost] = [AITerminalHost.local]
        var seen: Set<String> = [AITerminalHost.local.id]

        for host in configuration.savedHosts where seen.insert(host.id).inserted {
            result.append(host)
        }
        for host in mergedImportedHosts where seen.insert(host.id).inserted {
            result.append(host)
        }

        return result.sorted { lhs, rhs in
            if lhs.id == AITerminalHost.local.id { return true }
            if rhs.id == AITerminalHost.local.id { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var savedHosts: [AITerminalHost] {
        configuration.savedHosts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var mergedImportedHosts: [AITerminalHost] {
        Self.mergedImportedHosts(imported: importedSSHHosts, overrides: configuration.importedHostOverrides)
    }

    nonisolated static func mergedImportedHosts(
        imported: [AITerminalHost],
        overrides: [AITerminalHost]
    ) -> [AITerminalHost] {
        let overrideLookup = Dictionary(uniqueKeysWithValues: overrides.map { ($0.id, $0) })
        return imported.map { host in
            guard let override = overrideLookup[host.id] else { return host }
            var merged = host
            merged.name = override.name
            merged.sshAlias = override.sshAlias
            merged.hostname = override.hostname
            merged.user = override.user
            merged.port = override.port
            merged.defaultDirectory = override.defaultDirectory
            merged.authMode = override.authMode
            return merged
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var recentHosts: [AITerminalHost] {
        let lookup = Dictionary(uniqueKeysWithValues: availableHosts.map { ($0.id, $0) })
        return configuration.recentHosts
            .sorted { $0.connectedAt > $1.connectedAt }
            .compactMap { lookup[$0.id] }
    }

    var favoriteHosts: [AITerminalHost] {
        let lookup = Dictionary(uniqueKeysWithValues: availableHosts.map { ($0.id, $0) })
        return configuration.favoriteHostIDs.compactMap { lookup[$0] }
    }

    func recentRecord(for host: AITerminalHost) -> AITerminalRecentHostRecord? {
        configuration.recentHosts
            .filter { $0.id == host.id }
            .sorted { $0.connectedAt > $1.connectedAt }
            .first
    }

    func isFavorite(_ host: AITerminalHost) -> Bool {
        configuration.favoriteHostIDs.contains(host.id)
    }

    func toggleFavorite(_ host: AITerminalHost) {
        guard !host.isLocal else { return }

        if let index = configuration.favoriteHostIDs.firstIndex(of: host.id) {
            configuration.favoriteHostIDs.remove(at: index)
        } else {
            configuration.favoriteHostIDs.append(host.id)
        }

        persistConfiguration()
        rebuildSessions()
    }

    func hasStoredPassword(for host: AITerminalHost) -> Bool {
        guard host.authMode == .password else { return false }
        return (try? credentialStore.password(for: host.id))?.isEmpty == false
    }

    var workspaces: [AITerminalWorkspaceTemplate] {
        configuration.workspaces.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var learningSettings: AITerminalLearningSettings {
        configuration.learningSettings
    }

    var learningLogs: [AITerminalLearningLogEntry] {
        Array(configuration.learningLogs.reversed())
    }

    var managedSkillStatuses: [ManagedSkillRepositoryStatus] {
        managedSkillRepositoryStatuses
    }

    var selectedSession: AITerminalSessionSummary? {
        guard let selectedSessionID else { return nil }
        return sessions.first(where: { $0.id == selectedSessionID })
    }

    func isUserManagedHost(_ host: AITerminalHost) -> Bool {
        configuration.savedHosts.contains(where: { $0.id == host.id })
    }

    func isImportedHost(_ host: AITerminalHost) -> Bool {
        importedSSHHosts.contains(where: { $0.id == host.id })
    }

    func isImportedHostOverridden(_ host: AITerminalHost) -> Bool {
        configuration.importedHostOverrides.contains(where: { $0.id == host.id })
    }

    func refresh() {
        if let loaded = try? Self.loadConfiguration(from: configurationURL) {
            configuration = loaded
        }

        importedSSHHosts = sshConfigHostLoader()
        reconcileImportedState()
        rebuildSessions()
    }

    func reloadImportedSSHHosts() {
        importedSSHHosts = sshConfigHostLoader()
        reconcileImportedState()
        lastError = nil
        rebuildSessions()
    }

    func openLocalShell() {
        launch(.localShell())
    }

    func open(host: AITerminalHost) {
        open(host: host, directoryOverride: nil)
    }

    func openInNewTab(host: AITerminalHost) {
        if host.isLocal {
            openLocalShell(launchTarget: .tab)
            return
        }

        open(host: host, directoryOverride: nil, launchTarget: .tab)
    }

    func newTabPickerEntries() -> [NewTabPickerEntry] {
        NewTabPickerModel.entries(
            favoriteHosts: favoriteHosts,
            recentHosts: recentHosts,
            savedHosts: savedHosts,
            importedHosts: mergedImportedHosts
        ) { [weak self] host in
            self?.hasStoredPassword(for: host) ?? false
        }
    }

    func open(host: AITerminalHost, directoryOverride: String?) {
        open(host: host, directoryOverride: directoryOverride, launchTarget: launchTarget)
    }

    func openLocalShell(launchTarget: AITerminalLaunchTarget) {
        _ = launch(.localShell(), target: launchTarget)
    }

    private func open(
        host: AITerminalHost,
        directoryOverride: String?,
        launchTarget: AITerminalLaunchTarget
    ) {
        switch host.transport {
        case .local:
            openLocalShell(launchTarget: launchTarget)
            return

        case .localmcd:
            guard let plan = AITerminalLaunchPlan.localCommand(host: host, directoryOverride: directoryOverride) else {
                lastError = L10n.AITerminalManager.localMCDCommandsEmpty
                recordRecentHost(host.id, status: .failed, errorSummary: lastError)
                return
            }
            _ = launch(plan, target: launchTarget)
            recordRecentHost(host.id, status: .connected)
            return

        case .ssh:
            let passwordResolution = resolvedPasswordAutomation(for: host)
            if let message = passwordResolution.error {
                lastError = message
                recordRecentHost(host.id, status: .failed, errorSummary: message)
                return
            }
            let savedPassword = passwordResolution.password

            guard let plan = AITerminalLaunchPlan.remote(host: host, directoryOverride: directoryOverride) else {
                lastError = L10n.AITerminalManager.hostMissingSSHDetails
                recordRecentHost(host.id, status: .failed, errorSummary: lastError)
                return
            }

            guard let sessionID = launch(plan, target: launchTarget) else { return }
            registerRemoteSession(sessionID, host: host, savedPassword: savedPassword)
            recordRecentHost(host.id, status: .connected)
        }
    }

    func open(workspace: AITerminalWorkspaceTemplate) {
        guard let host = availableHosts.first(where: { $0.id == workspace.hostID }) else {
            lastError = L10n.AITerminalManager.workspaceUnknownHost(workspace.name)
            return
        }
        guard let plan = AITerminalLaunchPlan.workspace(workspace, host: host) else {
            lastError = L10n.AITerminalManager.workspaceInvalidPlan(workspace.name)
            return
        }

        let passwordResolution = resolvedPasswordAutomation(for: host)
        if let message = passwordResolution.error {
            lastError = message
            recordRecentHost(host.id, status: .failed, errorSummary: message)
            return
        }
        let savedPassword = passwordResolution.password

        guard let sessionID = launch(plan) else { return }
        if host.transport == .ssh {
            registerRemoteSession(sessionID, host: host, savedPassword: savedPassword)
        }
        if !host.isLocal {
            recordRecentHost(host.id, status: .connected)
        }
    }

    func addWorkspaceFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.AITerminalManager.addWorkspacePrompt

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path(percentEncoded: false)
        var workspaces = configuration.workspaces
        let name = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
        workspaces.append(.init(
            id: "workspace:\(UUID().uuidString)",
            name: name,
            hostID: AITerminalHost.local.id,
            directory: path
        ))
        configuration.workspaces = workspaces
        persistConfiguration()
        rebuildSessions()
    }

    func saveHost(
        existingHostID: String? = nil,
        name: String,
        sshAlias: String,
        hostname: String,
        user: String,
        port: String,
        defaultDirectory: String,
        authMode: AITerminalHostAuthMode = .system,
        password: String? = nil
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = defaultDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAlias.isEmpty || !trimmedHostname.isEmpty else {
            lastError = L10n.AITerminalManager.hostMissingAliasOrHostname
            return
        }

        let resolvedName = Self.resolvedHostName(
            explicitName: trimmedName,
            sshAlias: trimmedAlias,
            hostname: trimmedHostname,
            user: trimmedUser
        )

        let parsedPort: Int?
        if port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsedPort = nil
        } else if let v = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) {
            parsedPort = v
        } else {
            lastError = L10n.AITerminalManager.hostInvalidPort
            return
        }

        let hostID = AITerminalHost.stableID(
            existingID: existingHostID,
            sshAlias: trimmedAlias,
            hostname: trimmedHostname,
            user: trimmedUser
        )
        let host = AITerminalHost(
            id: hostID,
            name: resolvedName,
            transport: .ssh,
            sshAlias: trimmedAlias.isEmpty ? nil : trimmedAlias,
            hostname: trimmedHostname.isEmpty ? nil : trimmedHostname,
            user: trimmedUser.isEmpty ? nil : trimmedUser,
            port: parsedPort,
            defaultDirectory: trimmedDirectory.isEmpty ? nil : trimmedDirectory,
            source: .configurationFile,
            authMode: authMode
        )

        switch authMode {
        case .system:
            do {
                try credentialStore.removePassword(for: hostID)
            } catch {
                lastError = L10n.SSHConnections.passwordDeleteFailed(error.localizedDescription)
                return
            }

        case .password:
            do {
                if let trimmedPassword, !trimmedPassword.isEmpty {
                    try credentialStore.setPassword(trimmedPassword, for: hostID)
                } else if try credentialStore.password(for: hostID) == nil {
                    lastError = L10n.SSHConnections.passwordRequired
                    return
                }
            } catch {
                lastError = L10n.SSHConnections.passwordSaveFailed(error.localizedDescription)
                return
            }
        }

        if importedSSHHosts.contains(where: { $0.id == host.id }) {
            configuration.importedHostOverrides.removeAll { $0.id == host.id }
            configuration.importedHostOverrides.append(host)
            configuration.importedHostOverrides.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } else {
            configuration.savedHosts.removeAll { $0.id == host.id }
            configuration.savedHosts.append(host)
            configuration.savedHosts.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func saveLocalMCDHost(
        existingHostID: String? = nil,
        name: String,
        defaultDirectory: String,
        startupCommands: String
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = defaultDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedCommands = startupCommands
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parsedCommands.isEmpty else {
            lastError = L10n.AITerminalManager.localMCDCommandsEmpty
            return
        }

        let resolvedName = trimmedName.isEmpty
            ? (parsedCommands.first ?? L10n.AITerminalManager.localShell)
            : trimmedName
        let hostID = existingHostID ?? "localmcd:\(UUID().uuidString)"
        let host = AITerminalHost(
            id: hostID,
            name: resolvedName,
            transport: .localmcd,
            startupCommands: parsedCommands,
            sshAlias: nil,
            hostname: nil,
            user: nil,
            port: nil,
            defaultDirectory: trimmedDirectory.isEmpty ? nil : trimmedDirectory,
            source: .configurationFile,
            authMode: .system
        )

        configuration.savedHosts.removeAll { $0.id == host.id }
        configuration.savedHosts.append(host)
        configuration.savedHosts.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    nonisolated static func resolvedHostName(
        explicitName: String,
        sshAlias: String,
        hostname: String,
        user: String
    ) -> String {
        let trimmedName = explicitName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let trimmedAlias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAlias.isEmpty {
            return trimmedAlias
        }

        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHostname.isEmpty {
            return trimmedUser.isEmpty ? trimmedHostname : "\(trimmedUser)@\(trimmedHostname)"
        }

        return ""
    }

    func removeHost(_ host: AITerminalHost) {
        do {
            try credentialStore.removePassword(for: host.id)
        } catch {
            lastError = L10n.SSHConnections.passwordDeleteFailed(error.localizedDescription)
            return
        }
        configuration.savedHosts.removeAll { $0.id == host.id }
        configuration.importedHostOverrides.removeAll { $0.id == host.id }
        configuration.favoriteHostIDs.removeAll { $0 == host.id }
        configuration.recentHosts.removeAll { $0.id == host.id }
        if !importedSSHHosts.contains(where: { $0.id == host.id }) {
            configuration.workspaces.removeAll { $0.hostID == host.id }
        }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func resetImportedHostOverride(_ host: AITerminalHost) {
        do {
            try credentialStore.removePassword(for: host.id)
        } catch {
            lastError = L10n.SSHConnections.passwordDeleteFailed(error.localizedDescription)
            return
        }
        configuration.importedHostOverrides.removeAll { $0.id == host.id }
        configuration.favoriteHostIDs.removeAll { $0 == host.id }
        configuration.recentHosts.removeAll { $0.id == host.id }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func saveWorkspace(
        name: String,
        hostID: String,
        directory: String
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            lastError = L10n.AITerminalManager.workspaceNameEmpty
            return
        }
        guard !trimmedDirectory.isEmpty else {
            lastError = L10n.AITerminalManager.workspaceDirectoryEmpty
            return
        }

        configuration.workspaces.append(.init(
            id: "workspace:\(UUID().uuidString)",
            name: trimmedName,
            hostID: hostID,
            directory: trimmedDirectory
        ))
        configuration.workspaces.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func removeWorkspace(_ workspace: AITerminalWorkspaceTemplate) {
        configuration.workspaces.removeAll { $0.id == workspace.id }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func saveLearningSettings(_ newSettings: AITerminalLearningSettings) {
        var settings = configuration.learningSettings
        settings.enabled = newSettings.enabled
        settings.preferTabWorkingDirectory = newSettings.preferTabWorkingDirectory
        settings.defaultProjectPath = newSettings.defaultProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedNotesPath = newSettings.notesRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.notesRelativePath = trimmedNotesPath.isEmpty
            ? AITerminalLearningSettings.defaultNotesRelativePath
            : trimmedNotesPath

        let trimmedCommandTemplate = newSettings.commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.commandTemplate = AITerminalLearningSettings.normalizedCommandTemplate(trimmedCommandTemplate)

        // Fast model and prompt editors are hidden in UI. Keep these fields stable and lightweight.
        settings.fastModel = AITerminalLearningSettings.defaultFastModel
        settings.promptTemplate = AITerminalLearningSettings.defaultPromptTemplate

        configuration.learningSettings = settings
        lastError = nil
        persistConfiguration()
    }

    @discardableResult
    func initializeChatAndLearnWorkspace(
        chatWorkspacePath: String,
        commandTemplate: String
    ) -> LearningWorkspaceBootstrapResult? {
        let trimmedChatWorkspacePath = chatWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatWorkspacePath.isEmpty else {
            lastError = L10n.AITerminalManager.workspaceDirectoryEmpty
            return nil
        }

        let expandedChatWorkspacePath = NSString(string: trimmedChatWorkspacePath).expandingTildeInPath
        var chatWorkspaceURL = URL(fileURLWithPath: expandedChatWorkspacePath, isDirectory: true)
            .standardizedFileURL
        if chatWorkspaceURL.lastPathComponent == AITerminalLearningSettings.learnWorkspaceDirectoryName {
            chatWorkspaceURL.deleteLastPathComponent()
        }
        let learnWorkspacePath = AITerminalLearningSettings.learnWorkspacePath(
            fromChatWorkspacePath: chatWorkspaceURL.path
        )
        let learnWorkspaceURL = URL(fileURLWithPath: learnWorkspacePath, isDirectory: true)

        let trimmedCommandTemplate = commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCommandTemplate = AITerminalLearningSettings.normalizedCommandTemplate(trimmedCommandTemplate)

        do {
            let result = try Self.createWorkspaceScaffold(
                chatWorkspaceURL: chatWorkspaceURL,
                learnWorkspaceURL: learnWorkspaceURL,
                resolvedCommandTemplate: resolvedCommandTemplate
            )

            let currentSettings = configuration.learningSettings
            saveLearningSettings(.init(
                enabled: currentSettings.enabled,
                preferTabWorkingDirectory: false,
                defaultProjectPath: learnWorkspaceURL.path,
                notesRelativePath: AITerminalLearningSettings.defaultNotesRelativePath,
                commandTemplate: resolvedCommandTemplate,
                fastModel: currentSettings.fastModel,
                promptTemplate: currentSettings.promptTemplate
            ))
            if !Self.isRunningTests {
                _ = syncManagedSkillRepositories(chatWorkspacePath: chatWorkspaceURL.path)
            }

            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func initializeChatAndLearnWorkspaceAsync(
        chatWorkspacePath: String,
        commandTemplate: String
    ) async -> LearningWorkspaceBootstrapResult? {
        let trimmedChatWorkspacePath = chatWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatWorkspacePath.isEmpty else {
            lastError = L10n.AITerminalManager.workspaceDirectoryEmpty
            return nil
        }

        let trimmedCommandTemplate = commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCommandTemplate = AITerminalLearningSettings.normalizedCommandTemplate(trimmedCommandTemplate)

        let bootstrapResult: LearningWorkspaceBootstrapResult
        do {
            let expandedPath = NSString(string: trimmedChatWorkspacePath).expandingTildeInPath
            var chatWorkspaceURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
                .standardizedFileURL
            if chatWorkspaceURL.lastPathComponent == AITerminalLearningSettings.learnWorkspaceDirectoryName {
                chatWorkspaceURL.deleteLastPathComponent()
            }
            let learnWorkspaceURL = URL(
                fileURLWithPath: AITerminalLearningSettings.learnWorkspacePath(
                    fromChatWorkspacePath: chatWorkspaceURL.path
                ),
                isDirectory: true
            )
            bootstrapResult = try Self.createWorkspaceScaffold(
                chatWorkspaceURL: chatWorkspaceURL,
                learnWorkspaceURL: learnWorkspaceURL,
                resolvedCommandTemplate: resolvedCommandTemplate
            )
        } catch {
            lastError = error.localizedDescription
            return nil
        }

        let currentSettings = configuration.learningSettings
        saveLearningSettings(.init(
            enabled: currentSettings.enabled,
            preferTabWorkingDirectory: false,
            defaultProjectPath: bootstrapResult.learnWorkspacePath,
            notesRelativePath: AITerminalLearningSettings.defaultNotesRelativePath,
            commandTemplate: resolvedCommandTemplate,
            fastModel: currentSettings.fastModel,
            promptTemplate: currentSettings.promptTemplate
        ))

        if !Self.isRunningTests {
            let statuses = await Task.detached(priority: .utility) {
                Self.evaluateManagedSkillRepositoryStatuses(
                    chatWorkspacePath: bootstrapResult.chatWorkspacePath,
                    shouldSync: true
                )
            }.value
            managedSkillRepositoryStatuses = statuses
            if let failure = statuses.first(where: { $0.state == .error }) {
                lastError = failure.message
            } else {
                lastError = nil
            }
        }

        return bootstrapResult
    }

    @discardableResult
    func checkManagedSkillRepositoryUpdates(chatWorkspacePath: String) -> [ManagedSkillRepositoryStatus] {
        let statuses = Self.evaluateManagedSkillRepositoryStatuses(
            chatWorkspacePath: chatWorkspacePath,
            shouldSync: false
        )
        managedSkillRepositoryStatuses = statuses
        return statuses
    }

    @discardableResult
    func checkManagedSkillRepositoryUpdatesAsync(chatWorkspacePath: String) async -> [ManagedSkillRepositoryStatus] {
        let statuses = await Task.detached(priority: .utility) {
            Self.evaluateManagedSkillRepositoryStatuses(
                chatWorkspacePath: chatWorkspacePath,
                shouldSync: false
            )
        }.value
        managedSkillRepositoryStatuses = statuses
        return statuses
    }

    @discardableResult
    func syncManagedSkillRepositories(chatWorkspacePath: String) -> [ManagedSkillRepositoryStatus] {
        let statuses = Self.evaluateManagedSkillRepositoryStatuses(
            chatWorkspacePath: chatWorkspacePath,
            shouldSync: true
        )
        managedSkillRepositoryStatuses = statuses
        if let failure = statuses.first(where: { $0.state == .error }) {
            lastError = failure.message
        } else {
            lastError = nil
        }
        return statuses
    }

    @discardableResult
    func syncManagedSkillRepositoriesAsync(chatWorkspacePath: String) async -> [ManagedSkillRepositoryStatus] {
        let statuses = await Task.detached(priority: .utility) {
            Self.evaluateManagedSkillRepositoryStatuses(
                chatWorkspacePath: chatWorkspacePath,
                shouldSync: true
            )
        }.value
        managedSkillRepositoryStatuses = statuses
        if let failure = statuses.first(where: { $0.state == .error }) {
            lastError = failure.message
        } else {
            lastError = nil
        }
        return statuses
    }

    func appendLearningLog(
        status: AITerminalLearningLogEntry.Status,
        outputSummary: String,
        outputDetail: String? = nil,
        exitCode: Int32? = nil,
        commandTemplate: String,
        projectPath: String,
        notesAbsolutePath: String
    ) {
        let trimmedSummary = outputSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSummary = trimmedSummary.isEmpty
            ? "(no output)"
            : trimmedSummary
        let summary = Self.clampText(
            normalizedSummary,
            maxCharacters: Self.maxLearningLogSummaryCharacters
        )
        let detail = outputDetail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail: String? = if let detail, !detail.isEmpty {
            Self.clampText(
                detail,
                maxCharacters: Self.maxLearningLogDetailCharacters
            )
        } else {
            nil
        }

        let entry = AITerminalLearningLogEntry(
            status: status,
            outputSummary: summary,
            outputDetail: normalizedDetail,
            exitCode: exitCode,
            commandTemplate: commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
            projectPath: projectPath.trimmingCharacters(in: .whitespacesAndNewlines),
            notesAbsolutePath: notesAbsolutePath.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        configuration.learningLogs.append(entry)
        if configuration.learningLogs.count > Self.maxLearningLogEntries {
            configuration.learningLogs = Array(configuration.learningLogs.suffix(Self.maxLearningLogEntries))
        }

        lastError = nil
        persistConfiguration()
    }

    nonisolated private static func evaluateManagedSkillRepositoryStatuses(
        chatWorkspacePath: String,
        shouldSync: Bool
    ) -> [ManagedSkillRepositoryStatus] {
        let normalizedChatPath = normalizedChatWorkspacePath(from: chatWorkspacePath)
        guard !normalizedChatPath.isEmpty else { return [] }

        let chatWorkspaceURL = URL(fileURLWithPath: normalizedChatPath, isDirectory: true)
        let learnWorkspaceURL = URL(
            fileURLWithPath: AITerminalLearningSettings.learnWorkspacePath(
                fromChatWorkspacePath: normalizedChatPath
            ),
            isDirectory: true
        )
        let repositoryCacheRootURL = chatWorkspaceURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("skill-repos", isDirectory: true)

        if shouldSync {
            try? FileManager.default.createDirectory(at: repositoryCacheRootURL, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(
                at: chatWorkspaceURL.appendingPathComponent(".codex/skills", isDirectory: true),
                withIntermediateDirectories: true
            )
            try? FileManager.default.createDirectory(
                at: learnWorkspaceURL.appendingPathComponent(".codex/skills", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        return managedSkillRepositorySpecs.map { spec in
            evaluateManagedSkillRepositoryStatus(
                spec: spec,
                chatWorkspaceURL: chatWorkspaceURL,
                learnWorkspaceURL: learnWorkspaceURL,
                repositoryCacheRootURL: repositoryCacheRootURL,
                shouldSync: shouldSync
            )
        }
    }

    nonisolated private static func evaluateManagedSkillRepositoryStatus(
        spec: ManagedSkillRepositorySpec,
        chatWorkspaceURL: URL,
        learnWorkspaceURL: URL,
        repositoryCacheRootURL: URL,
        shouldSync: Bool
    ) -> ManagedSkillRepositoryStatus {
        let checkoutURL = repositoryCacheRootURL.appendingPathComponent(spec.id, isDirectory: true)
        let destinationRootURL: URL = switch spec.scope {
        case .chat:
            chatWorkspaceURL
        case .learn:
            learnWorkspaceURL
        }
        let destinationURL = destinationRootURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(spec.skillName, isDirectory: true)

        var localCommit: String?
        var remoteCommit: String?
        var state: ManagedSkillRepositoryState = .notInstalled
        var message: String?

        do {
            if shouldSync {
                try syncManagedSkillRepositoryCheckout(spec: spec, checkoutURL: checkoutURL)
                try deployManagedSkillRepository(
                    from: checkoutURL,
                    to: destinationURL
                )
            }

            guard isGitRepository(checkoutURL) else {
                return .init(
                    id: spec.id,
                    skillName: spec.skillName,
                    repositoryURL: spec.repositoryURL,
                    branch: spec.branch,
                    destinationPath: destinationURL.path,
                    localCommit: nil,
                    remoteCommit: nil,
                    expectedTag: spec.expectedTag,
                    expectedCommit: spec.expectedCommit,
                    state: .notInstalled,
                    message: nil
                )
            }

            _ = try runGit(
                arguments: [
                    "-C", checkoutURL.path,
                    "fetch",
                    "--quiet",
                    "origin",
                    spec.branch,
                ]
            )
            localCommit = try gitOutput(
                arguments: ["-C", checkoutURL.path, "rev-parse", "--short", "HEAD"]
            )
            remoteCommit = try gitOutput(
                arguments: ["-C", checkoutURL.path, "rev-parse", "--short", "origin/\(spec.branch)"]
            )
            let dirty = try !gitOutput(
                arguments: ["-C", checkoutURL.path, "status", "--porcelain"]
            ).isEmpty

            if dirty {
                state = .localChanges
                message = "Local modifications detected in cached repository."
            } else if localCommit == remoteCommit {
                state = .latest
            } else {
                state = .updateAvailable
            }
        } catch {
            state = .error
            message = error.localizedDescription
        }

        return .init(
            id: spec.id,
            skillName: spec.skillName,
            repositoryURL: spec.repositoryURL,
            branch: spec.branch,
            destinationPath: destinationURL.path,
            localCommit: localCommit,
            remoteCommit: remoteCommit,
            expectedTag: spec.expectedTag,
            expectedCommit: spec.expectedCommit,
            state: state,
            message: message
        )
    }

    nonisolated private static func syncManagedSkillRepositoryCheckout(
        spec: ManagedSkillRepositorySpec,
        checkoutURL: URL
    ) throws {
        let fileManager = FileManager.default
        let checkoutExists = fileManager.fileExists(atPath: checkoutURL.path)

        if !isGitRepository(checkoutURL) {
            if checkoutExists {
                try fileManager.removeItem(at: checkoutURL)
            }

            _ = try runGit(
                arguments: [
                    "clone",
                    "--branch", spec.branch,
                    "--single-branch",
                    spec.repositoryURL,
                    checkoutURL.path,
                ]
            )
            return
        }

        _ = try runGit(arguments: ["-C", checkoutURL.path, "remote", "set-url", "origin", spec.repositoryURL])
        _ = try runGit(arguments: ["-C", checkoutURL.path, "fetch", "origin", spec.branch, "--tags"])
        _ = try runGit(arguments: ["-C", checkoutURL.path, "checkout", spec.branch])
        _ = try runGit(arguments: ["-C", checkoutURL.path, "pull", "--ff-only", "origin", spec.branch])
    }

    nonisolated private static func deployManagedSkillRepository(
        from checkoutURL: URL,
        to destinationURL: URL
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try runRsync(
            arguments: [
                "-a",
                "--delete",
                "--exclude", ".git",
                "\(checkoutURL.path)/",
                "\(destinationURL.path)/",
            ]
        )
        try ensureShellScriptsExecutable(at: destinationURL)
    }

    nonisolated private static func ensureShellScriptsExecutable(at directoryURL: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "sh" else { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
        }
    }

    nonisolated private static func normalizedChatWorkspacePath(from path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var url = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
        if url.lastPathComponent == AITerminalLearningSettings.learnWorkspaceDirectoryName {
            url.deleteLastPathComponent()
        }
        return url.path
    }

    nonisolated private static func isGitRepository(_ directoryURL: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent(".git", isDirectory: true).path
        )
    }

    private struct CommandExecutionResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private struct ProcessExecutionError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    nonisolated private static func gitOutput(arguments: [String]) throws -> String {
        let result = try runGit(arguments: arguments)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func runGit(arguments: [String]) throws -> CommandExecutionResult {
        try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git"] + arguments
        )
    }

    nonisolated private static func runRsync(arguments: [String]) throws -> CommandExecutionResult {
        try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/rsync"),
            arguments: arguments
        )
    }

    nonisolated private static func runCommand(
        executableURL: URL,
        arguments: [String]
    ) throws -> CommandExecutionResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ProcessExecutionError(message: "Failed to start process: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let result = CommandExecutionResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )

        if result.exitCode != 0 {
            let message = [result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                           result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)]
                .first(where: { !$0.isEmpty }) ?? "exit code \(result.exitCode)"
            throw ProcessExecutionError(message: message)
        }

        return result
    }

    func clearLearningLogs() {
        configuration.learningLogs.removeAll()
        lastError = nil
        persistConfiguration()
    }

    private static func createWorkspaceScaffold(
        chatWorkspaceURL: URL,
        learnWorkspaceURL: URL,
        resolvedCommandTemplate: String
    ) throws -> LearningWorkspaceBootstrapResult {
        var createdFileCount = 0
        var reusedFileCount = 0

        try FileManager.default.createDirectory(at: chatWorkspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: learnWorkspaceURL, withIntermediateDirectories: true)

        let chatAgentsURL = chatWorkspaceURL.appendingPathComponent("AGENTS.md")
        let chatKnowledgesInboxURL = chatWorkspaceURL
            .appendingPathComponent("knowledges", isDirectory: true)
            .appendingPathComponent("inbox.md")
        let chatSkillURL = chatWorkspaceURL
            .appendingPathComponent(".codex/skills/chat-knowledge-sync", isDirectory: true)
            .appendingPathComponent("SKILL.md")

        let learnAgentsURL = learnWorkspaceURL.appendingPathComponent("AGENTS.md")
        let learnRunbookURL = learnWorkspaceURL.appendingPathComponent("RUNBOOK.md")
        let learnEnvURL = learnWorkspaceURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("learn.env")
        let learnSkillRootURL = learnWorkspaceURL
            .appendingPathComponent(".codex/skills/terminal-learning-notes", isDirectory: true)
        let learnSkillURL = learnSkillRootURL.appendingPathComponent("SKILL.md")
        let learnCaptureScriptURL = learnSkillRootURL
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("run_learn_capture.sh")
        let learnSimpleScriptURL = learnSkillRootURL
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("learn.sh")
        let learnArchiveURL = learnWorkspaceURL
            .appendingPathComponent(".codex/learning-archive", isDirectory: true)
            .appendingPathComponent("raw-selections.jsonl")

        try writeTextFileIfMissing(
            chatWorkspaceAgentsTemplate,
            to: chatAgentsURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )
        try migrateLegacyChatAgentsTemplateIfNeeded(at: chatAgentsURL)
        try writeTextFileIfMissing(
            "",
            to: chatKnowledgesInboxURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )
        try writeTextFileIfMissing(
            chatWorkspaceSkillTemplate,
            to: chatSkillURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )
        try writeTextFileIfMissing(
            learnWorkspaceAgentsTemplate,
            to: learnAgentsURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )
        try writeTextFileIfMissing(
            learnRunbookTemplate,
            to: learnRunbookURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )
        try writeTextFileIfMissing(
            learnEnvTemplate(
                learnWorkspacePath: learnWorkspaceURL.path,
                commandTemplate: resolvedCommandTemplate
            ),
            to: learnEnvURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )
        try writeTextFileIfMissing(
            learnSkillTemplate,
            to: learnSkillURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )
        try writeTextFileIfMissing(
            learnCaptureScriptTemplate,
            to: learnCaptureScriptURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )
        try writeTextFileIfMissing(
            learnSimpleScriptTemplate,
            to: learnSimpleScriptURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )
        try writeTextFileIfMissing(
            "",
            to: learnArchiveURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )

        // Keep existing scaffold files compatible with trusted-directory checks.
        try ensureCodexExecSkipGitRepoCheck(in: learnEnvURL)
        try ensureCodexExecSkipGitRepoCheck(in: learnSkillURL)
        try ensureCodexExecSkipGitRepoCheck(in: learnCaptureScriptURL)

        try ensureExecutable(at: learnCaptureScriptURL)
        try ensureExecutable(at: learnSimpleScriptURL)

        return .init(
            chatWorkspacePath: chatWorkspaceURL.path,
            learnWorkspacePath: learnWorkspaceURL.path,
            createdFileCount: createdFileCount,
            reusedFileCount: reusedFileCount
        )
    }

    private static func writeTextFileIfMissing(
        _ content: String,
        to url: URL,
        createdFileCount: inout Int,
        reusedFileCount: inout Int
    ) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            reusedFileCount += 1
            return
        }

        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        createdFileCount += 1
    }

    private static func ensureExecutable(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func migrateLegacyChatAgentsTemplateIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let content = try String(contentsOf: url, encoding: .utf8)
        let isLegacyTemplate = content.contains("## Goal\nKeep chat knowledge lightweight and easy to reuse.")
            && content.contains("`knowledges/inbox.md`: chat project knowledge bullets.")
            && content.contains("- Avoid duplicating semantically identical entries.")

        guard isLegacyTemplate else { return }
        try chatWorkspaceAgentsTemplate.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func ensureCodexExecSkipGitRepoCheck(in url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let content = try String(contentsOf: url, encoding: .utf8)
        let updated = injectSkipGitRepoCheck(in: content)
        guard updated != content else { return }

        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func injectSkipGitRepoCheck(in text: String) -> String {
        let pattern = #"codex1m exec(?! --skip-git-repo-check)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "codex1m exec --skip-git-repo-check"
        )
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func learnEnvTemplate(
        learnWorkspacePath: String,
        commandTemplate: String
    ) -> String {
        """
        # Workspace path for codex exec -C
        LEARN_WORKSPACE="\(learnWorkspacePath)"

        # Strict command template (can be replaced in Settings Panel)
        LEARN_EXEC_COMMAND_TEMPLATE=\(shellSingleQuoted(commandTemplate))
        """
    }

    private static let chatWorkspaceAgentsTemplate = #"""
    # codex_chat_workspace

    If `knowledges/*.md` exists, treat those files as the real project knowledge notes and reference them directly.
    """#

    private static let chatWorkspaceSkillTemplate = #"""
    ---
    name: chat-knowledge-sync
    description: "Use knowledges/inbox.md as lightweight project memory."
    ---

    # Chat Knowledge Sync

    ## Use This Skill When
    - You need to read or update `knowledges/inbox.md`.

    ## Rules
    - Keep notes concise.
    - Preserve source meaning.
    - Prefer append or exact-match update.
    """#

    private static let learnWorkspaceAgentsTemplate = #"""
    # codex_learn_workspace

    ## Goal
    Keep learning flow minimal and source-faithful.

    ## Minimal Flow (Strict)
    1. Read selected text.
    2. Archive raw input text into this project.
    3. Run one codex exec command in learn workspace.
    4. Return Markdown bullets only.

    ## Hard Constraints
    - Never add new facts that are not in user input.
    - Never paraphrase into new meaning.
    - No web search, no external lookup, no speculative reasoning.
    - Output must be list items only (`- ...`), with no title or commentary.
    """#

    private static let learnSkillTemplate = #"""
    ---
    name: terminal-learning-notes
    description: "Strict learning capture: preserve source meaning, no expansion, no speculation, Markdown bullets only."
    ---

    # Terminal Learning Notes (Strict Preserve Mode)

    ## Use This Skill When
    - You want to capture terminal-selected text into notes without semantic changes.

    ## Command Baseline
    `/Users/leongong/.local/bin/codex1m exec --skip-git-repo-check -c 'mcp_servers.gemini.enabled=false' -c 'mcp_servers.grok-research.enabled=false' -c 'mcp_servers.opus-planning.enabled=false' -C "$LEARN_WORKSPACE" "$PROMPT"`

    ## Recommended Launcher
    `./.codex/skills/terminal-learning-notes/scripts/run_learn_capture.sh`

    ## Hard Rules
    - Do not expand, infer, speculate, or add any information not present in the source text.
    - Do not rewrite meaning. Keep wording as close to source as possible.
    - Output must be Markdown bullet lines only (`- ...`), with no title/preamble/explanation.
    """#

    private static let learnRunbookTemplate = #"""
    # Runbook

    ## Recommended Ghostty Learning Command Template
    Use this command in Ghostty Learning settings:

    ```bash
    ./.codex/skills/terminal-learning-notes/scripts/run_learn_capture.sh
    ```
    """#

    private static let learnCaptureScriptTemplate = #"""
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
    WORKSPACE_DIR="$(cd "${SKILL_DIR}/../../../" && pwd)"

    read_selection() {
      if [[ -n "${SELECTION:-}" ]]; then
        printf '%s' "$SELECTION"
        return
      fi
      if [[ $# -gt 0 ]]; then
        printf '%s' "$*"
        return
      fi
      if [[ ! -t 0 ]]; then
        cat
        return
      fi
      return 1
    }

    one_line() {
      printf '%s' "$1" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
    }

    json_escape() {
      local value="$1"
      value=${value//\\/\\\\}
      value=${value//\"/\\\"}
      value=${value//$'\n'/\\n}
      value=${value//$'\r'/\\r}
      value=${value//$'\t'/\\t}
      printf '%s' "$value"
    }

    selection="$(read_selection "$@" || true)"
    if [[ -z "${selection//[$' \t\n\r']/}" ]]; then
      echo "No selection text provided." >&2
      exit 2
    fi

    LEARN_WORKSPACE="${LEARN_WORKSPACE:-$WORKSPACE_DIR}"
    PROJECT_PATH="${PROJECT_PATH:-${TAB_WORKING_DIRECTORY:-$LEARN_WORKSPACE}}"

    ARCHIVE_DIR="${LEARN_WORKSPACE}/.codex/learning-archive"
    ARCHIVE_FILE="${ARCHIVE_DIR}/raw-selections.jsonl"
    mkdir -p "$ARCHIVE_DIR"

    timestamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf '{"time":"%s","project_path":"%s","tab_working_directory":"%s","selection":"%s"}\n' \
      "$(json_escape "$timestamp")" \
      "$(json_escape "$PROJECT_PATH")" \
      "$(json_escape "${TAB_WORKING_DIRECTORY:-}")" \
      "$(json_escape "$selection")" >> "$ARCHIVE_FILE"

    PROMPT="${PROMPT:-请执行“原文保真整理”。严格规则：1) 仅输出 Markdown 列表，每行以“- ”开头。2) 每条必须直接摘录原文，不得改写、扩写、推断、补充。3) 不要输出标题、解释或额外文本。原文如下：
    $selection}"

    LEARN_EXEC_COMMAND_TEMPLATE="${LEARN_EXEC_COMMAND_TEMPLATE:-/Users/leongong/.local/bin/codex1m exec --skip-git-repo-check -c 'mcp_servers.gemini.enabled=false' -c 'mcp_servers.grok-research.enabled=false' -c 'mcp_servers.opus-planning.enabled=false' -C \"$LEARN_WORKSPACE\" \"$PROMPT\"}"

    set +e
    command_output="$(
      PROMPT="$PROMPT" \
      SELECTION="$selection" \
      PROJECT_PATH="$PROJECT_PATH" \
      LEARN_WORKSPACE="$LEARN_WORKSPACE" \
      TAB_WORKING_DIRECTORY="${TAB_WORKING_DIRECTORY:-}" \
      /bin/zsh -lc "$LEARN_EXEC_COMMAND_TEMPLATE" 2>&1
    )"
    command_status=$?
    set -e

    if (( command_status != 0 )); then
      echo "$command_output" >&2
      exit "$command_status"
    fi

    selection_flat="$(one_line "$selection")"
    has_output=0
    while IFS= read -r raw_line; do
      line="$(printf '%s' "$raw_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [[ -z "$line" ]] && continue
      payload=""
      if [[ "$line" == "- "* || "$line" == "* "* ]]; then
        payload="${line:2}"
      elif printf '%s' "$line" | grep -Eq '^[0-9]+[.)][[:space:]]+'; then
        payload="$(printf '%s' "$line" | sed -E 's/^[0-9]+[.)][[:space:]]+//')"
      else
        continue
      fi
      cleaned="$(one_line "$payload")"
      [[ -z "$cleaned" ]] && continue
      [[ "$selection_flat" != *"$cleaned"* ]] && continue
      printf -- '- %s\n' "$cleaned"
      has_output=1
    done <<< "$command_output"

    if (( has_output == 0 )); then
      while IFS= read -r raw_line; do
        line="$(printf '%s' "$raw_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [[ -z "$line" ]] && continue
        printf -- '- %s\n' "$line"
      done <<< "$selection"
    fi
    """#

    private static let learnSimpleScriptTemplate = #"""
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec "${SCRIPT_DIR}/run_learn_capture.sh" "$@"
    """#

    func setManagedState(_ state: AITerminalManagedState, for sessionID: UUID) {
        var registration = registrations[sessionID] ?? .init(
            hostID: AITerminalHost.local.id,
            workspaceID: nil,
            managedState: .manual,
            sourceLabel: L10n.AITerminalManager.manualSession
        )
        registration.managedState = state
        registrations[sessionID] = registration
        rebuildSessions()
    }

    func task(for sessionID: UUID) -> AITerminalTaskRecord? {
        guard let taskID = taskBindings[sessionID] else { return nil }
        return tasks.first(where: { $0.id == taskID })
    }

    func createTask(for sessionID: UUID, title: String? = nil) {
        guard sessions.contains(where: { $0.id == sessionID }) else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        if let existing = task(for: sessionID) {
            updateTask(existing.id, state: .active, note: existing.note)
            setManagedState(.managedActive, for: sessionID)
            return
        }

        let task = AITerminalTaskRecord(
            title: title ?? defaultTaskTitle(for: sessionID),
            sessionID: sessionID,
            state: .active
        )
        taskBindings[sessionID] = task.id
        tasks.insert(task, at: 0)
        setManagedState(.managedActive, for: sessionID)
        lastError = nil
        rebuildSessions()
    }

    func pauseTask(for sessionID: UUID) {
        guard let task = task(for: sessionID) else { return }
        updateTask(task.id, state: .paused, note: task.note)
        setManagedState(.managedPaused, for: sessionID)
    }

    func resumeTask(for sessionID: UUID) {
        guard let task = task(for: sessionID) else {
            createTask(for: sessionID)
            return
        }
        updateTask(task.id, state: .active, note: task.note)
        setManagedState(.managedActive, for: sessionID)
    }

    func requireApproval(for sessionID: UUID) {
        guard let task = task(for: sessionID) else {
            createTask(for: sessionID)
            requireApproval(for: sessionID)
            return
        }
        updateTask(task.id, state: .waitingApproval, note: L10n.AITerminalManager.waitingForOperator)
        setManagedState(.managedWaitingApproval, for: sessionID)
    }

    func completeTask(for sessionID: UUID) {
        guard let task = task(for: sessionID) else { return }
        updateTask(task.id, state: .completed, note: L10n.AITerminalManager.markedComplete)
        setManagedState(.managedCompleted, for: sessionID)
    }

    func failTask(for sessionID: UUID) {
        guard let task = task(for: sessionID) else { return }
        updateTask(task.id, state: .failed, note: L10n.AITerminalManager.markedFailed)
        setManagedState(.managedFailed, for: sessionID)
    }

    func focus(sessionID: UUID) {
        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: sessionID) else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        NotificationCenter.default.post(
            name: Ghostty.Notification.ghosttyPresentTerminal,
            object: surface
        )
        lastError = nil
    }

    func selectSession(_ sessionID: UUID?) {
        guard let sessionID else {
            selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
            lastError = nil
            return
        }

        guard sessions.contains(where: { $0.id == sessionID }) else {
            selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        selectedSessionID = sessionID
        refreshSelectedSessionSnapshot()
    }

    func refreshSelectedSessionSnapshot() {
        guard let currentSelectedSessionID = selectedSessionID else {
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
            lastError = nil
            return
        }

        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: currentSelectedSessionID) else {
            self.selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        selectedSessionVisibleText = surface.aiManagerVisibleText()
        selectedSessionScreenText = surface.aiManagerScreenText()
        lastError = nil
    }

    func sendInput(_ input: String, to sessionID: UUID? = nil) {
        guard let payload = Self.textPayload(for: input) else {
            lastError = L10n.AITerminalManager.inputEmpty
            return
        }

        let targetSessionID = sessionID ?? selectedSessionID
        guard let targetSessionID else {
            lastError = L10n.AITerminalManager.selectSessionFirst
            return
        }

        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: targetSessionID) else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        surface.aiManagerSendText(payload)
        if selectedSessionID == targetSessionID {
            refreshSelectedSessionSnapshot()
        } else {
            lastError = nil
        }
    }

    func sendCommand(_ command: String, to sessionID: UUID? = nil) {
        guard let payload = Self.commandPayload(for: command) else {
            lastError = L10n.AITerminalManager.commandEmpty
            return
        }

        let targetSessionID = sessionID ?? selectedSessionID
        guard let targetSessionID else {
            lastError = L10n.AITerminalManager.selectSessionFirst
            return
        }

        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: targetSessionID) else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        surface.aiManagerSendText(payload)
        if selectedSessionID == targetSessionID {
            refreshSelectedSessionSnapshot()
        } else {
            lastError = nil
        }
    }

    func closeSession(_ sessionID: UUID? = nil) {
        let targetSessionID = sessionID ?? selectedSessionID
        guard let targetSessionID else {
            lastError = L10n.AITerminalManager.selectSessionFirst
            return
        }

        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: targetSessionID),
              let nativeSurface = surface.surface else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        appDelegate.ghostty.requestClose(surface: nativeSurface)
        if selectedSessionID == targetSessionID {
            selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
        }
        lastError = nil
        rebuildSessions()
    }

    @discardableResult
    private func launch(
        _ plan: AITerminalLaunchPlan,
        target: AITerminalLaunchTarget? = nil
    ) -> UUID? {
        guard let appDelegate = appDelegateProvider() else {
            lastError = L10n.AITerminalManager.appDelegateUnavailable
            return nil
        }

        let createdSurface: Ghostty.SurfaceView?
        switch target ?? launchTarget {
        case .tab:
            if let controller = TerminalController.newTab(
                appDelegate.ghostty,
                from: TerminalController.preferredParent?.window,
                withBaseConfig: plan.surfaceConfiguration
            ) {
                createdSurface = controller.surfaceTree.root?.leftmostLeaf()
            } else {
                let controller = TerminalController.newWindow(
                    appDelegate.ghostty,
                    withBaseConfig: plan.surfaceConfiguration
                )
                createdSurface = controller.surfaceTree.root?.leftmostLeaf()
            }

        case .window:
            let controller = TerminalController.newWindow(
                appDelegate.ghostty,
                withBaseConfig: plan.surfaceConfiguration
            )
            createdSurface = controller.surfaceTree.root?.leftmostLeaf()
        }

        guard let createdSurface else {
            lastError = L10n.AITerminalManager.createSessionFailed
            return nil
        }

        registrations[createdSurface.id] = plan.registration
        rebuildSessions()
        return createdSurface.id
    }

    private func rebuildSessions() {
        let hostLookup = Dictionary(uniqueKeysWithValues: availableHosts.map { ($0.id, $0) })
        let activeSessionIDs = Set(
            TerminalController.all.flatMap { controller in
                controller.surfaceTree.map(\.id)
            }
        )

        pruneClosedSessions(activeSessionIDs: activeSessionIDs)

        sessions = TerminalController.all
            .flatMap { controller in
                controller.surfaceTree.map { surface in
                    let registration = registrations[surface.id]
                    let task = task(for: surface.id)
                    let hostLabel = registration
                        .flatMap { $0.hostID }
                        .flatMap { hostLookup[$0]?.name }
                        ?? L10n.AITerminalManager.manualSession
                    let title: String
                    if let override = controller.titleOverride, !override.isEmpty {
                        title = override
                    } else if !surface.title.isEmpty {
                        title = surface.title
                    } else {
                        title = L10n.Common.untitled
                    }

                    return AITerminalSessionSummary(
                        id: surface.id,
                        title: title,
                        workingDirectory: surface.pwd,
                        isFocused: surface.focused,
                        hostLabel: hostLabel,
                        managedState: registration?.managedState ?? .manual,
                        taskID: task?.id,
                        taskTitle: task?.title,
                        taskState: task?.state
                    )
                }
            }
            .sorted {
                if $0.isFocused != $1.isFocused {
                    return $0.isFocused && !$1.isFocused
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

        processPendingSSHPasswordPrompts()
        rebuildRemoteSessions(hostLookup: hostLookup)

        if let selectedSessionID, sessions.contains(where: { $0.id == selectedSessionID }) {
            refreshSelectedSessionSnapshot()
        } else if self.selectedSessionID != nil {
            self.selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
        }
    }

    private func pruneClosedSessions(activeSessionIDs: Set<UUID>) {
        let trackedSessionIDs = Set(taskBindings.keys)
            .union(registrations.keys)
            .union(sshSessionAuthStates.keys)
            .union(pendingSSHPasswordAutomations.keys)
        let closedSessionIDs = trackedSessionIDs.subtracting(activeSessionIDs)
        guard !closedSessionIDs.isEmpty else { return }

        for sessionID in closedSessionIDs {
            registrations.removeValue(forKey: sessionID)
            sshSessionAuthStates.removeValue(forKey: sessionID)
            pendingSSHPasswordAutomations.removeValue(forKey: sessionID)
            if let taskID = taskBindings.removeValue(forKey: sessionID),
               let index = tasks.firstIndex(where: { $0.id == taskID && $0.state == .active }) {
                tasks[index].state = .failed
                tasks[index].updatedAt = .now
                tasks[index].note = L10n.AITerminalManager.sessionClosed
            }
        }

        if pendingSSHPasswordAutomations.isEmpty {
            stopSSHPasswordAutomationTimer()
        }
    }

    private func registerRemoteSession(_ sessionID: UUID, host: AITerminalHost, savedPassword: String?) {
        if let savedPassword {
            pendingSSHPasswordAutomations[sessionID] = .init(
                hostID: host.id,
                password: savedPassword,
                hasSentPassword: false
            )
            sshSessionAuthStates[sessionID] = .awaitingPassword
            ensureSSHPasswordAutomationTimer()
        } else {
            sshSessionAuthStates[sessionID] = .connecting
        }
        rebuildSessions()
    }

    private func rebuildRemoteSessions(hostLookup: [String: AITerminalHost]) {
        remoteSessions = sessions.compactMap { session in
            guard let registration = registrations[session.id],
                  let hostID = registration.hostID,
                  hostID != AITerminalHost.local.id,
                  let host = hostLookup[hostID],
                  host.transport == .ssh
            else {
                return nil
            }

            let authState: AITerminalSSHSessionAuthState
            if let trackedState = sshSessionAuthStates[session.id] {
                if pendingSSHPasswordAutomations[session.id] != nil || trackedState == .failed {
                    authState = trackedState
                } else {
                    authState = .connected
                }
            } else {
                authState = .connected
            }

            return AITerminalRemoteSessionSummary(
                id: session.id,
                title: session.title,
                hostID: hostID,
                hostName: host.name,
                hostTarget: host.connectionTarget ?? host.displaySubtitle,
                workingDirectory: session.workingDirectory,
                authState: authState,
                isFocused: session.isFocused
            )
        }
    }

    private func resolvedPasswordAutomation(for host: AITerminalHost) -> (password: String?, error: String?) {
        guard host.transport == .ssh else { return (nil, nil) }

        switch host.authMode {
        case .system:
            return (nil, nil)
        case .password:
            do {
                guard let password = try credentialStore.password(for: host.id), !password.isEmpty else {
                    return (nil, L10n.SSHConnections.passwordMissing)
                }
                return (password, nil)
            } catch {
                return (nil, L10n.SSHConnections.passwordReadFailed(error.localizedDescription))
            }
        }
    }

    private func processPendingSSHPasswordPrompts() {
        guard !pendingSSHPasswordAutomations.isEmpty else {
            stopSSHPasswordAutomationTimer()
            return
        }
        guard let appDelegate = appDelegateProvider() else {
            return
        }

        for (sessionID, pending) in pendingSSHPasswordAutomations {
            guard let surface = appDelegate.findSurface(forUUID: sessionID) else { continue }
            let visibleText = surface.aiManagerVisibleText()

            if Self.containsSSHAuthenticationFailure(in: visibleText) {
                sshSessionAuthStates[sessionID] = .failed
                pendingSSHPasswordAutomations.removeValue(forKey: sessionID)
                recordRecentHost(
                    pending.hostID,
                    status: .failed,
                    errorSummary: L10n.SSHConnections.authenticationFailed
                )
                continue
            }

            if pending.hasSentPassword {
                if !Self.containsSSHPasswordPrompt(in: visibleText) {
                    sshSessionAuthStates[sessionID] = .connected
                    pendingSSHPasswordAutomations.removeValue(forKey: sessionID)
                }
                continue
            }

            if Self.containsSSHPasswordPrompt(in: visibleText) {
                surface.aiManagerSendText("\(pending.password)\n")
                pendingSSHPasswordAutomations[sessionID]?.hasSentPassword = true
                sshSessionAuthStates[sessionID] = .authenticating
            } else {
                sshSessionAuthStates[sessionID] = .awaitingPassword
            }
        }

        if pendingSSHPasswordAutomations.isEmpty {
            stopSSHPasswordAutomationTimer()
        }
    }

    private func ensureSSHPasswordAutomationTimer() {
        guard sshPasswordAutomationTimer == nil else { return }

        let timer = Timer(
            timeInterval: 0.2,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            guard !self.pendingSSHPasswordAutomations.isEmpty else {
                self.stopSSHPasswordAutomationTimer()
                return
            }

            self.processPendingSSHPasswordPrompts()
            let hostLookup = Dictionary(uniqueKeysWithValues: self.availableHosts.map { ($0.id, $0) })
            self.rebuildRemoteSessions(hostLookup: hostLookup)
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        sshPasswordAutomationTimer = timer
    }

    private func stopSSHPasswordAutomationTimer() {
        sshPasswordAutomationTimer?.invalidate()
        sshPasswordAutomationTimer = nil
    }

    private func updateTask(_ taskID: UUID, state: AITerminalTaskState, note: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].state = state
        tasks[index].updatedAt = .now
        tasks[index].note = note
        lastError = nil
        rebuildSessions()
    }

    private func defaultTaskTitle(for sessionID: UUID) -> String {
        if let session = sessions.first(where: { $0.id == sessionID }) {
            return L10n.AITerminalManager.manageSession(session.title)
        }
        return L10n.AITerminalManager.defaultTaskTitle
    }

    private func reconcileImportedState() {
        let nextConfiguration = Self.reconciledConfiguration(
            configuration,
            importedHosts: importedSSHHosts
        )
        guard nextConfiguration.importedHostOverrides != configuration.importedHostOverrides
            || nextConfiguration.recentHosts != configuration.recentHosts
        else { return }
        configuration = nextConfiguration
        persistConfiguration()
    }

    nonisolated static func reconciledConfiguration(
        _ configuration: AITerminalManagerConfiguration,
        importedHosts: [AITerminalHost]
    ) -> AITerminalManagerConfiguration {
        let importedIDs = Set(importedHosts.map(\.id))
        let savedIDs = Set(configuration.savedHosts.map(\.id))
        let allowedRecentIDs = importedIDs.union(savedIDs)
        let allowedFavoriteIDs = importedIDs.union(savedIDs)

        var next = configuration
        next.importedHostOverrides = configuration.importedHostOverrides.filter {
            importedIDs.contains($0.id)
        }
        next.favoriteHostIDs = configuration.favoriteHostIDs.filter {
            allowedFavoriteIDs.contains($0)
        }
        next.recentHosts = configuration.recentHosts.filter {
            allowedRecentIDs.contains($0.id)
        }
        return next
    }

    nonisolated static func loadSSHConfigHostsFromDefaultPath() -> [AITerminalHost] {
        let sshConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
            .appendingPathComponent("config")
        guard let contents = try? String(contentsOf: sshConfig, encoding: .utf8) else { return [] }
        return AITerminalSSHConfigParser.parse(contents)
    }

    private func recordRecentHost(
        _ hostID: String,
        status: AITerminalRecentHostRecord.Status,
        errorSummary: String? = nil
    ) {
        guard hostID != AITerminalHost.local.id else { return }
        configuration.recentHosts = Self.upsertRecentHostRecord(
            configuration.recentHosts,
            hostID: hostID,
            status: status,
            errorSummary: errorSummary
        )
        persistConfiguration()
    }

    nonisolated static func upsertRecentHostRecord(
        _ records: [AITerminalRecentHostRecord],
        hostID: String,
        status: AITerminalRecentHostRecord.Status,
        errorSummary: String? = nil,
        now: Date = .now
    ) -> [AITerminalRecentHostRecord] {
        var next = records
        next.removeAll { $0.id == hostID }
        next.insert(
            .init(id: hostID, connectedAt: now, status: status, errorSummary: errorSummary),
            at: 0
        )
        return Array(next.prefix(8))
    }

    nonisolated static func duplicateAlias(
        for host: AITerminalHost,
        existingHosts: [AITerminalHost]
    ) -> String {
        let seed = (host.sshAlias?.isEmpty == false ? host.sshAlias : nil)
            ?? (host.hostname?.isEmpty == false ? host.hostname : nil)
            ?? host.name
        let normalizedSeed = seed
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = normalizedSeed.isEmpty ? "host" : normalizedSeed

        let existingAliases = Set(existingHosts.compactMap(\.sshAlias))
        var candidate = "\(base)-copy"
        var index = 2
        while existingAliases.contains(candidate) {
            candidate = "\(base)-copy-\(index)"
            index += 1
        }
        return candidate
    }

    nonisolated static func containsSSHPasswordPrompt(in text: String) -> Bool {
        guard let line = lastNonEmptyLine(in: text)?.lowercased() else { return false }
        return line.hasSuffix("password:") || line.contains("'s password:")
    }

    nonisolated static func containsSSHAuthenticationFailure(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("permission denied")
            || normalized.contains("connection refused")
            || normalized.contains("network is unreachable")
    }

    private nonisolated static func lastNonEmptyLine(in text: String) -> String? {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty })
    }

    private func persistConfiguration() {
        do {
            try Self.saveConfiguration(configuration, to: configurationURL)
        } catch {
            lastError = L10n.AITerminalManager.saveConfigurationFailed(error.localizedDescription)
        }
    }

    private static func defaultConfigurationURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser

        let bundleID = Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty"
        let directory = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ai-terminal-manager.json", isDirectory: false)
    }

    private static func loadConfiguration(from url: URL) throws -> AITerminalManagerConfiguration {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)
        return sanitizeLearningLogs(in: decoded)
    }

    private static func saveConfiguration(_ configuration: AITerminalManagerConfiguration, to url: URL) throws {
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: url, options: .atomic)
    }

    private static func sanitizeLearningLogs(in configuration: AITerminalManagerConfiguration) -> AITerminalManagerConfiguration {
        var next = configuration
        if next.learningLogs.count > Self.maxLearningLogEntries {
            next.learningLogs = Array(next.learningLogs.suffix(Self.maxLearningLogEntries))
        }
        next.learningLogs = next.learningLogs.map { entry in
            var updated = entry
            updated.outputSummary = clampText(
                entry.outputSummary,
                maxCharacters: Self.maxLearningLogSummaryCharacters
            )
            if let detail = entry.outputDetail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                updated.outputDetail = clampText(
                    detail,
                    maxCharacters: Self.maxLearningLogDetailCharacters
                )
            } else {
                updated.outputDetail = nil
            }
            return updated
        }
        return next
    }

    private static func clampText(_ text: String, maxCharacters: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
        return "\(trimmed[..<endIndex])\n...(truncated)"
    }

    nonisolated static func commandPayload(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return input.hasSuffix("\n") ? input : "\(input)\n"
    }

    nonisolated static func textPayload(for input: String) -> String? {
        guard !input.isEmpty else { return nil }
        return input
    }
}
