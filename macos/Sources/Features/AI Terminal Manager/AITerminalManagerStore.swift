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

    @Published private(set) var configuration: AITerminalManagerConfiguration
    @Published private(set) var importedSSHHosts: [AITerminalHost] = []
    @Published private(set) var remoteSessions: [AITerminalRemoteSessionSummary] = []
    @Published private(set) var sessions: [AITerminalSessionSummary] = []
    @Published private(set) var tasks: [AITerminalTaskRecord] = []
    @Published private(set) var selectedSessionID: UUID?
    @Published private(set) var selectedSessionVisibleText = ""
    @Published private(set) var selectedSessionScreenText = ""
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
        return try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)
    }

    private static func saveConfiguration(_ configuration: AITerminalManagerConfiguration, to url: URL) throws {
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: url, options: .atomic)
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
