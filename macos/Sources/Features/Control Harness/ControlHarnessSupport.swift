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
        case "new-tab",
            "close-tab",
            "rename-tab",
            "send-text",
            "run-command",
            "close-terminal",
            "todo-add",
            "todo-update",
            "todo-complete",
            "todo-assign",
            "todo-sync-stale":
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
    var lastAccessedAt: Date
}

enum ControlHarnessIdempotencyLookup {
    case miss
    case hit(ControlHarnessResponse, Int64?)
    case conflict
}

final class ControlHarnessIdempotencyStore {
    private static let entryTTL: TimeInterval = 15 * 60
    private static let maxEntries = 4_096

    private let queue = DispatchQueue(label: "com.leongong.ghodex.control-harness.idempotency")
    private var entries: [String: ControlHarnessIdempotencyEntry] = [:]
    private var entryOrder: [String] = []

    func lookup(token: String, fingerprint: Data) -> ControlHarnessIdempotencyLookup {
        queue.sync {
            let now = Date()
            pruneLocked(now: now)
            guard var entry = entries[token] else {
                return .miss
            }
            guard entry.fingerprint == fingerprint else {
                return .conflict
            }

            entry.lastAccessedAt = now
            entries[token] = entry
            touchEntryLocked(token)
            return .hit(entry.response, entry.sequence)
        }
    }

    func store(
        response: ControlHarnessResponse,
        sequence: Int64?,
        token: String,
        fingerprint: Data
    ) {
        queue.sync {
            let now = Date()
            pruneLocked(now: now)
            entries[token] = .init(
                fingerprint: fingerprint,
                response: response,
                sequence: sequence,
                lastAccessedAt: now
            )
            touchEntryLocked(token)
            pruneLocked(now: now)
        }
    }

    private func touchEntryLocked(_ token: String) {
        entryOrder.removeAll { $0 == token }
        entryOrder.append(token)
    }

    private func pruneLocked(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.entryTTL)
        var removedByTTL = 0
        for (token, entry) in entries where entry.lastAccessedAt < cutoff {
            entries.removeValue(forKey: token)
            removedByTTL += 1
        }

        entryOrder.removeAll { entries[$0] == nil }
        var removedByCapacity = 0
        while entries.count > Self.maxEntries, let oldest = entryOrder.first {
            entryOrder.removeFirst()
            entries.removeValue(forKey: oldest)
            removedByCapacity += 1
        }

