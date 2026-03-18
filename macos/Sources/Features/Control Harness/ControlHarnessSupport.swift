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

struct ControlHarnessReadChangedRow: Encodable {
    let index: Int
    let kind: String
    let text: String?
}

struct ControlHarnessReadDelta {
    let kind: String
    let text: String
    let changedRows: [ControlHarnessReadChangedRow]
    let hasChanges: Bool
}

struct ControlHarnessReadWindow {
    let text: String
    let totalLines: Int
    let returnedLines: Int
    let truncated: Bool
    let nextCursor: String?
}

struct ControlHarnessReadFrameSnapshot {
    let frameID: String
    let parentFrameID: String?
    let delta: ControlHarnessReadDelta
}

private enum ControlHarnessPendingWriteKind {
    case text
    case command(String)
}

private struct ControlHarnessPendingWriteScopeState {
    let baselineFrameID: String?
    var firstPostWriteFrameID: String?
    var awaitingDistinctNonEchoFrame: Bool
    var isReady: Bool
}

private struct ControlHarnessPendingWriteEntry {
    let terminalID: String
    let sequence: Int64
    let kind: ControlHarnessPendingWriteKind
    var scopeStates: [String: ControlHarnessPendingWriteScopeState]
}

@MainActor
final class ControlHarnessTerminalReadStore {
    private struct FrameKey: Hashable {
        let terminalID: String
        let scope: String
    }

    private struct Frame {
        let frameID: String
        let parentFrameID: String?
        let terminalID: String
        let scope: String
        let content: String
        let lines: [String]
    }

    private var nextFrameID: Int64 = 0
    private var latestFrames: [FrameKey: Frame] = [:]
    private var framesByID: [String: Frame] = [:]
    private var frameOrder: [FrameKey: [String]] = [:]
    private let maxFramesPerKey = 32

    func latestFrameID(for terminalID: String, scope: String) -> String? {
        latestFrames[.init(terminalID: terminalID, scope: scope)]?.frameID
    }

    func capture(terminalID: String, scope: String, content: String) -> ControlHarnessReadFrameSnapshot {
        let key = FrameKey(terminalID: terminalID, scope: scope)
        let lines = splitLines(content)

        if let latest = latestFrames[key], latest.content == content {
            return .init(
                frameID: latest.frameID,
                parentFrameID: latest.parentFrameID,
                delta: .init(kind: "none", text: "", changedRows: [], hasChanges: false)
            )
        }

        let previous = latestFrames[key]
        let frameID = makeFrameID()
        let frame = Frame(
            frameID: frameID,
            parentFrameID: previous?.frameID,
            terminalID: terminalID,
            scope: scope,
            content: content,
            lines: lines
        )

        latestFrames[key] = frame
        framesByID[frameID] = frame
        frameOrder[key, default: []].append(frameID)
        pruneFrames(for: key)

        return .init(
            frameID: frameID,
            parentFrameID: previous?.frameID,
            delta: delta(from: previous, to: frame)
        )
    }

    func delta(from sinceFrameID: String?, to frameID: String) -> ControlHarnessReadDelta {
        guard let frame = framesByID[frameID] else {
            return .init(kind: "none", text: "", changedRows: [], hasChanges: false)
        }
        guard let sinceFrameID, let base = framesByID[sinceFrameID] else {
            return .init(kind: "reset", text: frame.content, changedRows: [], hasChanges: !frame.content.isEmpty)
        }
        guard base.terminalID == frame.terminalID, base.scope == frame.scope else {
            return .init(kind: "reset", text: frame.content, changedRows: [], hasChanges: !frame.content.isEmpty)
        }
        return delta(from: base, to: frame)
    }

    func window(
        frameID: String,
        cursor: String?,
        maxLines: Int?,
        maxChars: Int?
    ) -> ControlHarnessReadWindow {
        guard let frame = framesByID[frameID] else {
            return .init(text: "", totalLines: 0, returnedLines: 0, truncated: false, nextCursor: nil)
        }

        let totalLines = frame.lines.count
        let end = min(max(parseCursor(cursor) ?? totalLines, 0), totalLines)
        let start: Int
        if let maxLines {
            start = max(0, end - maxLines)
        } else {
            start = 0
        }

        var text = frame.lines[start..<end].joined(separator: "\n")
        var truncated = start > 0 || end < totalLines
        if let maxChars, maxChars >= 0, text.count > maxChars {
            text = String(text.suffix(maxChars))
            truncated = true
        }

        let nextCursor = start > 0 ? String(start) : nil
        return .init(
            text: text,
            totalLines: totalLines,
            returnedLines: max(end - start, 0),
            truncated: truncated,
            nextCursor: nextCursor
        )
    }

