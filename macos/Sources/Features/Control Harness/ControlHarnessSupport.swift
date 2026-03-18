import Foundation
import OSLog

enum ControlHarnessCommandKind {
    case query
    case mutation
    case subscription
}

extension ControlHarnessRequest {
    var commandKind: ControlHarnessCommandKind {
        switch command {
        case "new-tab", "close-tab", "send-text", "run-command", "close-terminal":
            return .mutation
        case "events.subscribe":
            return .subscription
        default:
            return .query
        }
    }

    var isMutation: Bool { commandKind == .mutation }

    var idempotencyToken: String? {
        let explicit = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty {
            return explicit
        }

        let requestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        return requestID.isEmpty ? nil : requestID
    }
}

struct ControlHarnessEventResource: Encodable {
    let type: String
    let id: String
    let generation: Int
}

struct ControlHarnessEventRecord: Encodable {
    let streamKind = "event"
    let eventID: String
    let sequence: Int64
    let timestamp: String
    let event: String
    let requestID: String?
    let resource: ControlHarnessEventResource?
    let payload: AnyEncodable?

    enum CodingKeys: String, CodingKey {
        case streamKind = "stream_kind"
        case eventID = "event_id"
        case sequence
        case timestamp
        case event
        case requestID = "request_id"
        case resource
        case payload
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(streamKind, forKey: .streamKind)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(event, forKey: .event)
        try container.encodeIfPresent(requestID, forKey: .requestID)
        try container.encodeIfPresent(resource, forKey: .resource)
        if let payload {
            try payload.encode(to: container.superEncoder(forKey: .payload))
        }
    }
}

private struct ControlHarnessIdempotencyEntry {
    let fingerprint: Data
    let response: ControlHarnessResponse
    let sequence: Int64?
}

enum ControlHarnessIdempotencyLookup {
    case miss
    case hit(ControlHarnessResponse, Int64?)
    case conflict
}

final class ControlHarnessIdempotencyStore {
    private let queue = DispatchQueue(label: "com.leongong.ghodex.control-harness.idempotency")
    private var entries: [String: ControlHarnessIdempotencyEntry] = [:]

    func lookup(token: String, fingerprint: Data) -> ControlHarnessIdempotencyLookup {
        queue.sync {
            guard let entry = entries[token] else {
                return .miss
            }
            return entry.fingerprint == fingerprint ? .hit(entry.response, entry.sequence) : .conflict
        }
    }

    func store(
        response: ControlHarnessResponse,
        sequence: Int64?,
        token: String,
        fingerprint: Data
    ) {
        queue.sync {
            entries[token] = .init(
                fingerprint: fingerprint,
                response: response,
                sequence: sequence
            )
        }
    }
}

@MainActor
final class ControlHarnessGenerationTracker {
    private enum ResourceType: String {
        case tab
        case terminal
    }

    private var generations: [String: Int] = [:]

    func currentTabGeneration(for tabID: String) -> Int {
        currentGeneration(for: .tab, id: tabID)
    }

    func currentTerminalGeneration(for terminalID: String) -> Int {
        currentGeneration(for: .terminal, id: terminalID)
    }

    func assertExpectedGeneration(
        _ expectedGeneration: Int?,
        resourceType: String,
        resourceID: String,
        currentGeneration: Int
    ) throws {
        guard let expectedGeneration else { return }
        guard expectedGeneration == currentGeneration else {
            throw ControlHarnessCoreError.staleTarget(
                resourceType: resourceType,
                resourceID: resourceID,
                expected: expectedGeneration,
                actual: currentGeneration
            )
        }
    }

    func advanceTabGeneration(for tabID: String) -> Int {
        advanceGeneration(for: .tab, id: tabID)
    }

    func advanceTerminalGeneration(for terminalID: String) -> Int {
        advanceGeneration(for: .terminal, id: terminalID)
    }

    private func currentGeneration(for type: ResourceType, id: String) -> Int {
        let key = generationKey(for: type, id: id)
        if let generation = generations[key] {
            return generation
        }
        generations[key] = 1
        return 1
    }

