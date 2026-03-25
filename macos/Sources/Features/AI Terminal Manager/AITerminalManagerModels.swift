import Foundation
import GhoDexKit

enum AITerminalManagedState: String, Codable, CaseIterable, Sendable {
    case manual
    case observed
    case managedActive = "managed_active"
    case managedWaitingApproval = "managed_waiting_approval"
    case managedPaused = "managed_paused"
    case managedCompleted = "managed_completed"
    case managedFailed = "managed_failed"

    var displayName: String {
        switch self {
        case .manual: L10n.AITerminalManager.manual
        case .observed: L10n.AITerminalManager.observed
        case .managedActive: L10n.AITerminalManager.managed
        case .managedWaitingApproval: L10n.AITerminalManager.awaitingApproval
        case .managedPaused: L10n.AITerminalManager.paused
        case .managedCompleted: L10n.AITerminalManager.completed
        case .managedFailed: L10n.AITerminalManager.failed
        }
    }
}

enum AITerminalLaunchTarget: String, CaseIterable, Identifiable {
    case tab
    case window

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tab: L10n.AITerminalManager.newTab
        case .window: L10n.AITerminalManager.newWindow
        }
    }
}

enum AITerminalHostSource: String, Codable, Sendable {
    case builtIn = "built_in"
    case configurationFile = "configuration_file"
    case sshConfig = "ssh_config"

    var isUserManaged: Bool {
        switch self {
        case .builtIn, .sshConfig:
            false
        case .configurationFile:
            true
        }
    }
}

enum AITerminalTransport: String, Codable, Sendable {
    case local
    case localmcd
    case ssh
}

enum AITerminalHostAuthMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case password

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: L10n.SSHConnections.authModeSystem
        case .password: L10n.SSHConnections.authModePassword
        }
    }
}

struct AITerminalHost: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var transport: AITerminalTransport
    var startupCommands: [String]
    var sshAlias: String?
    var hostname: String?
    var user: String?
    var port: Int?
    var defaultDirectory: String?
    var source: AITerminalHostSource
    var authMode: AITerminalHostAuthMode

    init(
        id: String,
        name: String,
        transport: AITerminalTransport,
        startupCommands: [String] = [],
        sshAlias: String?,
        hostname: String?,
        user: String?,
        port: Int?,
        defaultDirectory: String?,
        source: AITerminalHostSource,
        authMode: AITerminalHostAuthMode = .system
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.startupCommands = startupCommands
        self.sshAlias = sshAlias
        self.hostname = hostname
        self.user = user
        self.port = port
        self.defaultDirectory = defaultDirectory
        self.source = source
        self.authMode = authMode
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case transport
        case startupCommands
        case sshAlias
        case hostname
        case user
        case port
        case defaultDirectory
        case source
        case authMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        transport = try container.decode(AITerminalTransport.self, forKey: .transport)
        startupCommands = try container.decodeIfPresent([String].self, forKey: .startupCommands) ?? []
        sshAlias = try container.decodeIfPresent(String.self, forKey: .sshAlias)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        user = try container.decodeIfPresent(String.self, forKey: .user)
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        defaultDirectory = try container.decodeIfPresent(String.self, forKey: .defaultDirectory)
        source = try container.decode(AITerminalHostSource.self, forKey: .source)
        authMode = try container.decodeIfPresent(AITerminalHostAuthMode.self, forKey: .authMode) ?? .system
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(transport, forKey: .transport)
        try container.encode(startupCommands, forKey: .startupCommands)
        try container.encodeIfPresent(sshAlias, forKey: .sshAlias)
        try container.encodeIfPresent(hostname, forKey: .hostname)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encodeIfPresent(defaultDirectory, forKey: .defaultDirectory)
        try container.encode(source, forKey: .source)
        try container.encode(authMode, forKey: .authMode)
    }

    static let local = AITerminalHost(
        id: "local",
        name: L10n.AITerminalManager.thisMac,
        transport: .local,
        startupCommands: [],
        sshAlias: nil,
        hostname: nil,
        user: nil,
        port: nil,
        defaultDirectory: nil,
        source: .builtIn,
        authMode: .system
    )

    var isLocal: Bool { transport == .local }

    var displaySubtitle: String {
        switch transport {
        case .local:
            return defaultDirectory ?? L10n.AITerminalManager.localShell
        case .localmcd:
            if startupCommands.isEmpty {
                return defaultDirectory ?? L10n.AITerminalManager.localShell
            }
            return startupCommands.joined(separator: "  •  ")
        case .ssh:
            var parts: [String] = []
            if let sshAlias, !sshAlias.isEmpty {
                parts.append(sshAlias)
            }
            if let hostname, !hostname.isEmpty, hostname != sshAlias {
                parts.append(hostname)
            }
            if let user, !user.isEmpty {
                parts.append(user)
            }
            if let port = port {
                parts.append(":\(port)")
            }
            if let defaultDirectory, !defaultDirectory.isEmpty {
                parts.append(defaultDirectory)
            }
            return parts.joined(separator: " • ")
        }
    }

    var connectionTarget: String? {
        if let sshAlias, !sshAlias.isEmpty {
            return sshAlias
        }
        guard let hostname, !hostname.isEmpty else { return nil }
        if let user, !user.isEmpty {
            return "\(user)@\(hostname)"
        }
        return hostname
    }

    static func stableID(
        existingID: String? = nil,
        sshAlias: String,
        hostname: String,
        user: String
    ) -> String {
        if let existingID, !existingID.isEmpty {
            return existingID
        }

        let trimmedAlias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAlias.isEmpty {
            return "ssh:\(trimmedAlias)"
        }

        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let stableKey = trimmedUser.isEmpty ? trimmedHostname : "\(trimmedUser)@\(trimmedHostname)"
        return "configured:\(stableKey)"
    }
}