    private func delta(from previous: Frame?, to current: Frame) -> ControlHarnessReadDelta {
        guard let previous else {
            return .init(
                kind: "snapshot",
                text: current.content,
                changedRows: [],
                hasChanges: !current.content.isEmpty
            )
        }

        if previous.content == current.content {
            return .init(kind: "none", text: "", changedRows: [], hasChanges: false)
        }

        let sharedPrefix = sharedPrefixLineCount(previous.lines, current.lines)
        if sharedPrefix == previous.lines.count, current.lines.count >= previous.lines.count {
            let appended = Array(current.lines[sharedPrefix...])
            return .init(
                kind: "append",
                text: appended.joined(separator: "\n"),
                changedRows: appended.enumerated().map { offset, line in
                    .init(index: sharedPrefix + offset, kind: "insert", text: line)
                },
                hasChanges: true
            )
        }

        var changedRows: [ControlHarnessReadChangedRow] = []
        let limit = max(previous.lines.count, current.lines.count)
        for index in 0..<limit {
            let oldLine = index < previous.lines.count ? previous.lines[index] : nil
            let newLine = index < current.lines.count ? current.lines[index] : nil
            guard oldLine != newLine else { continue }

            let kind: String
            switch (oldLine, newLine) {
            case (nil, .some):
                kind = "insert"
            case (.some, nil):
                kind = "delete"
            default:
                kind = "update"
            }

            changedRows.append(.init(index: index, kind: kind, text: newLine))
        }

        let summary = changedRows.map { row -> String in
            switch row.kind {
            case "delete":
                return "[line \(row.index)] <deleted>"
            default:
                return "[line \(row.index)] \(row.text ?? "")"
            }
        }.joined(separator: "\n")

        return .init(kind: "rows", text: summary, changedRows: changedRows, hasChanges: !changedRows.isEmpty)
    }

    private func pruneFrames(for key: FrameKey) {
        guard var ordered = frameOrder[key], ordered.count > maxFramesPerKey else { return }
        while ordered.count > maxFramesPerKey {
            let evicted = ordered.removeFirst()
            framesByID.removeValue(forKey: evicted)
        }
        frameOrder[key] = ordered
    }

    private func makeFrameID() -> String {
        nextFrameID += 1
        return "frm_\(nextFrameID)"
    }

    private func parseCursor(_ cursor: String?) -> Int? {
        guard let cursor, !cursor.isEmpty else { return nil }
        return Int(cursor)
    }

    private func splitLines(_ content: String) -> [String] {
        content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    private func sharedPrefixLineCount(_ lhs: [String], _ rhs: [String]) -> Int {
        let count = min(lhs.count, rhs.count)
        var index = 0
        while index < count, lhs[index] == rhs[index] {
            index += 1
        }
        return index
    }
}

final class ControlHarnessReadAfterWriteStore {
    private let queue = DispatchQueue(label: "com.leongong.ghodex.control-harness.read-after-write")
    private var entries: [String: ControlHarnessPendingWriteEntry] = [:]

    func recordTextWrite(
        terminalID: String,
        writeID: String,
        sequence: Int64,
        visibleFrameID: String?,
        screenFrameID: String?
    ) {
        recordWrite(
            terminalID: terminalID,
            writeID: writeID,
            sequence: sequence,
            kind: .text,
            visibleFrameID: visibleFrameID,
            screenFrameID: screenFrameID
        )
    }

    func recordCommandWrite(
        terminalID: String,
        writeID: String,
        sequence: Int64,
        commandText: String,
        visibleFrameID: String?,
        screenFrameID: String?
    ) {
        recordWrite(
            terminalID: terminalID,
            writeID: writeID,
            sequence: sequence,
            kind: .command(commandText),
            visibleFrameID: visibleFrameID,
            screenFrameID: screenFrameID
        )
    }

    func readiness(
        for writeID: String,
        terminalID: String,
        scope: String,
        currentSequence: Int64,
        frame: ControlHarnessReadFrameSnapshot,
        delta: ControlHarnessReadDelta
    ) -> Bool {
        queue.sync {
            guard var entry = entries[writeID], entry.terminalID == terminalID else {
                return false
            }
            guard currentSequence >= entry.sequence else {
                return false
            }

            var scopeState = entry.scopeStates[scope] ?? .init(
                baselineFrameID: nil,
                firstPostWriteFrameID: nil,
                awaitingDistinctNonEchoFrame: false,
                isReady: false
            )

            if scopeState.isReady {
                return true
            }

            if frame.frameID == scopeState.baselineFrameID {
                entry.scopeStates[scope] = scopeState
                entries[writeID] = entry
                return false
            }

            let echoOnly = isEchoOnly(delta: delta, kind: entry.kind)
            if scopeState.firstPostWriteFrameID == nil {
                scopeState.firstPostWriteFrameID = frame.frameID
                scopeState.awaitingDistinctNonEchoFrame = echoOnly
                entry.scopeStates[scope] = scopeState
                entries[writeID] = entry
                return false
            }

            if scopeState.awaitingDistinctNonEchoFrame {
                if frame.frameID == scopeState.firstPostWriteFrameID || echoOnly {
                    if frame.frameID != scopeState.firstPostWriteFrameID {
                        scopeState.firstPostWriteFrameID = frame.frameID
                    }
                    entry.scopeStates[scope] = scopeState
                    entries[writeID] = entry
                    return false
                }
            }

            scopeState.awaitingDistinctNonEchoFrame = false
            scopeState.isReady = true
            entry.scopeStates[scope] = scopeState
            entries[writeID] = entry
            return true
        }
    }

