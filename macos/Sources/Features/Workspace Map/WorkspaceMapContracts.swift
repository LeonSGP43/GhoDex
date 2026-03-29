import Foundation

/// Versioned schema marker for the Workspace Map projection payload.
enum WorkspaceMapGraphSchemaVersion: Int, Codable, Hashable {
    case v1 = 1
}

enum WorkspaceMapLayoutSchemaVersion: Int, Codable, Hashable {
    case v1 = 1
}

enum WorkspaceMapSplitBranch: String, Codable, Hashable, Sendable {
    case left = "l"
    case right = "r"
}

enum WorkspaceMapSplitDirection: String, Codable, Hashable, Sendable {
    case horizontal
    case vertical
}

/// Stable identity for entities projected into the Workspace Map graph.
struct WorkspaceMapEntityID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ value: String) {
        self.rawValue = value
    }
}

extension WorkspaceMapEntityID {
    static func terminalGroup(_ workspaceID: UUID) -> Self {
        .init("terminal-group:\(workspaceID.uuidString.lowercased())")
    }

    static func browserGroup(_ workspaceID: UUID) -> Self {
        .init("browser-group:\(workspaceID.uuidString.lowercased())")
    }

    static func browserGroup(_ externalID: String) -> Self {
        .init("browser-group:\(externalID)")
    }

    static func pane(_ paneID: UUID) -> Self {
        .init("pane:\(paneID.uuidString.lowercased())")
    }

    static func paneTab(_ paneTabID: UUID) -> Self {
        .init("pane-tab:\(paneTabID.uuidString.lowercased())")
    }

    static func split(groupID: WorkspaceMapEntityID, path: [WorkspaceMapSplitBranch]) -> Self {
        let pathToken = path.isEmpty ? "root" : path.map(\.rawValue).joined(separator: ".")
        return .init("split:\(groupID.rawValue):\(pathToken)")
    }

    var terminalGroupUUID: UUID? {
        parseUUID(prefix: "terminal-group:")
    }

    var browserGroupExternalID: String? {
        parseSuffix(prefix: "browser-group:")
    }

    var browserGroupUUID: UUID? {
        parseUUID(prefix: "browser-group:")
    }

    var paneUUID: UUID? {
        parseUUID(prefix: "pane:")
    }

    var paneTabUUID: UUID? {
        parseUUID(prefix: "pane-tab:")
    }

    private func parseUUID(prefix: String) -> UUID? {
        guard let suffix = parseSuffix(prefix: prefix) else { return nil }
        return UUID(uuidString: suffix)
    }

    private func parseSuffix(prefix: String) -> String? {
        guard rawValue.hasPrefix(prefix) else { return nil }
        return String(rawValue.dropFirst(prefix.count))
    }
}

enum WorkspaceMapGroupKind: String, Codable, Hashable, Sendable {
    case terminal
    case browser
}

enum WorkspaceMapNodeKind: String, Codable, Hashable, Sendable {
    case split
    case pane
    case paneTab
}

struct WorkspaceMapSnapshot: Codable, Hashable, Sendable {
    let schemaVersion: WorkspaceMapGraphSchemaVersion
    let generatedAt: Date
    let groups: [WorkspaceMapGroupSnapshot]

    init(
        schemaVersion: WorkspaceMapGraphSchemaVersion = .v1,
        generatedAt: Date = Date(),
        groups: [WorkspaceMapGroupSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.groups = groups
    }
}

extension WorkspaceMapSnapshot {
    func semanticallyEquals(_ other: WorkspaceMapSnapshot) -> Bool {
        schemaVersion == other.schemaVersion && groups == other.groups
    }
}

struct WorkspaceMapLayoutSnapshot: Codable, Hashable, Sendable {
    let schemaVersion: WorkspaceMapLayoutSchemaVersion
    var viewport: WorkspaceMapViewportSnapshot
    var groups: [WorkspaceMapGroupLayoutSnapshot]

    init(
        schemaVersion: WorkspaceMapLayoutSchemaVersion = .v1,
        viewport: WorkspaceMapViewportSnapshot = .default,
        groups: [WorkspaceMapGroupLayoutSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.viewport = viewport
        self.groups = groups
    }
}

struct WorkspaceMapViewportSnapshot: Codable, Hashable, Sendable {
    var offsetX: Double
    var offsetY: Double
    var zoom: Double