struct AITerminalRecentHostRecord: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case connected
        case failed
    }

    let id: String
    var connectedAt: Date
    var status: Status
    var errorSummary: String?

    init(
        id: String,
        connectedAt: Date = .now,
        status: Status,
        errorSummary: String? = nil
    ) {
        self.id = id
        self.connectedAt = connectedAt
        self.status = status
        self.errorSummary = errorSummary
    }
}

struct AITerminalWorkspaceTemplate: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var hostID: String
    var directory: String
}

enum AITerminalSavedWorkspaceSplitDirection: String, Codable, Hashable, Sendable {
    case horizontal
    case vertical
}

struct AITerminalSavedWorkspaceTab: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var hostID: String
    var directory: String?

    init(
        id: String = "workspace-tab:\(UUID().uuidString)",
        hostID: String,
        directory: String? = nil
    ) {
        self.id = id
        self.hostID = hostID
        self.directory = directory
    }
}

struct AITerminalSavedWorkspacePane: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var tabs: [AITerminalSavedWorkspaceTab]
    var activeTabIndex: Int

    init(
        id: String = "workspace-pane:\(UUID().uuidString)",
        tabs: [AITerminalSavedWorkspaceTab],
        activeTabIndex: Int = 0
    ) {
        self.id = id
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
    }

    var normalizedActiveTabIndex: Int {
        guard !tabs.isEmpty else { return 0 }
        return min(max(activeTabIndex, 0), tabs.count - 1)
    }
}

indirect enum AITerminalSavedWorkspaceNode: Codable, Hashable, Sendable {
    case pane(AITerminalSavedWorkspacePane)
    case split(Split)

    struct Split: Codable, Hashable, Sendable {
        var direction: AITerminalSavedWorkspaceSplitDirection
        var ratio: Double
        var left: AITerminalSavedWorkspaceNode
        var right: AITerminalSavedWorkspaceNode
    }

    var paneCount: Int {
        switch self {
        case .pane:
            return 1
        case .split(let split):
            return split.left.paneCount + split.right.paneCount
        }
    }

    var tabCount: Int {
        switch self {
        case .pane(let pane):
            return pane.tabs.count
        case .split(let split):
            return split.left.tabCount + split.right.tabCount
        }
    }
}

struct AITerminalSavedWorkspaceTemplate: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var root: AITerminalSavedWorkspaceNode
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "saved-workspace:\(UUID().uuidString)",
        name: String,
        root: AITerminalSavedWorkspaceNode,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.root = root
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var paneCount: Int { root.paneCount }
    var tabCount: Int { root.tabCount }
}

enum AITerminalHeartbeatTaskType: String, Codable, CaseIterable, Sendable {
    case exec
    case script
}

enum AITerminalHeartbeatTaskStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case done
    case failed
    case cancelled
}

struct AITerminalHeartbeatTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var command: String
    var type: AITerminalHeartbeatTaskType
    var executeAt: Date
    var createdAt: Date
    var updatedAt: Date
    var status: AITerminalHeartbeatTaskStatus
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        command: String,
        type: AITerminalHeartbeatTaskType = .exec,
        executeAt: Date,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        status: AITerminalHeartbeatTaskStatus = .queued,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.command = command
        self.type = type
        self.executeAt = executeAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.errorMessage = errorMessage
    }
}

struct AITerminalHeartbeatQueueSettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var heartbeatIntervalSeconds: Double
    var maxConcurrentTasks: Int

    init(
        enabled: Bool = true,
        heartbeatIntervalSeconds: Double = 5,
        maxConcurrentTasks: Int = 4
    ) {
        self.enabled = enabled
        self.heartbeatIntervalSeconds = heartbeatIntervalSeconds
        self.maxConcurrentTasks = maxConcurrentTasks
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case heartbeatIntervalSeconds
        case maxConcurrentTasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        heartbeatIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .heartbeatIntervalSeconds) ?? 5
        maxConcurrentTasks = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentTasks) ?? 4
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(heartbeatIntervalSeconds, forKey: .heartbeatIntervalSeconds)
        try container.encode(maxConcurrentTasks, forKey: .maxConcurrentTasks)
    }
}