    private func recordWrite(
        terminalID: String,
        writeID: String,
        sequence: Int64,
        kind: ControlHarnessPendingWriteKind,
        visibleFrameID: String?,
        screenFrameID: String?
    ) {
        queue.sync {
            entries[writeID] = .init(
                terminalID: terminalID,
                sequence: sequence,
                kind: kind,
                scopeStates: [
                    "visible": .init(
                        baselineFrameID: visibleFrameID,
                        firstPostWriteFrameID: nil,
                        awaitingDistinctNonEchoFrame: false,
                        isReady: false
                    ),
                    "screen": .init(
                        baselineFrameID: screenFrameID,
                        firstPostWriteFrameID: nil,
                        awaitingDistinctNonEchoFrame: false,
                        isReady: false
                    ),
                ]
            )
        }
    }

    private func isEchoOnly(delta: ControlHarnessReadDelta, kind: ControlHarnessPendingWriteKind) -> Bool {
        guard case .command(let commandText) = kind else {
            return false
        }

        let trimmedCommand = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return false }

        let changedTexts = delta.changedRows.compactMap(\.text)
        guard !changedTexts.isEmpty, changedTexts.count == 1 else {
            return false
        }

        let line = changedTexts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return false }
        return line.contains(trimmedCommand)
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

struct ControlHarnessSubscriptionEnvelope {
    let response: ControlHarnessResponse
    let session: ControlHarnessEventSubscriptionSession?
}

enum ControlHarnessServiceReply {
    case single(ControlHarnessResponse)
    case subscription(ControlHarnessSubscriptionEnvelope)
}

final class ControlHarnessEventSubscriptionSession {
    private let queue = DispatchQueue(label: "com.leongong.ghodex.control-harness.subscription")
    private let eventHub: ControlHarnessEventHub

    let replayEvents: [Data]
    private var remainingLiveEvents: Int?
    private var finished = false
    private var bufferingLiveEvents = false
    private var bufferedLiveEvents: [Data] = []
    private var deliverySink: (@Sendable (Data) -> Bool)?
    private var finishHandler: (@Sendable () -> Void)?
    private var finishSignaled = false
    private var completionPending = false

    init(eventHub: ControlHarnessEventHub, replayEvents: [Data], eventLimit: Int?) {
        self.eventHub = eventHub
        self.replayEvents = replayEvents
        if let eventLimit {
            self.remainingLiveEvents = max(eventLimit - replayEvents.count, 0)
        } else {
            self.remainingLiveEvents = nil
        }
    }

    var shouldStreamLive: Bool {
        queue.sync { !finished && remainingLiveEvents != 0 }
    }

    func addSubscriber(
        sink: @escaping @Sendable (Data) -> Bool,
        onFinish: @escaping @Sendable () -> Void
    ) -> UUID? {
        queue.sync {
            guard !finished, remainingLiveEvents != 0 else {
                finished = true
                signalFinishLocked(onFinish)
                return nil
            }
            bufferingLiveEvents = true
            bufferedLiveEvents.removeAll(keepingCapacity: true)
            deliverySink = sink
            finishHandler = onFinish
            completionPending = false
            return eventHub.addSubscriber { [weak self] data in
                guard let self else {
                    onFinish()
                    return false
                }
                return self.consumeLiveEvent(data: data)
            }
        }
    }

    func completeReplay() {
        queue.sync {
            bufferingLiveEvents = false

            while !bufferedLiveEvents.isEmpty {
                let data = bufferedLiveEvents.removeFirst()
                guard let deliverySink, deliverySink(data) else {
                    finished = true
                    completionPending = true
                    bufferedLiveEvents.removeAll(keepingCapacity: false)
                    break
                }
            }

            if completionPending {
                signalFinishLocked()
            }
        }
    }

    private func consumeLiveEvent(data: Data) -> Bool {
        queue.sync {
            guard !finished, remainingLiveEvents != 0 else {
                finished = true
                if bufferingLiveEvents {
                    completionPending = true
                } else {
                    signalFinishLocked()
                }
                return false
            }

            if bufferingLiveEvents {
                bufferedLiveEvents.append(data)
            } else {
                guard let deliverySink, deliverySink(data) else {
                    finished = true
                    signalFinishLocked()
                    return false
                }
            }

            if let remainingLiveEvents {
                let next = remainingLiveEvents - 1
                self.remainingLiveEvents = next
                if next == 0 {
                    finished = true
                    if bufferingLiveEvents {
                        completionPending = true
                    } else {
                        signalFinishLocked()
                    }
                    return false
                }
            }

            return true
        }
    }

    private func signalFinishLocked(_ finishHandlerOverride: (@Sendable () -> Void)? = nil) {
        guard !finishSignaled else { return }
        finishSignaled = true
        (finishHandlerOverride ?? finishHandler)?()
    }
}
