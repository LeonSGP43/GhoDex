import Foundation

enum AgentRuntimeClientKind: String, Codable, CaseIterable, Sendable {
    case codexTab = "codex_tab"
    case hostExecutor = "host_executor"
}

enum AgentRuntimeSessionState: String, Codable, CaseIterable, Sendable {
    case booting
    case active
    case waitingApproval = "waiting_approval"
    case paused
    case expired
    case released
    case failed

    var isLeaseManaged: Bool {
        switch self {
        case .booting, .active, .waitingApproval, .paused:
            return true
        case .expired, .released, .failed:
            return false
        }
    }
}

enum AgentRuntimeTaskKind: String, Codable, CaseIterable, Sendable {
    case terminalCommand = "terminal_command"
    case terminalText = "terminal_text"
    case browserNavigation = "browser_navigation"
    case browserInteraction = "browser_interaction"
    case visionAutomation = "vision_automation"
    case hostWorkflow = "host_workflow"
    case approvalCheckpoint = "approval_checkpoint"
    case systemMaintenance = "system_maintenance"

    var defaultCapabilityRequirements: [String] {
        switch self {
        case .terminalCommand, .terminalText:
            return [AgentRuntimeCapability.runtimeExecutorTerminal.rawValue]
        case .browserNavigation, .browserInteraction:
            return [AgentRuntimeCapability.runtimeExecutorBrowser.rawValue]
        case .visionAutomation:
            return [AgentRuntimeCapability.runtimeExecutorVision.rawValue]
        case .hostWorkflow, .approvalCheckpoint, .systemMaintenance:
            return []
        }
    }
}

enum AgentRuntimeCapability: String, CaseIterable, Sendable {
    case runtimeObserve = "runtime.observe"
    case runtimeTaskClaim = "runtime.task.claim"
    case runtimeTaskManage = "runtime.task.manage"
    case runtimeExecutorTerminal = "runtime.executor.terminal"
    case runtimeExecutorBrowser = "runtime.executor.browser"
    case runtimeExecutorVision = "runtime.executor.vision"
    case runtimeAdmin = "runtime.admin"

    fileprivate static let legacyAliases: [String: String] = [
        "observe": AgentRuntimeCapability.runtimeObserve.rawValue,
        "task-runtime": AgentRuntimeCapability.runtimeTaskManage.rawValue,
        "task-claim": AgentRuntimeCapability.runtimeTaskClaim.rawValue,
        "terminal": AgentRuntimeCapability.runtimeExecutorTerminal.rawValue,
        "browser": AgentRuntimeCapability.runtimeExecutorBrowser.rawValue,
        "vision": AgentRuntimeCapability.runtimeExecutorVision.rawValue,
        "admin": AgentRuntimeCapability.runtimeAdmin.rawValue,
    ]

    fileprivate static func canonicalize(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return legacyAliases[trimmed] ?? trimmed
    }
}

enum AgentRuntimeTaskState: String, Codable, CaseIterable, Sendable {
    case queued
    case claimed
    case running
    case waitingApproval = "waiting_approval"
    case paused
    case completed
    case failed
    case cancelled

    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .queued, .claimed, .running, .waitingApproval, .paused:
            return false
        }
    }

    func canTransition(to next: Self) -> Bool {
        if self == next {
            return true
        }

        switch (self, next) {
        case (.queued, .claimed), (.queued, .cancelled):
            return true

        case (.claimed, .running), (.claimed, .waitingApproval), (.claimed, .paused), (.claimed, .failed), (.claimed, .cancelled), (.claimed, .queued):
            return true

        case (.running, .waitingApproval), (.running, .paused), (.running, .completed), (.running, .failed), (.running, .cancelled), (.running, .queued):
            return true

        case (.waitingApproval, .paused), (.waitingApproval, .failed), (.waitingApproval, .cancelled):
            return true

        case (.paused, .claimed), (.paused, .running), (.paused, .failed), (.paused, .cancelled), (.paused, .queued):
            return true

        case (.completed, _), (.failed, _), (.cancelled, _):
            return false

        default:
            return false
        }
    }
}