enum AITerminalTodoSidebarEdge: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case leading
    case trailing

    var id: String { rawValue }

    static func normalized(_ value: String?) -> Self {
        guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let edge = Self(rawValue: rawValue) else {
            return .leading
        }
        return edge
    }
}

enum AITerminalTodoOverlayCorner: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case topLeading = "top-leading"
    case topTrailing = "top-trailing"
    case bottomLeading = "bottom-leading"
    case bottomTrailing = "bottom-trailing"

    var id: String { rawValue }

    static func normalized(_ value: String?) -> Self {
        guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let corner = Self(rawValue: rawValue) else {
            return .topLeading
        }
        return corner
    }
}

struct AITerminalTodoSettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var workspaceRootPath: String
    var showCompletedItems: Bool
    var selectedDateAnchor: String
    var sidebarEdge: AITerminalTodoSidebarEdge
    var workspaceOverlayVisible: Bool
    var workspaceOverlayCorner: AITerminalTodoOverlayCorner

    static let workspaceDirectoryName = "gho_todolist_workspace"
    static var defaultWorkspaceRootPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("LeonProjects", isDirectory: true)
            .appendingPathComponent("gho_workspace", isDirectory: true)
            .appendingPathComponent(workspaceDirectoryName, isDirectory: true)
            .path
    }
    static let dayFilenameFormatter = ISO8601DateFormatter.todoDayFormatter
    static let defaultSelectedDateAnchor = dayFilenameFormatter.string(from: .now)

    init(
        enabled: Bool = true,
        workspaceRootPath: String = AITerminalTodoSettings.defaultWorkspaceRootPath,
        showCompletedItems: Bool = true,
        selectedDateAnchor: String = AITerminalTodoSettings.defaultSelectedDateAnchor,
        sidebarEdge: AITerminalTodoSidebarEdge = .leading,
        workspaceOverlayVisible: Bool = false,
        workspaceOverlayCorner: AITerminalTodoOverlayCorner = .topLeading
    ) {
        self.enabled = enabled
        self.workspaceRootPath = workspaceRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.showCompletedItems = showCompletedItems
        self.selectedDateAnchor = Self.normalizedDateAnchor(selectedDateAnchor)
        self.sidebarEdge = sidebarEdge
        self.workspaceOverlayVisible = workspaceOverlayVisible
        self.workspaceOverlayCorner = workspaceOverlayCorner
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case workspaceRootPath
        case showCompletedItems
        case selectedDateAnchor
        case sidebarEdge
        case workspaceOverlayVisible
        case workspaceOverlayCorner
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        workspaceRootPath = (
            try container.decodeIfPresent(String.self, forKey: .workspaceRootPath)
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.defaultWorkspaceRootPath
        showCompletedItems = try container.decodeIfPresent(Bool.self, forKey: .showCompletedItems) ?? true
        selectedDateAnchor = Self.normalizedDateAnchor(
            try container.decodeIfPresent(String.self, forKey: .selectedDateAnchor)
            ?? Self.defaultSelectedDateAnchor
        )
        sidebarEdge = try container.decodeIfPresent(
            AITerminalTodoSidebarEdge.self,
            forKey: .sidebarEdge
        ) ?? .leading
        workspaceOverlayVisible = try container.decodeIfPresent(
            Bool.self,
            forKey: .workspaceOverlayVisible
        ) ?? false
        workspaceOverlayCorner = try container.decodeIfPresent(
            AITerminalTodoOverlayCorner.self,
            forKey: .workspaceOverlayCorner
        ) ?? .topLeading
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(workspaceRootPath, forKey: .workspaceRootPath)
        try container.encode(showCompletedItems, forKey: .showCompletedItems)
        try container.encode(selectedDateAnchor, forKey: .selectedDateAnchor)
        try container.encode(sidebarEdge, forKey: .sidebarEdge)
        try container.encode(workspaceOverlayVisible, forKey: .workspaceOverlayVisible)
        try container.encode(workspaceOverlayCorner, forKey: .workspaceOverlayCorner)
    }

    static func normalizedDateAnchor(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = dayFilenameFormatter.date(from: trimmed) else {
            return defaultSelectedDateAnchor
        }
        return dayFilenameFormatter.string(from: parsed)
    }

    static func date(fromDayString value: String) -> Date? {
        dayFilenameFormatter.date(from: normalizedDateAnchor(value))
    }

    static func dayString(from date: Date) -> String {
        dayFilenameFormatter.string(from: date)
    }

    func dayFilePath(for date: Date) -> String {
        URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
            .appendingPathComponent("days", isDirectory: true)
            .appendingPathComponent("\(Self.dayString(from: date)).json", isDirectory: false)
            .path
    }
}

struct AITerminalTodoItem: Identifiable, Codable, Hashable, Sendable {
    var sourceItem: AITerminalTodoSourceReference?
    let id: UUID
    var title: String
    var notes: String
    var assignedWorkspaceID: UUID?
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    init(
        sourceItem: AITerminalTodoSourceReference? = nil,
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        assignedWorkspaceID: UUID? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sortOrder: Int = 0
    ) {
        self.sourceItem = sourceItem
        self.id = id
        self.title = title
        self.notes = notes
        self.assignedWorkspaceID = assignedWorkspaceID
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    var isCarryForwardPointer: Bool {
        sourceItem != nil
    }
}

struct AITerminalTodoSourceReference: Codable, Hashable, Sendable {
    var day: String
    var itemID: UUID

