import AppKit
import Foundation
import SwiftUI
import GhoDexKit

private actor TodoDocumentPersistenceCoordinator {
    private struct PendingSave {
        var document: AITerminalTodoDayDocument
        var path: String
    }

    private var pendingByPath: [String: PendingSave] = [:]
    private var activePaths: Set<String> = []

    func scheduleSave(
        document: AITerminalTodoDayDocument,
        to path: String,
        writer: @Sendable @escaping (AITerminalTodoDayDocument, String) throws -> Void,
        onError: @Sendable @escaping (Error) async -> Void
    ) async {
        pendingByPath[path] = .init(document: document, path: path)
        guard activePaths.insert(path).inserted else { return }

        while let pending = pendingByPath[path] {
            pendingByPath[path] = nil
            do {
                try writer(pending.document, pending.path)
            } catch {
                await onError(error)
            }
        }

        activePaths.remove(path)
    }
}

@MainActor
final class AITerminalManagerStore: ObservableObject {
    private struct PendingSSHPasswordAutomation {
        var hostID: String
        var password: String
        var hasSentPassword: Bool
    }

    private struct ResolvedTodoSourceState {
        var reference: AITerminalTodoSourceReference
        var item: AITerminalTodoItem
    }

    private struct TodoSyncCandidate {
        var reference: AITerminalTodoSourceReference
        var item: AITerminalTodoItem
    }

    private struct TodoDocumentCacheEntry {
        var document: AITerminalTodoDayDocument
        var cachedAt: Date
        var lastAccessedAt: Date
    }

    private enum ExternalHeartbeatTaskAction: String, Codable {
        case enqueue
        case cancel
        case clearFinished = "clear_finished"
        case configure
    }

    private struct ExternalHeartbeatTaskRequest: Codable {
        var action: ExternalHeartbeatTaskAction?
        var command: String?
        var type: AITerminalHeartbeatTaskType?
        var executeAtMS: Int64?
        var taskID: UUID?
        var enabled: Bool?
        var heartbeatIntervalSeconds: Double?
        var maxConcurrentTasks: Int?

        enum CodingKeys: String, CodingKey {
            case action
            case command
            case type
            case executeAtMS = "execute_at_ms"
            case taskID = "task_id"
            case enabled
            case heartbeatIntervalSeconds = "heartbeat_interval_seconds"
            case maxConcurrentTasks = "max_concurrent_tasks"
        }
    }

    struct LearningWorkspaceBootstrapResult {
        var chatWorkspacePath: String
        var learnWorkspacePath: String
        var createdFileCount: Int
        var reusedFileCount: Int
    }

    struct TodoWorkspaceBootstrapResult {
        var workspaceRootPath: String
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

    struct ProjectedSessionTaskSummary: Equatable, Sendable {
        var taskID: UUID?
        var taskTitle: String?
        var taskState: AITerminalTaskState?
    }

    struct AgentRuntimeSnapshotState: Equatable, Sendable {
        var settings: AgentRuntimeSettings
        var sessions: [AgentRuntimeSession]
        var tasks: [AgentRuntimeTask]
        var schedules: [AgentRuntimeSchedule]
    }

    @Published private(set) var configuration: AITerminalManagerConfiguration
    @Published private(set) var importedSSHHosts: [AITerminalHost] = []
    @Published private(set) var remoteSessions: [AITerminalRemoteSessionSummary] = []
    @Published private(set) var sessions: [AITerminalSessionSummary] = []
    @Published private(set) var tasks: [AITerminalTaskRecord] = []
    @Published private(set) var heartbeatLastBeatAt: Date?
    @Published private(set) var heartbeatIsExecutingTask = false
    @Published private(set) var configurationRevision = UUID()
    @Published private(set) var selectedSessionID: UUID?
    @Published private(set) var selectedSessionVisibleText = ""
    @Published private(set) var selectedSessionScreenText = ""
    @Published private(set) var managedSkillRepositoryStatuses: [ManagedSkillRepositoryStatus] = []
    @Published private(set) var todoRevision = UUID()
    @Published var launchTarget: AITerminalLaunchTarget = .tab
    @Published var lastError: String?

    private let appDelegateProvider: () -> AppDelegate?
    private let configurationURL: URL
    private let heartbeatInboxDirectoryURL: URL
    private let agentRuntimeEventsURL: URL
    private let sshConfigHostLoader: () -> [AITerminalHost]
    private let credentialStore: SSHConnectionCredentialStore
    private let todoDocumentPersistence = TodoDocumentPersistenceCoordinator()
    private var registrations: [UUID: AITerminalLaunchRegistration] = [:]
    private var sshSessionAuthStates: [UUID: AITerminalSSHSessionAuthState] = [:]
    private var pendingSSHPasswordAutomations: [UUID: PendingSSHPasswordAutomation] = [:]
    private var taskBindings: [UUID: UUID] = [:]
    private var todoDocumentCache: [String: TodoDocumentCacheEntry] = [:]
    private var sshPasswordAutomationTimer: Timer?
    private var sshPasswordAutomationInterval: TimeInterval = 0.2
    private var sshPasswordAutomationIdlePollCount = 0
    private var heartbeatTimer: Timer?
    private var heartbeatSchedulerTimer: Timer?
    private var agentRuntimeRecoveryTimer: Timer?
    private var agentRuntimeSchedulerTimer: Timer?
    private var ghosttyConfigObserver: NSObjectProtocol?
    private var splitSurfaceObserver: NSObjectProtocol?
    nonisolated private static let maxLearningLogEntries = 200
    nonisolated private static let maxLearningLogSummaryCharacters = 400
    nonisolated private static let maxLearningLogDetailCharacters = 8_000
    nonisolated private static let minHeartbeatIntervalSeconds = 0.5
    nonisolated private static let maxHeartbeatIntervalSeconds = 60.0
    nonisolated private static let minHeartbeatMaxConcurrentTasks = 1
    nonisolated private static let maxHeartbeatMaxConcurrentTasks = 16
    nonisolated private static let maxHeartbeatTaskEntries = 1_024
    nonisolated private static let heartbeatFinishedTaskRetentionSeconds: TimeInterval = 24 * 60 * 60
    nonisolated private static let todoDocumentCacheMaxEntries = 128
    nonisolated private static let todoDocumentCacheTTLSeconds: TimeInterval = 10 * 60
    nonisolated private static let sshPasswordAutomationFastInterval: TimeInterval = 0.2
    nonisolated private static let sshPasswordAutomationMaxInterval: TimeInterval = 2.0
    nonisolated private static let sshPasswordAutomationBackoffMultiplier: TimeInterval = 1.5
    nonisolated private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    nonisolated private static let legacyConfigurationFilename = "ai-terminal-manager.json"
    nonisolated private static let managedConfigStartMarker = "# >>> GhoDex managed settings >>>"
    nonisolated private static let managedConfigEndMarker = "# <<< GhoDex managed settings <<<"
    nonisolated private static let agentRuntimeScheduleIDMetadataKey = "ghodex_schedule_id"
    nonisolated private static let agentRuntimeScheduleFireAtMetadataKey = "ghodex_schedule_fire_at"
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
        self.heartbeatInboxDirectoryURL = self.configurationURL
            .deletingLastPathComponent()
            .appendingPathComponent("ai-task-queue-inbox", isDirectory: true)
        self.agentRuntimeEventsURL = self.configurationURL
            .deletingLastPathComponent()
            .appendingPathComponent("agent-runtime-events.jsonl", isDirectory: false)
        self.sshConfigHostLoader = sshConfigHostLoader
        self.credentialStore = credentialStore
        self.configuration = (try? Self.loadConfiguration(at: self.configurationURL)) ?? .empty
        if Self.shouldObserveGlobalGhosttyConfig(for: self.configurationURL) {
            installGhosttyConfigObserver()
        }
        installSplitSurfaceObserver()
        refresh()
        migrateLegacyConfigurationIfNeeded()
    }