    static let `default` = WorkspaceMapViewportSnapshot(offsetX: 120, offsetY: 100, zoom: 1.0)
}

struct WorkspaceMapGroupLayoutSnapshot: Codable, Hashable, Identifiable, Sendable {
    let id: WorkspaceMapEntityID
    var centerX: Double
    var centerY: Double
    var isCollapsed: Bool
}

struct WorkspaceMapGroupSnapshot: Codable, Hashable, Identifiable, Sendable {
    let id: WorkspaceMapEntityID
    let kind: WorkspaceMapGroupKind
    let title: String
    let isFocused: Bool
    let terminal: WorkspaceMapTerminalGroupSnapshot?
    let browser: WorkspaceMapBrowserGroupSnapshot?
}

enum WorkspaceMapPerformanceWorkload: String, Codable, Hashable, Sendable, CaseIterable {
    case largeA
    case largeB
    case largeC

    var displayName: String {
        switch self {
        case .largeA: return "Large-A"
        case .largeB: return "Large-B"
        case .largeC: return "Large-C"
        }
    }
}

struct WorkspaceMapPerformanceThreshold: Codable, Hashable, Sendable {
    let snapshotBuildP95MS: Double
    let snapshotBuildP99MS: Double
    let publishCadenceMaxPerSecond: Double
    let mainThreadSpikeMaxCount: Int
    let commandLatencyP95MS: Double
    let commandFailureRateMax: Double
}

enum WorkspaceMapPerformanceBudget {
    static let mainThreadSpikeThresholdMS: Double = 32

    static let thresholdsByWorkload: [WorkspaceMapPerformanceWorkload: WorkspaceMapPerformanceThreshold] = [
        .largeA: WorkspaceMapPerformanceThreshold(
            snapshotBuildP95MS: 25,
            snapshotBuildP99MS: 40,
            publishCadenceMaxPerSecond: 12,
            mainThreadSpikeMaxCount: 2,
            commandLatencyP95MS: 50,
            commandFailureRateMax: 0
        ),
        .largeB: WorkspaceMapPerformanceThreshold(
            snapshotBuildP95MS: 20,
            snapshotBuildP99MS: 35,
            publishCadenceMaxPerSecond: 20,
            mainThreadSpikeMaxCount: 5,
            commandLatencyP95MS: 55,
            commandFailureRateMax: 0
        ),
        .largeC: WorkspaceMapPerformanceThreshold(
            snapshotBuildP95MS: 20,
            snapshotBuildP99MS: 35,
            publishCadenceMaxPerSecond: 15,
            mainThreadSpikeMaxCount: 3,
            commandLatencyP95MS: 45,
            commandFailureRateMax: 0
        ),
    ]

    static func threshold(for workload: WorkspaceMapPerformanceWorkload) -> WorkspaceMapPerformanceThreshold {
        thresholdsByWorkload[workload]!
    }

    static var largeASnapshotBuildP95MS: Double {
        threshold(for: .largeA).snapshotBuildP95MS
    }
}

enum WorkspaceMapPerformanceGateStatus: String, Codable, Hashable, Sendable {
    case pass
    case fail
}

struct WorkspaceMapPerformanceMetrics: Codable, Hashable, Sendable {
    let snapshotBuildP95MS: Double
    let snapshotBuildP99MS: Double
    let commandLatencyP95MS: Double
    let publishCadencePerSecond: Double
    let mainThreadSpikeCount: Int
    let commandFailureRate: Double

    static let empty = WorkspaceMapPerformanceMetrics(
        snapshotBuildP95MS: 0,
        snapshotBuildP99MS: 0,
        commandLatencyP95MS: 0,
        publishCadencePerSecond: 0,
        mainThreadSpikeCount: 0,
        commandFailureRate: 0
    )
}

struct WorkspaceMapPerformanceWorkloadResult: Codable, Hashable, Sendable {
    let workload: WorkspaceMapPerformanceWorkload
    let status: WorkspaceMapPerformanceGateStatus
    let threshold: WorkspaceMapPerformanceThreshold
    let observed: WorkspaceMapPerformanceMetrics?
    let violations: [String]
}

struct WorkspaceMapPerformanceSnapshot: Codable, Hashable, Sendable {
    let snapshotBuildP95MS: Double
    let snapshotBuildP99MS: Double
    let commandLatencyP95MS: Double
    let publishCadencePerSecond: Double
    let mainThreadSpikeCount: Int
    let commandFailureRate: Double
    let gate: WorkspaceMapPerformanceGateStatus
    let workloadResults: [WorkspaceMapPerformanceWorkloadResult]