enum AgentRuntimeStaleTaskPolicy: String, Codable, CaseIterable, Sendable {
    case requeueClaimedWork = "requeue_claimed_work"
    case pauseClaimedWork = "pause_claimed_work"
}

enum AgentRuntimeScheduleState: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case completed
    case cancelled

    var isRunnable: Bool {
        self == .active
    }

    func canTransition(to next: Self) -> Bool {
        if self == next {
            return true
        }

        switch (self, next) {
        case (.active, .paused), (.active, .cancelled), (.active, .completed):
            return true
        case (.paused, .active), (.paused, .cancelled):
            return true
        case (.completed, _), (.cancelled, _):
            return false
        default:
            return false
        }
    }
}

struct AgentRuntimeScheduleRecurrence: Codable, Hashable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case once
        case interval
    }

    static let minimumIntervalSeconds: Double = 1
    static let maximumIntervalSeconds: Double = 86_400

    var mode: Mode
    var intervalSeconds: Double?

    init(
        mode: Mode = .once,
        intervalSeconds: Double? = nil
    ) {
        self.mode = mode
        self.intervalSeconds = intervalSeconds
    }

    func sanitized() -> Self {
        var next = self
        switch next.mode {
        case .once:
            next.intervalSeconds = nil
        case .interval:
            let interval = next.intervalSeconds ?? Self.minimumIntervalSeconds
            next.intervalSeconds = min(
                max(interval, Self.minimumIntervalSeconds),
                Self.maximumIntervalSeconds
            )
        }
        return next
    }
}

struct AgentRuntimeSchedule: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var taskKind: AgentRuntimeTaskKind
    var state: AgentRuntimeScheduleState
    var priority: Int
    var capabilityRequirements: [String]
    var payload: AgentRuntimeTaskPayload
    var startAt: Date
    var nextRunAt: Date?
    var recurrence: AgentRuntimeScheduleRecurrence
    var createdAt: Date
    var updatedAt: Date
    var maxRetryCount: Int
    var lastMaterializedAt: Date?
    var lastTaskID: UUID?

    init(
        id: UUID = UUID(),
        taskKind: AgentRuntimeTaskKind,
        state: AgentRuntimeScheduleState = .active,
        priority: Int = 0,
        capabilityRequirements: [String] = [],
        payload: AgentRuntimeTaskPayload = .init(),
        startAt: Date = .now,
        nextRunAt: Date? = nil,
        recurrence: AgentRuntimeScheduleRecurrence = .init(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        maxRetryCount: Int = 0,
        lastMaterializedAt: Date? = nil,
        lastTaskID: UUID? = nil
    ) {
        let normalizedRecurrence = recurrence.sanitized()
        self.id = id
        self.taskKind = taskKind
        self.state = state
        self.priority = priority
        self.capabilityRequirements = AgentRuntimeSession.normalizeCapabilities(capabilityRequirements)
        self.payload = payload
        self.startAt = startAt
        self.nextRunAt = nextRunAt ?? startAt
        self.recurrence = normalizedRecurrence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.maxRetryCount = max(0, maxRetryCount)
        self.lastMaterializedAt = lastMaterializedAt
        self.lastTaskID = lastTaskID
    }

    func isDue(at now: Date) -> Bool {
        guard state.isRunnable else { return false }
        guard let nextRunAt else { return false }
        return nextRunAt <= now
    }

    mutating func markMaterialized(
        fireAt: Date,
        materializedAt: Date,
        taskID: UUID
    ) {
        let normalizedRecurrence = recurrence.sanitized()
        recurrence = normalizedRecurrence
        lastMaterializedAt = materializedAt
        lastTaskID = taskID
        updatedAt = materializedAt

        switch normalizedRecurrence.mode {
        case .once:
            state = .completed
            nextRunAt = nil
        case .interval:
            let interval = normalizedRecurrence.intervalSeconds ?? AgentRuntimeScheduleRecurrence.minimumIntervalSeconds
            nextRunAt = max(fireAt, materializedAt).addingTimeInterval(interval)
        }
    }
}