    init(day: String, itemID: UUID) {
        self.day = AITerminalTodoSettings.normalizedDateAnchor(day)
        self.itemID = itemID
    }
}

struct AITerminalTodoDayDocument: Codable, Hashable, Sendable {
    var date: String
    var updatedAt: Date
    var items: [AITerminalTodoItem]

    init(
        date: String = AITerminalTodoSettings.defaultSelectedDateAnchor,
        updatedAt: Date = .now,
        items: [AITerminalTodoItem] = []
    ) {
        self.date = AITerminalTodoSettings.normalizedDateAnchor(date)
        self.updatedAt = updatedAt
        self.items = items
    }

    var completionRate: Double {
        guard !items.isEmpty else { return 0 }
        let completedCount = items.filter(\.isCompleted).count
        return Double(completedCount) / Double(items.count)
    }

    var orderedItems: [AITerminalTodoItem] {
        items.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

struct AITerminalTodoWorkspaceTarget: Identifiable, Hashable, Sendable {
    let workspaceID: UUID
    var title: String
    var subtitle: String
    var isFocused: Bool

    var id: UUID { workspaceID }
}

struct AITerminalTodoWorkspaceProgressSummary: Hashable, Sendable {
    let workspaceID: UUID
    var completedCount: Int
    var totalCount: Int

    var completionRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var remainingCount: Int {
        max(totalCount - completedCount, 0)
    }
}

struct AITerminalLearningSettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var preferTabWorkingDirectory: Bool
    var defaultProjectPath: String
    var notesRelativePath: String
    var commandTemplate: String
    var fastModel: String
    var promptTemplate: String

    static let chatWorkspaceDirectoryName = "codex_chat_workspace"
    static let learnWorkspaceDirectoryName = "codex_learn_workspace"
    static var defaultChatWorkspacePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(chatWorkspaceDirectoryName, isDirectory: true)
            .path
    }
    static var defaultLearnWorkspacePath: String {
        learnWorkspacePath(fromChatWorkspacePath: defaultChatWorkspacePath)
    }
    static let defaultNotesRelativePath = "../knowledges/inbox.md"
    static let defaultCommandTemplate = #"/Users/leongong/.local/bin/codex1m exec --skip-git-repo-check -c 'mcp_servers.gemini.enabled=false' -c 'mcp_servers.grok-research.enabled=false' -c 'mcp_servers.opus-planning.enabled=false' -C "$LEARN_WORKSPACE" "$PROMPT""#
    static let defaultFastModel = "gpt-5-codex"
    static let defaultPromptTemplate = #"""
请执行“原文保真整理”。
严格规则：
1) 仅输出 Markdown 列表，每行以“- ”开头。
2) 每条必须直接摘录原文，不得改写、扩写、推断、补充、联想。
3) 不要输出标题、解释或任何额外文本。
$SELECTION
"""#

    static let supportedPlaceholders = [
        "$PROMPT",
        "$SELECTION",
        "$LEARN_WORKSPACE",
        "$PROJECT_PATH",
    ]

    static func learnWorkspacePath(fromChatWorkspacePath chatWorkspacePath: String) -> String {
        URL(fileURLWithPath: chatWorkspacePath, isDirectory: true)
            .appendingPathComponent(learnWorkspaceDirectoryName, isDirectory: true)
            .path
    }

    static func chatWorkspacePath(fromLearnWorkspacePath learnWorkspacePath: String) -> String {
        let trimmed = learnWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var url = URL(fileURLWithPath: trimmed, isDirectory: true)
        if url.lastPathComponent == learnWorkspaceDirectoryName {
            url.deleteLastPathComponent()
        }
        return url.path
    }

    static func normalizedCommandTemplate(_ commandTemplate: String) -> String {
        let trimmed = commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultCommandTemplate }
        guard !trimmed.contains("--skip-git-repo-check") else { return trimmed }

        let absoluteMarker = "/Users/leongong/.local/bin/codex1m exec"
        if trimmed.contains(absoluteMarker) {
            return trimmed.replacingOccurrences(
                of: absoluteMarker,
                with: "\(absoluteMarker) --skip-git-repo-check",
                options: [],
                range: trimmed.range(of: absoluteMarker)
            )
        }

        let genericMarker = "codex1m exec"
        if trimmed.contains(genericMarker) {
            return trimmed.replacingOccurrences(
                of: genericMarker,
                with: "\(genericMarker) --skip-git-repo-check",
                options: [],
                range: trimmed.range(of: genericMarker)
            )
        }

        return trimmed
    }

    struct ResolvedContext: Hashable, Sendable {
        var commandTemplate: String
        var fastModel: String
        var prompt: String
        var selection: String
        var projectPath: String
        var notesRelativePath: String
        var notesAbsolutePath: String
        var tabWorkingDirectory: String

        var environmentVariables: [String: String] {
            [
                "MODEL": fastModel,
                "PROMPT": prompt,
                "SELECTION": selection,
                "PROJECT_PATH": projectPath,
                "LEARN_WORKSPACE": projectPath,
                "NOTES_RELATIVE_PATH": notesRelativePath,
                "NOTES_ABSOLUTE_PATH": notesAbsolutePath,
                "TAB_WORKING_DIRECTORY": tabWorkingDirectory,
            ]
        }
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case preferTabWorkingDirectory
        case defaultProjectPath
        case notesRelativePath
        case commandTemplate
        case fastModel
        case promptTemplate

        // Legacy keys from schemaVersion 3.
        case codexCommand
        case codexModel
    }

    init(
        enabled: Bool = true,
        preferTabWorkingDirectory: Bool = true,
        defaultProjectPath: String = AITerminalLearningSettings.defaultLearnWorkspacePath,
        notesRelativePath: String = AITerminalLearningSettings.defaultNotesRelativePath,
        commandTemplate: String = AITerminalLearningSettings.defaultCommandTemplate,
        fastModel: String = AITerminalLearningSettings.defaultFastModel,
        promptTemplate: String = AITerminalLearningSettings.defaultPromptTemplate
    ) {
        self.enabled = enabled
        self.preferTabWorkingDirectory = preferTabWorkingDirectory
        self.defaultProjectPath = defaultProjectPath
        self.notesRelativePath = notesRelativePath
        self.commandTemplate = Self.normalizedCommandTemplate(commandTemplate)
        self.fastModel = fastModel
        self.promptTemplate = promptTemplate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        preferTabWorkingDirectory = try container.decodeIfPresent(Bool.self, forKey: .preferTabWorkingDirectory) ?? true
        defaultProjectPath = try container.decodeIfPresent(String.self, forKey: .defaultProjectPath) ?? Self.defaultLearnWorkspacePath
        notesRelativePath = try container.decodeIfPresent(String.self, forKey: .notesRelativePath) ?? Self.defaultNotesRelativePath

        commandTemplate = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .commandTemplate)
            ?? container.decodeIfPresent(String.self, forKey: .codexCommand)
            ?? Self.defaultCommandTemplate
        )

        fastModel = try container.decodeIfPresent(String.self, forKey: .fastModel)
            ?? container.decodeIfPresent(String.self, forKey: .codexModel)
            ?? Self.defaultFastModel

        promptTemplate = try container.decodeIfPresent(String.self, forKey: .promptTemplate)
            ?? Self.defaultPromptTemplate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(preferTabWorkingDirectory, forKey: .preferTabWorkingDirectory)
        try container.encode(defaultProjectPath, forKey: .defaultProjectPath)
        try container.encode(notesRelativePath, forKey: .notesRelativePath)
        try container.encode(commandTemplate, forKey: .commandTemplate)
        try container.encode(fastModel, forKey: .fastModel)
        try container.encode(promptTemplate, forKey: .promptTemplate)
    }

    func resolvedContext(selection: String, tabWorkingDirectory: String?) -> ResolvedContext {
        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTabWorkingDirectory = tabWorkingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedCommandTemplate = Self.normalizedCommandTemplate(commandTemplate)

        let trimmedFastModel = fastModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFastModel = trimmedFastModel.isEmpty
            ? Self.defaultFastModel
            : trimmedFastModel

        let trimmedDefaultProjectPath = defaultProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProjectPath: String = if !trimmedDefaultProjectPath.isEmpty {
            trimmedDefaultProjectPath
        } else if preferTabWorkingDirectory && !trimmedTabWorkingDirectory.isEmpty {
            trimmedTabWorkingDirectory
        } else {
            trimmedTabWorkingDirectory
        }

        let trimmedNotesRelativePath = notesRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNotesRelativePath = trimmedNotesRelativePath.isEmpty
            ? Self.defaultNotesRelativePath
            : trimmedNotesRelativePath

        let resolvedNotesAbsolutePath: String = if resolvedNotesRelativePath.hasPrefix("/") {
            resolvedNotesRelativePath
        } else if !resolvedProjectPath.isEmpty {
            URL(fileURLWithPath: resolvedProjectPath)
                .appendingPathComponent(resolvedNotesRelativePath)
                .path
        } else if !trimmedTabWorkingDirectory.isEmpty {
            URL(fileURLWithPath: trimmedTabWorkingDirectory)
                .appendingPathComponent(resolvedNotesRelativePath)
                .path
        } else {
            resolvedNotesRelativePath
        }

        // Prompt editing is hidden in the UI; keep runtime behavior deterministic and lightweight.
        let resolvedPromptTemplate = Self.defaultPromptTemplate

        let replacements = [
            "$MODEL": resolvedFastModel,
            "$SELECTION": trimmedSelection,
            "$PROJECT_PATH": resolvedProjectPath,
            "$LEARN_WORKSPACE": resolvedProjectPath,
            "$NOTES_RELATIVE_PATH": resolvedNotesRelativePath,
            "$NOTES_ABSOLUTE_PATH": resolvedNotesAbsolutePath,
            "$TAB_WORKING_DIRECTORY": trimmedTabWorkingDirectory,
        ]
        let resolvedPrompt = Self.renderTemplate(
            resolvedPromptTemplate,
            replacements: replacements
        )

        return .init(
            commandTemplate: resolvedCommandTemplate,
            fastModel: resolvedFastModel,
            prompt: resolvedPrompt,
            selection: trimmedSelection,
            projectPath: resolvedProjectPath,
            notesRelativePath: resolvedNotesRelativePath,
            notesAbsolutePath: resolvedNotesAbsolutePath,
            tabWorkingDirectory: trimmedTabWorkingDirectory
        )
    }

    private static func renderTemplate(
        _ template: String,
        replacements: [String: String]
    ) -> String {
        let sorted = replacements.sorted { lhs, rhs in
            lhs.key.count > rhs.key.count
        }
        return sorted.reduce(template) { partial, item in
            partial.replacingOccurrences(of: item.key, with: item.value)
        }
    }
}

struct AITerminalLearningLogEntry: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case success
        case failure

        var displayName: String {
            switch self {
            case .success:
                return L10n.SSHConnections.learningLogStatusSuccess
            case .failure:
                return L10n.SSHConnections.learningLogStatusFailure
            }
        }
    }

    let id: UUID
    var createdAt: Date
    var status: Status
    var outputSummary: String
    var outputDetail: String?
    var exitCode: Int32?
    var commandTemplate: String
    var projectPath: String
    var notesAbsolutePath: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        status: Status,
        outputSummary: String,
        outputDetail: String? = nil,
        exitCode: Int32? = nil,
        commandTemplate: String,
        projectPath: String,
        notesAbsolutePath: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.status = status
        self.outputSummary = outputSummary
        self.outputDetail = outputDetail
        self.exitCode = exitCode
        self.commandTemplate = commandTemplate
        self.projectPath = projectPath
        self.notesAbsolutePath = notesAbsolutePath
    }
}

struct AITerminalManagerConfiguration: Codable, Sendable {
    var schemaVersion: Int
    var savedHosts: [AITerminalHost]
    var importedHostOverrides: [AITerminalHost]
    var favoriteHostIDs: [String]
    var recentHosts: [AITerminalRecentHostRecord]
    var workspaces: [AITerminalWorkspaceTemplate]
    var savedWorkspaceTemplates: [AITerminalSavedWorkspaceTemplate]
    var heartbeatQueueSettings: AITerminalHeartbeatQueueSettings
    var heartbeatTasks: [AITerminalHeartbeatTask]
    var todoSettings: AITerminalTodoSettings
    var learningSettings: AITerminalLearningSettings
    var learningLogs: [AITerminalLearningLogEntry]

    init(
        schemaVersion: Int = 7,
        savedHosts: [AITerminalHost] = [],
        importedHostOverrides: [AITerminalHost] = [],
        favoriteHostIDs: [String] = [],
        recentHosts: [AITerminalRecentHostRecord] = [],
        workspaces: [AITerminalWorkspaceTemplate] = [],
        savedWorkspaceTemplates: [AITerminalSavedWorkspaceTemplate] = [],
        heartbeatQueueSettings: AITerminalHeartbeatQueueSettings = .init(),
        heartbeatTasks: [AITerminalHeartbeatTask] = [],
        todoSettings: AITerminalTodoSettings = .init(),
        learningSettings: AITerminalLearningSettings = .init(),
        learningLogs: [AITerminalLearningLogEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.savedHosts = savedHosts
        self.importedHostOverrides = importedHostOverrides
        self.favoriteHostIDs = favoriteHostIDs
        self.recentHosts = recentHosts
        self.workspaces = workspaces
        self.savedWorkspaceTemplates = savedWorkspaceTemplates
        self.heartbeatQueueSettings = heartbeatQueueSettings
        self.heartbeatTasks = heartbeatTasks
        self.todoSettings = todoSettings
        self.learningSettings = learningSettings
        self.learningLogs = learningLogs
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case savedHosts
        case importedHostOverrides
        case favoriteHostIDs
        case recentHosts
        case workspaces
        case savedWorkspaceTemplates
        case heartbeatQueueSettings
        case heartbeatTasks
        case todoSettings
        case learningSettings
        case learningLogs
        case hosts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        savedHosts = try container.decodeIfPresent([AITerminalHost].self, forKey: .savedHosts)
            ?? container.decodeIfPresent([AITerminalHost].self, forKey: .hosts)
            ?? []
        importedHostOverrides = try container.decodeIfPresent([AITerminalHost].self, forKey: .importedHostOverrides) ?? []
        favoriteHostIDs = try container.decodeIfPresent([String].self, forKey: .favoriteHostIDs) ?? []
        recentHosts = try container.decodeIfPresent([AITerminalRecentHostRecord].self, forKey: .recentHosts) ?? []
        workspaces = try container.decodeIfPresent([AITerminalWorkspaceTemplate].self, forKey: .workspaces) ?? []
        savedWorkspaceTemplates = try container.decodeIfPresent([AITerminalSavedWorkspaceTemplate].self, forKey: .savedWorkspaceTemplates) ?? []
        heartbeatQueueSettings = try container.decodeIfPresent(AITerminalHeartbeatQueueSettings.self, forKey: .heartbeatQueueSettings) ?? .init()
        heartbeatTasks = try container.decodeIfPresent([AITerminalHeartbeatTask].self, forKey: .heartbeatTasks) ?? []
        todoSettings = try container.decodeIfPresent(AITerminalTodoSettings.self, forKey: .todoSettings) ?? .init()
        learningSettings = try container.decodeIfPresent(AITerminalLearningSettings.self, forKey: .learningSettings) ?? .init()
        learningLogs = try container.decodeIfPresent([AITerminalLearningLogEntry].self, forKey: .learningLogs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(savedHosts, forKey: .savedHosts)
        try container.encode(importedHostOverrides, forKey: .importedHostOverrides)
        try container.encode(favoriteHostIDs, forKey: .favoriteHostIDs)
        try container.encode(recentHosts, forKey: .recentHosts)
        try container.encode(workspaces, forKey: .workspaces)
        try container.encode(savedWorkspaceTemplates, forKey: .savedWorkspaceTemplates)
        try container.encode(heartbeatQueueSettings, forKey: .heartbeatQueueSettings)
        try container.encode(heartbeatTasks, forKey: .heartbeatTasks)
        try container.encode(todoSettings, forKey: .todoSettings)
        try container.encode(learningSettings, forKey: .learningSettings)
        try container.encode(learningLogs, forKey: .learningLogs)
    }
}

private extension ISO8601DateFormatter {
    static let todoDayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

struct AITerminalLaunchRegistration: Hashable, Sendable {
    var hostID: String?
    var workspaceID: String?
    var managedState: AITerminalManagedState
    var sourceLabel: String
}

enum AITerminalSSHSessionAuthState: String, Hashable, Sendable {
    case connecting
    case awaitingPassword = "awaiting_password"
    case authenticating
    case connected
    case failed

    var displayName: String {
        switch self {
        case .connecting: L10n.SSHConnections.authStateConnecting
        case .awaitingPassword: L10n.SSHConnections.authStateAwaitingPassword
        case .authenticating: L10n.SSHConnections.authStateAuthenticating
        case .connected: L10n.SSHConnections.authStateConnected
        case .failed: L10n.SSHConnections.authStateFailed
        }
    }
}

struct AITerminalRemoteSessionSummary: Identifiable, Hashable {
    let id: UUID
    var title: String
    var hostID: String
    var hostName: String
    var hostTarget: String
    var workingDirectory: String?
    var authState: AITerminalSSHSessionAuthState
    var isFocused: Bool
}

struct AITerminalSessionSummary: Identifiable, Hashable {
    let id: UUID
    var title: String
    var workingDirectory: String?
    var isFocused: Bool
    var hostLabel: String
    var managedState: AITerminalManagedState
    var taskID: UUID?
    var taskTitle: String?
    var taskState: AITerminalTaskState?
}

enum AITerminalTaskState: String, Codable, CaseIterable, Sendable {
    case queued
    case active
    case waitingApproval = "waiting_approval"
    case paused
    case completed
    case failed

    var displayName: String {
        switch self {
        case .queued: L10n.AITerminalManager.queued
        case .active: L10n.AITerminalManager.active
        case .waitingApproval: L10n.AITerminalManager.awaitingApproval
        case .paused: L10n.AITerminalManager.paused
        case .completed: L10n.AITerminalManager.completed
        case .failed: L10n.AITerminalManager.failed
        }
    }
}

struct AITerminalTaskRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var sessionID: UUID
    var state: AITerminalTaskState
    var createdAt: Date
    var updatedAt: Date
    var note: String?

    init(
        id: UUID = UUID(),
        title: String,
        sessionID: UUID,
        state: AITerminalTaskState = .queued,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sessionID = sessionID
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.note = note
    }
}

struct AITerminalLaunchPlan {
    var surfaceConfiguration: Ghostty.SurfaceConfiguration
    var registration: AITerminalLaunchRegistration

    static func localShell() -> AITerminalLaunchPlan {
        var config = Ghostty.SurfaceConfiguration()
        config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
        config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "local"
        return .init(
            surfaceConfiguration: config,
            registration: .init(
                hostID: AITerminalHost.local.id,
                workspaceID: nil,
                managedState: .manual,
                sourceLabel: AITerminalHost.local.name
            )
        )
    }

    static func workspace(
        _ workspace: AITerminalWorkspaceTemplate,
        host: AITerminalHost
    ) -> AITerminalLaunchPlan? {
        switch host.transport {
        case .local:
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = workspace.directory
            config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
            config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "local_workspace"
            config.environmentVariables["GHOSTTY_AI_WORKSPACE_ID"] = workspace.id
            return .init(
                surfaceConfiguration: config,
                registration: .init(
                    hostID: host.id,
                    workspaceID: workspace.id,
                    managedState: .manual,
                    sourceLabel: workspace.name
                )
            )

        case .localmcd:
            return localCommand(
                host: host,
                directoryOverride: workspace.directory,
                workspaceID: workspace.id,
                sourceLabel: workspace.name
            )

        case .ssh:
            return remote(host: host, directoryOverride: workspace.directory, workspaceID: workspace.id, sourceLabel: workspace.name)
        }
    }

    static func localCommand(
        host: AITerminalHost,
        directoryOverride: String? = nil,
        workspaceID: String? = nil,
        sourceLabel: String? = nil
    ) -> AITerminalLaunchPlan? {
        guard host.transport == .localmcd else { return nil }
        let startupCommands = host.startupCommands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !startupCommands.isEmpty else { return nil }

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = directoryOverride ?? host.defaultDirectory
        config.initialInput = startupCommands.joined(separator: "\n") + "\n"
        config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
        config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "local_mcd"
        config.environmentVariables["GHOSTTY_AI_HOST_ID"] = host.id
        if let workspaceID = workspaceID {
            config.environmentVariables["GHOSTTY_AI_WORKSPACE_ID"] = workspaceID
        }

        return .init(
            surfaceConfiguration: config,
            registration: .init(
                hostID: host.id,
                workspaceID: workspaceID,
                managedState: .manual,
                sourceLabel: sourceLabel ?? host.name
            )
        )
    }

    static func remote(
        host: AITerminalHost,
        directoryOverride: String? = nil,
        workspaceID: String? = nil,
        sourceLabel: String? = nil
    ) -> AITerminalLaunchPlan? {
        guard let command = remoteCommand(host: host, directoryOverride: directoryOverride) else {
            return nil
        }

        var config = Ghostty.SurfaceConfiguration()
        config.command = command
        config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
        config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "remote_ssh"
        config.environmentVariables["GHOSTTY_AI_HOST_ID"] = host.id
        if let workspaceID = workspaceID {
            config.environmentVariables["GHOSTTY_AI_WORKSPACE_ID"] = workspaceID
        }

        return .init(
            surfaceConfiguration: config,
            registration: .init(
                hostID: host.id,
                workspaceID: workspaceID,
                managedState: .manual,
                sourceLabel: sourceLabel ?? host.name
            )
        )
    }

    static func remoteCommand(
        host: AITerminalHost,
        directoryOverride: String? = nil
    ) -> String? {
        guard let target = host.connectionTarget else { return nil }

        var command = "ssh"
        if host.sshAlias == nil, let port = host.port {
            command += " -p \(port)"
        }
        command += " \(Ghostty.Shell.quote(target))"

        let directory = directoryOverride ?? host.defaultDirectory
        let remoteShell: String
        if let directory, !directory.isEmpty {
            remoteShell = "export TERM=xterm-256color && export COLORTERM=truecolor && unset LC_ALL && cd \(Ghostty.Shell.quote(directory)) && exec ${SHELL:-/bin/sh} -l"
        } else {
            remoteShell = "export TERM=xterm-256color && export COLORTERM=truecolor && unset LC_ALL && exec ${SHELL:-/bin/sh} -l"
        }
        command += " -t \(Ghostty.Shell.quote(remoteShell))"

        return command
    }
}

enum AITerminalSSHConfigParser {
    private struct Accumulator {
        var aliases: [String] = []
        var hostname: String?
        var user: String?
        var port: Int?
    }

    static func parse(_ text: String) -> [AITerminalHost] {
        var result: [AITerminalHost] = []
        var current = Accumulator()

        func flush() {
            guard !current.aliases.isEmpty else { return }
            for alias in current.aliases {
                result.append(
                    AITerminalHost(
                        id: "ssh:\(alias)",
                        name: alias,
                        transport: .ssh,
                        sshAlias: alias,
                        hostname: current.hostname,
                        user: current.user,
                        port: current.port,
                        defaultDirectory: nil,
                        source: .sshConfig
                    )
                )
            }
            current = Accumulator()
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            let line = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let key = parts.first?.lowercased(), parts.count >= 2 else { continue }

            switch key {
            case "host":
                flush()
                current.aliases = parts.dropFirst().filter {
                    !$0.contains("*") && !$0.contains("?") && !$0.contains("!")
                }

            case "hostname":
                current.hostname = parts.dropFirst().joined(separator: " ")

            case "user":
                current.user = parts.dropFirst().joined(separator: " ")

            case "port":
                current.port = Int(parts.dropFirst().joined(separator: " "))

            default:
                continue
            }
        }

        flush()

        var seen: Set<String> = []
        return result.filter { seen.insert($0.id).inserted }
    }
}

extension AITerminalManagerConfiguration {
    static let empty = AITerminalManagerConfiguration()
}