        if removedByTTL > 0 || removedByCapacity > 0 {
            RuntimeDiagnosticsLogger.log(
                component: "control_harness.idempotency",
                event: "prune",
                details: [
                    "removed_ttl": "\(removedByTTL)",
                    "removed_capacity": "\(removedByCapacity)",
                    "remaining_entries": "\(entries.count)",
                ]
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
    let createdAt: Date
    var scopeStates: [String: ControlHarnessPendingWriteScopeState]
}

@MainActor
final class ControlHarnessTerminalReadStore {
    struct DebugSnapshot {
        let keyCount: Int
        let totalFrameCount: Int
        let totalContentBytes: Int
    }

    private struct FrameKey: Hashable {
        let terminalID: String
        let scope: String
    }

    private struct Frame {
        let frameID: String
        let parentFrameID: String?
        let key: FrameKey
        let content: String
        let contentBytes: Int
    }

    private var nextFrameID: Int64 = 0
    private var latestFrames: [FrameKey: Frame] = [:]
    private var framesByID: [String: Frame] = [:]
    private var frameOrder: [FrameKey: [String]] = [:]
    private var globalFrameOrder: [String] = []
    private var totalContentBytes = 0
    private let maxFramesPerKey: Int
    private let maxTotalFrames: Int
    private let maxTotalContentBytes: Int

    init(
        maxFramesPerKey: Int = 32,
        maxTotalFrames: Int = 256,
        maxTotalContentBytes: Int = 16 * 1024 * 1024
    ) {
        self.maxFramesPerKey = max(1, maxFramesPerKey)
        self.maxTotalFrames = max(1, maxTotalFrames)
        self.maxTotalContentBytes = max(1, maxTotalContentBytes)
    }

    func latestFrameID(for terminalID: String, scope: String) -> String? {
        latestFrames[.init(terminalID: terminalID, scope: scope)]?.frameID
    }

    func removeTerminal(_ terminalID: String) {
        let frameIDs = framesByID.values
            .filter { $0.key.terminalID == terminalID }
            .map(\.frameID)

        for frameID in frameIDs {
            removeFrame(frameID)
        }

        latestFrames.keys
            .filter { $0.terminalID == terminalID }
            .forEach { latestFrames.removeValue(forKey: $0) }

        frameOrder.keys
            .filter { $0.terminalID == terminalID }
            .forEach { frameOrder.removeValue(forKey: $0) }
    }

    func debugSnapshot() -> DebugSnapshot {
        .init(
            keyCount: latestFrames.count,
            totalFrameCount: framesByID.count,
            totalContentBytes: totalContentBytes
        )
    }

    func capture(terminalID: String, scope: String, content: String) -> ControlHarnessReadFrameSnapshot {
        let key = FrameKey(terminalID: terminalID, scope: scope)

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
            key: key,
            content: content,
            contentBytes: estimatedContentBytes(for: content)
        )

        latestFrames[key] = frame
        storeFrame(frame)
        pruneFrames(for: key, protectedFrameID: frameID)
        pruneGlobalFrames(protectedFrameID: frameID)

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
        guard base.key == frame.key else {
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

        let lines = splitLines(frame.content)
        let totalLines = lines.count
        let end = min(max(parseCursor(cursor) ?? totalLines, 0), totalLines)
        let start: Int
        if let maxLines {
            start = max(0, end - maxLines)
        } else {
            start = 0
        }

        var text = lines[start..<end].joined(separator: "\n")
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

        let previousLines = splitLines(previous.content)
        let currentLines = splitLines(current.content)
        let sharedPrefix = sharedPrefixLineCount(previousLines, currentLines)
        if sharedPrefix == previousLines.count, currentLines.count >= previousLines.count {
            let appended = Array(currentLines[sharedPrefix...])
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
        let limit = max(previousLines.count, currentLines.count)
        for index in 0..<limit {
            let oldLine = index < previousLines.count ? previousLines[index] : nil
            let newLine = index < currentLines.count ? currentLines[index] : nil
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

    private func storeFrame(_ frame: Frame) {
        framesByID[frame.frameID] = frame
        frameOrder[frame.key, default: []].append(frame.frameID)
        globalFrameOrder.append(frame.frameID)
        totalContentBytes += frame.contentBytes
    }

    private func pruneFrames(for key: FrameKey, protectedFrameID: String) {
        while (frameOrder[key]?.count ?? 0) > maxFramesPerKey {
            guard let evicted = frameOrder[key]?.first else { break }
            if evicted == protectedFrameID {
                break
            }
            removeFrame(evicted)
        }
    }

    private func pruneGlobalFrames(protectedFrameID: String) {
        while framesByID.count > maxTotalFrames || totalContentBytes > maxTotalContentBytes {
            guard let evicted = nextEvictionCandidate(protectedFrameID: protectedFrameID) else { break }
            removeFrame(evicted)
        }
    }

    private func nextEvictionCandidate(protectedFrameID: String) -> String? {
        for frameID in globalFrameOrder {
            guard frameID != protectedFrameID, let frame = framesByID[frameID] else { continue }
            if latestFrames[frame.key]?.frameID != frameID {
                return frameID
            }
        }

        return globalFrameOrder.first { $0 != protectedFrameID }
    }

    private func removeFrame(_ frameID: String) {
        guard let frame = framesByID.removeValue(forKey: frameID) else { return }

        totalContentBytes = max(0, totalContentBytes - frame.contentBytes)

        if let index = globalFrameOrder.firstIndex(of: frameID) {
            globalFrameOrder.remove(at: index)
        }

        if var ordered = frameOrder[frame.key], let index = ordered.firstIndex(of: frameID) {
            ordered.remove(at: index)
            if ordered.isEmpty {
                frameOrder.removeValue(forKey: frame.key)
            } else {
                frameOrder[frame.key] = ordered
            }
        }

        if latestFrames[frame.key]?.frameID == frameID {
            if let replacementID = frameOrder[frame.key]?.last, let replacement = framesByID[replacementID] {
                latestFrames[frame.key] = replacement
            } else {
                latestFrames.removeValue(forKey: frame.key)
            }
        }
    }

    private func makeFrameID() -> String {
        nextFrameID += 1
        return "frm_\(nextFrameID)"
    }

    private func parseCursor(_ cursor: String?) -> Int? {
        guard let cursor, !cursor.isEmpty else { return nil }
        return Int(cursor)
    }

    private func estimatedContentBytes(for content: String) -> Int {
        content.utf8.count
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
    private static let pendingEntryTTL: TimeInterval = 5 * 60
    private static let completedEntryTTL: TimeInterval = 60
    private static let maxPendingEntries = 2_048
    private static let maxCompletedEntries = 1_024

    private let queue = DispatchQueue(label: "com.leongong.ghodex.control-harness.read-after-write")
    private var entries: [String: ControlHarnessPendingWriteEntry] = [:]
    private var entryOrder: [String] = []
    private var completedEntries: [String: Date] = [:]
    private var completedOrder: [String] = []

    func removeTerminal(_ terminalID: String) {
        queue.sync {
            let removedWriteIDs = entries
                .filter { $0.value.terminalID == terminalID }
                .map(\.key)
            guard !removedWriteIDs.isEmpty else { return }

            let removed = Set(removedWriteIDs)
            for writeID in removedWriteIDs {
                entries.removeValue(forKey: writeID)
            }
            entryOrder.removeAll { removed.contains($0) }
        }
    }

    func debugEntryCount() -> Int {
        queue.sync { entries.count }
    }

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
            let now = Date()
            pruneLocked(now: now)
            if let completedAt = completedEntries[writeID], now.timeIntervalSince(completedAt) <= Self.completedEntryTTL {
                touchCompletedEntryLocked(writeID)
                return true
            }

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
                touchPendingEntryLocked(writeID)
                return false
            }

            let echoOnly = isEchoOnly(delta: delta, kind: entry.kind)
            if scopeState.firstPostWriteFrameID == nil {
                scopeState.firstPostWriteFrameID = frame.frameID
                scopeState.awaitingDistinctNonEchoFrame = echoOnly
                entry.scopeStates[scope] = scopeState
                entries[writeID] = entry
                touchPendingEntryLocked(writeID)
                return false
            }

            if scopeState.awaitingDistinctNonEchoFrame {
                if frame.frameID == scopeState.firstPostWriteFrameID || echoOnly {
                    if frame.frameID != scopeState.firstPostWriteFrameID {
                        scopeState.firstPostWriteFrameID = frame.frameID
                    }
                    entry.scopeStates[scope] = scopeState
                    entries[writeID] = entry
                    touchPendingEntryLocked(writeID)
                    return false
                }
            }

            scopeState.awaitingDistinctNonEchoFrame = false
            scopeState.isReady = true
            entry.scopeStates[scope] = scopeState
            if entry.scopeStates.values.allSatisfy({ $0.isReady }) {
                entries.removeValue(forKey: writeID)
                entryOrder.removeAll { $0 == writeID }
                completedEntries[writeID] = now
                touchCompletedEntryLocked(writeID)
                pruneLocked(now: now)
            } else {
                entries[writeID] = entry
                touchPendingEntryLocked(writeID)
            }
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
            let now = Date()
            pruneLocked(now: now)
            entries[writeID] = .init(
                terminalID: terminalID,
                sequence: sequence,
                kind: kind,
                createdAt: now,
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
            touchPendingEntryLocked(writeID)
            pruneLocked(now: now)
        }
    }

    private func touchPendingEntryLocked(_ writeID: String) {
        entryOrder.removeAll { $0 == writeID }
        entryOrder.append(writeID)
    }

    private func touchCompletedEntryLocked(_ writeID: String) {
        completedOrder.removeAll { $0 == writeID }
        completedOrder.append(writeID)
    }

    private func pruneLocked(now: Date) {
        let pendingCutoff = now.addingTimeInterval(-Self.pendingEntryTTL)
        var removedPendingByTTL = 0
        for (writeID, entry) in entries where entry.createdAt < pendingCutoff {
            entries.removeValue(forKey: writeID)
            removedPendingByTTL += 1
        }
        entryOrder.removeAll { entries[$0] == nil }
        var removedPendingByCapacity = 0
        while entries.count > Self.maxPendingEntries, let oldest = entryOrder.first {
            entryOrder.removeFirst()
            entries.removeValue(forKey: oldest)
            removedPendingByCapacity += 1
        }

        let completedCutoff = now.addingTimeInterval(-Self.completedEntryTTL)
        var removedCompletedByTTL = 0
        for (writeID, completedAt) in completedEntries where completedAt < completedCutoff {
            completedEntries.removeValue(forKey: writeID)
            removedCompletedByTTL += 1
        }
        completedOrder.removeAll { completedEntries[$0] == nil }
        var removedCompletedByCapacity = 0
        while completedEntries.count > Self.maxCompletedEntries, let oldest = completedOrder.first {
            completedOrder.removeFirst()
            completedEntries.removeValue(forKey: oldest)
            removedCompletedByCapacity += 1
        }

        if removedPendingByTTL > 0 ||
            removedPendingByCapacity > 0 ||
            removedCompletedByTTL > 0 ||
            removedCompletedByCapacity > 0 {
            RuntimeDiagnosticsLogger.log(
                component: "control_harness.read_after_write",
                event: "prune",
                details: [
                    "removed_pending_ttl": "\(removedPendingByTTL)",
                    "removed_pending_capacity": "\(removedPendingByCapacity)",
                    "removed_completed_ttl": "\(removedCompletedByTTL)",
                    "removed_completed_capacity": "\(removedCompletedByCapacity)",
                    "remaining_pending": "\(entries.count)",
                    "remaining_completed": "\(completedEntries.count)",
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

    private static let maxReplayEvents = 4_096
    private static let maxReplayBytes = 8 * 1024 * 1024

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
            let threshold = afterSequence ?? 0
            let effectiveLimit = limit.map { min($0, Self.maxReplayEvents) }
            var remaining = effectiveLimit
            var replayed: [Data] = []
            var replayedBytes = 0
            var truncatedByBudget = false

            Self.forEachJSONLLine(in: fileURL) { lineData in
                guard remaining != 0 else {
                    return false
                }
                guard let sequence = Self.sequence(from: lineData), sequence > threshold else {
                    return true
                }

                let eventData = lineData + Data([0x0A])
                let nextByteCount = replayedBytes + eventData.count
                if replayed.count >= Self.maxReplayEvents || nextByteCount > Self.maxReplayBytes {
                    truncatedByBudget = true
                    return false
                }

                replayed.append(eventData)
                replayedBytes = nextByteCount
                if let currentRemaining = remaining {
                    remaining = currentRemaining - 1
                }
                return remaining != 0
            }

            if truncatedByBudget {
                logger.notice(
                    "control harness replay truncated by budget replayed=\(replayed.count, privacy: .public) bytes=\(replayedBytes, privacy: .public)"
                )
                RuntimeDiagnosticsLogger.log(
                    component: "control_harness.events",
                    event: "replay_truncated",
                    details: [
                        "replayed_events": "\(replayed.count)",
                        "replayed_bytes": "\(replayedBytes)",
                        "threshold_sequence": "\(threshold)",
                        "effective_limit": "\(effectiveLimit?.description ?? "none")",
                    ]
                )
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
        var lastSequence: Int64 = 0
        Self.forEachJSONLLine(in: fileURL) { lineData in
            if let sequence = sequence(from: lineData) {
                lastSequence = max(lastSequence, sequence)
            }
            return true
        }
        return lastSequence
    }

    private static func forEachJSONLLine(
        in fileURL: URL,
        _ body: (Data) -> Bool
    ) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return
        }
        defer { try? handle.close() }

        var buffer = Data()
        while true {
            guard let chunk = try? handle.read(upToCount: 64 * 1024),
                  !chunk.isEmpty else {
                break
            }

            buffer.append(chunk)
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                if lineData.isEmpty {
                    continue
                }
                guard body(lineData) else {
                    return
                }
            }
        }

        if !buffer.isEmpty {
            _ = body(buffer)
        }
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
    private let maxBufferedLiveEvents: Int
    private let maxBufferedLiveBytes: Int

    let replayEvents: [Data]
    private var remainingLiveEvents: Int?
    private var finished = false
    private var bufferingLiveEvents = false
    private var bufferedLiveEvents: [Data] = []
    private var bufferedLiveEventBytes = 0
    private var deliverySink: (@Sendable (Data) -> Bool)?
    private var finishHandler: (@Sendable () -> Void)?
    private var finishSignaled = false
    private var completionPending = false

    init(
        eventHub: ControlHarnessEventHub,
        replayEvents: [Data],
        eventLimit: Int?,
        maxBufferedLiveEvents: Int = 512,
        maxBufferedLiveBytes: Int = 8 * 1024 * 1024
    ) {
        self.eventHub = eventHub
        self.replayEvents = replayEvents
        self.maxBufferedLiveEvents = max(1, maxBufferedLiveEvents)
        self.maxBufferedLiveBytes = max(1_024, maxBufferedLiveBytes)
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
            bufferedLiveEventBytes = 0
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
                bufferedLiveEventBytes = max(0, bufferedLiveEventBytes - data.count)
                guard let deliverySink, deliverySink(data) else {
                    finished = true
                    completionPending = true
                    bufferedLiveEvents.removeAll(keepingCapacity: false)
                    bufferedLiveEventBytes = 0
                    break
                }
            }

            if completionPending {
                signalFinishLocked()
            }
        }
    }

    func removeSubscriber(_ id: UUID?) {
        guard let id else { return }

        var shouldRemoveFromHub = false
        let finishHandler = queue.sync { () -> (@Sendable () -> Void)? in
            guard !finished else { return nil }
            finished = true
            bufferingLiveEvents = false
            bufferedLiveEvents.removeAll(keepingCapacity: false)
            bufferedLiveEventBytes = 0
            completionPending = false
            shouldRemoveFromHub = true
            let handler = self.finishHandler
            deliverySink = nil
            self.finishHandler = nil
            return handler
        }

        if shouldRemoveFromHub {
            eventHub.removeSubscriber(id)
        }
        finishHandler?()
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
                appendBufferedLiveEventLocked(data)
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

    private func appendBufferedLiveEventLocked(_ data: Data) {
        bufferedLiveEvents.append(data)
        bufferedLiveEventBytes += data.count

        while bufferedLiveEvents.count > maxBufferedLiveEvents || bufferedLiveEventBytes > maxBufferedLiveBytes {
            guard !bufferedLiveEvents.isEmpty else { break }
            let dropped = bufferedLiveEvents.removeFirst()
            bufferedLiveEventBytes = max(0, bufferedLiveEventBytes - dropped.count)
        }
    }
}