struct AgentRuntimeSettings: Codable, Hashable, Sendable {
    static let minimumLeaseDurationSeconds: Double = 5
    static let maximumLeaseDurationSeconds: Double = 300

    var enabled: Bool
    var defaultLeaseDurationSeconds: Double
    var staleTaskPolicy: AgentRuntimeStaleTaskPolicy

    init(
        enabled: Bool = true,
        defaultLeaseDurationSeconds: Double = 30,
        staleTaskPolicy: AgentRuntimeStaleTaskPolicy = .requeueClaimedWork
    ) {
        self.enabled = enabled
        self.defaultLeaseDurationSeconds = defaultLeaseDurationSeconds
        self.staleTaskPolicy = staleTaskPolicy
    }

    func sanitized() -> Self {
        var next = self
        next.defaultLeaseDurationSeconds = min(
            max(next.defaultLeaseDurationSeconds, Self.minimumLeaseDurationSeconds),
            Self.maximumLeaseDurationSeconds
        )
        return next
    }
}

struct AgentRuntimeSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var clientKind: AgentRuntimeClientKind
    var tabID: UUID?
    var terminalID: UUID?
    var hostWorkspaceID: UUID?
    var state: AgentRuntimeSessionState
    var capabilities: [String]
    var createdAt: Date
    var updatedAt: Date
    var lastHeartbeatAt: Date?
    var leaseDurationSeconds: Double
    var leaseExpiresAt: Date?
    var currentTaskID: UUID?
    var lastError: String?

    init(
        id: UUID = UUID(),
        clientKind: AgentRuntimeClientKind,
        tabID: UUID? = nil,
        terminalID: UUID? = nil,
        hostWorkspaceID: UUID? = nil,
        state: AgentRuntimeSessionState = .booting,
        capabilities: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastHeartbeatAt: Date? = nil,
        leaseDurationSeconds: Double = AgentRuntimeSettings().defaultLeaseDurationSeconds,
        leaseExpiresAt: Date? = nil,
        currentTaskID: UUID? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.clientKind = clientKind
        self.tabID = tabID
        self.terminalID = terminalID
        self.hostWorkspaceID = hostWorkspaceID
        self.state = state
        self.capabilities = Self.normalizeCapabilities(capabilities)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.leaseDurationSeconds = leaseDurationSeconds
        self.leaseExpiresAt = leaseExpiresAt
        self.currentTaskID = currentTaskID
        self.lastError = lastError
    }

    static func normalizeCapabilities(_ values: [String]) -> [String] {
        Array(Set(values.map {
            AgentRuntimeCapability.canonicalize($0)
        }.filter { !$0.isEmpty })).sorted()
    }

    func normalizedLeaseDuration(defaults: AgentRuntimeSettings) -> Double {
        min(
            max(leaseDurationSeconds, AgentRuntimeSettings.minimumLeaseDurationSeconds),
            max(defaults.sanitized().defaultLeaseDurationSeconds, AgentRuntimeSettings.minimumLeaseDurationSeconds)
        )
    }

    func isLeaseExpired(at now: Date) -> Bool {
        guard state.isLeaseManaged else { return false }
        guard let leaseExpiresAt else { return false }
        return leaseExpiresAt <= now
    }

    mutating func renewLease(
        at now: Date,
        defaults: AgentRuntimeSettings,
        requestedLeaseDurationSeconds: Double? = nil
    ) {
        let base = requestedLeaseDurationSeconds ?? leaseDurationSeconds
        leaseDurationSeconds = min(
            max(base, AgentRuntimeSettings.minimumLeaseDurationSeconds),
            AgentRuntimeSettings.maximumLeaseDurationSeconds
        )
        lastHeartbeatAt = now
        leaseExpiresAt = now.addingTimeInterval(leaseDurationSeconds)
        updatedAt = now
        if state == .booting || state == .expired || state == .failed {
            state = .active
        }
        if !defaults.enabled {
            state = .paused
        }
        lastError = nil
    }
}

