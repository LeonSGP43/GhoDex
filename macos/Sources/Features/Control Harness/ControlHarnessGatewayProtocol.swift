import Foundation

enum ControlHarnessGatewaySessionEnqueueResult: Equatable {
    case buffered
    case overflowed
    case droppedOversize
}

struct ControlHarnessGatewaySessionDrainResult {
    let payloads: [Data]
    let requiresSnapshotResync: Bool
    let droppedEvents: Int
}

struct ControlHarnessGatewayOverflowMarker: Encodable {
    let streamKind = "gateway_status"
    let event = "overflow"
    let gap = true
    let requiresSnapshotResync = true
    let droppedEvents: Int

    enum CodingKeys: String, CodingKey {
        case streamKind = "stream_kind"
        case event
        case gap
        case requiresSnapshotResync = "requires_snapshot_resync"
        case droppedEvents = "dropped_events"
    }
}