    init(
        metrics: WorkspaceMapPerformanceMetrics,
        gate: WorkspaceMapPerformanceGateStatus,
        workloadResults: [WorkspaceMapPerformanceWorkloadResult]
    ) {
        self.snapshotBuildP95MS = metrics.snapshotBuildP95MS
        self.snapshotBuildP99MS = metrics.snapshotBuildP99MS
        self.commandLatencyP95MS = metrics.commandLatencyP95MS
        self.publishCadencePerSecond = metrics.publishCadencePerSecond
        self.mainThreadSpikeCount = metrics.mainThreadSpikeCount
        self.commandFailureRate = metrics.commandFailureRate
        self.gate = gate
        self.workloadResults = workloadResults
    }

    static let empty = WorkspaceMapPerformanceSnapshot(
        metrics: .empty,
        gate: .fail,
        workloadResults: WorkspaceMapPerformanceWorkload.allCases.map { workload in
            WorkspaceMapPerformanceWorkloadResult(
                workload: workload,
                status: .fail,
                threshold: WorkspaceMapPerformanceBudget.threshold(for: workload),
                observed: nil,
                violations: ["missing_artifact_data"]
            )
        }
    )
}

struct WorkspaceMapTerminalGroupSnapshot: Codable, Hashable, Sendable {
    let rootNodeID: WorkspaceMapEntityID?
    let splitCount: Int
    let paneCount: Int
    let tabCount: Int
    let nodes: [WorkspaceMapNodeSnapshot]
}

struct WorkspaceMapBrowserGroupSnapshot: Codable, Hashable, Sendable {
    let selectedPageID: String
    let displayedURL: String
}

struct WorkspaceMapNodeSnapshot: Codable, Hashable, Identifiable, Sendable {
    let id: WorkspaceMapEntityID
    let kind: WorkspaceMapNodeKind
    let title: String
    let parentID: WorkspaceMapEntityID?
    let isActive: Bool
    let childIDs: [WorkspaceMapEntityID]
    let splitDirection: WorkspaceMapSplitDirection?
    let splitRatio: Double?

    init(
        id: WorkspaceMapEntityID,
        kind: WorkspaceMapNodeKind,
        title: String,
        parentID: WorkspaceMapEntityID?,
        isActive: Bool,
        childIDs: [WorkspaceMapEntityID] = [],
        splitDirection: WorkspaceMapSplitDirection? = nil,
        splitRatio: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.parentID = parentID
        self.isActive = isActive
        self.childIDs = childIDs
        self.splitDirection = splitDirection
        self.splitRatio = splitRatio
    }
}

enum WorkspaceMapCommand: String, Codable, Hashable, Sendable {
    case focusTopLevelGroup
    case renameTopLevelGroup
    case closeTopLevelGroup
    case jumpToTerminalPaneTab
    case editSplitTree
}

struct WorkspaceMapCommandRequest: Codable, Hashable, Sendable {
    let command: WorkspaceMapCommand
    let targetID: WorkspaceMapEntityID
    let title: String?

    init(
        command: WorkspaceMapCommand,
        targetID: WorkspaceMapEntityID,
        title: String? = nil
    ) {
        self.command = command
        self.targetID = targetID
        self.title = title
    }
}

enum WorkspaceMapCommandStatus: String, Codable, Hashable, Sendable {
    case executed
    case blockedByPolicy
    case targetNotFound
    case invalidRequest
}

struct WorkspaceMapCommandResult: Codable, Hashable, Sendable {
    let status: WorkspaceMapCommandStatus
    let message: String
}

enum WorkspaceMapCommandPolicy {
    static let v1Allowlist: Set<WorkspaceMapCommand> = [
        .focusTopLevelGroup,
        .renameTopLevelGroup,
        .closeTopLevelGroup,
        .jumpToTerminalPaneTab,
    ]

    static func isAllowedInV1(_ command: WorkspaceMapCommand) -> Bool {
        v1Allowlist.contains(command)
    }
}