struct AgentRuntimeTaskPayload: Codable, Hashable, Sendable {
    var command: String?
    var text: String?
    var metadata: [String: String]

    init(
        command: String? = nil,
        text: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.command = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = text
        self.metadata = metadata
    }
}

struct AgentRuntimeTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: AgentRuntimeTaskKind
    var state: AgentRuntimeTaskState
    var priority: Int
    var sessionID: UUID?
    var capabilityRequirements: [String]
    var payload: AgentRuntimeTaskPayload
    var createdAt: Date
    var scheduledAt: Date
    var claimedAt: Date?
    var finishedAt: Date?
    var retryCount: Int
    var maxRetryCount: Int
    var errorSummary: String?

    init(
        id: UUID = UUID(),
        kind: AgentRuntimeTaskKind,
        state: AgentRuntimeTaskState = .queued,
        priority: Int = 0,
        sessionID: UUID? = nil,
        capabilityRequirements: [String] = [],
        payload: AgentRuntimeTaskPayload = .init(),
        createdAt: Date = .now,
        scheduledAt: Date = .now,
        claimedAt: Date? = nil,
        finishedAt: Date? = nil,
        retryCount: Int = 0,
        maxRetryCount: Int = 0,
        errorSummary: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.priority = priority
        self.sessionID = sessionID
        self.capabilityRequirements = AgentRuntimeSession.normalizeCapabilities(capabilityRequirements)
        self.payload = payload
        self.createdAt = createdAt
        self.scheduledAt = scheduledAt
        self.claimedAt = claimedAt
        self.finishedAt = finishedAt
        self.retryCount = retryCount
        self.maxRetryCount = maxRetryCount
        self.errorSummary = errorSummary
    }

    func isClaimable(by capabilities: Set<String>, now: Date) -> Bool {
        guard state == .queued else { return false }
        guard scheduledAt <= now else { return false }
        guard capabilityRequirements.isEmpty || Set(capabilityRequirements).isSubset(of: capabilities) else {
            return false
        }
        return true
    }
}

enum AgentRuntimeStoreError: Error, Equatable, LocalizedError {
    case runtimeDisabled
    case sessionNotFound(UUID)
    case sessionExpired(UUID)
    case sessionAlreadyHasActiveTask(UUID)
    case taskNotFound(UUID)
    case taskOwnershipMismatch(taskID: UUID, sessionID: UUID)
    case invalidTaskTransition(from: AgentRuntimeTaskState, to: AgentRuntimeTaskState)
    case scheduleNotFound(UUID)
    case invalidScheduleTransition(from: AgentRuntimeScheduleState, to: AgentRuntimeScheduleState)

    var errorDescription: String? {
        switch self {
        case .runtimeDisabled:
            return "Agent runtime is disabled."
        case .sessionNotFound(let sessionID):
            return "Agent runtime session \(sessionID.uuidString.lowercased()) was not found."
        case .sessionExpired(let sessionID):
            return "Agent runtime session \(sessionID.uuidString.lowercased()) is expired."
        case .sessionAlreadyHasActiveTask(let sessionID):
            return "Agent runtime session \(sessionID.uuidString.lowercased()) already has an active task."
        case .taskNotFound(let taskID):
            return "Agent runtime task \(taskID.uuidString.lowercased()) was not found."
        case .taskOwnershipMismatch(let taskID, let sessionID):
            return "Agent runtime task \(taskID.uuidString.lowercased()) is not owned by session \(sessionID.uuidString.lowercased())."
        case .invalidTaskTransition(let from, let to):
            return "Invalid agent runtime task transition: \(from.rawValue) -> \(to.rawValue)."
        case .scheduleNotFound(let scheduleID):
            return "Agent runtime schedule \(scheduleID.uuidString.lowercased()) was not found."
        case .invalidScheduleTransition(let from, let to):
            return "Invalid agent runtime schedule transition: \(from.rawValue) -> \(to.rawValue)."
        }
    }
}