    deinit {
        if let ghosttyConfigObserver {
            NotificationCenter.default.removeObserver(ghosttyConfigObserver)
        }
        if let splitSurfaceObserver {
            NotificationCenter.default.removeObserver(splitSurfaceObserver)
        }
        sshPasswordAutomationTimer?.invalidate()
        sshPasswordAutomationTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        heartbeatSchedulerTimer?.invalidate()
        heartbeatSchedulerTimer = nil
        agentRuntimeRecoveryTimer?.invalidate()
        agentRuntimeRecoveryTimer = nil
        agentRuntimeSchedulerTimer?.invalidate()
        agentRuntimeSchedulerTimer = nil
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

    var savedWorkspaceTemplates: [AITerminalSavedWorkspaceTemplate] {
        configuration.savedWorkspaceTemplates.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var learningSettings: AITerminalLearningSettings {
        configuration.learningSettings
    }

    var learningLogs: [AITerminalLearningLogEntry] {
        Array(configuration.learningLogs.reversed())
    }

    var heartbeatQueueSettings: AITerminalHeartbeatQueueSettings {
        configuration.heartbeatQueueSettings
    }

    var todoSettings: AITerminalTodoSettings {
        configuration.todoSettings
    }

    var heartbeatQueueTasks: [AITerminalHeartbeatTask] {
        configuration.heartbeatTasks.sorted {
            if $0.executeAt != $1.executeAt {
                return $0.executeAt > $1.executeAt
            }
            return $0.createdAt > $1.createdAt
        }
    }

    var heartbeatInboxDirectoryPath: String {
        heartbeatInboxDirectoryURL.standardizedFileURL.path
    }

    var agentRuntimeSettings: AgentRuntimeSettings {
        configuration.agentRuntimeSettings
    }

    var agentRuntimeSessions: [AgentRuntimeSession] {
        Self.sortedAgentRuntimeSessions(configuration.agentRuntimeSessions)
    }

    var agentRuntimeTasks: [AgentRuntimeTask] {
        Self.sortedAgentRuntimeTasks(configuration.agentRuntimeTasks)
    }

    var agentRuntimeSchedules: [AgentRuntimeSchedule] {
        Self.sortedAgentRuntimeSchedules(configuration.agentRuntimeSchedules)
    }

    func agentRuntimeSnapshot(now: Date = .now) -> AgentRuntimeSnapshotState {
        var projectedSessions = configuration.agentRuntimeSessions
        var projectedTasks = configuration.agentRuntimeTasks

        for index in projectedSessions.indices {
            guard projectedSessions[index].isLeaseExpired(at: now) else { continue }

            projectedSessions[index].state = .expired
            projectedSessions[index].updatedAt = now
            projectedSessions[index].lastError = "lease_expired"
            if let taskID = projectedSessions[index].currentTaskID {
                projectAgentRuntimeTaskRecoveryAfterLeaseExpiry(
                    taskID: taskID,
                    now: now,
                    tasks: &projectedTasks,
                    settings: configuration.agentRuntimeSettings
                )
                projectedSessions[index].currentTaskID = nil
            }
        }

        return .init(
            settings: configuration.agentRuntimeSettings,
            sessions: Self.sortedAgentRuntimeSessions(projectedSessions),
            tasks: Self.sortedAgentRuntimeTasks(projectedTasks),
            schedules: Self.sortedAgentRuntimeSchedules(configuration.agentRuntimeSchedules)
        )
    }

    private static func sortedAgentRuntimeSessions(
        _ sessions: [AgentRuntimeSession]
    ) -> [AgentRuntimeSession] {
        sessions.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func sortedAgentRuntimeTasks(
        _ tasks: [AgentRuntimeTask]
    ) -> [AgentRuntimeTask] {
        tasks.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if lhs.scheduledAt != rhs.scheduledAt {
                return lhs.scheduledAt < rhs.scheduledAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func sortedAgentRuntimeSchedules(
        _ schedules: [AgentRuntimeSchedule]
    ) -> [AgentRuntimeSchedule] {
        schedules.sorted { lhs, rhs in
            switch (lhs.nextRunAt, rhs.nextRunAt) {
            case let (lhsNext?, rhsNext?) where lhsNext != rhsNext:
                return lhsNext < rhsNext
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    var heartbeatQueuedCount: Int {
        configuration.heartbeatTasks.filter { $0.status == .queued }.count
    }

    var heartbeatRunningCount: Int {
        configuration.heartbeatTasks.filter { $0.status == .running }.count
    }

    var heartbeatDoneCount: Int {
        configuration.heartbeatTasks.filter { $0.status == .done }.count
    }

    var heartbeatFailedCount: Int {
        configuration.heartbeatTasks.filter { $0.status == .failed }.count
    }

    var todoWorkspaceRootPath: String {
        configuration.todoSettings.workspaceRootPath
    }

    func liveTodoWorkspaceTargets() -> [AITerminalTodoWorkspaceTarget] {
        let focusedWindow = NSApp.keyWindow?.tabGroup?.selectedWindow ?? NSApp.keyWindow
        return TerminalController.all.compactMap { controller in
            guard let window = controller.window else { return nil }
            let trimmedTitle = controller.titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = trimmedTitle.isEmpty ? window.title : trimmedTitle
            return .init(
                workspaceID: controller.workspaceID,
                title: title.isEmpty ? "Tab" : title,
                subtitle: window.title,
                isFocused: window === focusedWindow
            )
        }
        .sorted { lhs, rhs in
            if lhs.isFocused != rhs.isFocused {
                return lhs.isFocused && !rhs.isFocused
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func todoWorkspaceSummary(
        for workspaceID: UUID,
        on date: Date = .now
    ) -> AITerminalTodoWorkspaceProgressSummary {
        todoWorkspaceSnapshot(for: workspaceID, on: date).summary
    }

    func todoItems(
        assignedTo workspaceID: UUID,
        on date: Date = .now,
        includeCompleted: Bool = true
    ) -> [AITerminalTodoItem] {
        todoWorkspaceSnapshot(
            for: workspaceID,
            on: date,
            includeCompleted: includeCompleted
        ).items
    }

    func todoWorkspaceSnapshot(
        for workspaceID: UUID,
        on date: Date = .now,
        includeCompleted: Bool = true
    ) -> AITerminalTodoWorkspaceSnapshot {
        let items = todoDocumentSnapshot(for: date)
            .orderedItems
            .filter { $0.assignedWorkspaceID == workspaceID }
        let filteredItems = includeCompleted
            ? items
            : items.filter { !$0.isCompleted }
        return .init(workspaceID: workspaceID, items: filteredItems)
    }

    func saveTodoSettings(_ settings: AITerminalTodoSettings) {
        configuration.todoSettings = .init(
            enabled: settings.enabled,
            workspaceRootPath: settings.workspaceRootPath,
            showCompletedItems: settings.showCompletedItems,
            selectedDateAnchor: settings.selectedDateAnchor,
            sidebarEdge: settings.sidebarEdge,
            workspaceOverlayVisible: settings.workspaceOverlayVisible,
            workspaceOverlayCorner: settings.workspaceOverlayCorner
        )
        lastError = nil
        persistConfiguration()
        bumpTodoRevision()
    }

    @discardableResult
    func initializeTodoWorkspace(rootPath: String? = nil) -> TodoWorkspaceBootstrapResult? {
        let candidatePath = rootPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? configuration.todoSettings.workspaceRootPath
        guard !candidatePath.isEmpty else {
            lastError = L10n.AITerminalManager.workspaceDirectoryEmpty
            return nil
        }

        do {
            let result = try Self.createTodoWorkspaceScaffold(rootPath: candidatePath)
            var settings = configuration.todoSettings
            settings.workspaceRootPath = result.workspaceRootPath
            configuration.todoSettings = settings
            persistConfiguration()
            bumpTodoRevision()
            lastError = nil
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func todoDocument(for date: Date) -> AITerminalTodoDayDocument {
        do {
            let dayString = AITerminalTodoSettings.dayString(from: date)
            let document = try rawTodoDocument(forDayString: dayString)
            let refreshed = refreshedTodoDocument(document)
            cacheTodoDocument(refreshed)
            lastError = nil
            return refreshed
        } catch {
            lastError = error.localizedDescription
            let fallback = AITerminalTodoDayDocument(date: AITerminalTodoSettings.dayString(from: date))
            cacheTodoDocument(fallback)
            return fallback
        }
    }

    @discardableResult
    func addTodoItem(
        title: String,
        notes: String,
        for date: Date
    ) -> AITerminalTodoDayDocument? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastError = "Todo title cannot be empty."
            return nil
        }

        return mutateTodoDocument(for: date) { document in
            let nextSortOrder = (document.items.map(\.sortOrder).max() ?? -1) + 1
            document.items.append(.init(
                title: trimmedTitle,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: nextSortOrder
            ))
        }.map { _ in
            self.todoDocument(for: date)
        }
    }

    @discardableResult
    func updateTodoItem(
        id: UUID,
        title: String,
        notes: String,
        for date: Date
    ) -> AITerminalTodoDayDocument? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastError = "Todo title cannot be empty."
            return nil
        }

        let dayString = AITerminalTodoSettings.dayString(from: date)
        guard let target = resolvedTodoMutationTarget(for: id, on: dayString),
              let targetDate = AITerminalTodoSettings.date(fromDayString: target.day) else {
            lastError = "Todo item not found."
            return nil
        }

        guard mutateTodoDocument(for: targetDate, mutation: { document in
            guard let index = document.items.firstIndex(where: { $0.id == target.itemID }) else { return }
            document.items[index].title = trimmedTitle
            document.items[index].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            document.items[index].updatedAt = .now
        }) != nil else {
            return nil
        }

        return todoDocument(for: date)
    }

    @discardableResult
    func setTodoItemCompleted(
        id: UUID,
        isCompleted: Bool,
        for date: Date
    ) -> AITerminalTodoDayDocument? {
        let dayString = AITerminalTodoSettings.dayString(from: date)
        guard let target = resolvedTodoMutationTarget(for: id, on: dayString),
              let targetDate = AITerminalTodoSettings.date(fromDayString: target.day) else {
            lastError = "Todo item not found."
            return nil
        }

        guard mutateTodoDocument(for: targetDate, mutation: { document in
            guard let index = document.items.firstIndex(where: { $0.id == target.itemID }) else { return }
            document.items[index].isCompleted = isCompleted
            document.items[index].completedAt = isCompleted ? .now : nil
            document.items[index].updatedAt = .now
        }) != nil else {
            return nil
        }

        return todoDocument(for: date)
    }

    @discardableResult
    func assignTodoItem(
        id: UUID,
        to workspaceID: UUID?,
        for date: Date
    ) -> AITerminalTodoDayDocument? {
        let dayString = AITerminalTodoSettings.dayString(from: date)
        guard let target = resolvedTodoMutationTarget(for: id, on: dayString),
              let targetDate = AITerminalTodoSettings.date(fromDayString: target.day) else {
            lastError = "Todo item not found."
            return nil
        }

        guard mutateTodoDocument(for: targetDate, mutation: { document in
            guard let index = document.items.firstIndex(where: { $0.id == target.itemID }) else { return }
            document.items[index].assignedWorkspaceID = workspaceID
            document.items[index].updatedAt = .now
        }) != nil else {
            return nil
        }

        return todoDocument(for: date)
    }

    @discardableResult
    func syncIncompleteTodoPointers(into date: Date = .now) -> Int? {
        let dayString = AITerminalTodoSettings.dayString(from: date)

        do {
            let candidates = try staleTodoSyncCandidates(into: dayString)
            guard !candidates.isEmpty else {
                lastError = nil
                return 0
            }

            guard mutateTodoDocument(for: date, mutation: { document in
                var nextSortOrder = (document.items.map(\.sortOrder).max() ?? -1) + 1
                for candidate in candidates {
                    document.items.append(.init(
                        sourceItem: candidate.reference,
                        title: candidate.item.title,
                        notes: candidate.item.notes,
                        assignedWorkspaceID: candidate.item.assignedWorkspaceID,
                        isCompleted: candidate.item.isCompleted,
                        completedAt: candidate.item.completedAt,
                        createdAt: candidate.item.createdAt,
                        updatedAt: candidate.item.updatedAt,
                        sortOrder: nextSortOrder
                    ))
                    nextSortOrder += 1
                }
            }) != nil else {
                return nil
            }

            return candidates.count
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func syncableStaleTodoPointerCount(into date: Date = .now) -> Int {
        do {
            return try staleTodoSyncCandidates(into: AITerminalTodoSettings.dayString(from: date)).count
        } catch {
            lastError = error.localizedDescription
            return 0
        }
    }

    func saveHeartbeatQueueSettings(_ settings: AITerminalHeartbeatQueueSettings) {
        let interval = min(
            max(settings.heartbeatIntervalSeconds, Self.minHeartbeatIntervalSeconds),
            Self.maxHeartbeatIntervalSeconds
        )
        let maxConcurrentTasks = min(
            max(settings.maxConcurrentTasks, Self.minHeartbeatMaxConcurrentTasks),
            Self.maxHeartbeatMaxConcurrentTasks
        )
        configuration.heartbeatQueueSettings = .init(
            enabled: settings.enabled,
            heartbeatIntervalSeconds: interval,
            maxConcurrentTasks: maxConcurrentTasks,
            allowExternalInboxMutations: settings.allowExternalInboxMutations
        )
        pruneHeartbeatTasks()
        persistConfiguration()
        syncHeartbeatRuntime()
    }

    @discardableResult
    func enqueueHeartbeatTask(
        command: String,
        type: AITerminalHeartbeatTaskType = .exec,
        executeAt: Date? = nil
    ) -> UUID? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Task queue command is required."
            return nil
        }

        let task = AITerminalHeartbeatTask(
            command: command,
            type: type,
            executeAt: executeAt ?? .now
        )
        configuration.heartbeatTasks.append(task)
        pruneHeartbeatTasks()
        persistConfiguration()
        lastError = nil
        syncHeartbeatRuntime()
        return task.id
    }

    func cancelHeartbeatTask(_ id: UUID) {
        guard let idx = configuration.heartbeatTasks.firstIndex(where: { $0.id == id }) else { return }
        guard configuration.heartbeatTasks[idx].status == .queued else { return }
        configuration.heartbeatTasks[idx].status = .cancelled
        configuration.heartbeatTasks[idx].updatedAt = .now
        pruneHeartbeatTasks()
        persistConfiguration()
        syncHeartbeatRuntime()
    }

    func cancelAllQueuedHeartbeatTasks() {
        var changed = false
        for index in configuration.heartbeatTasks.indices where configuration.heartbeatTasks[index].status == .queued {
            configuration.heartbeatTasks[index].status = .cancelled
            configuration.heartbeatTasks[index].updatedAt = .now
            changed = true
        }
        guard changed else { return }
        pruneHeartbeatTasks()
        persistConfiguration()
        syncHeartbeatRuntime()
    }

    func clearFinishedHeartbeatTasks() {
        configuration.heartbeatTasks.removeAll { task in
            switch task.status {
            case .done, .failed, .cancelled:
                return true
            case .queued, .running:
                return false
            }
        }
        pruneHeartbeatTasks()
        persistConfiguration()
        syncHeartbeatRuntime()
    }

    func saveAgentRuntimeSettings(_ settings: AgentRuntimeSettings) {
        configuration.agentRuntimeSettings = settings.sanitized()
        persistConfiguration()
        syncAgentRuntimeRecovery()
        syncAgentRuntimeSchedules()
    }

    @discardableResult
    func enqueueAgentRuntimeSchedule(
        taskKind: AgentRuntimeTaskKind,
        priority: Int = 0,
        capabilityRequirements: [String] = [],
        payload: AgentRuntimeTaskPayload = .init(),
        startAt: Date? = nil,
        recurrence: AgentRuntimeScheduleRecurrence = .init(),
        maxRetryCount: Int = 0,
        now: Date = .now
    ) throws -> AgentRuntimeSchedule {
        try ensureAgentRuntimeEnabled()
        let schedule = AgentRuntimeSchedule(
            taskKind: taskKind,
            priority: priority,
            capabilityRequirements: taskKind.defaultCapabilityRequirements + capabilityRequirements,
            payload: payload,
            startAt: startAt ?? now,
            recurrence: recurrence,
            createdAt: now,
            updatedAt: now,
            maxRetryCount: maxRetryCount
        )
        configuration.agentRuntimeSchedules.append(schedule)
        persistConfiguration()
        syncAgentRuntimeSchedules(now: now)
        let persistedSchedule = configuration.agentRuntimeSchedules.first(where: { $0.id == schedule.id }) ?? schedule
        appendAgentRuntimeEvent(
            "schedule_enqueued",
            details: [
                "schedule_id": schedule.id.uuidString.lowercased(),
                "task_kind": taskKind.rawValue,
                "recurrence_mode": schedule.recurrence.mode.rawValue,
            ]
        )
        return persistedSchedule
    }

    @discardableResult
    func updateAgentRuntimeSchedule(
        scheduleID: UUID,
        state: AgentRuntimeScheduleState? = nil,
        startAt: Date? = nil,
        recurrence: AgentRuntimeScheduleRecurrence? = nil,
        now: Date = .now
    ) throws -> AgentRuntimeSchedule {
        try ensureAgentRuntimeEnabled()
        guard let index = configuration.agentRuntimeSchedules.firstIndex(where: { $0.id == scheduleID }) else {
            throw AgentRuntimeStoreError.scheduleNotFound(scheduleID)
        }

        if let state {
            let currentState = configuration.agentRuntimeSchedules[index].state
            guard currentState.canTransition(to: state) else {
                throw AgentRuntimeStoreError.invalidScheduleTransition(from: currentState, to: state)
            }
            configuration.agentRuntimeSchedules[index].state = state
            if state == .cancelled {
                configuration.agentRuntimeSchedules[index].nextRunAt = nil
            } else if state == .active, configuration.agentRuntimeSchedules[index].nextRunAt == nil {
                configuration.agentRuntimeSchedules[index].nextRunAt = startAt ?? configuration.agentRuntimeSchedules[index].startAt
            }
        }

        if let startAt {
            configuration.agentRuntimeSchedules[index].startAt = startAt
            if configuration.agentRuntimeSchedules[index].state.isRunnable {
                configuration.agentRuntimeSchedules[index].nextRunAt = startAt
            }
        }

        if let recurrence {
            configuration.agentRuntimeSchedules[index].recurrence = recurrence.sanitized()
        }

        configuration.agentRuntimeSchedules[index].updatedAt = now
        persistConfiguration()
        syncAgentRuntimeSchedules(now: now)
        let schedule = configuration.agentRuntimeSchedules.first(where: { $0.id == scheduleID })
            ?? configuration.agentRuntimeSchedules[index]
        appendAgentRuntimeEvent(
            "schedule_updated",
            details: [
                "schedule_id": schedule.id.uuidString.lowercased(),
                "state": schedule.state.rawValue,
            ]
        )
        return schedule
    }

    @discardableResult
    func cancelAgentRuntimeSchedule(
        scheduleID: UUID,
        now: Date = .now
    ) throws -> AgentRuntimeSchedule {
        try updateAgentRuntimeSchedule(
            scheduleID: scheduleID,
            state: .cancelled,
            now: now
        )
    }

    @discardableResult
    func enqueueAgentRuntimeTask(
        kind: AgentRuntimeTaskKind,
        priority: Int = 0,
        capabilityRequirements: [String] = [],
        payload: AgentRuntimeTaskPayload = .init(),
        scheduledAt: Date? = nil,
        maxRetryCount: Int = 0,
        now: Date = .now
    ) throws -> AgentRuntimeTask {
        try ensureAgentRuntimeEnabled()
        let task = AgentRuntimeTask(
            kind: kind,
            priority: priority,
            capabilityRequirements: kind.defaultCapabilityRequirements + capabilityRequirements,
            payload: payload,
            createdAt: now,
            scheduledAt: scheduledAt ?? now,
            maxRetryCount: maxRetryCount
        )
        configuration.agentRuntimeTasks.append(task)
        persistConfiguration()
        appendAgentRuntimeEvent(
            "task_enqueued",
            taskID: task.id,
            details: [
                "kind": kind.rawValue,
                "priority": "\(priority)",
            ]
        )
        return task
    }

    @discardableResult
    func registerAgentRuntimeSession(
        clientKind: AgentRuntimeClientKind,
        tabID: UUID? = nil,
        terminalID: UUID? = nil,
        hostWorkspaceID: UUID? = nil,
        capabilities: [String] = [],
        existingSessionID: UUID? = nil,
        leaseDurationSeconds: Double? = nil,
        now: Date = .now
    ) throws -> AgentRuntimeSession {
        try ensureAgentRuntimeEnabled()
        _ = expireStaleAgentRuntimeSessions(now: now)

        let settings = configuration.agentRuntimeSettings.sanitized()
        if let existingSessionID,
           let index = configuration.agentRuntimeSessions.firstIndex(where: { $0.id == existingSessionID }) {
            configuration.agentRuntimeSessions[index].clientKind = clientKind
            configuration.agentRuntimeSessions[index].tabID = tabID
            configuration.agentRuntimeSessions[index].terminalID = terminalID
            configuration.agentRuntimeSessions[index].hostWorkspaceID = hostWorkspaceID
            configuration.agentRuntimeSessions[index].capabilities = AgentRuntimeSession.normalizeCapabilities(capabilities)
            configuration.agentRuntimeSessions[index].renewLease(
                at: now,
                defaults: settings,
                requestedLeaseDurationSeconds: leaseDurationSeconds
            )
            let session = configuration.agentRuntimeSessions[index]
            persistConfiguration()
            appendAgentRuntimeEvent("session_registered", sessionID: session.id, details: [
                "mode": "reattach",
                "client_kind": clientKind.rawValue,
            ])
            return session
        }

        expireOverlappingAgentRuntimeSessions(
            clientKind: clientKind,
            tabID: tabID,
            terminalID: terminalID,
            hostWorkspaceID: hostWorkspaceID,
            now: now
        )

        var session = AgentRuntimeSession(
            clientKind: clientKind,
            tabID: tabID,
            terminalID: terminalID,
            hostWorkspaceID: hostWorkspaceID,
            capabilities: capabilities,
            createdAt: now,
            updatedAt: now,
            leaseDurationSeconds: leaseDurationSeconds ?? settings.defaultLeaseDurationSeconds
        )
        session.renewLease(
            at: now,
            defaults: settings,
            requestedLeaseDurationSeconds: leaseDurationSeconds
        )
        configuration.agentRuntimeSessions.append(session)
        persistConfiguration()
        appendAgentRuntimeEvent("session_registered", sessionID: session.id, details: [
            "mode": "new",
            "client_kind": clientKind.rawValue,
        ])
        return session
    }

    @discardableResult
    func heartbeatAgentRuntimeSession(
        _ sessionID: UUID,
        leaseDurationSeconds: Double? = nil,
        now: Date = .now
    ) throws -> AgentRuntimeSession {
        try ensureAgentRuntimeEnabled()
        _ = expireStaleAgentRuntimeSessions(now: now)
        let index = try activeAgentRuntimeSessionIndex(sessionID: sessionID, now: now)
        configuration.agentRuntimeSessions[index].renewLease(
            at: now,
            defaults: configuration.agentRuntimeSettings,
            requestedLeaseDurationSeconds: leaseDurationSeconds
        )
        let session = configuration.agentRuntimeSessions[index]
        persistConfiguration()
        appendAgentRuntimeEvent("session_heartbeat", sessionID: session.id)
        return session
    }

    @discardableResult
    func releaseAgentRuntimeSession(
        _ sessionID: UUID,
        reason: String? = nil,
        now: Date = .now
    ) throws -> AgentRuntimeSession {
        try ensureAgentRuntimeEnabled()
        let index = try agentRuntimeSessionIndex(sessionID: sessionID)
        if let taskID = configuration.agentRuntimeSessions[index].currentTaskID {
            recoverAgentRuntimeTaskAfterLeaseExpiry(taskID: taskID, now: now)
        }
        configuration.agentRuntimeSessions[index].state = .released
        configuration.agentRuntimeSessions[index].updatedAt = now
        configuration.agentRuntimeSessions[index].leaseExpiresAt = now
        configuration.agentRuntimeSessions[index].lastError = reason
        configuration.agentRuntimeSessions[index].currentTaskID = nil
        let session = configuration.agentRuntimeSessions[index]
        persistConfiguration()
        appendAgentRuntimeEvent("session_released", sessionID: session.id, details: [
            "reason": reason ?? "",
        ])
        return session
    }

    @discardableResult
    func expireStaleAgentRuntimeSessions(now: Date = .now) -> [UUID] {
        var expiredIDs: [UUID] = []

        for index in configuration.agentRuntimeSessions.indices {
            guard configuration.agentRuntimeSessions[index].isLeaseExpired(at: now) else { continue }
            configuration.agentRuntimeSessions[index].state = .expired
            configuration.agentRuntimeSessions[index].updatedAt = now
            configuration.agentRuntimeSessions[index].lastError = "lease_expired"
            if let taskID = configuration.agentRuntimeSessions[index].currentTaskID {
                recoverAgentRuntimeTaskAfterLeaseExpiry(taskID: taskID, now: now)
                configuration.agentRuntimeSessions[index].currentTaskID = nil
            }
            expiredIDs.append(configuration.agentRuntimeSessions[index].id)
            appendAgentRuntimeEvent(
                "session_expired",
                sessionID: configuration.agentRuntimeSessions[index].id
            )
        }

        if !expiredIDs.isEmpty {
            persistConfiguration()
        }
        return expiredIDs
    }

    @discardableResult
    func claimNextAgentRuntimeTask(
        sessionID: UUID,
        allowedKinds: Set<AgentRuntimeTaskKind>? = nil,
        now: Date = .now
    ) throws -> AgentRuntimeTask? {
        try ensureAgentRuntimeEnabled()
        _ = expireStaleAgentRuntimeSessions(now: now)
        let sessionIndex = try activeAgentRuntimeSessionIndex(sessionID: sessionID, now: now)
        if let currentTaskID = configuration.agentRuntimeSessions[sessionIndex].currentTaskID,
           let currentTask = configuration.agentRuntimeTasks.first(where: { $0.id == currentTaskID }),
           !currentTask.state.isFinished {
            throw AgentRuntimeStoreError.sessionAlreadyHasActiveTask(sessionID)
        }

        let capabilities = Set(configuration.agentRuntimeSessions[sessionIndex].capabilities)
        guard let taskIndex = configuration.agentRuntimeTasks.indices
            .filter({
                let task = configuration.agentRuntimeTasks[$0]
                guard task.isClaimable(by: capabilities, now: now) else {
                    return false
                }
                guard let allowedKinds else {
                    return true
                }
                return allowedKinds.contains(task.kind)
            })
            .sorted(by: { lhs, rhs in
                let lhsTask = configuration.agentRuntimeTasks[lhs]
                let rhsTask = configuration.agentRuntimeTasks[rhs]
                if lhsTask.priority != rhsTask.priority {
                    return lhsTask.priority > rhsTask.priority
                }
                if lhsTask.scheduledAt != rhsTask.scheduledAt {
                    return lhsTask.scheduledAt < rhsTask.scheduledAt
                }
                if lhsTask.createdAt != rhsTask.createdAt {
                    return lhsTask.createdAt < rhsTask.createdAt
                }
                return lhsTask.id.uuidString < rhsTask.id.uuidString
            })
            .first else {
            return nil
        }

        configuration.agentRuntimeTasks[taskIndex].state = .claimed
        configuration.agentRuntimeTasks[taskIndex].sessionID = sessionID
        configuration.agentRuntimeTasks[taskIndex].claimedAt = now
        configuration.agentRuntimeTasks[taskIndex].finishedAt = nil
        configuration.agentRuntimeTasks[taskIndex].errorSummary = nil
        configuration.agentRuntimeSessions[sessionIndex].currentTaskID = configuration.agentRuntimeTasks[taskIndex].id
        configuration.agentRuntimeSessions[sessionIndex].updatedAt = now
        let task = configuration.agentRuntimeTasks[taskIndex]
        persistConfiguration()
        appendAgentRuntimeEvent("task_claimed", sessionID: sessionID, taskID: task.id)
        return task
    }

    @discardableResult
    func updateAgentRuntimeTask(
        sessionID: UUID,
        taskID: UUID,
        state: AgentRuntimeTaskState,
        errorSummary: String? = nil,
        now: Date = .now
    ) throws -> AgentRuntimeTask {
        try ensureAgentRuntimeEnabled()
        let sessionIndex = try activeAgentRuntimeSessionIndex(sessionID: sessionID, now: now)
        guard let taskIndex = configuration.agentRuntimeTasks.firstIndex(where: { $0.id == taskID }) else {
            throw AgentRuntimeStoreError.taskNotFound(taskID)
        }
        guard configuration.agentRuntimeTasks[taskIndex].sessionID == sessionID else {
            throw AgentRuntimeStoreError.taskOwnershipMismatch(taskID: taskID, sessionID: sessionID)
        }
        guard configuration.agentRuntimeTasks[taskIndex].state.canTransition(to: state) else {
            throw AgentRuntimeStoreError.invalidTaskTransition(
                from: configuration.agentRuntimeTasks[taskIndex].state,
                to: state
            )
        }

        configuration.agentRuntimeTasks[taskIndex].state = state
        configuration.agentRuntimeTasks[taskIndex].errorSummary = errorSummary
        if state == .running && configuration.agentRuntimeTasks[taskIndex].claimedAt == nil {
            configuration.agentRuntimeTasks[taskIndex].claimedAt = now
        }
        if state == .queued {
            configuration.agentRuntimeTasks[taskIndex].sessionID = nil
            configuration.agentRuntimeTasks[taskIndex].claimedAt = nil
            configuration.agentRuntimeTasks[taskIndex].finishedAt = nil
            configuration.agentRuntimeSessions[sessionIndex].currentTaskID = nil
            if configuration.agentRuntimeSessions[sessionIndex].state.isLeaseManaged {
                configuration.agentRuntimeSessions[sessionIndex].state = .active
            }
        } else if state.isFinished {
            configuration.agentRuntimeTasks[taskIndex].finishedAt = now
            configuration.agentRuntimeSessions[sessionIndex].currentTaskID = nil
            if configuration.agentRuntimeSessions[sessionIndex].state.isLeaseManaged {
                configuration.agentRuntimeSessions[sessionIndex].state = .active
            }
        } else {
            configuration.agentRuntimeTasks[taskIndex].finishedAt = nil
            configuration.agentRuntimeSessions[sessionIndex].currentTaskID = taskID
            switch state {
            case .waitingApproval:
                configuration.agentRuntimeSessions[sessionIndex].state = .waitingApproval
            case .paused:
                configuration.agentRuntimeSessions[sessionIndex].state = .paused
            case .queued, .claimed, .running:
                configuration.agentRuntimeSessions[sessionIndex].state = .active
            case .completed, .failed, .cancelled:
                break
            }
        }
        if state != .queued {
            configuration.agentRuntimeTasks[taskIndex].sessionID = sessionID
        }
        configuration.agentRuntimeSessions[sessionIndex].updatedAt = now
        let task = configuration.agentRuntimeTasks[taskIndex]
        persistConfiguration()
        if state.isFinished || state == .queued {
            syncAgentRuntimeSchedules(now: now)
        }
        appendAgentRuntimeEvent(
            "task_updated",
            sessionID: sessionID,
            taskID: taskID,
            details: [
                "state": state.rawValue,
            ]
        )
        return task
    }

    @discardableResult
    func approveAgentRuntimeTask(
        sessionID: UUID,
        taskID: UUID,
        now: Date = .now
    ) throws -> AgentRuntimeTask {
        try ensureAgentRuntimeEnabled()
        let sessionIndex = try activeAgentRuntimeSessionIndex(sessionID: sessionID, now: now)
        guard let taskIndex = configuration.agentRuntimeTasks.firstIndex(where: { $0.id == taskID }) else {
            throw AgentRuntimeStoreError.taskNotFound(taskID)
        }
        guard configuration.agentRuntimeTasks[taskIndex].sessionID == sessionID else {
            throw AgentRuntimeStoreError.taskOwnershipMismatch(taskID: taskID, sessionID: sessionID)
        }
        guard configuration.agentRuntimeTasks[taskIndex].state == .waitingApproval else {
            throw AgentRuntimeStoreError.invalidTaskTransition(
                from: configuration.agentRuntimeTasks[taskIndex].state,
                to: .running
            )
        }

        configuration.agentRuntimeTasks[taskIndex].state = .running
        configuration.agentRuntimeTasks[taskIndex].finishedAt = nil
        configuration.agentRuntimeTasks[taskIndex].errorSummary = nil
        if configuration.agentRuntimeTasks[taskIndex].claimedAt == nil {
            configuration.agentRuntimeTasks[taskIndex].claimedAt = now
        }
        configuration.agentRuntimeSessions[sessionIndex].currentTaskID = taskID
        configuration.agentRuntimeSessions[sessionIndex].state = .active
        configuration.agentRuntimeSessions[sessionIndex].updatedAt = now
        let task = configuration.agentRuntimeTasks[taskIndex]
        persistConfiguration()
        appendAgentRuntimeEvent(
            "task_approved",
            sessionID: sessionID,
            taskID: taskID
        )
        return task
    }

    @discardableResult
    func cancelAgentRuntimeTask(
        taskID: UUID,
        sessionID: UUID? = nil,
        reason: String? = nil,
        force: Bool = false,
        now: Date = .now
    ) throws -> AgentRuntimeTask {
        try ensureAgentRuntimeEnabled()
        guard let taskIndex = configuration.agentRuntimeTasks.firstIndex(where: { $0.id == taskID }) else {
            throw AgentRuntimeStoreError.taskNotFound(taskID)
        }

        let ownerSessionID = configuration.agentRuntimeTasks[taskIndex].sessionID
        if let ownerSessionID {
            if force {
                if let sessionIndex = configuration.agentRuntimeSessions.firstIndex(where: { $0.id == ownerSessionID }) {
                    configuration.agentRuntimeSessions[sessionIndex].currentTaskID = nil
                    configuration.agentRuntimeSessions[sessionIndex].updatedAt = now
                    if configuration.agentRuntimeSessions[sessionIndex].state.isLeaseManaged {
                        configuration.agentRuntimeSessions[sessionIndex].state = .active
                    }
                }
            } else {
                guard let sessionID else {
                    throw AgentRuntimeStoreError.taskOwnershipMismatch(taskID: taskID, sessionID: ownerSessionID)
                }
                let sessionIndex = try activeAgentRuntimeSessionIndex(sessionID: sessionID, now: now)
                guard ownerSessionID == sessionID else {
                    throw AgentRuntimeStoreError.taskOwnershipMismatch(taskID: taskID, sessionID: sessionID)
                }
                configuration.agentRuntimeSessions[sessionIndex].currentTaskID = nil
                configuration.agentRuntimeSessions[sessionIndex].updatedAt = now
                if configuration.agentRuntimeSessions[sessionIndex].state.isLeaseManaged {
                    configuration.agentRuntimeSessions[sessionIndex].state = .active
                }
            }
        } else if !force, let sessionID {
            _ = try activeAgentRuntimeSessionIndex(sessionID: sessionID, now: now)
        }

        let currentState = configuration.agentRuntimeTasks[taskIndex].state
        guard currentState.canTransition(to: .cancelled) else {
            throw AgentRuntimeStoreError.invalidTaskTransition(from: currentState, to: .cancelled)
        }

        configuration.agentRuntimeTasks[taskIndex].state = .cancelled
        configuration.agentRuntimeTasks[taskIndex].finishedAt = now
        configuration.agentRuntimeTasks[taskIndex].errorSummary = reason
        let task = configuration.agentRuntimeTasks[taskIndex]
        persistConfiguration()
        syncAgentRuntimeSchedules(now: now)
        appendAgentRuntimeEvent(
            "task_cancelled",
            sessionID: sessionID ?? ownerSessionID,
            taskID: taskID,
            details: [
                "reason": reason ?? "",
                "force": force ? "true" : "false",
            ]
        )
        return task
    }

    private func pruneHeartbeatTasks(now: Date = .now) {
        let beforeCount = configuration.heartbeatTasks.count
        configuration.heartbeatTasks = Self.prunedHeartbeatTasks(configuration.heartbeatTasks, now: now)
        let removedCount = beforeCount - configuration.heartbeatTasks.count
        if removedCount > 0 {
            RuntimeDiagnosticsLogger.log(
                component: "ai_manager.heartbeat_tasks",
                event: "prune",
                details: [
                    "removed": "\(removedCount)",
                    "remaining": "\(configuration.heartbeatTasks.count)",
                ]
            )
        }
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
        applyConfiguration((try? Self.loadConfiguration(at: configurationURL)) ?? .empty)
        importedSSHHosts = sshConfigHostLoader()
        reconcileImportedState()
        rebuildSessions()
        syncHeartbeatRuntime()
        syncAgentRuntimeRecovery()
        syncAgentRuntimeSchedules()
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

    func openInPaneTab(host: AITerminalHost, controller: TerminalController, sourceSurface: Ghostty.SurfaceView) {
        if host.isLocal {
            _ = launch(.localShell(), inPaneOf: controller, sourceSurface: sourceSurface)
            return
        }

        open(host: host, directoryOverride: nil, inPaneOf: controller, sourceSurface: sourceSurface)
    }

    func openInSplit(
        host: AITerminalHost,
        controller: TerminalController,
        sourceSurface: Ghostty.SurfaceView,
        direction: SplitTree<TerminalPane>.NewDirection
    ) {
        if host.isLocal {
            _ = launch(.localShell(), inSplitOf: controller, sourceSurface: sourceSurface, direction: direction)
            return
        }

        open(
            host: host,
            directoryOverride: nil,
            inSplitOf: controller,
            sourceSurface: sourceSurface,
            direction: direction
        )
    }

    func newTabPickerEntries(mode: NewTabPickerMode = .topLevel) -> [NewTabPickerEntry] {
        NewTabPickerModel.entries(
            favoriteHosts: favoriteHosts,
            recentHosts: recentHosts,
            savedHosts: savedHosts,
            importedHosts: mergedImportedHosts,
            savedWorkspaceTemplates: savedWorkspaceTemplates,
            mode: mode
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

    private func open(
        host: AITerminalHost,
        directoryOverride: String?,
        inPaneOf controller: TerminalController,
        sourceSurface: Ghostty.SurfaceView
    ) {
        switch host.transport {
        case .local:
            _ = launch(.localShell(), inPaneOf: controller, sourceSurface: sourceSurface)
            return

        case .localmcd:
            guard let plan = AITerminalLaunchPlan.localCommand(host: host, directoryOverride: directoryOverride) else {
                lastError = L10n.AITerminalManager.localMCDCommandsEmpty
                recordRecentHost(host.id, status: .failed, errorSummary: lastError)
                return
            }
            _ = launch(plan, inPaneOf: controller, sourceSurface: sourceSurface)
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

            guard let sessionID = launch(plan, inPaneOf: controller, sourceSurface: sourceSurface) else { return }
            registerRemoteSession(sessionID, host: host, savedPassword: savedPassword)
            recordRecentHost(host.id, status: .connected)
        }
    }

    private func open(
        host: AITerminalHost,
        directoryOverride: String?,
        inSplitOf controller: TerminalController,
        sourceSurface: Ghostty.SurfaceView,
        direction: SplitTree<TerminalPane>.NewDirection
    ) {
        switch host.transport {
        case .local:
            _ = launch(.localShell(), inSplitOf: controller, sourceSurface: sourceSurface, direction: direction)
            return

        case .localmcd:
            guard let plan = AITerminalLaunchPlan.localCommand(host: host, directoryOverride: directoryOverride) else {
                lastError = L10n.AITerminalManager.localMCDCommandsEmpty
                recordRecentHost(host.id, status: .failed, errorSummary: lastError)
                return
            }
            _ = launch(plan, inSplitOf: controller, sourceSurface: sourceSurface, direction: direction)
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

            guard let sessionID = launch(
                plan,
                inSplitOf: controller,
                sourceSurface: sourceSurface,
                direction: direction
            ) else { return }
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

    func open(savedWorkspaceTemplate template: AITerminalSavedWorkspaceTemplate) {
        guard let appDelegate = appDelegateProvider() else {
            lastError = L10n.AITerminalManager.appDelegateUnavailable
            return
        }

        guard let build = buildSavedWorkspaceRuntime(template: template) else { return }

        let controller: TerminalController
        switch launchTarget {
        case .tab:
            controller = TerminalController.newTab(
                appDelegate.ghostty,
                from: TerminalController.preferredParent?.window,
                tree: build.tree
            ) ?? TerminalController.newWindow(appDelegate.ghostty, tree: build.tree)
        case .window:
            controller = TerminalController.newWindow(appDelegate.ghostty, tree: build.tree)
        }

        controller.titleOverride = template.name

        for registration in build.registrations {
            registrations[registration.surfaceID] = registration.registration
            if let remote = registration.pendingRemoteSession {
                registerRemoteSession(
                    registration.surfaceID,
                    host: remote.host,
                    savedPassword: remote.savedPassword,
                    shouldRebuild: false
                )
                recordRecentHost(remote.host.id, status: .connected)
            }
        }

        lastError = nil
        rebuildSessions()
    }

    func saveCurrentWorkspace(from controller: TerminalController, name: String) {
        saveCurrentWorkspace(from: controller, name: name, replacingID: nil)
    }

    func saveCurrentWorkspace(
        from controller: TerminalController,
        name: String,
        replacingID: String?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastError = L10n.AITerminalManager.workspaceNameEmpty
            return
        }

        guard let root = savedWorkspaceNode(from: controller.surfaceTree.root) else {
            lastError = L10n.AITerminalManager.workspaceEmpty
            return
        }

        _ = saveWorkspaceTemplate(
            name: trimmedName,
            root: root,
            replacingID: replacingID
        )
    }

    func existingSavedWorkspaceTemplate(
        named name: String,
        excludingID: String? = nil
    ) -> AITerminalSavedWorkspaceTemplate? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        return configuration.savedWorkspaceTemplates.first {
            $0.id != excludingID &&
            $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    @discardableResult
    func saveWorkspaceTemplate(
        name: String,
        root: AITerminalSavedWorkspaceNode,
        replacingID: String? = nil
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastError = L10n.AITerminalManager.workspaceNameEmpty
            return false
        }

        if existingSavedWorkspaceTemplate(named: trimmedName, excludingID: replacingID) != nil {
            lastError = L10n.AITerminalManager.workspaceDuplicateName
            return false
        }

        let existingTemplate = replacingID.flatMap { id in
            configuration.savedWorkspaceTemplates.first { $0.id == id }
        }

        configuration.savedWorkspaceTemplates.removeAll {
            $0.id == replacingID
        }
        configuration.savedWorkspaceTemplates.append(.init(
            id: existingTemplate?.id ?? "saved-workspace:\(UUID().uuidString)",
            name: trimmedName,
            root: root,
            createdAt: existingTemplate?.createdAt ?? .now,
            updatedAt: .now
        ))
        configuration.savedWorkspaceTemplates.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
        return true
    }

    func removeSavedWorkspaceTemplate(_ template: AITerminalSavedWorkspaceTemplate) {
        configuration.savedWorkspaceTemplates.removeAll { $0.id == template.id }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    private struct PendingRemoteWorkspaceSession {
        var host: AITerminalHost
        var savedPassword: String?
    }

    private struct SavedWorkspaceSurfaceRegistration {
        var surfaceID: UUID
        var registration: AITerminalLaunchRegistration
        var pendingRemoteSession: PendingRemoteWorkspaceSession?
    }

    private struct SavedWorkspaceRuntimeBuild {
        var tree: SplitTree<TerminalPane>
        var registrations: [SavedWorkspaceSurfaceRegistration]
    }

    private func buildSavedWorkspaceRuntime(
        template: AITerminalSavedWorkspaceTemplate
    ) -> SavedWorkspaceRuntimeBuild? {
        guard let ghosttyApp = appDelegateProvider()?.ghostty.app else {
            lastError = L10n.AITerminalManager.appDelegateUnavailable
            return nil
        }

        let hostLookup = Dictionary(uniqueKeysWithValues: availableHosts.map { ($0.id, $0) })
        var registrations: [SavedWorkspaceSurfaceRegistration] = []

        guard let root = buildSavedWorkspaceRuntimeNode(
            from: template.root,
            ghosttyApp: ghosttyApp,
            hostLookup: hostLookup,
            workspaceName: template.name,
            workspaceID: template.id,
            registrations: &registrations
        ) else {
            return nil
        }

        return .init(tree: .init(root: root, zoomed: nil), registrations: registrations)
    }

    private func buildSavedWorkspaceRuntimeNode(
        from node: AITerminalSavedWorkspaceNode,
        ghosttyApp: ghostty_app_t,
        hostLookup: [String: AITerminalHost],
        workspaceName: String,
        workspaceID: String,
        registrations: inout [SavedWorkspaceSurfaceRegistration]
    ) -> SplitTree<TerminalPane>.Node? {
        switch node {
        case .pane(let pane):
            guard !pane.tabs.isEmpty else {
                lastError = L10n.AITerminalManager.savedWorkspaceEmptyPane
                return nil
            }

            var surfaces: [Ghostty.SurfaceView] = []
            for tab in pane.tabs {
                guard let launch = launchSpec(
                    for: tab,
                    hostLookup: hostLookup,
                    workspaceName: workspaceName,
                    workspaceID: workspaceID
                ) else {
                    return nil
                }

                let surface = Ghostty.SurfaceView(ghosttyApp, baseConfig: launch.plan.surfaceConfiguration)
                registrations.append(.init(
                    surfaceID: surface.id,
                    registration: launch.plan.registration,
                    pendingRemoteSession: launch.pendingRemoteSession
                ))
                surfaces.append(surface)
            }

            let activeIndex = min(max(pane.normalizedActiveTabIndex, 0), surfaces.count - 1)
            return .leaf(view: TerminalPane(
                surfaces: surfaces,
                activeSurfaceID: surfaces[activeIndex].id
            ))

        case .split(let split):
            guard let left = buildSavedWorkspaceRuntimeNode(
                from: split.left,
                ghosttyApp: ghosttyApp,
                hostLookup: hostLookup,
                workspaceName: workspaceName,
                workspaceID: workspaceID,
                registrations: &registrations
            ), let right = buildSavedWorkspaceRuntimeNode(
                from: split.right,
                ghosttyApp: ghosttyApp,
                hostLookup: hostLookup,
                workspaceName: workspaceName,
                workspaceID: workspaceID,
                registrations: &registrations
            ) else {
                return nil
            }

            let direction: SplitTree<TerminalPane>.Direction = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            return .split(.init(
                direction: direction,
                ratio: split.ratio,
                left: left,
                right: right
            ))
        }
    }

    private func savedWorkspaceNode(
        from node: SplitTree<TerminalPane>.Node?
    ) -> AITerminalSavedWorkspaceNode? {
        guard let node else { return nil }

        switch node {
        case .leaf(let pane):
            let tabs = pane.surfaces.map { savedWorkspaceTab(from: $0) }
            return .pane(.init(
                tabs: tabs,
                activeTabIndex: pane.surfaces.firstIndex(where: { $0.id == pane.activeSurfaceID }) ?? 0
            ))

        case .split(let split):
            guard let left = savedWorkspaceNode(from: split.left),
                  let right = savedWorkspaceNode(from: split.right) else {
                return nil
            }

            let direction: AITerminalSavedWorkspaceSplitDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            return .split(.init(
                direction: direction,
                ratio: split.ratio,
                left: left,
                right: right
            ))
        }
    }

    private func savedWorkspaceTab(from surface: Ghostty.SurfaceView) -> AITerminalSavedWorkspaceTab {
        let registration = registrations[surface.id]
        return .init(
            hostID: registration?.hostID ?? AITerminalHost.local.id,
            directory: surface.pwd
        )
    }

    private func launchSpec(
        for tab: AITerminalSavedWorkspaceTab,
        hostLookup: [String: AITerminalHost],
        workspaceName: String,
        workspaceID: String
    ) -> (plan: AITerminalLaunchPlan, pendingRemoteSession: PendingRemoteWorkspaceSession?)? {
        let hostID = tab.hostID
        let host = hostLookup[hostID] ?? (hostID == AITerminalHost.local.id ? .local : nil)
        guard let host else {
            lastError = L10n.AITerminalManager.savedWorkspaceUnknownHost
            return nil
        }

        switch host.transport {
        case .local:
            var plan = AITerminalLaunchPlan.localShell()
            plan.surfaceConfiguration.workingDirectory = tab.directory
            plan.registration.workspaceID = workspaceID
            plan.registration.sourceLabel = workspaceName
            return (plan, nil)

        case .localmcd:
            guard let plan = AITerminalLaunchPlan.localCommand(
                host: host,
                directoryOverride: tab.directory,
                workspaceID: workspaceID,
                sourceLabel: workspaceName
            ) else {
                lastError = L10n.AITerminalManager.localMCDCommandsEmpty
                return nil
            }
            return (plan, nil)

        case .ssh:
            let passwordResolution = resolvedPasswordAutomation(for: host)
            if let message = passwordResolution.error {
                lastError = message
                return nil
            }
            guard let plan = AITerminalLaunchPlan.remote(
                host: host,
                directoryOverride: tab.directory,
                workspaceID: workspaceID,
                sourceLabel: workspaceName
            ) else {
                lastError = L10n.AITerminalManager.hostMissingSSHDetails
                return nil
            }
            return (
                plan,
                .init(host: host, savedPassword: passwordResolution.password)
            )
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
        try migrateLegacyLearnCaptureScriptIfNeeded(at: learnCaptureScriptURL)

        try ensureExecutable(at: learnCaptureScriptURL)
        try ensureExecutable(at: learnSimpleScriptURL)

        return .init(
            chatWorkspacePath: chatWorkspaceURL.path,
            learnWorkspacePath: learnWorkspaceURL.path,
            createdFileCount: createdFileCount,
            reusedFileCount: reusedFileCount
        )
    }

    nonisolated private static func writeTextFileIfMissing(
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

    private static func migrateLegacyLearnCaptureScriptIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let content = try String(contentsOf: url, encoding: .utf8)
        guard !content.contains("agent.runtime.session.register") else { return }

        let looksGenerated = content.contains("selection=\"$(read_selection \"$@\" || true)\"")
            && content.contains("PROJECT_PATH=\"${PROJECT_PATH:-${TAB_WORKING_DIRECTORY:-$LEARN_WORKSPACE}}\"")
            && content.contains("LEARN_EXEC_COMMAND_TEMPLATE=\"${LEARN_EXEC_COMMAND_TEMPLATE:-")
        guard looksGenerated else { return }

        try learnCaptureScriptTemplate.write(to: url, atomically: true, encoding: .utf8)
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

    runtime_is_bootstrap_enabled() {
      [[ -n "${GHODEX_AGENT_RUNTIME_SOCKET:-${GHODEX_CONTROL_SOCKET:-}}" ]] || return 1
      [[ "${GHODEX_AGENT_RUNTIME_SESSION_KIND:-}" == "codex_tab" ]] || return 1
      command -v python3 >/dev/null 2>&1 || return 1
      return 0
    }

    runtime_heartbeat_interval_seconds() {
      python3 -c $'import os\nraw_value = os.environ.get("GHODEX_AGENT_RUNTIME_DEFAULT_HEARTBEAT_SECONDS", "").strip()\ntry:\n    lease_seconds = float(raw_value) if raw_value else 30.0\nexcept ValueError:\n    lease_seconds = 30.0\ninterval = max(5.0, min(lease_seconds / 2.0, 30.0))\nrounded = round(interval)\nif abs(interval - rounded) < 1e-9:\n    print(int(rounded))\nelse:\n    print(f"{interval:.3f}".rstrip("0").rstrip("."))'
    }

    runtime_request() {
      local action="$1"
      local reason="${2:-}"
      RUNTIME_ACTION="$action" \
      RUNTIME_REASON="$reason" \
      RUNTIME_SOCKET="${GHODEX_AGENT_RUNTIME_SOCKET:-${GHODEX_CONTROL_SOCKET:-}}" \
      RUNTIME_CLIENT_ID="${GHODEX_AGENT_RUNTIME_CLIENT_ID:-}" \
      RUNTIME_SESSION_ID="${runtime_session_id:-}" \
      RUNTIME_WORKSPACE_ID="${GHODEX_AGENT_RUNTIME_WORKSPACE_ID:-}" \
      RUNTIME_CAPABILITIES="${GHODEX_AGENT_RUNTIME_CAPABILITIES:-}" \
      RUNTIME_LEASE_DURATION_SECONDS="${GHODEX_AGENT_RUNTIME_DEFAULT_HEARTBEAT_SECONDS:-}" \
      python3 -c $'import json\nimport os\nimport socket\nimport sys\nimport uuid\ndef trim(value):\n    return "" if value is None else str(value).strip()\naction = trim(os.environ.get("RUNTIME_ACTION"))\ncommands = {"register": "agent.runtime.session.register", "heartbeat": "agent.runtime.session.heartbeat", "release": "agent.runtime.session.release"}\nif action not in commands:\n    print(f"unsupported runtime action: {action}", file=sys.stderr)\n    sys.exit(2)\nsocket_path = trim(os.environ.get("RUNTIME_SOCKET"))\nif not socket_path:\n    print("runtime socket path is missing", file=sys.stderr)\n    sys.exit(2)\nclient_id = trim(os.environ.get("RUNTIME_CLIENT_ID")) or str(uuid.uuid4()).lower()\nrequest = {"request_id": f"runtime_{action}_{client_id}", "command": commands[action], "client": "codex-learn-bootstrap"}\nlease_raw = trim(os.environ.get("RUNTIME_LEASE_DURATION_SECONDS"))\nsession_id = trim(os.environ.get("RUNTIME_SESSION_ID"))\nworkspace_id = trim(os.environ.get("RUNTIME_WORKSPACE_ID"))\nreason = trim(os.environ.get("RUNTIME_REASON"))\ncapabilities = [item.strip() for item in trim(os.environ.get("RUNTIME_CAPABILITIES")).split(",") if item.strip()]\nif action == "register":\n    if client_id:\n        request["session_id"] = client_id\n    if workspace_id:\n        request["workspace_id"] = workspace_id\n    if capabilities:\n        request["capabilities"] = capabilities\n    if lease_raw:\n        try:\n            request["lease_duration_seconds"] = float(lease_raw)\n        except ValueError:\n            pass\nelif action in {"heartbeat", "release"}:\n    if not session_id:\n        print("runtime session id is missing", file=sys.stderr)\n        sys.exit(2)\n    request["session_id"] = session_id\n    if action == "heartbeat" and lease_raw:\n        try:\n            request["lease_duration_seconds"] = float(lease_raw)\n        except ValueError:\n            pass\n    if action == "release" and reason:\n        request["reason"] = reason\npayload = json.dumps(request, separators=(",", ":")).encode("utf-8")\nclient = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\ntry:\n    client.connect(socket_path)\n    client.sendall(payload)\n    try:\n        client.shutdown(socket.SHUT_WR)\n    except OSError:\n        pass\n    chunks = []\n    while True:\n        data = client.recv(65536)\n        if not data:\n            break\n        chunks.append(data)\nfinally:\n    client.close()\nresponse_bytes = b"".join(chunks)\nresponse = json.loads(response_bytes.decode("utf-8") if response_bytes else "{}")\nif response.get("status") != "ok":\n    message = response.get("error_message") or response.get("error_code") or "runtime_request_failed"\n    print(message, file=sys.stderr)\n    sys.exit(1)\nif action == "register":\n    session = response.get("result", {}).get("session", {})\n    registered_session_id = trim(session.get("id"))\n    if not registered_session_id:\n        print("runtime register returned an empty session id", file=sys.stderr)\n        sys.exit(1)\n    print(registered_session_id)'
    }

    runtime_start_heartbeat() {
      local interval="$1"
      (
        while true; do
          sleep "$interval"
          runtime_request heartbeat >/dev/null || break
        done
      ) &
      runtime_heartbeat_pid=$!
    }

    runtime_stop_heartbeat() {
      if [[ -n "${runtime_heartbeat_pid:-}" ]]; then
        kill "${runtime_heartbeat_pid}" >/dev/null 2>&1 || true
        wait "${runtime_heartbeat_pid}" >/dev/null 2>&1 || true
        runtime_heartbeat_pid=""
      fi
    }

    runtime_cleanup() {
      local exit_code="${1:-0}"
      runtime_stop_heartbeat
      if [[ -n "${runtime_session_id:-}" ]]; then
        runtime_request release "codex_exec_exit_${exit_code}" >/dev/null 2>&1 || true
        runtime_session_id=""
      fi
    }

    selection="$(read_selection "$@" || true)"
    if [[ -z "${selection//[$' \t\n\r']/}" ]]; then
      echo "No selection text provided." >&2
      exit 2
    fi

    LEARN_WORKSPACE="${LEARN_WORKSPACE:-$WORKSPACE_DIR}"
    PROJECT_PATH="${PROJECT_PATH:-${TAB_WORKING_DIRECTORY:-$LEARN_WORKSPACE}}"
    runtime_session_id=""
    runtime_heartbeat_pid=""
    trap 'runtime_cleanup $?' EXIT

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

    if runtime_is_bootstrap_enabled; then
      if runtime_session_id="$(runtime_request register)"; then
        runtime_interval="$(runtime_heartbeat_interval_seconds)"
        runtime_start_heartbeat "${runtime_interval:-15}"
      else
        echo "Warning: failed to register GhoDex runtime session; continuing without runtime heartbeat." >&2
        runtime_session_id=""
      fi
    fi

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

    func agentRuntimeSession(forTerminalID terminalID: UUID) -> AgentRuntimeSession? {
        configuration.agentRuntimeSessions
            .filter { $0.terminalID == terminalID }
            .sorted { lhs, rhs in
                let lhsPriority = agentRuntimeSessionProjectionPriority(lhs)
                let rhsPriority = agentRuntimeSessionProjectionPriority(rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
            .first
    }

    func agentRuntimeTask(forTerminalID terminalID: UUID) -> AgentRuntimeTask? {
        guard let session = agentRuntimeSession(forTerminalID: terminalID),
              let currentTaskID = session.currentTaskID else {
            return nil
        }
        return configuration.agentRuntimeTasks.first(where: { $0.id == currentTaskID })
    }

    func projectedManagedState(for terminalID: UUID) -> AITerminalManagedState {
        if let runtimeTask = agentRuntimeTask(forTerminalID: terminalID) {
            return compatibilityManagedState(for: runtimeTask.state)
        }

        if let runtimeSession = agentRuntimeSession(forTerminalID: terminalID) {
            switch runtimeSession.state {
            case .booting, .active:
                return .managedActive
            case .waitingApproval:
                return .managedWaitingApproval
            case .paused:
                return .managedPaused
            case .expired, .failed:
                return .managedFailed
            case .released:
                break
            }
        }

        return registrations[terminalID]?.managedState ?? .manual
    }

    func projectedSessionTaskSummary(for terminalID: UUID) -> ProjectedSessionTaskSummary {
        if let runtimeTask = agentRuntimeTask(forTerminalID: terminalID) {
            let legacyTask = task(for: terminalID)
            return .init(
                taskID: runtimeTask.id,
                taskTitle: legacyTask?.title ?? projectedTaskTitle(for: runtimeTask),
                taskState: compatibilityTaskState(for: runtimeTask.state)
            )
        }

        let legacyTask = task(for: terminalID)
        return .init(
            taskID: legacyTask?.id,
            taskTitle: legacyTask?.title,
            taskState: legacyTask?.state
        )
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

        let semanticSnapshot = semanticSnapshot(from: surface, refresh: false)
        selectedSessionVisibleText = semanticSnapshot.visibleExactText
        selectedSessionScreenText = semanticSnapshot.screenExactText
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
                createdSurface = controller.surfaceTree.leftmostActiveSurface()
            } else {
                let controller = TerminalController.newWindow(
                    appDelegate.ghostty,
                    withBaseConfig: plan.surfaceConfiguration
                )
                createdSurface = controller.surfaceTree.leftmostActiveSurface()
            }

        case .window:
            let controller = TerminalController.newWindow(
                appDelegate.ghostty,
                withBaseConfig: plan.surfaceConfiguration
            )
            createdSurface = controller.surfaceTree.leftmostActiveSurface()
        }

        guard let createdSurface else {
            lastError = L10n.AITerminalManager.createSessionFailed
            return nil
        }

        registrations[createdSurface.id] = plan.registration
        rebuildSessions()
        return createdSurface.id
    }

    @discardableResult
    private func launch(
        _ plan: AITerminalLaunchPlan,
        inPaneOf controller: TerminalController,
        sourceSurface: Ghostty.SurfaceView
    ) -> UUID? {
        guard let createdSurface = controller.createPaneTab(from: sourceSurface, withBaseConfig: plan.surfaceConfiguration) else {
            lastError = L10n.AITerminalManager.createSessionFailed
            return nil
        }

        registrations[createdSurface.id] = plan.registration
        rebuildSessions()
        return createdSurface.id
    }

    @discardableResult
    private func launch(
        _ plan: AITerminalLaunchPlan,
        inSplitOf controller: TerminalController,
        sourceSurface: Ghostty.SurfaceView,
        direction: SplitTree<TerminalPane>.NewDirection
    ) -> UUID? {
        guard let createdSurface = controller.newSplit(
            at: sourceSurface,
            direction: direction,
            baseConfig: plan.surfaceConfiguration
        ) else {
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
                controller.allSurfaces.map(\.id)
            }
        )

        pruneClosedSessions(activeSessionIDs: activeSessionIDs)

        sessions = TerminalController.all
            .flatMap { controller in
                controller.allSurfaces.map { surface in
                    let registration = registrations[surface.id]
                    let projectedTask = projectedSessionTaskSummary(for: surface.id)
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
                        managedState: projectedManagedState(for: surface.id),
                        taskID: projectedTask.taskID,
                        taskTitle: projectedTask.taskTitle,
                        taskState: projectedTask.taskState
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

    private func agentRuntimeSessionProjectionPriority(_ session: AgentRuntimeSession) -> Int {
        switch session.state {
        case .booting, .active, .waitingApproval, .paused:
            return 0
        case .failed, .expired:
            return 1
        case .released:
            return 2
        }
    }

    private func compatibilityManagedState(for runtimeState: AgentRuntimeTaskState) -> AITerminalManagedState {
        switch runtimeState {
        case .queued, .claimed, .running:
            return .managedActive
        case .waitingApproval:
            return .managedWaitingApproval
        case .paused:
            return .managedPaused
        case .completed:
            return .managedCompleted
        case .failed, .cancelled:
            return .managedFailed
        }
    }

    private func compatibilityTaskState(for runtimeState: AgentRuntimeTaskState) -> AITerminalTaskState {
        switch runtimeState {
        case .queued:
            return .queued
        case .claimed, .running:
            return .active
        case .waitingApproval:
            return .waitingApproval
        case .paused:
            return .paused
        case .completed:
            return .completed
        case .failed, .cancelled:
            return .failed
        }
    }

    private func projectedTaskTitle(for task: AgentRuntimeTask) -> String? {
        if let command = task.payload.command?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            return command
        }

        if let text = task.payload.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return task.kind.rawValue
    }

    private func registerRemoteSession(
        _ sessionID: UUID,
        host: AITerminalHost,
        savedPassword: String?,
        shouldRebuild: Bool = true
    ) {
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
        if shouldRebuild {
            rebuildSessions()
        }
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

    @discardableResult
    private func processPendingSSHPasswordPrompts() -> Bool {
        guard !pendingSSHPasswordAutomations.isEmpty else {
            stopSSHPasswordAutomationTimer()
            return false
        }
        guard let appDelegate = appDelegateProvider() else {
            return false
        }

        var observedActivity = false
        for (sessionID, pending) in pendingSSHPasswordAutomations {
            guard let surface = appDelegate.findSurface(forUUID: sessionID) else { continue }
            let visibleText = semanticSnapshot(from: surface, refresh: true).visibleExactText

            if Self.containsSSHAuthenticationFailure(in: visibleText) {
                observedActivity = true
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
                observedActivity = true
                if !Self.containsSSHPasswordPrompt(in: visibleText) {
                    sshSessionAuthStates[sessionID] = .connected
                    pendingSSHPasswordAutomations.removeValue(forKey: sessionID)
                }
                continue
            }

            if Self.containsSSHPasswordPrompt(in: visibleText) {
                observedActivity = true
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
        return observedActivity
    }

    private func ensureSSHPasswordAutomationTimer() {
        guard !pendingSSHPasswordAutomations.isEmpty else {
            stopSSHPasswordAutomationTimer()
            return
        }
        guard sshPasswordAutomationTimer == nil else { return }

        sshPasswordAutomationInterval = Self.sshPasswordAutomationFastInterval
        sshPasswordAutomationIdlePollCount = 0
        RuntimeDiagnosticsLogger.log(
            component: "ai_manager.ssh_password_automation",
            event: "start",
            details: [
                "pending_sessions": "\(pendingSSHPasswordAutomations.count)",
                "interval_seconds": String(format: "%.3f", sshPasswordAutomationInterval),
            ]
        )
        scheduleSSHPasswordAutomationTick(after: 0.01)
    }

    private func scheduleSSHPasswordAutomationTick(after interval: TimeInterval) {
        sshPasswordAutomationTimer?.invalidate()

        let resolvedInterval = max(0.05, interval)
        let timer = Timer(
            timeInterval: resolvedInterval,
            repeats: false
        ) { [weak self] _ in
            self?.runSSHPasswordAutomationTick()
        }
        timer.tolerance = min(max(resolvedInterval * 0.25, 0.05), 0.25)
        RunLoop.main.add(timer, forMode: .common)
        sshPasswordAutomationTimer = timer
    }

    private func runSSHPasswordAutomationTick() {
        guard !pendingSSHPasswordAutomations.isEmpty else {
            stopSSHPasswordAutomationTimer()
            return
        }

        let observedActivity = processPendingSSHPasswordPrompts()
        let hostLookup = Dictionary(uniqueKeysWithValues: availableHosts.map { ($0.id, $0) })
        rebuildRemoteSessions(hostLookup: hostLookup)

        guard !pendingSSHPasswordAutomations.isEmpty else {
            stopSSHPasswordAutomationTimer()
            return
        }

        let previousInterval = sshPasswordAutomationInterval
        if observedActivity {
            sshPasswordAutomationIdlePollCount = 0
            sshPasswordAutomationInterval = Self.sshPasswordAutomationFastInterval
        } else {
            sshPasswordAutomationIdlePollCount += 1
            if sshPasswordAutomationIdlePollCount == 1 {
                sshPasswordAutomationInterval = min(
                    Self.sshPasswordAutomationMaxInterval,
                    max(sshPasswordAutomationInterval, 0.35)
                )
            } else {
                sshPasswordAutomationInterval = min(
                    Self.sshPasswordAutomationMaxInterval,
                    sshPasswordAutomationInterval * Self.sshPasswordAutomationBackoffMultiplier
                )
            }
        }

        if abs(previousInterval - sshPasswordAutomationInterval) > 0.000_1 {
            RuntimeDiagnosticsLogger.log(
                component: "ai_manager.ssh_password_automation",
                event: "interval_change",
                details: [
                    "observed_activity": observedActivity ? "true" : "false",
                    "pending_sessions": "\(pendingSSHPasswordAutomations.count)",
                    "previous_seconds": String(format: "%.3f", previousInterval),
                    "next_seconds": String(format: "%.3f", sshPasswordAutomationInterval),
                ]
            )
        }

        scheduleSSHPasswordAutomationTick(after: sshPasswordAutomationInterval)
    }

    private func stopSSHPasswordAutomationTimer() {
        let hadTimer = sshPasswordAutomationTimer != nil
        sshPasswordAutomationTimer?.invalidate()
        sshPasswordAutomationTimer = nil
        sshPasswordAutomationInterval = Self.sshPasswordAutomationFastInterval
        sshPasswordAutomationIdlePollCount = 0
        if hadTimer {
            RuntimeDiagnosticsLogger.log(
                component: "ai_manager.ssh_password_automation",
                event: "stop"
            )
        }
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

    private func semanticSnapshot(
        from surface: Ghostty.SurfaceView,
        refresh: Bool
    ) -> (visibleExactText: String, screenExactText: String) {
        let semanticProfile = appDelegateProvider()?.controlHarnessGatewaySettings.semanticProfileValue
            ?? .defaultValue
        let visible = surface.controlHarnessVisibleText(refresh: refresh).content
        let screen = surface.controlHarnessScreenText(refresh: refresh).content
        let visibleProjection = controlHarnessSemanticProjection(
            from: visible,
            profile: semanticProfile
        )
        let screenProjection = controlHarnessSemanticProjection(
            from: screen,
            profile: semanticProfile
        )
        return (
            visibleExactText: visibleProjection.exactText,
            screenExactText: screenProjection.exactText
        )
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

    private func syncHeartbeatRuntime() {
        ensureHeartbeatInboxDirectory()
        ensureHeartbeatTimer()

        guard configuration.heartbeatQueueSettings.enabled else {
            stopHeartbeatExecutionTimers()
            return
        }

        // Process pending inbox mutations immediately so config changes do not
        // wait for the next timer tick to quarantine or enqueue work.
        importHeartbeatTasksFromInbox()
        scheduleNextHeartbeatExecution()
        runDueHeartbeatTasksIfNeeded()
    }

    private func syncAgentRuntimeRecovery() {
        agentRuntimeRecoveryTimer?.invalidate()
        agentRuntimeRecoveryTimer = nil

        guard configuration.agentRuntimeSettings.enabled else { return }

        _ = expireStaleAgentRuntimeSessions(now: .now)
        let interval = min(
            max(configuration.agentRuntimeSettings.sanitized().defaultLeaseDurationSeconds / 2, 1),
            5
        )
        let timer = Timer(
            timeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            _ = self.expireStaleAgentRuntimeSessions(now: .now)
        }
        timer.tolerance = min(max(interval * 0.2, 0.1), 1)
        RunLoop.main.add(timer, forMode: .common)
        agentRuntimeRecoveryTimer = timer
    }

    private func syncAgentRuntimeSchedules(now: Date = .now) {
        agentRuntimeSchedulerTimer?.invalidate()
        agentRuntimeSchedulerTimer = nil

        guard configuration.agentRuntimeSettings.enabled else { return }

        _ = materializeDueAgentRuntimeSchedules(now: now)
        scheduleNextAgentRuntimeMaterialization(now: now)
    }

    private func scheduleNextAgentRuntimeMaterialization(now: Date = .now) {
        agentRuntimeSchedulerTimer?.invalidate()
        agentRuntimeSchedulerTimer = nil

        guard configuration.agentRuntimeSettings.enabled else { return }
        guard let nextDate = configuration.agentRuntimeSchedules
            .compactMap({ nextAgentRuntimeScheduleEvaluationDate(for: $0, now: now) })
            .min()
        else {
            return
        }

        let delay = max(0, nextDate.timeIntervalSince(now))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.syncAgentRuntimeSchedules()
        }
        timer.tolerance = min(max(delay * 0.1, 0.05), 1)
        RunLoop.main.add(timer, forMode: .common)
        agentRuntimeSchedulerTimer = timer
    }

    @discardableResult
    private func materializeDueAgentRuntimeSchedules(now: Date = .now) -> [AgentRuntimeTask] {
        guard configuration.agentRuntimeSettings.enabled else { return [] }

        let dueIndices = configuration.agentRuntimeSchedules.indices
            .filter { index in
                let schedule = configuration.agentRuntimeSchedules[index]
                guard schedule.isDue(at: now) else { return false }
                return !isAgentRuntimeScheduleBlockedByActiveTask(schedule)
            }
            .sorted { lhs, rhs in
                let lhsSchedule = configuration.agentRuntimeSchedules[lhs]
                let rhsSchedule = configuration.agentRuntimeSchedules[rhs]
                let lhsNext = lhsSchedule.nextRunAt ?? lhsSchedule.startAt
                let rhsNext = rhsSchedule.nextRunAt ?? rhsSchedule.startAt
                if lhsNext != rhsNext {
                    return lhsNext < rhsNext
                }
                if lhsSchedule.priority != rhsSchedule.priority {
                    return lhsSchedule.priority > rhsSchedule.priority
                }
                if lhsSchedule.createdAt != rhsSchedule.createdAt {
                    return lhsSchedule.createdAt < rhsSchedule.createdAt
                }
                return lhsSchedule.id.uuidString < rhsSchedule.id.uuidString
            }

        guard !dueIndices.isEmpty else { return [] }

        var materializedTasks: [AgentRuntimeTask] = []
        var events: [(scheduleID: UUID, taskID: UUID, nextRunAt: String)] = []

        for index in dueIndices {
            let schedule = configuration.agentRuntimeSchedules[index]
            let fireAt = schedule.nextRunAt ?? schedule.startAt
            var metadata = schedule.payload.metadata
            metadata[Self.agentRuntimeScheduleIDMetadataKey] = schedule.id.uuidString.lowercased()
            metadata[Self.agentRuntimeScheduleFireAtMetadataKey] = Self.iso8601(fireAt)

            let task = AgentRuntimeTask(
                kind: schedule.taskKind,
                priority: schedule.priority,
                capabilityRequirements: schedule.capabilityRequirements,
                payload: .init(
                    command: schedule.payload.command,
                    text: schedule.payload.text,
                    metadata: metadata
                ),
                createdAt: now,
                scheduledAt: fireAt,
                maxRetryCount: schedule.maxRetryCount
            )
            configuration.agentRuntimeTasks.append(task)
            configuration.agentRuntimeSchedules[index].markMaterialized(
                fireAt: fireAt,
                materializedAt: now,
                taskID: task.id
            )
            materializedTasks.append(task)
            events.append((
                scheduleID: schedule.id,
                taskID: task.id,
                nextRunAt: configuration.agentRuntimeSchedules[index].nextRunAt.map(Self.iso8601) ?? ""
            ))
        }

        persistConfiguration()
        for event in events {
            appendAgentRuntimeEvent(
                "schedule_materialized",
                taskID: event.taskID,
                details: [
                    "schedule_id": event.scheduleID.uuidString.lowercased(),
                    "next_run_at": event.nextRunAt,
                ]
            )
        }
        return materializedTasks
    }

    private func nextAgentRuntimeScheduleEvaluationDate(
        for schedule: AgentRuntimeSchedule,
        now: Date
    ) -> Date? {
        guard schedule.state.isRunnable else { return nil }
        guard let nextRunAt = schedule.nextRunAt else { return nil }
        if nextRunAt > now {
            return nextRunAt
        }
        if isAgentRuntimeScheduleBlockedByActiveTask(schedule) {
            return now.addingTimeInterval(1)
        }
        return nextRunAt
    }

    private func isAgentRuntimeScheduleBlockedByActiveTask(_ schedule: AgentRuntimeSchedule) -> Bool {
        guard let lastTaskID = schedule.lastTaskID,
              let task = configuration.agentRuntimeTasks.first(where: { $0.id == lastTaskID }) else {
            return false
        }
        return !task.state.isFinished
    }

    private func ensureHeartbeatInboxDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: heartbeatInboxDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            lastError = "Failed to create task queue inbox: \(error.localizedDescription)"
        }
    }

    private func ensureHeartbeatTimer() {
        let interval = min(
            max(configuration.heartbeatQueueSettings.heartbeatIntervalSeconds, Self.minHeartbeatIntervalSeconds),
            Self.maxHeartbeatIntervalSeconds
        )
        if let heartbeatTimer {
            if abs(heartbeatTimer.timeInterval - interval) < 0.001 {
                return
            }
            heartbeatTimer.invalidate()
            self.heartbeatTimer = nil
        }

        let timer = Timer(
            timeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            self.processHeartbeatTick(now: .now)
        }
        timer.tolerance = min(max(interval * 0.1, 0.05), 1)
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    func processHeartbeatTick(now: Date = .now) {
        heartbeatLastBeatAt = now
        importHeartbeatTasksFromInbox()
        if configuration.agentRuntimeSettings.enabled {
            _ = expireStaleAgentRuntimeSessions(now: now)
        }
        if configuration.heartbeatQueueSettings.enabled {
            runDueHeartbeatTasksIfNeeded()
        }
    }

    private func stopHeartbeatExecutionTimers() {
        heartbeatSchedulerTimer?.invalidate()
        heartbeatSchedulerTimer = nil
        heartbeatIsExecutingTask = configuration.heartbeatTasks.contains(where: { $0.status == .running })
    }

    private func scheduleNextHeartbeatExecution() {
        heartbeatSchedulerTimer?.invalidate()
        heartbeatSchedulerTimer = nil

        guard configuration.heartbeatQueueSettings.enabled else { return }

        guard let nextDate = configuration.heartbeatTasks
            .filter({ $0.status == .queued })
            .map(\.executeAt)
            .min()
        else {
            return
        }

        let delay = max(0, nextDate.timeIntervalSinceNow)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.runDueHeartbeatTasksIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatSchedulerTimer = timer
    }

    private func runDueHeartbeatTasksIfNeeded() {
        guard configuration.heartbeatQueueSettings.enabled else { return }

        let runningCount = configuration.heartbeatTasks.filter { $0.status == .running }.count
        let maxConcurrent = min(
            max(configuration.heartbeatQueueSettings.maxConcurrentTasks, Self.minHeartbeatMaxConcurrentTasks),
            Self.maxHeartbeatMaxConcurrentTasks
        )
        let availableSlots = maxConcurrent - runningCount
        heartbeatIsExecutingTask = runningCount > 0

        guard availableSlots > 0 else {
            scheduleNextHeartbeatExecution()
            return
        }

        let now = Date()
        let dueIndices = configuration.heartbeatTasks.indices
            .filter { index in
                let task = configuration.heartbeatTasks[index]
                return task.status == .queued && task.executeAt <= now
            }
            .sorted { lhs, rhs in
                let lhsTask = configuration.heartbeatTasks[lhs]
                let rhsTask = configuration.heartbeatTasks[rhs]
                if lhsTask.executeAt != rhsTask.executeAt {
                    return lhsTask.executeAt < rhsTask.executeAt
                }
                return lhsTask.createdAt < rhsTask.createdAt
            }

        guard !dueIndices.isEmpty else {
            scheduleNextHeartbeatExecution()
            return
        }

        let selectedIndices = Array(dueIndices.prefix(availableSlots))
        var runningTasks: [AITerminalHeartbeatTask] = []
        runningTasks.reserveCapacity(selectedIndices.count)

        for index in selectedIndices {
            configuration.heartbeatTasks[index].status = .running
            configuration.heartbeatTasks[index].updatedAt = .now
            configuration.heartbeatTasks[index].errorMessage = nil
            runningTasks.append(configuration.heartbeatTasks[index])
        }

        heartbeatIsExecutingTask = true
        pruneHeartbeatTasks()
        persistConfiguration()
        scheduleNextHeartbeatExecution()

        for task in runningTasks {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let result = Self.executeHeartbeatTask(task)
                Task { @MainActor [weak self] in
                    self?.finishHeartbeatTask(taskID: task.id, succeeded: result.succeeded, errorMessage: result.errorMessage)
                }
            }
        }
    }

    private func finishHeartbeatTask(taskID: UUID, succeeded: Bool, errorMessage: String?) {
        guard let index = configuration.heartbeatTasks.firstIndex(where: { $0.id == taskID }) else {
            heartbeatIsExecutingTask = configuration.heartbeatTasks.contains(where: { $0.status == .running })
            pruneHeartbeatTasks()
            persistConfiguration()
            scheduleNextHeartbeatExecution()
            runDueHeartbeatTasksIfNeeded()
            return
        }

        configuration.heartbeatTasks[index].status = succeeded ? .done : .failed
        configuration.heartbeatTasks[index].updatedAt = .now
        configuration.heartbeatTasks[index].errorMessage = errorMessage
        heartbeatIsExecutingTask = configuration.heartbeatTasks.contains(where: { $0.status == .running })
        pruneHeartbeatTasks()
        persistConfiguration()
        scheduleNextHeartbeatExecution()
        runDueHeartbeatTasksIfNeeded()
    }

    private nonisolated static func executeHeartbeatTask(_ task: AITerminalHeartbeatTask) -> (succeeded: Bool, errorMessage: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        switch task.type {
        case .exec:
            process.arguments = ["-lc", task.command]
        case .script:
            process.arguments = [task.command]
        }

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return (false, "failed to launch: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        if process.terminationStatus == 0 {
            return (true, nil)
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stderr.isEmpty {
            return (false, "exit code \(process.terminationStatus)")
        }
        return (false, stderr)
    }

    private func importHeartbeatTasksFromInbox() {
        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(
                at: heartbeatInboxDirectoryURL,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            lastError = "Failed to read task queue inbox: \(error.localizedDescription)"
            return
        }

        guard !fileURLs.isEmpty else { return }

        guard configuration.heartbeatQueueSettings.allowExternalInboxMutations else {
            quarantineHeartbeatInboxRequests(fileURLs)
            return
        }

        let decoder = JSONDecoder()
        for url in fileURLs {
            do {
                let data = try Data(contentsOf: url)
                let request = try decoder.decode(ExternalHeartbeatTaskRequest.self, from: data)
                try applyExternalHeartbeatTaskRequest(request)
                try? FileManager.default.removeItem(at: url)
            } catch {
                let failedURL = url.deletingPathExtension().appendingPathExtension("failed")
                try? FileManager.default.moveItem(at: url, to: failedURL)
            }
        }
    }

    private func quarantineHeartbeatInboxRequests(_ fileURLs: [URL]) {
        for url in fileURLs {
            let blockedURL = url.deletingPathExtension().appendingPathExtension("blocked")
            do {
                if FileManager.default.fileExists(atPath: blockedURL.path) {
                    try FileManager.default.removeItem(at: blockedURL)
                }
                try FileManager.default.moveItem(at: url, to: blockedURL)
            } catch {
                RuntimeDiagnosticsLogger.log(
                    component: "ai_manager.heartbeat_tasks",
                    event: "blocked_inbox_request",
                    details: [
                        "path": url.path,
                        "error": error.localizedDescription,
                    ]
                )
            }
        }
    }

    private func applyExternalHeartbeatTaskRequest(_ request: ExternalHeartbeatTaskRequest) throws {
        let action = request.action ?? .enqueue

        switch action {
        case .enqueue:
            guard let command = request.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
                throw NSError(
                    domain: "AITerminalHeartbeatQueue",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "enqueue requires non-empty command"]
                )
            }
            let executeAt: Date? = if let executeAtMS = request.executeAtMS {
                Date(timeIntervalSince1970: TimeInterval(executeAtMS) / 1000)
            } else {
                nil
            }
            _ = enqueueHeartbeatTask(
                command: command,
                type: request.type ?? .exec,
                executeAt: executeAt
            )

        case .cancel:
            if let taskID = request.taskID {
                cancelHeartbeatTask(taskID)
            } else {
                cancelAllQueuedHeartbeatTasks()
            }

        case .clearFinished:
            clearFinishedHeartbeatTasks()

        case .configure:
            var settings = configuration.heartbeatQueueSettings
            if let enabled = request.enabled {
                settings.enabled = enabled
            }
            if let heartbeatIntervalSeconds = request.heartbeatIntervalSeconds {
                settings.heartbeatIntervalSeconds = heartbeatIntervalSeconds
            }
            if let maxConcurrentTasks = request.maxConcurrentTasks {
                settings.maxConcurrentTasks = maxConcurrentTasks
            }
            saveHeartbeatQueueSettings(settings)
        }
    }

    private func persistConfiguration() {
        do {
            try Self.saveConfiguration(configuration, to: configurationURL)
            configurationRevision = UUID()
            appDelegateProvider()?.ghostty.reloadConfig()
        } catch {
            lastError = L10n.AITerminalManager.saveConfigurationFailed(error.localizedDescription)
        }
    }

    nonisolated private static func defaultConfigurationURL() -> URL {
        let fileManager = FileManager.default
        if let path = Ghostty.App.configPath(), !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: false)
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return url
        }

        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser

        let bundleID = Bundle.main.bundleIdentifier ?? "com.sgpleon.ghodex"
        let directory = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("config.ghodex", isDirectory: false)
    }

    nonisolated private static func shouldObserveGlobalGhosttyConfig(for configurationURL: URL) -> Bool {
        configurationURL.standardizedFileURL == defaultConfigurationURL().standardizedFileURL
    }

    nonisolated static func loadConfiguration(at url: URL) throws -> AITerminalManagerConfiguration {
        let fileManager = FileManager.default
        var managedText: String?
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8),
               let firstNonWhitespace = text.trimmingCharacters(in: .whitespacesAndNewlines).first,
               firstNonWhitespace == "{" {
                let configuration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)
                return sanitizeConfiguration(configuration)
            }
            managedText = String(data: data, encoding: .utf8)
        }

        let config = Ghostty.Config(at: url.path(percentEncoded: false))
        var configuration = configuration(from: config)
        if let override = managedBooleanValue(
            for: "ghodex-heartbeat-allow-external-inbox-mutations",
            in: managedText
        ) {
            configuration.heartbeatQueueSettings.allowExternalInboxMutations = override
        }
        if let override = decodeManagedPayloads(
            AgentRuntimeSchedule.self,
            for: "ghodex-agent-runtime-schedule",
            in: managedText
        ) {
            configuration.agentRuntimeSchedules = override
        }
        return sanitizeConfiguration(configuration)
    }

    nonisolated private static func saveConfiguration(_ configuration: AITerminalManagerConfiguration, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existingText: String
        if fileManager.fileExists(atPath: url.path) {
            existingText = try String(contentsOf: url, encoding: .utf8)
        } else {
            existingText = ""
        }

        let stripped = stripManagedConfig(from: existingText)
        let block = managedConfigBlock(for: configuration)
        let normalized = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = normalized.isEmpty ? "\(block)\n" : "\(normalized)\n\n\(block)\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated private static func isFinishedHeartbeatTaskStatus(_ status: AITerminalHeartbeatTaskStatus) -> Bool {
        switch status {
        case .done, .failed, .cancelled:
            return true
        case .queued, .running:
            return false
        }
    }

    nonisolated private static func heartbeatTaskEvictionPriority(_ status: AITerminalHeartbeatTaskStatus) -> Int {
        switch status {
        case .done:
            return 0
        case .failed:
            return 1
        case .cancelled:
            return 2
        case .queued:
            return 3
        case .running:
            return 4
        }
    }

    nonisolated private static func prunedHeartbeatTasks(
        _ tasks: [AITerminalHeartbeatTask],
        now: Date = .now
    ) -> [AITerminalHeartbeatTask] {
        let finishedCutoff = now.addingTimeInterval(-Self.heartbeatFinishedTaskRetentionSeconds)
        let initialCount = tasks.count
        var filtered = tasks.filter { task in
            guard isFinishedHeartbeatTaskStatus(task.status) else {
                return true
            }
            return task.updatedAt >= finishedCutoff
        }
        let removedFinished = initialCount - filtered.count

        let overflowCount = filtered.count - Self.maxHeartbeatTaskEntries
        guard overflowCount > 0 else {
            if removedFinished > 0 {
                RuntimeDiagnosticsLogger.log(
                    component: "ai_manager.heartbeat_tasks",
                    event: "prune_reason",
                    details: [
                        "removed_finished": "\(removedFinished)",
                        "removed_capacity": "0",
                        "remaining": "\(filtered.count)",
                    ]
                )
            }
            return filtered
        }

        let evictionIDs = Set(
            filtered
                .sorted { lhs, rhs in
                    let lhsPriority = heartbeatTaskEvictionPriority(lhs.status)
                    let rhsPriority = heartbeatTaskEvictionPriority(rhs.status)
                    if lhsPriority != rhsPriority {
                        return lhsPriority < rhsPriority
                    }
                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt < rhs.updatedAt
                    }
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .prefix(overflowCount)
                .map(\.id)
        )
        filtered.removeAll { evictionIDs.contains($0.id) }
        RuntimeDiagnosticsLogger.log(
            component: "ai_manager.heartbeat_tasks",
            event: "prune_reason",
            details: [
                "removed_finished": "\(removedFinished)",
                "removed_capacity": "\(evictionIDs.count)",
                "remaining": "\(filtered.count)",
            ]
        )
        return filtered
    }

    nonisolated private static func sanitizeConfiguration(_ configuration: AITerminalManagerConfiguration) -> AITerminalManagerConfiguration {
        var next = configuration
        next.heartbeatQueueSettings.heartbeatIntervalSeconds = min(
            max(next.heartbeatQueueSettings.heartbeatIntervalSeconds, Self.minHeartbeatIntervalSeconds),
            Self.maxHeartbeatIntervalSeconds
        )
        next.heartbeatQueueSettings.maxConcurrentTasks = min(
            max(next.heartbeatQueueSettings.maxConcurrentTasks, Self.minHeartbeatMaxConcurrentTasks),
            Self.maxHeartbeatMaxConcurrentTasks
        )
        next.heartbeatTasks = prunedHeartbeatTasks(next.heartbeatTasks)
        next.agentRuntimeSettings = next.agentRuntimeSettings.sanitized()
        next.agentRuntimeSchedules = next.agentRuntimeSchedules.map { schedule in
            var updated = schedule
            updated.recurrence = updated.recurrence.sanitized()
            updated.maxRetryCount = max(0, updated.maxRetryCount)
            if updated.nextRunAt == nil, updated.state.isRunnable {
                updated.nextRunAt = updated.startAt
            }
            return updated
        }
        next.todoSettings = .init(
            enabled: next.todoSettings.enabled,
            workspaceRootPath: next.todoSettings.workspaceRootPath.isEmpty
                ? AITerminalTodoSettings.defaultWorkspaceRootPath
                : next.todoSettings.workspaceRootPath,
            showCompletedItems: next.todoSettings.showCompletedItems,
            selectedDateAnchor: next.todoSettings.selectedDateAnchor,
            sidebarEdge: next.todoSettings.sidebarEdge,
            workspaceOverlayVisible: next.todoSettings.workspaceOverlayVisible,
            workspaceOverlayCorner: next.todoSettings.workspaceOverlayCorner
        )
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

    nonisolated private static func clampText(_ text: String, maxCharacters: Int) -> String {
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

    nonisolated private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func installGhosttyConfigObserver() {
        ghosttyConfigObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard notification.object == nil else { return }
            guard let config = notification.userInfo?[Notification.Name.GhosttyConfigChangeKey] as? Ghostty.Config else { return }
            Task { @MainActor [weak self] in
                self?.applyGhosttyConfig(config)
            }
        }
    }

    private func installSplitSurfaceObserver() {
        splitSurfaceObserver = NotificationCenter.default.addObserver(
            forName: Ghostty.Notification.didCreateSplitSurface,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleDidCreateSplitSurface(notification)
            }
        }
    }

    private func handleDidCreateSplitSurface(_ notification: Notification) {
        guard let newSurface = notification.object as? Ghostty.SurfaceView,
              let sourceSurface = notification.userInfo?["sourceSurface"] as? Ghostty.SurfaceView,
              let sourceRegistration = registrations[sourceSurface.id] else {
            return
        }

        registrations[newSurface.id] = sourceRegistration

        if let hostID = sourceRegistration.hostID,
           hostID != AITerminalHost.local.id,
           let host = availableHosts.first(where: { $0.id == hostID }),
           host.transport == .ssh {
            let passwordResolution = resolvedPasswordAutomation(for: host)
            if passwordResolution.error == nil {
                registerRemoteSession(
                    newSurface.id,
                    host: host,
                    savedPassword: passwordResolution.password,
                    shouldRebuild: false
                )
                recordRecentHost(host.id, status: .connected)
            }
        }

        rebuildSessions()
    }

    private func applyGhosttyConfig(_ ghosttyConfig: Ghostty.Config) {
        let reloadedConfiguration = (try? Self.loadConfiguration(at: configurationURL))
            ?? Self.configuration(from: ghosttyConfig)
        applyConfiguration(reloadedConfiguration)
        importedSSHHosts = sshConfigHostLoader()
        reconcileImportedState()
        rebuildSessions()
        syncHeartbeatRuntime()
        syncAgentRuntimeRecovery()
        syncAgentRuntimeSchedules()
    }

    private func migrateLegacyConfigurationIfNeeded() {
        guard configurationURL.lastPathComponent != Self.legacyConfigurationFilename else { return }
        guard !Self.hasManagedConfigEntries(at: configurationURL) else { return }

        let legacyURL = configurationURL
            .deletingLastPathComponent()
            .appendingPathComponent(Self.legacyConfigurationFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        guard let legacyConfiguration = try? Self.loadConfiguration(at: legacyURL) else { return }

        applyConfiguration(legacyConfiguration)
        importedSSHHosts = sshConfigHostLoader()
        let reconciled = Self.reconciledConfiguration(configuration, importedHosts: importedSSHHosts)
        applyConfiguration(reconciled)
        rebuildSessions()
        syncHeartbeatRuntime()
        syncAgentRuntimeSchedules()
        persistConfiguration()
    }

    private func applyConfiguration(_ nextConfiguration: AITerminalManagerConfiguration) {
        configuration = Self.sanitizeConfiguration(nextConfiguration)
        todoDocumentCache.removeAll()
        configurationRevision = UUID()
        bumpTodoRevision()
    }

    nonisolated private static func configuration(from config: Ghostty.Config) -> AITerminalManagerConfiguration {
        .init(
            savedHosts: decodePayloads(AITerminalHost.self, from: config.ghodexSavedHosts),
            importedHostOverrides: decodePayloads(AITerminalHost.self, from: config.ghodexImportedHostOverrides),
            favoriteHostIDs: config.ghodexFavoriteHosts,
            recentHosts: decodePayloads(AITerminalRecentHostRecord.self, from: config.ghodexRecentHosts),
            workspaces: decodePayloads(AITerminalWorkspaceTemplate.self, from: config.ghodexWorkspaces),
            savedWorkspaceTemplates: decodePayloads(AITerminalSavedWorkspaceTemplate.self, from: config.ghodexSavedWorkspaceTemplates),
            heartbeatQueueSettings: .init(
                enabled: config.ghodexHeartbeatEnabled,
                heartbeatIntervalSeconds: config.ghodexHeartbeatIntervalSeconds,
                maxConcurrentTasks: config.ghodexHeartbeatMaxConcurrentTasks,
                allowExternalInboxMutations: config.ghodexHeartbeatAllowExternalInboxMutations
            ),
            heartbeatTasks: decodePayloads(AITerminalHeartbeatTask.self, from: config.ghodexHeartbeatTasks),
            agentRuntimeSettings: .init(
                enabled: config.ghodexAgentRuntimeEnabled,
                defaultLeaseDurationSeconds: config.ghodexAgentRuntimeDefaultLeaseSeconds,
                staleTaskPolicy: AgentRuntimeStaleTaskPolicy(
                    rawValue: decodedStringValue(config.ghodexAgentRuntimeStaleTaskPolicy) ?? ""
                ) ?? .requeueClaimedWork
            ),
            agentRuntimeSessions: decodePayloads(AgentRuntimeSession.self, from: config.ghodexAgentRuntimeSessions),
            agentRuntimeTasks: decodePayloads(AgentRuntimeTask.self, from: config.ghodexAgentRuntimeTasks),
            agentRuntimeSchedules: decodePayloads(AgentRuntimeSchedule.self, from: config.ghodexAgentRuntimeSchedules),
            todoSettings: .init(
                enabled: config.ghodexTodoEnabled,
                workspaceRootPath: decodedStringValue(config.ghodexTodoWorkspaceRootPath) ?? AITerminalTodoSettings.defaultWorkspaceRootPath,
                showCompletedItems: config.ghodexTodoShowCompletedItems,
                selectedDateAnchor: decodedStringValue(config.ghodexTodoSelectedDateAnchor) ?? AITerminalTodoSettings.defaultSelectedDateAnchor,
                sidebarEdge: AITerminalTodoSidebarEdge.normalized(
                    decodedStringValue(config.ghodexTodoSidebarEdge)
                ),
                workspaceOverlayVisible: config.ghodexTodoWorkspaceOverlayVisible,
                workspaceOverlayCorner: AITerminalTodoOverlayCorner.normalized(
                    decodedStringValue(config.ghodexTodoWorkspaceOverlayCorner)
                )
            ),
            learningSettings: .init(
                enabled: config.ghodexLearningEnabled,
                preferTabWorkingDirectory: config.ghodexLearningPreferTabWorkingDirectory,
                defaultProjectPath: decodedStringValue(config.ghodexLearningDefaultProjectPath) ?? AITerminalLearningSettings.defaultLearnWorkspacePath,
                notesRelativePath: decodedStringValue(config.ghodexLearningNotesRelativePath) ?? AITerminalLearningSettings.defaultNotesRelativePath,
                commandTemplate: decodedStringValue(config.ghodexLearningCommandTemplate) ?? AITerminalLearningSettings.defaultCommandTemplate,
                fastModel: decodedStringValue(config.ghodexLearningFastModel) ?? AITerminalLearningSettings.defaultFastModel,
                promptTemplate: decodedStringValue(config.ghodexLearningPromptTemplate) ?? AITerminalLearningSettings.defaultPromptTemplate
            ),
            learningLogs: decodePayloads(AITerminalLearningLogEntry.self, from: config.ghodexLearningLogs)
        )
    }

    nonisolated private static func decodePayloads<T: Decodable>(_ type: T.Type, from values: [String]) -> [T] {
        let decoder = JSONDecoder()
        return values.compactMap { value in
            if let data = Data(base64Encoded: value),
               let decoded = try? decoder.decode(T.self, from: data) {
                return decoded
            }

            guard let data = value.data(using: .utf8) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    nonisolated private static func managedConfigBlock(for configuration: AITerminalManagerConfiguration) -> String {
        let sanitized = sanitizeConfiguration(configuration)
        var lines = [managedConfigStartMarker]
        lines.append(contentsOf: renderedConfigLines(for: sanitized))
        lines.append(managedConfigEndMarker)
        return lines.joined(separator: "\n")
    }

    nonisolated private static func renderedConfigLines(for configuration: AITerminalManagerConfiguration) -> [String] {
        var lines: [String] = []

        appendPayloadLines("ghodex-saved-host", values: configuration.savedHosts, to: &lines)
        appendPayloadLines("ghodex-imported-host-override", values: configuration.importedHostOverrides, to: &lines)
        appendStringLines("ghodex-favorite-host", values: configuration.favoriteHostIDs, to: &lines)
        appendPayloadLines("ghodex-recent-host", values: configuration.recentHosts, to: &lines)
        appendPayloadLines("ghodex-workspace", values: configuration.workspaces, to: &lines)
        appendPayloadLines("ghodex-saved-workspace-template", values: configuration.savedWorkspaceTemplates, to: &lines)
        appendPayloadLines("ghodex-heartbeat-task", values: configuration.heartbeatTasks, to: &lines)
        appendPayloadLines("ghodex-agent-runtime-session", values: configuration.agentRuntimeSessions, to: &lines)
        appendPayloadLines("ghodex-agent-runtime-task", values: configuration.agentRuntimeTasks, to: &lines)
        appendPayloadLines("ghodex-agent-runtime-schedule", values: configuration.agentRuntimeSchedules, to: &lines)
        appendPayloadLines("ghodex-learning-log", values: configuration.learningLogs, to: &lines)

        lines.append("ghodex-todo-enabled = \(configuration.todoSettings.enabled ? "true" : "false")")
        lines.append("ghodex-todo-workspace-root-path = \(configStringLiteral(encodeStringValue(configuration.todoSettings.workspaceRootPath)))")
        lines.append("ghodex-todo-show-completed-items = \(configuration.todoSettings.showCompletedItems ? "true" : "false")")
        lines.append("ghodex-todo-selected-date-anchor = \(configStringLiteral(encodeStringValue(configuration.todoSettings.selectedDateAnchor)))")
        lines.append("ghodex-todo-sidebar-edge = \(configStringLiteral(encodeStringValue(configuration.todoSettings.sidebarEdge.rawValue)))")
        lines.append("ghodex-todo-workspace-overlay-visible = \(configuration.todoSettings.workspaceOverlayVisible ? "true" : "false")")
        lines.append("ghodex-todo-workspace-overlay-corner = \(configStringLiteral(encodeStringValue(configuration.todoSettings.workspaceOverlayCorner.rawValue)))")
        lines.append("ghodex-learning-enabled = \(configuration.learningSettings.enabled ? "true" : "false")")
        lines.append("ghodex-learning-prefer-tab-working-directory = \(configuration.learningSettings.preferTabWorkingDirectory ? "true" : "false")")
        lines.append("ghodex-learning-default-project-path = \(configStringLiteral(encodeStringValue(configuration.learningSettings.defaultProjectPath)))")
        lines.append("ghodex-learning-notes-relative-path = \(configStringLiteral(encodeStringValue(configuration.learningSettings.notesRelativePath)))")
        lines.append("ghodex-learning-command-template = \(configStringLiteral(encodeStringValue(configuration.learningSettings.commandTemplate)))")
        lines.append("ghodex-learning-fast-model = \(configStringLiteral(encodeStringValue(configuration.learningSettings.fastModel)))")
        lines.append("ghodex-learning-prompt-template = \(configStringLiteral(encodeStringValue(configuration.learningSettings.promptTemplate)))")
        lines.append("ghodex-heartbeat-enabled = \(configuration.heartbeatQueueSettings.enabled ? "true" : "false")")
        lines.append("ghodex-heartbeat-interval-seconds = \(formatDouble(configuration.heartbeatQueueSettings.heartbeatIntervalSeconds))")
        lines.append("ghodex-heartbeat-max-concurrent-tasks = \(configuration.heartbeatQueueSettings.maxConcurrentTasks)")
        lines.append("ghodex-heartbeat-allow-external-inbox-mutations = \(configuration.heartbeatQueueSettings.allowExternalInboxMutations ? "true" : "false")")
        lines.append("ghodex-agent-runtime-enabled = \(configuration.agentRuntimeSettings.enabled ? "true" : "false")")
        lines.append("ghodex-agent-runtime-default-lease-seconds = \(formatDouble(configuration.agentRuntimeSettings.defaultLeaseDurationSeconds))")
        lines.append("ghodex-agent-runtime-stale-task-policy = \(configStringLiteral(encodeStringValue(configuration.agentRuntimeSettings.staleTaskPolicy.rawValue)))")

        return lines
    }

    private func ensureAgentRuntimeEnabled() throws {
        guard configuration.agentRuntimeSettings.enabled else {
            throw AgentRuntimeStoreError.runtimeDisabled
        }
    }

    private func agentRuntimeSessionIndex(sessionID: UUID) throws -> Int {
        guard let index = configuration.agentRuntimeSessions.firstIndex(where: { $0.id == sessionID }) else {
            throw AgentRuntimeStoreError.sessionNotFound(sessionID)
        }
        return index
    }

    private func activeAgentRuntimeSessionIndex(sessionID: UUID, now: Date) throws -> Int {
        let index = try agentRuntimeSessionIndex(sessionID: sessionID)
        if configuration.agentRuntimeSessions[index].isLeaseExpired(at: now) {
            throw AgentRuntimeStoreError.sessionExpired(sessionID)
        }
        switch configuration.agentRuntimeSessions[index].state {
        case .expired, .released, .failed:
            throw AgentRuntimeStoreError.sessionExpired(sessionID)
        case .booting, .active, .waitingApproval, .paused:
            return index
        }
    }

    private func expireOverlappingAgentRuntimeSessions(
        clientKind: AgentRuntimeClientKind,
        tabID: UUID?,
        terminalID: UUID?,
        hostWorkspaceID: UUID?,
        now: Date
    ) {
        for index in configuration.agentRuntimeSessions.indices {
            let session = configuration.agentRuntimeSessions[index]
            guard session.clientKind == clientKind else { continue }
            let matches = (tabID != nil && session.tabID == tabID)
                || (terminalID != nil && session.terminalID == terminalID)
                || (
                    tabID == nil
                        && terminalID == nil
                        && session.tabID == nil
                        && session.terminalID == nil
                        && hostWorkspaceID != nil
                        && session.hostWorkspaceID == hostWorkspaceID
                )
            guard matches else { continue }
            guard session.state.isLeaseManaged else { continue }

            configuration.agentRuntimeSessions[index].state = .expired
            configuration.agentRuntimeSessions[index].updatedAt = now
            configuration.agentRuntimeSessions[index].leaseExpiresAt = now
            configuration.agentRuntimeSessions[index].lastError = "superseded_by_new_registration"
            if let taskID = configuration.agentRuntimeSessions[index].currentTaskID {
                recoverAgentRuntimeTaskAfterLeaseExpiry(taskID: taskID, now: now)
                configuration.agentRuntimeSessions[index].currentTaskID = nil
            }
        }
    }

    private func recoverAgentRuntimeTaskAfterLeaseExpiry(taskID: UUID, now: Date) {
        guard let taskIndex = configuration.agentRuntimeTasks.firstIndex(where: { $0.id == taskID }) else { return }

        switch configuration.agentRuntimeTasks[taskIndex].state {
        case .claimed, .running, .paused:
            switch configuration.agentRuntimeSettings.staleTaskPolicy {
            case .requeueClaimedWork:
                configuration.agentRuntimeTasks[taskIndex].state = .queued
                configuration.agentRuntimeTasks[taskIndex].sessionID = nil
                configuration.agentRuntimeTasks[taskIndex].claimedAt = nil
            case .pauseClaimedWork:
                configuration.agentRuntimeTasks[taskIndex].state = .paused
            }
            configuration.agentRuntimeTasks[taskIndex].finishedAt = nil
            configuration.agentRuntimeTasks[taskIndex].errorSummary = "lease_expired"
        case .waitingApproval:
            configuration.agentRuntimeTasks[taskIndex].state = .paused
            configuration.agentRuntimeTasks[taskIndex].errorSummary = "lease_expired"
        case .queued, .completed, .failed, .cancelled:
            break
        }
    }

    private func projectAgentRuntimeTaskRecoveryAfterLeaseExpiry(
        taskID: UUID,
        now: Date,
        tasks: inout [AgentRuntimeTask],
        settings: AgentRuntimeSettings
    ) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return }

        switch tasks[taskIndex].state {
        case .claimed, .running, .paused:
            switch settings.staleTaskPolicy {
            case .requeueClaimedWork:
                tasks[taskIndex].state = .queued
                tasks[taskIndex].sessionID = nil
                tasks[taskIndex].claimedAt = nil
            case .pauseClaimedWork:
                tasks[taskIndex].state = .paused
            }
            tasks[taskIndex].finishedAt = nil
            tasks[taskIndex].errorSummary = "lease_expired"
        case .waitingApproval:
            tasks[taskIndex].state = .paused
            tasks[taskIndex].errorSummary = "lease_expired"
        case .queued, .completed, .failed, .cancelled:
            break
        }
    }

    private func appendAgentRuntimeEvent(
        _ event: String,
        sessionID: UUID? = nil,
        taskID: UUID? = nil,
        details: [String: String] = [:]
    ) {
        struct AgentRuntimeEventRecord: Encodable {
            let timestamp: String
            let event: String
            let sessionID: String?
            let taskID: String?
            let details: [String: String]
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: agentRuntimeEventsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let record = AgentRuntimeEventRecord(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                event: event,
                sessionID: sessionID?.uuidString.lowercased(),
                taskID: taskID?.uuidString.lowercased(),
                details: details
            )
            var line = try JSONEncoder().encode(record)
            line.append(0x0A)
            if fileManager.fileExists(atPath: agentRuntimeEventsURL.path) {
                let handle = try FileHandle(forWritingTo: agentRuntimeEventsURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: agentRuntimeEventsURL, options: .atomic)
            }
        } catch {
            RuntimeDiagnosticsLogger.log(
                component: "agent_runtime",
                event: "event_log_failure",
                details: [
                    "log_path": agentRuntimeEventsURL.path,
                    "error": error.localizedDescription,
                ]
            )
        }
    }

    nonisolated private static func appendPayloadLines<T: Encodable>(
        _ key: String,
        values: [T],
        to lines: inout [String]
    ) {
        for value in values {
            guard let payload = encodedPayload(value) else { continue }
            lines.append("\(key) = \(configStringLiteral(payload))")
        }
    }

    nonisolated private static func appendStringLines(
        _ key: String,
        values: [String],
        to lines: inout [String]
    ) {
        for value in values {
            lines.append("\(key) = \(configStringLiteral(value))")
        }
    }

    private func todoDocumentPath(forDayString dayString: String) -> String {
        URL(fileURLWithPath: configuration.todoSettings.workspaceRootPath, isDirectory: true)
            .appendingPathComponent("days", isDirectory: true)
            .appendingPathComponent("\(AITerminalTodoSettings.normalizedDateAnchor(dayString)).json", isDirectory: false)
            .path
    }

    private func cacheTodoDocument(_ document: AITerminalTodoDayDocument) {
        let now = Date()
        pruneTodoDocumentCache(now: now)
        let path = todoDocumentPath(forDayString: document.date)
        todoDocumentCache[todoDocumentCacheKey(for: path)] = .init(
            document: document,
            cachedAt: now,
            lastAccessedAt: now
        )
        pruneTodoDocumentCache(now: now)
    }

    private func rawTodoDocument(forDayString dayString: String) throws -> AITerminalTodoDayDocument {
        let now = Date()
        pruneTodoDocumentCache(now: now)
        let normalizedDayString = AITerminalTodoSettings.normalizedDateAnchor(dayString)
        let path = todoDocumentPath(forDayString: normalizedDayString)
        let cacheKey = todoDocumentCacheKey(for: path)
        if var cached = todoDocumentCache[cacheKey] {
            if now.timeIntervalSince(cached.cachedAt) <= Self.todoDocumentCacheTTLSeconds {
                cached.lastAccessedAt = now
                todoDocumentCache[cacheKey] = cached
                return cached.document
            }
            todoDocumentCache.removeValue(forKey: cacheKey)
        }

        let document = try Self.loadTodoDocument(at: path, date: normalizedDayString)
        todoDocumentCache[cacheKey] = .init(
            document: document,
            cachedAt: now,
            lastAccessedAt: now
        )
        pruneTodoDocumentCache(now: now)
        return document
    }

    private func pruneTodoDocumentCache(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Self.todoDocumentCacheTTLSeconds)
        var removedByTTL = 0
        for (key, entry) in todoDocumentCache where entry.lastAccessedAt < cutoff {
            todoDocumentCache.removeValue(forKey: key)
            removedByTTL += 1
        }

        let overflowCount = todoDocumentCache.count - Self.todoDocumentCacheMaxEntries
        guard overflowCount > 0 else {
            if removedByTTL > 0 {
                RuntimeDiagnosticsLogger.log(
                    component: "ai_manager.todo_document_cache",
                    event: "prune",
                    details: [
                        "removed_ttl": "\(removedByTTL)",
                        "removed_capacity": "0",
                        "remaining": "\(todoDocumentCache.count)",
                    ]
                )
            }
            return
        }

        let evictionKeys = todoDocumentCache
            .sorted { lhs, rhs in
                if lhs.value.lastAccessedAt != rhs.value.lastAccessedAt {
                    return lhs.value.lastAccessedAt < rhs.value.lastAccessedAt
                }
                return lhs.key < rhs.key
            }
            .prefix(overflowCount)
            .map(\.key)
        for key in evictionKeys {
            todoDocumentCache.removeValue(forKey: key)
        }
        RuntimeDiagnosticsLogger.log(
            component: "ai_manager.todo_document_cache",
            event: "prune",
            details: [
                "removed_ttl": "\(removedByTTL)",
                "removed_capacity": "\(evictionKeys.count)",
                "remaining": "\(todoDocumentCache.count)",
            ]
        )
    }

    private func refreshedTodoDocument(_ document: AITerminalTodoDayDocument) -> AITerminalTodoDayDocument {
        var refreshed = document

        for index in refreshed.items.indices {
            guard let sourceReference = refreshed.items[index].sourceItem,
                  let resolvedSource = resolvedTodoSourceState(for: sourceReference) else {
                continue
            }

            refreshed.items[index] = .init(
                sourceItem: resolvedSource.reference,
                id: refreshed.items[index].id,
                title: resolvedSource.item.title,
                notes: resolvedSource.item.notes,
                assignedWorkspaceID: resolvedSource.item.assignedWorkspaceID,
                isCompleted: resolvedSource.item.isCompleted,
                completedAt: resolvedSource.item.completedAt,
                createdAt: resolvedSource.item.createdAt,
                updatedAt: resolvedSource.item.updatedAt,
                sortOrder: refreshed.items[index].sortOrder
            )
        }

        return refreshed
    }

    private func resolvedTodoSourceState(
        for reference: AITerminalTodoSourceReference,
        visited: Set<String> = []
    ) -> ResolvedTodoSourceState? {
        let visitKey = todoSourceReferenceKey(reference)
        guard !visited.contains(visitKey) else { return nil }

        guard let sourceDocument = try? rawTodoDocument(forDayString: reference.day),
              let sourceItem = sourceDocument.items.first(where: { $0.id == reference.itemID }) else {
            return nil
        }

        if let nestedReference = sourceItem.sourceItem,
           let resolvedNested = resolvedTodoSourceState(
                for: nestedReference,
                visited: visited.union([visitKey])
           ) {
            return resolvedNested
        }

        return .init(reference: reference, item: sourceItem)
    }

    private func resolvedTodoMutationTarget(
        for id: UUID,
        on dayString: String
    ) -> AITerminalTodoSourceReference? {
        guard let item = try? rawTodoDocument(forDayString: dayString).items.first(where: { $0.id == id }) else {
            return nil
        }

        if let sourceReference = item.sourceItem {
            return resolvedTodoSourceState(for: sourceReference)?.reference ?? sourceReference
        }

        return .init(day: dayString, itemID: id)
    }

    private func staleTodoSyncCandidates(into dayString: String) throws -> [TodoSyncCandidate] {
        let normalizedDayString = AITerminalTodoSettings.normalizedDateAnchor(dayString)
        let destinationDocument = try rawTodoDocument(forDayString: normalizedDayString)
        var existingReferences = Set(
            destinationDocument.items.compactMap { $0.sourceItem.map(todoSourceReferenceKey) }
        )
        var candidates: [TodoSyncCandidate] = []

        for url in try todoDayFileURLs(before: normalizedDayString) {
            let sourceDayString = url.deletingPathExtension().lastPathComponent
            let sourceDocument = try rawTodoDocument(forDayString: sourceDayString)

            for item in sourceDocument.orderedItems where !item.isCompleted {
                let resolvedSource: ResolvedTodoSourceState
                if let sourceReference = item.sourceItem,
                   let resolved = resolvedTodoSourceState(for: sourceReference) {
                    resolvedSource = resolved
                } else {
                    resolvedSource = .init(
                        reference: .init(day: sourceDayString, itemID: item.id),
                        item: item
                    )
                }

                let referenceKey = todoSourceReferenceKey(resolvedSource.reference)
                if existingReferences.contains(referenceKey) || resolvedSource.item.isCompleted {
                    continue
                }
                existingReferences.insert(referenceKey)
                candidates.append(.init(reference: resolvedSource.reference, item: resolvedSource.item))
            }
        }

        return candidates
    }

    private func todoDayFileURLs(before dayString: String) throws -> [URL] {
        let daysURL = URL(fileURLWithPath: configuration.todoSettings.workspaceRootPath, isDirectory: true)
            .appendingPathComponent("days", isDirectory: true)
        guard FileManager.default.fileExists(atPath: daysURL.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: daysURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .filter { $0.deletingPathExtension().lastPathComponent < dayString }
        .sorted { lhs, rhs in
            lhs.deletingPathExtension().lastPathComponent < rhs.deletingPathExtension().lastPathComponent
        }
    }

    private func todoSourceReferenceKey(_ reference: AITerminalTodoSourceReference) -> String {
        "\(reference.day)#\(reference.itemID.uuidString.lowercased())"
    }

    private func mutateTodoDocument(
        for date: Date,
        mutation: (inout AITerminalTodoDayDocument) -> Void
    ) -> AITerminalTodoDayDocument? {
        do {
            let dayString = AITerminalTodoSettings.dayString(from: date)
            let path = todoDocumentPath(forDayString: dayString)
            var document = try rawTodoDocument(forDayString: dayString)
            let original = document
            mutation(&document)
            guard document != original else {
                cacheTodoDocument(document)
                lastError = nil
                return document
            }
            document.updatedAt = .now
            cacheTodoDocument(document)
            if Self.isRunningTests {
                try Self.saveTodoDocument(document, to: path)
            } else {
                enqueueTodoDocumentSave(document, to: path)
            }
            bumpTodoRevision()
            lastError = nil
            return document
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func todoDocumentSnapshot(for date: Date) -> AITerminalTodoDayDocument {
        let dayString = AITerminalTodoSettings.dayString(from: date)

        do {
            // Keep read-only snapshot queries side-effect free because SwiftUI
            // views call them during body evaluation.
            let document = try rawTodoDocument(forDayString: dayString)
            let refreshed = refreshedTodoDocument(document)
            cacheTodoDocument(refreshed)
            return refreshed
        } catch {
            return .init(date: AITerminalTodoSettings.normalizedDateAnchor(dayString))
        }
    }

    private func bumpTodoRevision() {
        todoRevision = UUID()
        NotificationCenter.default.post(name: .ghodexTodoStateDidChange, object: self)
    }

    private func enqueueTodoDocumentSave(_ document: AITerminalTodoDayDocument, to path: String) {
        let persistence = todoDocumentPersistence
        Task(priority: .utility) { [weak self] in
            await persistence.scheduleSave(
                document: document,
                to: path,
                writer: { document, path in
                    try Self.saveTodoDocument(document, to: path)
                },
                onError: { error in
                    await MainActor.run {
                        self?.lastError = error.localizedDescription
                    }
                }
            )
        }
    }

    private func todoDocumentCacheKey(for path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL.path
    }

    nonisolated private static func encodedPayload<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return data.base64EncodedString()
    }

    nonisolated private static func encodeStringValue(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    nonisolated private static func decodedStringValue(_ value: String?) -> String? {
        guard let value else { return nil }
        if let data = Data(base64Encoded: value),
           let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return value
    }

    nonisolated private static func configStringLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
        guard
            let data,
            let encoded = String(data: data, encoding: .utf8),
            encoded.count >= 2
        else {
            return "\"\""
        }

        let start = encoded.index(after: encoded.startIndex)
        let end = encoded.index(before: encoded.endIndex)
        return String(encoded[start..<end])
    }

    nonisolated private static func createTodoWorkspaceScaffold(rootPath: String) throws -> TodoWorkspaceBootstrapResult {
        let expandedPath = NSString(string: rootPath).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
        let daysURL = rootURL.appendingPathComponent("days", isDirectory: true)
        let readmeURL = rootURL.appendingPathComponent("README.md", isDirectory: false)
        let creatorURL = rootURL.appendingPathComponent("creator.md", isDirectory: false)

        var createdFileCount = 0
        var reusedFileCount = 0

        let daysExisted = FileManager.default.fileExists(atPath: daysURL.path)
        try FileManager.default.createDirectory(at: daysURL, withIntermediateDirectories: true)
        if daysExisted {
            reusedFileCount += 1
        } else {
            createdFileCount += 1
        }

        let readme = """
        # GhoDex Todo Workspace

        Daily todo files live under `days/YYYY-MM-DD.json`.
        """
        try writeTextFileIfMissing(
            readme,
            to: readmeURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )

        let creator = """
        # creator

        ## Why this folder exists
        This workspace stores daily GhoDex todo files in a user-visible location.

        ## Created by
        GhoDex todo workspace scaffold

        ## Creation date
        \(AITerminalTodoSettings.dayString(from: .now))

        ## Scope
        - Store date-based todo files under `days/`.
        - Keep task state human-visible and editable.
        """
        try writeTextFileIfMissing(
            creator,
            to: creatorURL,
            createdFileCount: &createdFileCount,
            reusedFileCount: &reusedFileCount
        )

        return .init(
            workspaceRootPath: rootURL.path,
            createdFileCount: createdFileCount,
            reusedFileCount: reusedFileCount
        )
    }

    nonisolated private static func loadTodoDocument(
        at path: String,
        date: String
    ) throws -> AITerminalTodoDayDocument {
        let url = URL(fileURLWithPath: path, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .init(date: date)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        var document = try decoder.decode(AITerminalTodoDayDocument.self, from: data)
        document.date = AITerminalTodoSettings.normalizedDateAnchor(document.date)
        return document
    }

    nonisolated private static func saveTodoDocument(
        _ document: AITerminalTodoDayDocument,
        to path: String
    ) throws {
        let url = URL(fileURLWithPath: path, isDirectory: false)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func formatDouble(_ value: Double) -> String {
        var rendered = String(value)
        if rendered.contains(".") {
            while rendered.hasSuffix("0") {
                rendered.removeLast()
            }
            if rendered.hasSuffix(".") {
                rendered.removeLast()
            }
        }
        return rendered
    }

    nonisolated private static func stripManagedConfig(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var isInsideManagedBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == managedConfigStartMarker {
                isInsideManagedBlock = true
                continue
            }

            if trimmed == managedConfigEndMarker {
                isInsideManagedBlock = false
                continue
            }

            if isInsideManagedBlock {
                continue
            }

            if trimmed.hasPrefix("ghodex-") {
                continue
            }

            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    nonisolated private static func managedBooleanValue(for key: String, in text: String?) -> Bool? {
        guard let rawValue = managedValue(for: key, in: text) else { return nil }
        switch rawValue.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    nonisolated private static func managedValue(for key: String, in text: String?) -> String? {
        guard let text else { return nil }
        let prefix = "\(key) ="
        var isInsideManagedBlock = false
        var lastValue: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == managedConfigStartMarker {
                isInsideManagedBlock = true
                continue
            }
            if trimmed == managedConfigEndMarker {
                isInsideManagedBlock = false
                continue
            }

            guard isInsideManagedBlock || trimmed.hasPrefix("ghodex-") else { continue }
            guard trimmed.hasPrefix(prefix) else { continue }
            lastValue = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        return lastValue
    }

    nonisolated private static func managedValues(for key: String, in text: String?) -> [String]? {
        guard let text else { return nil }
        let prefix = "\(key) ="
        var isInsideManagedBlock = false
        var values: [String] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == managedConfigStartMarker {
                isInsideManagedBlock = true
                continue
            }
            if trimmed == managedConfigEndMarker {
                isInsideManagedBlock = false
                continue
            }

            guard isInsideManagedBlock || trimmed.hasPrefix("ghodex-") else { continue }
            guard trimmed.hasPrefix(prefix) else { continue }
            let rawValue = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            values.append(decodedConfigStringLiteral(rawValue))
        }

        return values.isEmpty ? nil : values
    }

    nonisolated private static func decodeManagedPayloads<T: Decodable>(
        _ type: T.Type,
        for key: String,
        in text: String?
    ) -> [T]? {
        guard let values = managedValues(for: key, in: text) else { return nil }
        return decodePayloads(T.self, from: values)
    }

    nonisolated private static func decodedConfigStringLiteral(_ value: String) -> String {
        guard value.first == "\"", value.last == "\"" else { return value }
        let data = Data("[\(value)]".utf8)
        guard
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String],
              let first = decoded.first else {
            return value
        }
        return first
    }

    nonisolated private static func hasManagedConfigEntries(at url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        if text.contains(managedConfigStartMarker) || text.contains(managedConfigEndMarker) {
            return true
        }

        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { $0.hasPrefix("ghodex-") }
    }
}