    private func advanceGeneration(for type: ResourceType, id: String) -> Int {
        let key = generationKey(for: type, id: id)
        let nextGeneration = (generations[key] ?? 0) + 1
        generations[key] = max(nextGeneration, 1)
        return generations[key] ?? 1
    }

    private func generationKey(for type: ResourceType, id: String) -> String {
        "\(type.rawValue):\(id)"
    }
}

final class ControlHarnessEventHub {
    private struct Subscriber {
        let sink: @Sendable (Data) -> Bool
    }

    private let queue = DispatchQueue(label: "com.leongong.ghodex.control-harness.events")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let fileManager = FileManager.default
    private let fileURL: URL
    private let logger: Logger

    private var nextSequenceValue: Int64
    private var subscribers: [UUID: Subscriber] = [:]

    init(bundleID: String) {
        self.fileURL = ControlHarnessAuditLogger.baseDirectory(bundleID: bundleID)
            .appendingPathComponent("control-harness-events.jsonl", isDirectory: false)
        self.logger = Logger(subsystem: bundleID, category: "ControlHarnessEvents")
        self.nextSequenceValue = Self.loadLastSequence(from: fileURL)
    }

    func currentSequence() -> Int64 {
        queue.sync { nextSequenceValue }
    }

    @discardableResult
    func emit(
        event: String,
        requestID: String?,
        resource: ControlHarnessEventResource?,
        payload: AnyEncodable?
    ) -> Int64 {
        queue.sync {
            nextSequenceValue += 1
            let record = ControlHarnessEventRecord(
                eventID: "evt_\(nextSequenceValue)",
                sequence: nextSequenceValue,
                timestamp: ControlHarnessCore.iso8601(Date()),
                event: event,
                requestID: requestID,
                resource: resource,
                payload: payload
            )

            do {
                let data = try encoder.encode(record) + Data([0x0A])
                try append(data)

                for (id, subscriber) in subscribers where !subscriber.sink(data) {
                    subscribers.removeValue(forKey: id)
                }
            } catch {
                logger.error("failed to emit control harness event: \(error.localizedDescription, privacy: .public)")
            }

            return nextSequenceValue
        }
    }

    func replay(afterSequence: Int64?, limit: Int?) -> [Data] {
        queue.sync {
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
                return []
            }
            defer { try? handle.close() }

            guard let rawData = try? handle.readToEnd(), !rawData.isEmpty else {
                return []
            }

            let threshold = afterSequence ?? 0
            var remaining = limit
            var replayed: [Data] = []

            rawData.split(separator: 0x0A).forEach { line in
                guard remaining != 0 else { return }

                let lineData = Data(line)
                guard let sequence = Self.sequence(from: lineData), sequence > threshold else {
                    return
                }

                replayed.append(lineData + Data([0x0A]))
                if let currentRemaining = remaining {
                    remaining = currentRemaining - 1
                }
            }

            return replayed
        }
    }

    func addSubscriber(_ sink: @escaping @Sendable (Data) -> Bool) -> UUID {
        queue.sync {
            let id = UUID()
            subscribers[id] = .init(sink: sink)
            return id
        }
    }

    func removeSubscriber(_ id: UUID) {
        _ = queue.sync {
            subscribers.removeValue(forKey: id)
        }
    }

    private func append(_ data: Data) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private static func loadLastSequence(from fileURL: URL) -> Int64 {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return 0
        }
        defer { try? handle.close() }

        guard let rawData = try? handle.readToEnd(), !rawData.isEmpty else {
            return 0
        }

        var lastSequence: Int64 = 0
        rawData.split(separator: 0x0A).forEach { line in
            let lineData = Data(line)
            if let sequence = sequence(from: lineData) {
                lastSequence = max(lastSequence, sequence)
            }
        }
        return lastSequence
    }

    private static func sequence(from lineData: Data) -> Int64? {
        guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return nil
        }
        if let sequence = object["sequence"] as? NSNumber {
            return sequence.int64Value
        }
        return nil
    }
}
