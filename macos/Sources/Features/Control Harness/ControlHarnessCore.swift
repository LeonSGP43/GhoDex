import AppKit
import Darwin
import Foundation
import OSLog
import GhoDexKit

struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeImpl = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}

private struct ControlTerminalSnapshotCapture {
    let content: String
    let consistency: String
    let cacheAgeMs: Int
    let capturedAt: Date
    let frame: ControlHarnessReadFrameSnapshot
}

private struct ControlTerminalStreamChunkPayload {
    let streamID: String
    let terminalID: String
    let generation: Int
    let frameID: String
    let parentFrameID: String?
    let deltaKind: String
    let content: String
    let changedRows: [ControlHarnessReadChangedRow]
}

private struct RuntimeDiagnosticsRecord: Encodable {
    let timestamp: String
    let component: String
    let event: String
    let details: [String: String]
}

private struct RuntimeLifecycleSessionState: Codable {
    let schemaVersion: Int
    var sessionID: String
    var pid: Int32
    var startedAt: String
    var lastUpdatedAt: String
    var gracefulEnd: Bool
    var gracefulEndReason: String?
    var terminateRequestedReason: String?
    var terminateRequestedBy: String?
    var lastSignal: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case pid
        case startedAt = "started_at"
        case lastUpdatedAt = "last_updated_at"
        case gracefulEnd = "graceful_end"
        case gracefulEndReason = "graceful_end_reason"
        case terminateRequestedReason = "terminate_requested_reason"
        case terminateRequestedBy = "terminate_requested_by"
        case lastSignal = "last_signal"
    }
}

private struct RuntimeDiagnosticsRegionSnapshot {
    let sampleDate: Date
    let sampledAt: String
    let iosurfaceResidentBytes: Int64?
    let ioacceleratorGraphicsResidentBytes: Int64?
    let mallocResidentBytes: Int64?
    let totalResidentBytes: Int64?
    let totalDirtyBytes: Int64?
    let totalSwappedBytes: Int64?
    let vmAllocateVirtualBytes: Int64?
    let vmAllocateResidentBytes: Int64?
    let vmAllocateDirtyBytes: Int64?
    let vmAllocateSwappedBytes: Int64?
    let vmAllocateRegionCount: Int?
    let vmAllocateSwappedRatio: Double?
    let memoryTag253VirtualBytes: Int64?
    let memoryTag253ResidentBytes: Int64?
    let memoryTag253SwappedBytes: Int64?
    let topSwappedRegionName: String?
    let topSwappedRegionBytes: Int64?
    let topResidentRegionName: String?
    let topResidentRegionBytes: Int64?
    let deltaIntervalSeconds: TimeInterval?
    let totalResidentDeltaBytes: Int64?
    let totalSwappedDeltaBytes: Int64?
    let vmAllocateVirtualDeltaBytes: Int64?
    let vmAllocateResidentDeltaBytes: Int64?
    let vmAllocateSwappedDeltaBytes: Int64?
    let memoryTag253SwappedDeltaBytes: Int64?
    let growthSuspect: String?

    func merge(into details: inout [String: String]) {
        details["vmmap_sampled_at"] = sampledAt
        if let iosurfaceResidentBytes {
            details["iosurface_resident_bytes"] = "\(iosurfaceResidentBytes)"
        }
        if let ioacceleratorGraphicsResidentBytes {
            details["ioaccelerator_graphics_resident_bytes"] = "\(ioacceleratorGraphicsResidentBytes)"
        }
        if let mallocResidentBytes {
            details["malloc_resident_bytes"] = "\(mallocResidentBytes)"
        }
        if let totalResidentBytes {
            details["total_resident_bytes"] = "\(totalResidentBytes)"
        }
        if let totalDirtyBytes {
            details["total_dirty_bytes"] = "\(totalDirtyBytes)"
        }
        if let totalSwappedBytes {
            details["total_swapped_bytes"] = "\(totalSwappedBytes)"
        }
        if let vmAllocateVirtualBytes {
            details["vm_allocate_virtual_bytes"] = "\(vmAllocateVirtualBytes)"
        }
        if let vmAllocateResidentBytes {
            details["vm_allocate_resident_bytes"] = "\(vmAllocateResidentBytes)"
        }
        if let vmAllocateDirtyBytes {
            details["vm_allocate_dirty_bytes"] = "\(vmAllocateDirtyBytes)"
        }
        if let vmAllocateSwappedBytes {
            details["vm_allocate_swapped_bytes"] = "\(vmAllocateSwappedBytes)"
        }
        if let vmAllocateRegionCount {
            details["vm_allocate_region_count"] = "\(vmAllocateRegionCount)"
        }
        if let vmAllocateSwappedRatio {
            details["vm_allocate_swapped_ratio"] = String(format: "%.6f", vmAllocateSwappedRatio)
        }
        if let memoryTag253VirtualBytes {
            details["memory_tag_253_virtual_bytes"] = "\(memoryTag253VirtualBytes)"
        }
        if let memoryTag253ResidentBytes {
            details["memory_tag_253_resident_bytes"] = "\(memoryTag253ResidentBytes)"
        }
        if let memoryTag253SwappedBytes {
            details["memory_tag_253_swapped_bytes"] = "\(memoryTag253SwappedBytes)"
        }
        if let topSwappedRegionName {
            details["top_swapped_region"] = topSwappedRegionName
        }
        if let topSwappedRegionBytes {
            details["top_swapped_region_bytes"] = "\(topSwappedRegionBytes)"
        }
        if let topResidentRegionName {
            details["top_resident_region"] = topResidentRegionName
        }
        if let topResidentRegionBytes {
            details["top_resident_region_bytes"] = "\(topResidentRegionBytes)"
        }
        if let deltaIntervalSeconds {
            details["vmmap_delta_interval_seconds"] = String(format: "%.3f", deltaIntervalSeconds)
        }
        if let totalResidentDeltaBytes {
            details["total_resident_delta_bytes"] = "\(totalResidentDeltaBytes)"
        }
        if let totalSwappedDeltaBytes {
            details["total_swapped_delta_bytes"] = "\(totalSwappedDeltaBytes)"
        }
        if let vmAllocateVirtualDeltaBytes {
            details["vm_allocate_virtual_delta_bytes"] = "\(vmAllocateVirtualDeltaBytes)"
        }
        if let vmAllocateResidentDeltaBytes {
            details["vm_allocate_resident_delta_bytes"] = "\(vmAllocateResidentDeltaBytes)"
        }
        if let vmAllocateSwappedDeltaBytes {
            details["vm_allocate_swapped_delta_bytes"] = "\(vmAllocateSwappedDeltaBytes)"
        }
        if let memoryTag253SwappedDeltaBytes {
            details["memory_tag_253_swapped_delta_bytes"] = "\(memoryTag253SwappedDeltaBytes)"
        }
        if let growthSuspect {
            details["vmmap_growth_suspect"] = growthSuspect
        }
    }
}

final class RuntimeDiagnosticsLogger {
    private static let fileName = "runtime-memory-diagnostics.jsonl"
    private static let rotatedFileName = "runtime-memory-diagnostics.1.jsonl"
    private static let lifecycleStateFileName = "runtime-lifecycle-state.json"
    private static let lifecycleStateSchemaVersion = 1
    private static let maxFileBytes: Int64 = 4 * 1024 * 1024
    private static let periodicRegionSampleSeconds: TimeInterval = 60

    static let shared = RuntimeDiagnosticsLogger()

    private let queue = DispatchQueue(label: "com.leongong.ghodex.runtime-diagnostics")
    private let queueSpecificKey = DispatchSpecificKey<Void>()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let fileManager = FileManager.default
    private let fileURL: URL?
    private let rotatedFileURL: URL?
    private let lockFileURL: URL?
    private let stateFileURL: URL?
    private let enabled: Bool
    private let vmmapSamplingEnabled: Bool
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.leongong.ghodex",
        category: "RuntimeDiagnostics"
    )
    private var periodicRegionSampler: DispatchSourceTimer?
    private var latestRegionSnapshot: RuntimeDiagnosticsRegionSnapshot?
    private var previousProcessMemorySnapshot: RuntimeProcessMemorySnapshot?
    private var previousProcessMemorySampleDate: Date?
    private var lifecycleSessionState: RuntimeLifecycleSessionState?
    private var lifecycleSessionStarted = false

    private init() {
        let configured = Self.parseEnabledFlag(ProcessInfo.processInfo.environment["GHODEX_RUNTIME_DIAG_LOG"])
        self.enabled = configured ?? true
        let vmmapConfigured = Self.parseEnabledFlag(ProcessInfo.processInfo.environment["GHODEX_RUNTIME_DIAG_VMMAP"])
        self.vmmapSamplingEnabled = vmmapConfigured ?? false
        queue.setSpecific(key: queueSpecificKey, value: ())
        guard enabled else {
            self.fileURL = nil
            self.rotatedFileURL = nil
            self.lockFileURL = nil
            self.stateFileURL = nil
            return
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.leongong.ghodex"
        let directory = Self.diagnosticsDirectory(bundleID: bundleID)
        self.fileURL = directory.appendingPathComponent(Self.fileName, isDirectory: false)
        self.rotatedFileURL = directory.appendingPathComponent(Self.rotatedFileName, isDirectory: false)
        self.lockFileURL = directory.appendingPathComponent("\(Self.fileName).lock", isDirectory: false)
        self.stateFileURL = directory.appendingPathComponent(Self.lifecycleStateFileName, isDirectory: false)
        self.ensureLifecycleSessionStarted(waitUntilFinished: true)
        self.startPeriodicRegionSampler()
    }

    static func log(component: String, event: String, details: [String: String] = [:]) {
        shared.append(component: component, event: event, details: details)
    }

    static func beginLifecycleSessionIfNeeded() {
        shared.ensureLifecycleSessionStarted(waitUntilFinished: false)
    }

    static func recordLifecycleTerminateRequested(
        reason: String,
        requestedBy: String,
        details: [String: String] = [:]
    ) {
        shared.appendLifecycleTerminateRequested(
            reason: reason,
            requestedBy: requestedBy,
            details: details
        )
    }

    static func recordLifecycleTerminateCancelled(
        reason: String,
        requestedBy: String,
        details: [String: String] = [:]
    ) {
        shared.appendLifecycleTerminateCancelled(
            reason: reason,
            requestedBy: requestedBy,
            details: details
        )
    }

    static func recordLifecycleSignalReceived(
        signalNumber: Int32,
        signalName: String,
        mappedReason: String
    ) {
        shared.appendLifecycleSignalReceived(
            signalNumber: signalNumber,
            signalName: signalName,
            mappedReason: mappedReason
        )
    }

    static func recordLifecycleWillTerminate(reason: String?, details: [String: String] = [:]) {
        shared.appendLifecycleWillTerminate(reason: reason, details: details)
    }

    static func markLifecycleGracefulTerminate(
        reason: String,
        details: [String: String] = [:]
    ) {
        shared.appendLifecycleGracefulTerminate(
            reason: reason,
            details: details
        )
    }

    private static func parseEnabledFlag(_ rawValue: String?) -> Bool? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func diagnosticsDirectory(bundleID: String) -> URL {
        let fileManager = FileManager.default
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private func append(component: String, event: String, details: [String: String]) {
        guard enabled else { return }
        runOnQueue(waitUntilFinished: false) { [weak self] in
            self?.writeRecordLocked(component: component, event: event, details: details)
        }
    }

    private func runOnQueue(waitUntilFinished: Bool, _ body: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            body()
            return
        }

        if waitUntilFinished {
            queue.sync(execute: body)
        } else {
            queue.async(execute: body)
        }
    }

    private func ensureLifecycleSessionStarted(waitUntilFinished: Bool) {
        guard enabled else { return }
        runOnQueue(waitUntilFinished: waitUntilFinished) { [weak self] in
            self?.ensureLifecycleSessionStartedLocked()
        }
    }

    private func ensureLifecycleSessionStartedLocked() {
        guard enabled else { return }
        guard !lifecycleSessionStarted else { return }
        lifecycleSessionStarted = true
        beginLifecycleSessionLocked()
    }

    private func appendLifecycleTerminateRequested(
        reason: String,
        requestedBy: String,
        details: [String: String]
    ) {
        guard enabled else { return }
        runOnQueue(waitUntilFinished: false) { [weak self] in
            guard let self else { return }
            self.ensureLifecycleSessionStartedLocked()

            var payload = details
            payload["reason"] = reason
            payload["requested_by"] = requestedBy
            self.appendLifecycleEventLocked(event: "terminate_requested", details: payload)
            self.updateLifecycleStateLocked { state in
                state.terminateRequestedReason = reason
                state.terminateRequestedBy = requestedBy
            }
        }
    }

    private func appendLifecycleTerminateCancelled(
        reason: String,
        requestedBy: String,
        details: [String: String]
    ) {
        guard enabled else { return }
        runOnQueue(waitUntilFinished: false) { [weak self] in
            guard let self else { return }
            self.ensureLifecycleSessionStartedLocked()

            var payload = details
            payload["reason"] = reason
            payload["requested_by"] = requestedBy
            self.appendLifecycleEventLocked(event: "terminate_cancelled", details: payload)
            self.updateLifecycleStateLocked { state in
                state.terminateRequestedReason = nil
                state.terminateRequestedBy = nil
            }
        }
    }

    private func appendLifecycleSignalReceived(
        signalNumber: Int32,
        signalName: String,
        mappedReason: String
    ) {
        guard enabled else { return }
        runOnQueue(waitUntilFinished: true) { [weak self] in
            guard let self else { return }
            self.ensureLifecycleSessionStartedLocked()

            self.appendLifecycleEventLocked(
                event: "signal_received",
                details: [
                    "signal_number": "\(signalNumber)",
                    "signal_name": signalName,
                    "mapped_reason": mappedReason,
                ]
            )
            self.updateLifecycleStateLocked { state in
                state.lastSignal = signalName
                state.terminateRequestedReason = mappedReason
                state.terminateRequestedBy = "signal"
            }
        }
    }

    private func appendLifecycleWillTerminate(reason: String?, details: [String: String]) {
        guard enabled else { return }
        runOnQueue(waitUntilFinished: true) { [weak self] in
            guard let self else { return }
            self.ensureLifecycleSessionStartedLocked()

            var payload = details
            if let reason {
                payload["reason"] = reason
            }
            self.appendLifecycleEventLocked(event: "will_terminate", details: payload)
        }
    }

    private func appendLifecycleGracefulTerminate(reason: String, details: [String: String]) {
        guard enabled else { return }
        runOnQueue(waitUntilFinished: true) { [weak self] in
            guard let self else { return }
            self.ensureLifecycleSessionStartedLocked()

            var payload = details
            payload["reason"] = reason
            self.appendLifecycleEventLocked(event: "graceful_terminate", details: payload)
            self.updateLifecycleStateLocked { state in
                state.gracefulEnd = true
                state.gracefulEndReason = reason
                if state.terminateRequestedReason == nil {
                    state.terminateRequestedReason = reason
                }
            }
        }
    }

    private func appendLifecycleEventLocked(event: String, details: [String: String]) {
        writeRecordLocked(
            component: "runtime.lifecycle",
            event: event,
            details: lifecycleDetailsLocked(details)
        )
    }

    private func lifecycleDetailsLocked(_ details: [String: String]) -> [String: String] {
        var enriched = details
        if let state = lifecycleSessionState {
            enriched["session_id"] = state.sessionID
            enriched["session_started_at"] = state.startedAt
            enriched["session_pid"] = "\(state.pid)"
        }
        return enriched
    }

    private func updateLifecycleStateLocked(
        _ mutate: (inout RuntimeLifecycleSessionState) -> Void
    ) {
        guard var state = lifecycleSessionState else { return }
        mutate(&state)
        state.lastUpdatedAt = Self.iso8601Timestamp()
        lifecycleSessionState = state
        persistLifecycleStateLocked(state)
    }

    private func persistLifecycleStateLocked(_ state: RuntimeLifecycleSessionState) {
        guard
            let stateFileURL,
            let lockFileURL
        else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: stateFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let stateData = try encoder.encode(state)
            try Self.withFileLock(lockFileURL: lockFileURL) {
                try stateData.write(to: stateFileURL, options: .atomic)
            }
        } catch {
            logger.error("failed to write runtime lifecycle state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func beginLifecycleSessionLocked() {
        guard
            enabled,
            let stateFileURL,
            let lockFileURL
        else {
            return
        }

        let previousState = readLifecycleStateLocked()
        if let previousState, !previousState.gracefulEnd {
            var details: [String: String] = [
                "previous_session_id": previousState.sessionID,
                "previous_started_at": previousState.startedAt,
                "previous_pid": "\(previousState.pid)",
            ]
            if let reason = previousState.terminateRequestedReason {
                details["previous_terminate_requested_reason"] = reason
            }
            if let requestedBy = previousState.terminateRequestedBy {
                details["previous_terminate_requested_by"] = requestedBy
            }
            if let signal = previousState.lastSignal {
                details["previous_last_signal"] = signal
            }
            if let gracefulReason = previousState.gracefulEndReason {
                details["previous_graceful_end_reason"] = gracefulReason
            }
            appendLifecycleEventLocked(event: "unclean_previous_session", details: details)
        }

        let nowTimestamp = Self.iso8601Timestamp()
        let state = RuntimeLifecycleSessionState(
            schemaVersion: Self.lifecycleStateSchemaVersion,
            sessionID: UUID().uuidString.lowercased(),
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: nowTimestamp,
            lastUpdatedAt: nowTimestamp,
            gracefulEnd: false,
            gracefulEndReason: nil,
            terminateRequestedReason: nil,
            terminateRequestedBy: nil,
            lastSignal: nil
        )
        lifecycleSessionState = state

        do {
            try fileManager.createDirectory(
                at: stateFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let stateData = try encoder.encode(state)
            try Self.withFileLock(lockFileURL: lockFileURL) {
                try stateData.write(to: stateFileURL, options: .atomic)
            }
        } catch {
            logger.error("failed to initialize runtime lifecycle state: \(error.localizedDescription, privacy: .public)")
        }

        appendLifecycleEventLocked(event: "session_start", details: [:])
    }

    private func readLifecycleStateLocked() -> RuntimeLifecycleSessionState? {
        guard
            let stateFileURL,
            let lockFileURL
        else {
            return nil
        }

        do {
            var state: RuntimeLifecycleSessionState?
            try Self.withFileLock(lockFileURL: lockFileURL) {
                guard fileManager.fileExists(atPath: stateFileURL.path) else {
                    state = nil
                    return
                }

                let stateData = try Data(contentsOf: stateFileURL)
                guard !stateData.isEmpty else {
                    state = nil
                    return
                }
                state = try JSONDecoder().decode(RuntimeLifecycleSessionState.self, from: stateData)
            }
            return state
        } catch {
            logger.error("failed to read runtime lifecycle state: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func iso8601Timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func rotateIfNeeded(
        fileURL: URL,
        rotatedFileURL: URL,
        fileManager: FileManager
    ) throws {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
            let bytes = (attributes[.size] as? NSNumber)?.int64Value,
            bytes >= maxFileBytes
        else {
            return
        }

        if fileManager.fileExists(atPath: rotatedFileURL.path) {
            try fileManager.removeItem(at: rotatedFileURL)
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.moveItem(at: fileURL, to: rotatedFileURL)
        }
    }

    private func startPeriodicRegionSampler() {
        guard enabled else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: .seconds(Int(Self.periodicRegionSampleSeconds)),
            leeway: .seconds(5)
        )
        timer.setEventHandler { [weak self] in
            self?.capturePeriodicRegionSampleLocked()
        }
        periodicRegionSampler = timer
        timer.resume()
    }

    private func capturePeriodicRegionSampleLocked() {
        guard enabled else { return }
        if vmmapSamplingEnabled {
            if let snapshot = Self.captureRegionSnapshot(
                processID: ProcessInfo.processInfo.processIdentifier,
                previous: latestRegionSnapshot
            ) {
                latestRegionSnapshot = snapshot
            }
        }
        writeRecordLocked(
            component: "runtime.memory",
            event: "periodic_sample",
            details: [
                "interval_seconds": String(format: "%.0f", Self.periodicRegionSampleSeconds),
            ]
        )
    }

    private func writeRecordLocked(component: String, event: String, details: [String: String]) {
        guard
            enabled,
            let fileURL,
            let rotatedFileURL,
            let lockFileURL
        else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            var enriched = details
            let sampledAt = Date()
            mergeProcessMemoryDetailsLocked(into: &enriched, sampledAt: sampledAt)
            latestRegionSnapshot?.merge(into: &enriched)

            let record = RuntimeDiagnosticsRecord(
                timestamp: ISO8601DateFormatter().string(from: sampledAt),
                component: component,
                event: event,
                details: enriched
            )
            var line = try encoder.encode(record)
            line.append(0x0A)

            try Self.withFileLock(lockFileURL: lockFileURL) {
                try Self.rotateIfNeeded(
                    fileURL: fileURL,
                    rotatedFileURL: rotatedFileURL,
                    fileManager: fileManager
                )
                try Self.appendLine(line, to: fileURL)
            }
        } catch {
            logger.error("failed to write runtime diagnostics record: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func withFileLock(lockFileURL: URL, _ body: () throws -> Void) throws {
        let fileDescriptor = open(
            lockFileURL.path,
            O_RDWR | O_CREAT,
            mode_t(S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        )
        guard fileDescriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(fileDescriptor) }

        guard flock(fileDescriptor, LOCK_EX) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = flock(fileDescriptor, LOCK_UN) }

        try body()
    }

    private static func appendLine(_ line: Data, to fileURL: URL) throws {
        let fileDescriptor = open(
            fileURL.path,
            O_WRONLY | O_CREAT | O_APPEND,
            mode_t(S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        )
        guard fileDescriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(fileDescriptor) }

        try line.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            var offset = 0
            while remaining > 0 {
                let wrote = Darwin.write(fileDescriptor, baseAddress.advanced(by: offset), remaining)
                if wrote < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                remaining -= wrote
                offset += wrote
            }
        }
    }

    private struct RuntimeProcessMemorySnapshot {
        let rssBytes: UInt64
        let virtualSizeBytes: UInt64
        let physicalFootprintBytes: UInt64?
    }

    private struct VmmapSummaryRow {
        let regionType: String
        let virtualBytes: Int64
        let residentBytes: Int64
        let dirtyBytes: Int64
        let swappedBytes: Int64
        let regionCount: Int
    }

    private func mergeProcessMemoryDetailsLocked(into details: inout [String: String], sampledAt: Date) {
        details["pid"] = "\(ProcessInfo.processInfo.processIdentifier)"

        guard let snapshot = Self.currentProcessMemorySnapshot() else { return }
        details["rss_bytes"] = "\(snapshot.rssBytes)"
        details["virtual_size_bytes"] = "\(snapshot.virtualSizeBytes)"
        if let footprintBytes = snapshot.physicalFootprintBytes {
            details["physical_footprint_bytes"] = "\(footprintBytes)"
        }

        if let previous = previousProcessMemorySnapshot {
            details["rss_delta_bytes"] = "\(Self.deltaUInt64(current: snapshot.rssBytes, previous: previous.rssBytes))"
            details["virtual_size_delta_bytes"] =
                "\(Self.deltaUInt64(current: snapshot.virtualSizeBytes, previous: previous.virtualSizeBytes))"
            if let currentFootprint = snapshot.physicalFootprintBytes,
               let previousFootprint = previous.physicalFootprintBytes {
                details["physical_footprint_delta_bytes"] =
                    "\(Self.deltaUInt64(current: currentFootprint, previous: previousFootprint))"
            }
        }

        if let previousSampleDate = previousProcessMemorySampleDate {
            details["process_memory_delta_interval_seconds"] =
                String(format: "%.3f", sampledAt.timeIntervalSince(previousSampleDate))
        }

        previousProcessMemorySnapshot = snapshot
        previousProcessMemorySampleDate = sampledAt
    }

    private static func currentProcessMemorySnapshot() -> RuntimeProcessMemorySnapshot? {
        var basicInfo = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let basicResult: kern_return_t = withUnsafeMutablePointer(to: &basicInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &basicCount
                )
            }
        }
        guard basicResult == KERN_SUCCESS else { return nil }

        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let vmResult: kern_return_t = withUnsafeMutablePointer(to: &vmInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &vmCount
                )
            }
        }

        return RuntimeProcessMemorySnapshot(
            rssBytes: UInt64(basicInfo.resident_size),
            virtualSizeBytes: UInt64(basicInfo.virtual_size),
            physicalFootprintBytes: vmResult == KERN_SUCCESS ? UInt64(vmInfo.phys_footprint) : nil
        )
    }

    private static func captureRegionSnapshot(
        processID: Int32,
        previous: RuntimeDiagnosticsRegionSnapshot?
    ) -> RuntimeDiagnosticsRegionSnapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/vmmap")
        process.arguments = ["-summary", "\(processID)"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard !outputData.isEmpty else { return nil }
        guard let output = String(data: outputData, encoding: .utf8) else { return nil }

        let rows = parseVmmapSummaryRows(from: output)
        guard !rows.isEmpty else { return nil }

        let sampledAtDate = Date()
        let totalRow = rows["TOTAL"]
        let vmAllocateRow = rows["VM_ALLOCATE"]
        let ioSurfaceRow = rows["IOSurface"]
        let ioAcceleratorGraphicsRow = rows["IOAccelerator (graphics)"]
        let mallocRow = rows["MALLOC"]
        let memoryTag253Row = rows["Memory Tag 253"]
        let topSwappedRow = rows.values
            .filter { $0.regionType != "TOTAL" }
            .max(by: { $0.swappedBytes < $1.swappedBytes })
        let topResidentRow = rows.values
            .filter { $0.regionType != "TOTAL" }
            .max(by: { $0.residentBytes < $1.residentBytes })

        let vmAllocateSwappedRatio: Double?
        if let vmAllocateSwappedBytes = vmAllocateRow?.swappedBytes,
           let totalSwappedBytes = totalRow?.swappedBytes,
           totalSwappedBytes > 0 {
            vmAllocateSwappedRatio = Double(vmAllocateSwappedBytes) / Double(totalSwappedBytes)
        } else {
            vmAllocateSwappedRatio = nil
        }

        let deltaIntervalSeconds = previous.map { sampledAtDate.timeIntervalSince($0.sampleDate) }
        let totalResidentDeltaBytes = Self.delta(
            current: totalRow?.residentBytes,
            previous: previous?.totalResidentBytes
        )
        let totalSwappedDeltaBytes = Self.delta(
            current: totalRow?.swappedBytes,
            previous: previous?.totalSwappedBytes
        )
        let vmAllocateVirtualDeltaBytes = Self.delta(
            current: vmAllocateRow?.virtualBytes,
            previous: previous?.vmAllocateVirtualBytes
        )
        let vmAllocateResidentDeltaBytes = Self.delta(
            current: vmAllocateRow?.residentBytes,
            previous: previous?.vmAllocateResidentBytes
        )
        let vmAllocateSwappedDeltaBytes = Self.delta(
            current: vmAllocateRow?.swappedBytes,
            previous: previous?.vmAllocateSwappedBytes
        )
        let memoryTag253SwappedDeltaBytes = Self.delta(
            current: memoryTag253Row?.swappedBytes,
            previous: previous?.memoryTag253SwappedBytes
        )
        let growthSuspect = Self.growthSuspect(
            vmAllocateSwappedRatio: vmAllocateSwappedRatio,
            vmAllocateSwappedDeltaBytes: vmAllocateSwappedDeltaBytes,
            totalSwappedDeltaBytes: totalSwappedDeltaBytes,
            vmAllocateVirtualDeltaBytes: vmAllocateVirtualDeltaBytes,
            memoryTag253SwappedDeltaBytes: memoryTag253SwappedDeltaBytes
        )

        return RuntimeDiagnosticsRegionSnapshot(
            sampleDate: sampledAtDate,
            sampledAt: ISO8601DateFormatter().string(from: sampledAtDate),
            iosurfaceResidentBytes: ioSurfaceRow?.residentBytes,
            ioacceleratorGraphicsResidentBytes: ioAcceleratorGraphicsRow?.residentBytes,
            mallocResidentBytes: mallocRow?.residentBytes,
            totalResidentBytes: totalRow?.residentBytes,
            totalDirtyBytes: totalRow?.dirtyBytes,
            totalSwappedBytes: totalRow?.swappedBytes,
            vmAllocateVirtualBytes: vmAllocateRow?.virtualBytes,
            vmAllocateResidentBytes: vmAllocateRow?.residentBytes,
            vmAllocateDirtyBytes: vmAllocateRow?.dirtyBytes,
            vmAllocateSwappedBytes: vmAllocateRow?.swappedBytes,
            vmAllocateRegionCount: vmAllocateRow?.regionCount,
            vmAllocateSwappedRatio: vmAllocateSwappedRatio,
            memoryTag253VirtualBytes: memoryTag253Row?.virtualBytes,
            memoryTag253ResidentBytes: memoryTag253Row?.residentBytes,
            memoryTag253SwappedBytes: memoryTag253Row?.swappedBytes,
            topSwappedRegionName: topSwappedRow?.regionType,
            topSwappedRegionBytes: topSwappedRow?.swappedBytes,
            topResidentRegionName: topResidentRow?.regionType,
            topResidentRegionBytes: topResidentRow?.residentBytes,
            deltaIntervalSeconds: deltaIntervalSeconds,
            totalResidentDeltaBytes: totalResidentDeltaBytes,
            totalSwappedDeltaBytes: totalSwappedDeltaBytes,
            vmAllocateVirtualDeltaBytes: vmAllocateVirtualDeltaBytes,
            vmAllocateResidentDeltaBytes: vmAllocateResidentDeltaBytes,
            vmAllocateSwappedDeltaBytes: vmAllocateSwappedDeltaBytes,
            memoryTag253SwappedDeltaBytes: memoryTag253SwappedDeltaBytes,
            growthSuspect: growthSuspect
        )
    }

    private static func parseVmmapSummaryRows(from vmmapSummary: String) -> [String: VmmapSummaryRow] {
        var rows: [String: VmmapSummaryRow] = [:]
        var inRegionSummaryTable = false

        for rawLine in vmmapSummary.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.contains("REGION TYPE") {
                inRegionSummaryTable = true
                continue
            }
            guard inRegionSummaryTable else { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("==========") else { continue }

            guard let row = parseVmmapSummaryRow(trimmed) else { continue }
            rows[row.regionType] = row

            if row.regionType == "TOTAL" {
                break
            }
        }

        return rows
    }

    private static func parseVmmapSummaryRow(_ line: String) -> VmmapSummaryRow? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 9 else { return nil }

        for valueStart in 1..<(tokens.count - 7) {
            guard
                let virtualBytes = parseByteToken(tokens[valueStart]),
                let residentBytes = parseByteToken(tokens[valueStart + 1]),
                let dirtyBytes = parseByteToken(tokens[valueStart + 2]),
                let swappedBytes = parseByteToken(tokens[valueStart + 3]),
                parseByteToken(tokens[valueStart + 4]) != nil,
                parseByteToken(tokens[valueStart + 5]) != nil,
                parseByteToken(tokens[valueStart + 6]) != nil
            else {
                continue
            }

            let regionCountToken = tokens[valueStart + 7].replacingOccurrences(of: ",", with: "")
            guard let regionCount = Int(regionCountToken) else { continue }

            let regionType = tokens[0..<valueStart].joined(separator: " ")
            guard !regionType.isEmpty else { continue }

            return VmmapSummaryRow(
                regionType: regionType,
                virtualBytes: virtualBytes,
                residentBytes: residentBytes,
                dirtyBytes: dirtyBytes,
                swappedBytes: swappedBytes,
                regionCount: regionCount
            )
        }

        return nil
    }

    private static func delta(current: Int64?, previous: Int64?) -> Int64? {
        guard let current, let previous else { return nil }
        return current - previous
    }

    private static func deltaUInt64(current: UInt64, previous: UInt64) -> Int64 {
        if current >= previous {
            let difference = current - previous
            return difference > UInt64(Int64.max) ? Int64.max : Int64(difference)
        }
        let difference = previous - current
        return difference > UInt64(Int64.max) ? Int64.min : -Int64(difference)
    }

    private static func growthSuspect(
        vmAllocateSwappedRatio: Double?,
        vmAllocateSwappedDeltaBytes: Int64?,
        totalSwappedDeltaBytes: Int64?,
        vmAllocateVirtualDeltaBytes: Int64?,
        memoryTag253SwappedDeltaBytes: Int64?
    ) -> String? {
        let positiveSignals: [(String, Int64)] = [
            ("vm_allocate_swapped_growth", vmAllocateSwappedDeltaBytes ?? Int64.min),
            ("total_swapped_growth", totalSwappedDeltaBytes ?? Int64.min),
            ("vm_allocate_virtual_growth", vmAllocateVirtualDeltaBytes ?? Int64.min),
            ("memory_tag_253_swapped_growth", memoryTag253SwappedDeltaBytes ?? Int64.min),
        ]
            .filter { $0.1 > 0 }

        if let strongestSignal = positiveSignals.max(by: { $0.1 < $1.1 }) {
            return strongestSignal.0
        }
        if let vmAllocateSwappedRatio, vmAllocateSwappedRatio >= 0.60 {
            return "vm_allocate_dominant_swapped"
        }
        return nil
    }

    private static func parseByteToken(_ token: String) -> Int64? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        guard let lastCharacter = normalized.last else { return nil }
        let multipliers: [Character: Double] = [
            "K": 1_024,
            "M": 1_024 * 1_024,
            "G": 1_024 * 1_024 * 1_024,
            "T": 1_024 * 1_024 * 1_024 * 1_024,
        ]

        if let multiplier = multipliers[lastCharacter] {
            let numberPortion = normalized.dropLast()
            guard let value = Double(numberPortion) else { return nil }
            return Int64(value * multiplier)
        }
        guard let bytes = Double(normalized) else { return nil }
        return Int64(bytes)
    }
}

struct ControlHarnessRequest: Codable {
    let requestID: String
    let protocolVersion: String?
    let authToken: String?
    let transportMode: String?
    let encryptedPayload: String?
    let command: String
    let date: String?
    let tabID: String?
    let parentTabID: String?
    let terminalID: String?
    let todoID: String?
    let windowNumber: Int?
    let panelID: String?
    let panelTabID: String?
    let scope: String?
    let text: String?
    let terminalKey: String?
    let commandText: String?
    let workingDirectory: String?
    let title: String?
    let notes: String?
    let environment: [String: String]?
    let force: Bool?
    let completed: Bool?
    let workspaceID: String?
    let includeCompleted: Bool?
    let client: String?
    let deviceID: String?
    let deviceLabel: String?
    let desktopID: String?
    let idempotencyKey: String?
    let expectedGeneration: Int?
    let sinceSequence: Int64?
    let eventLimit: Int?
    let mode: String?
    let sinceFrameID: String?
    let maxChars: Int?
    let maxLines: Int?
    let cursor: String?
    let readAfterWriteID: String?
    let streamID: String?
    let ackBytes: Int?
    let lastAckSequence: Int64?
    let pairingCode: String?
    let requestedScopes: [String]?
    let sessionID: String?
    let taskID: String?
    let scheduleID: String?
    let capabilities: [String]?
    let leaseDurationSeconds: Double?
    let taskKind: String?
    let taskKinds: [String]?
    let recurrenceMode: String?
    let intervalSeconds: Double?
    let priority: Int?
    let scheduledAt: String?
    let maxRetryCount: Int?
    let metadata: [String: String]?
    let taskState: String?
    let scheduleState: String?
    let errorSummary: String?
    let reason: String?
    let desktopLabel: String?
    let upstreamHost: String?
    let upstreamPort: UInt16?
    let browserTabID: String?
    let browserContextID: String?
    let pageID: String?
    let frameName: String?
    let documentRevision: Int?
    let payload: [String: String]?
    let target: ControlHarnessRequestTarget?
    let options: ControlHarnessRequestOptions?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case protocolVersion = "protocol_version"
        case authToken = "auth_token"
        case transportMode = "transport_mode"
        case encryptedPayload = "encrypted_payload"
        case command
        case date
        case tabID = "tab_id"
        case parentTabID = "parent_tab_id"
        case terminalID = "terminal_id"
        case todoID = "todo_id"
        case windowNumber = "window_number"
        case panelID = "panel_id"
        case panelTabID = "panel_tab_id"
        case scope
        case text
        case terminalKey = "terminal_key"
        case commandText = "command_text"
        case workingDirectory = "working_directory"
        case title
        case notes
        case environment
        case force
        case completed
        case workspaceID = "workspace_id"
        case includeCompleted = "include_completed"
        case client
        case deviceID = "device_id"
        case deviceLabel = "device_label"
        case desktopID = "desktop_id"
        case idempotencyKey = "idempotency_key"
        case expectedGeneration = "expected_generation"
        case sinceSequence = "since_sequence"
        case eventLimit = "event_limit"
        case mode
        case sinceFrameID = "since_frame_id"
        case maxChars = "max_chars"
        case maxLines = "max_lines"
        case cursor
        case readAfterWriteID = "read_after_write_id"
        case streamID = "stream_id"
        case ackBytes = "ack_bytes"
        case lastAckSequence = "last_ack_sequence"
        case pairingCode = "pairing_code"
        case requestedScopes = "requested_scopes"
        case sessionID = "session_id"
        case taskID = "task_id"
        case scheduleID = "schedule_id"
        case capabilities
        case leaseDurationSeconds = "lease_duration_seconds"
        case taskKind = "task_kind"
        case taskKinds = "task_kinds"
        case recurrenceMode = "recurrence_mode"
        case intervalSeconds = "interval_seconds"
        case priority
        case scheduledAt = "scheduled_at"
        case maxRetryCount = "max_retry_count"
        case metadata
        case taskState = "task_state"
        case scheduleState = "schedule_state"
        case errorSummary = "error_summary"
        case reason
        case desktopLabel = "desktop_label"
        case upstreamHost = "upstream_host"
        case upstreamPort = "upstream_port"
        case browserTabID = "browser_tab_id"
        case browserContextID = "browser_context_id"
        case pageID = "page_id"
        case frameName = "frame_name"
        case documentRevision = "document_revision"
        case payload
        case target
        case options
    }

    init(
        requestID: String,
        protocolVersion: String?,
        authToken: String? = nil,
        transportMode: String? = nil,
        encryptedPayload: String? = nil,
        command: String,
        date: String? = nil,
        tabID: String?,
        parentTabID: String?,
        terminalID: String?,
        todoID: String? = nil,
        windowNumber: Int? = nil,
        panelID: String? = nil,
        panelTabID: String? = nil,
        scope: String?,
        text: String?,
        terminalKey: String? = nil,
        commandText: String?,
        workingDirectory: String?,
        title: String?,
        notes: String? = nil,
        environment: [String: String]?,
        force: Bool?,
        completed: Bool? = nil,
        workspaceID: String? = nil,
        includeCompleted: Bool? = nil,
        client: String?,
        deviceID: String? = nil,
        deviceLabel: String? = nil,
        desktopID: String? = nil,
        idempotencyKey: String?,
        expectedGeneration: Int?,
        sinceSequence: Int64?,
        eventLimit: Int?,
        mode: String?,
        sinceFrameID: String?,
        maxChars: Int?,
        maxLines: Int?,
        cursor: String?,
        readAfterWriteID: String?,
        streamID: String? = nil,
        ackBytes: Int? = nil,
        lastAckSequence: Int64? = nil,
        pairingCode: String? = nil,
        requestedScopes: [String]? = nil,
        sessionID: String? = nil,
        taskID: String? = nil,
        scheduleID: String? = nil,
        capabilities: [String]? = nil,
        leaseDurationSeconds: Double? = nil,
        taskKind: String? = nil,
        taskKinds: [String]? = nil,
        recurrenceMode: String? = nil,
        intervalSeconds: Double? = nil,
        priority: Int? = nil,
        scheduledAt: String? = nil,
        maxRetryCount: Int? = nil,
        metadata: [String: String]? = nil,
        taskState: String? = nil,
        scheduleState: String? = nil,
        errorSummary: String? = nil,
        reason: String? = nil,
        desktopLabel: String? = nil,
        upstreamHost: String? = nil,
        upstreamPort: UInt16? = nil,
        browserTabID: String? = nil,
        browserContextID: String? = nil,
        pageID: String? = nil,
        frameName: String? = nil,
        documentRevision: Int? = nil,
        payload: [String: String]? = nil,
        target: ControlHarnessRequestTarget? = nil,
        options: ControlHarnessRequestOptions? = nil
    ) {
        self.requestID = requestID
        self.protocolVersion = protocolVersion
        self.authToken = authToken
        self.transportMode = transportMode
        self.encryptedPayload = encryptedPayload
        self.command = command
        self.date = date
        self.tabID = tabID
        self.parentTabID = parentTabID
        self.terminalID = terminalID
        self.todoID = todoID
        self.windowNumber = windowNumber
        self.panelID = panelID
        self.panelTabID = panelTabID
        self.scope = scope
        self.text = text
        self.terminalKey = terminalKey
        self.commandText = commandText
        self.workingDirectory = workingDirectory
        self.title = title
        self.notes = notes
        self.environment = environment
        self.force = force
        self.completed = completed
        self.workspaceID = workspaceID
        self.includeCompleted = includeCompleted
        self.client = client
        self.deviceID = deviceID
        self.deviceLabel = deviceLabel
        self.desktopID = desktopID
        self.idempotencyKey = idempotencyKey
        self.expectedGeneration = expectedGeneration
        self.sinceSequence = sinceSequence
        self.eventLimit = eventLimit
        self.mode = mode
        self.sinceFrameID = sinceFrameID
        self.maxChars = maxChars
        self.maxLines = maxLines
        self.cursor = cursor
        self.readAfterWriteID = readAfterWriteID
        self.streamID = streamID
        self.ackBytes = ackBytes
        self.lastAckSequence = lastAckSequence
        self.pairingCode = pairingCode
        self.requestedScopes = requestedScopes
        self.sessionID = sessionID
        self.taskID = taskID
        self.scheduleID = scheduleID
        self.capabilities = capabilities
        self.leaseDurationSeconds = leaseDurationSeconds
        self.taskKind = taskKind
        self.taskKinds = taskKinds
        self.recurrenceMode = recurrenceMode
        self.intervalSeconds = intervalSeconds
        self.priority = priority
        self.scheduledAt = scheduledAt
        self.maxRetryCount = maxRetryCount
        self.metadata = metadata
        self.taskState = taskState
        self.scheduleState = scheduleState
        self.errorSummary = errorSummary
        self.reason = reason
        self.desktopLabel = desktopLabel
        self.upstreamHost = upstreamHost
        self.upstreamPort = upstreamPort
        self.browserTabID = browserTabID
        self.browserContextID = browserContextID
        self.pageID = pageID
        self.frameName = frameName
        self.documentRevision = documentRevision
        self.payload = payload
        self.target = target
        self.options = options
    }
}

struct ControlHarnessResponse: Encodable {
    let requestID: String
    let status: String
    let result: AnyEncodable?
    let errorCode: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case result
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(status, forKey: .status)
        if let result {
            try result.encode(to: container.superEncoder(forKey: .result))
        }
        try container.encodeIfPresent(errorCode, forKey: .errorCode)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
    }
}

private struct ControlHandshakeResult: Encodable {
    let protocolVersion: String
    let socketPath: String
    let commands: [String]
    let compatibility: ControlCompatibilityMetadata
    let lastSequence: Int64

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case socketPath = "socket_path"
        case commands
        case compatibility
        case lastSequence = "last_sequence"
    }
}

private struct ControlResolvedInstanceRecord: Encodable {
    let socketPath: String
    let processID: Int32
    let bundleID: String
    let executablePath: String?

    enum CodingKeys: String, CodingKey {
        case socketPath = "socket_path"
        case processID = "process_id"
        case bundleID = "bundle_id"
        case executablePath = "executable_path"
    }
}

private struct ControlTargetResolveResult: Encodable {
    let protocolVersion: String
    let instance: ControlResolvedInstanceRecord

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case instance
    }
}

private struct ControlCapabilitiesResult: Encodable {
    let protocolVersion: String
    let commands: [String]
    let backends: [String]
    let features: [String]
    let compatibility: ControlCompatibilityMetadata
    let lastSequence: Int64

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case commands
        case backends
        case features
        case compatibility
        case lastSequence = "last_sequence"
    }
}

private struct ControlCompatibilityMetadata: Encodable {
    let authority: String
    let legacyCommands: [String]
    let migrations: [ControlCommandMigrationNotice]

    enum CodingKeys: String, CodingKey {
        case authority
        case legacyCommands = "legacy_commands"
        case migrations
    }
}

private struct ControlCommandMigrationNotice: Encodable {
    let command: String
    let replacementCommands: [String]
    let status: String
    let removalPhase: String
    let detail: String

    enum CodingKeys: String, CodingKey {
        case command
        case replacementCommands = "replacement_commands"
        case status
        case removalPhase = "removal_phase"
        case detail
    }
}

private struct ControlSnapshotResult: Encodable {
    let protocolVersion: String
    let generatedAt: String
    let lastSequence: Int64
    let tabs: [ControlTabSnapshot]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case generatedAt = "generated_at"
        case lastSequence = "last_sequence"
        case tabs
    }
}

private struct ControlAppStateResult: Encodable {
    let protocolVersion: String
    let generatedAt: String
    let isActive: Bool
    let isHidden: Bool
    let frontmostWindowNumber: Int?
    let windowCount: Int
    let panelCount: Int
    let settingsDraftPending: Bool

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case generatedAt = "generated_at"
        case isActive = "is_active"
        case isHidden = "is_hidden"
        case frontmostWindowNumber = "frontmost_window_number"
        case windowCount = "window_count"
        case panelCount = "panel_count"
        case settingsDraftPending = "settings_draft_pending"
    }
}

private struct ControlWindowSummary: Encodable {
    let windowNumber: Int
    let kind: String
    let title: String
    let isVisible: Bool
    let isFocused: Bool
    let isMainWindow: Bool
    let isMiniaturized: Bool
    let isFloatingOnTop: Bool
    let tabbedWindowCount: Int
    let tabOverviewVisible: Bool

    enum CodingKeys: String, CodingKey {
        case windowNumber = "window_number"
        case kind
        case title
        case isVisible = "is_visible"
        case isFocused = "is_focused"
        case isMainWindow = "is_main_window"
        case isMiniaturized = "is_miniaturized"
        case isFloatingOnTop = "is_floating_on_top"
        case tabbedWindowCount = "tabbed_window_count"
        case tabOverviewVisible = "tab_overview_visible"
    }
}

private struct ControlWindowListResult: Encodable {
    let protocolVersion: String
    let windows: [ControlWindowSummary]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case windows
    }
}

private struct ControlWindowMutationResult: Encodable {
    let window: ControlWindowSummary
    let action: String

    enum CodingKeys: String, CodingKey {
        case window
        case action
    }
}

private struct ControlPanelSummary: Encodable {
    let panelID: String
    let title: String
    let isVisible: Bool
    let selectedTabID: String?
    let supportedTabIDs: [String]
    let windowNumber: Int?

    enum CodingKeys: String, CodingKey {
        case panelID = "panel_id"
        case title
        case isVisible = "is_visible"
        case selectedTabID = "selected_tab_id"
        case supportedTabIDs = "supported_tab_ids"
        case windowNumber = "window_number"
    }
}

private struct ControlPanelListResult: Encodable {
    let protocolVersion: String
    let panels: [ControlPanelSummary]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case panels
    }
}

private struct ControlPanelMutationResult: Encodable {
    let panel: ControlPanelSummary
    let action: String

    enum CodingKeys: String, CodingKey {
        case panel
        case action
    }
}

private struct ControlSettingsSchemaEntry: Encodable {
    let key: String
    let valueType: String
    let defaultValue: String
    let enumValues: [String]?
    let description: String

    enum CodingKeys: String, CodingKey {
        case key
        case valueType = "value_type"
        case defaultValue = "default_value"
        case enumValues = "enum_values"
        case description
    }
}

private struct ControlSettingsSchemaResult: Encodable {
    let protocolVersion: String
    let entries: [ControlSettingsSchemaEntry]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case entries
    }
}

private struct ControlSettingsValuesResult: Encodable {
    let protocolVersion: String
    let values: [String: String]
    let stagedValues: [String: String]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case values
        case stagedValues = "staged_values"
    }
}

private struct ControlSettingsDiffEntry: Encodable {
    let key: String
    let currentValue: String
    let nextValue: String

    enum CodingKeys: String, CodingKey {
        case key
        case currentValue = "current_value"
        case nextValue = "next_value"
    }
}

private struct ControlSettingsDiffResult: Encodable {
    let protocolVersion: String
    let entries: [ControlSettingsDiffEntry]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case entries
    }
}

private struct ControlSettingsMutationResult: Encodable {
    let protocolVersion: String
    let values: [String: String]
    let stagedValues: [String: String]?
    let changedKeys: [String]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case values
        case stagedValues = "staged_values"
        case changedKeys = "changed_keys"
    }
}

private struct ControlDiagnosticsMetricsResult: Encodable {
    let protocolVersion: String
    let metrics: ControlHarnessPerformanceSnapshot

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case metrics
    }
}

private struct ControlDiagnosticsLogLine: Encodable {
    let source: String
    let lineNumber: Int
    let raw: String

    enum CodingKeys: String, CodingKey {
        case source
        case lineNumber = "line_number"
        case raw
    }
}

private struct ControlDiagnosticsLogsTailResult: Encodable {
    let protocolVersion: String
    let source: String
    let lines: [ControlDiagnosticsLogLine]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case source
        case lines
    }
}

private struct ControlDiagnosticsRecentError: Encodable {
    let source: String
    let timestamp: String?
    let code: String?
    let message: String
    let command: String?

    enum CodingKeys: String, CodingKey {
        case source
        case timestamp
        case code
        case message
        case command
    }
}

private struct ControlDiagnosticsRecentErrorsResult: Encodable {
    let protocolVersion: String
    let errors: [ControlDiagnosticsRecentError]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case errors
    }
}

private struct ControlDiagnosticsAuditQueryResult: Encodable {
    let protocolVersion: String
    let records: [ControlAuditRecord]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case records
    }
}

private struct ControlDiagnosticsEventBufferStatusResult: Encodable {
    let protocolVersion: String
    let status: ControlDiagnosticsEventBufferStatus

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case status
    }
}

private struct ControlDiagnosticsEventBufferStatus: Encodable {
    let subscriptionCount: Int
    let liveSubscriptionCount: Int
    let bufferedEventCount: Int
    let bufferedBytes: Int
    let subscriptionsRequiringSnapshotResync: Int
    let droppedEvents: Int
    let maxBufferedEvents: Int
    let maxBufferedBytes: Int

    enum CodingKeys: String, CodingKey {
        case subscriptionCount = "subscription_count"
        case liveSubscriptionCount = "live_subscription_count"
        case bufferedEventCount = "buffered_event_count"
        case bufferedBytes = "buffered_bytes"
        case subscriptionsRequiringSnapshotResync = "subscriptions_requiring_snapshot_resync"
        case droppedEvents = "dropped_events"
        case maxBufferedEvents = "max_buffered_events"
        case maxBufferedBytes = "max_buffered_bytes"
    }
}

private struct ControlTabSnapshot: Encodable {
    let tabID: String
    let generation: Int
    let windowNumber: Int
    let title: String
    let isFocused: Bool
    let isMainWindow: Bool
    let hasBell: Bool
    let terminals: [ControlTerminalSnapshot]

    enum CodingKeys: String, CodingKey {
        case tabID = "tab_id"
        case generation
        case windowNumber = "window_number"
        case title
        case isFocused = "is_focused"
        case isMainWindow = "is_main_window"
        case hasBell = "has_bell"
        case terminals
    }
}

private struct ControlTerminalSnapshot: Encodable {
    let terminalID: String
    let generation: Int
    let title: String
    let workingDirectory: String?
    let isFocused: Bool
    let isVisible: Bool

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case generation
        case title
        case workingDirectory = "working_directory"
        case isFocused = "is_focused"
        case isVisible = "is_visible"
    }
}

private struct ControlCreateTabResult: Encodable {
    let tabID: String
    let tabGeneration: Int
    let terminalID: String?
    let terminalGeneration: Int?
    let sequence: Int64

    enum CodingKeys: String, CodingKey {
        case tabID = "tab_id"
        case tabGeneration = "tab_generation"
        case terminalID = "terminal_id"
        case terminalGeneration = "terminal_generation"
        case sequence
    }
}

private struct ControlReadTerminalResult: Encodable {
    let terminalID: String
    let generation: Int
    let scope: String
    let mode: String
    let contentKind: String
    let consistency: String
    let capturedAt: String
    let cacheAgeMs: Int
    let lastSequence: Int64
    let frameID: String
    let parentFrameID: String?
    let hasChanges: Bool
    let deltaKind: String
    let deltaText: String?
    let changedRows: [ControlHarnessReadChangedRow]
    let totalLines: Int
    let returnedLines: Int
    let truncated: Bool
    let nextCursor: String?
    let observedWriteID: String?
    let readAfterReady: Bool?
    let content: String

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case generation
        case scope
        case mode
        case contentKind = "content_kind"
        case consistency
        case capturedAt = "captured_at"
        case cacheAgeMs = "cache_age_ms"
        case lastSequence = "last_sequence"
        case frameID = "frame_id"
        case parentFrameID = "parent_frame_id"
        case hasChanges = "has_changes"
        case deltaKind = "delta_kind"
        case deltaText = "delta_text"
        case changedRows = "changed_rows"
        case totalLines = "total_lines"
        case returnedLines = "returned_lines"
        case truncated
        case nextCursor = "next_cursor"
        case observedWriteID = "observed_write_id"
        case readAfterReady = "read_after_ready"
        case content
    }
}

private struct ControlTabCloseResult: Encodable {
    let tabID: String
    let generation: Int
    let sequence: Int64
    let closed: Bool
    let requiresConfirmation: Bool
    let confirmationTitle: String?
    let confirmationMessage: String?

    enum CodingKeys: String, CodingKey {
        case tabID = "tab_id"
        case generation
        case sequence
        case closed
        case requiresConfirmation = "requires_confirmation"
        case confirmationTitle = "confirmation_title"
        case confirmationMessage = "confirmation_message"
    }
}

private struct ControlTabMutationResult: Encodable {
    let tabID: String
    let generation: Int
    let sequence: Int64
    let title: String?
    let closed: Bool
    let requiresConfirmation: Bool
    let confirmationTitle: String?
    let confirmationMessage: String?

    enum CodingKeys: String, CodingKey {
        case tabID = "tab_id"
        case generation
        case sequence
        case title
        case closed
        case requiresConfirmation = "requires_confirmation"
        case confirmationTitle = "confirmation_title"
        case confirmationMessage = "confirmation_message"
    }
}

struct ControlTabCloseConfirmation: Equatable {
    let title: String
    let message: String

    static func resolve(hasMultipleTabs: Bool, needsConfirmQuit: Bool) -> Self? {
        guard needsConfirmQuit else {
            return nil
        }

        if hasMultipleTabs {
            return .init(
                title: "Close Tab?",
                message: "The terminal still has a running process. If you close the tab the process will be killed."
            )
        }

        return .init(
            title: "Close Window?",
            message: "All terminal sessions in this window will be terminated."
        )
    }
}

private struct ControlTerminalMutationResult: Encodable {
    let terminalID: String
    let generation: Int
    let sequence: Int64
    let operation: String
    let acknowledged: Bool
    let writeID: String?

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case generation
        case sequence
        case operation
        case acknowledged
        case writeID = "write_id"
    }
}

private struct ControlTodoItemRecord: Encodable {
    let todoID: String
    let sourceDay: String?
    let sourceItemID: String?
    let title: String
    let notes: String
    let assignedWorkspaceID: String?
    let isCompleted: Bool
    let completedAt: String?
    let createdAt: String
    let updatedAt: String
    let sortOrder: Int
    let isCarryForwardPointer: Bool

    enum CodingKeys: String, CodingKey {
        case todoID = "todo_id"
        case sourceDay = "source_day"
        case sourceItemID = "source_item_id"
        case title
        case notes
        case assignedWorkspaceID = "assigned_workspace_id"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sortOrder = "sort_order"
        case isCarryForwardPointer = "is_carry_forward_pointer"
    }
}

private struct ControlTodoSnapshotResult: Encodable {
    let date: String
    let includeCompleted: Bool
    let updatedAt: String
    let completionRate: Double
    let totalCount: Int
    let completedCount: Int
    let remainingCount: Int
    let returnedCount: Int
    let items: [ControlTodoItemRecord]

    enum CodingKeys: String, CodingKey {
        case date
        case includeCompleted = "include_completed"
        case updatedAt = "updated_at"
        case completionRate = "completion_rate"
        case totalCount = "total_count"
        case completedCount = "completed_count"
        case remainingCount = "remaining_count"
        case returnedCount = "returned_count"
        case items
    }
}

private struct ControlTodoMutationResult: Encodable {
    let operation: String
    let date: String
    let mutatedTodoID: String?
    let syncedCount: Int?
    let snapshot: ControlTodoSnapshotResult

    enum CodingKeys: String, CodingKey {
        case operation
        case date
        case mutatedTodoID = "mutated_todo_id"
        case syncedCount = "synced_count"
        case snapshot
    }
}

private struct ControlEventSubscriptionResult: Encodable {
    let protocolVersion: String
    let subscribed: Bool
    let streamID: String?
    let lastSequence: Int64
    let sinceSequence: Int64?
    let eventLimit: Int?
    let replayedEventCount: Int
    let liveStreamOpen: Bool

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case subscribed
        case streamID = "stream_id"
        case lastSequence = "last_sequence"
        case sinceSequence = "since_sequence"
        case eventLimit = "event_limit"
        case replayedEventCount = "replayed_event_count"
        case liveStreamOpen = "live_stream_open"
    }
}

private struct ControlBufferedEventStreamDrainResult: Encodable {
    let protocolVersion: String
    let streamID: String
    let lastSequence: Int64
    let eventLimit: Int?
    let drainedEventCount: Int
    let requiresSnapshotResync: Bool
    let droppedEvents: Int
    let liveStreamOpen: Bool
    let events: [ControlHarnessJSONValue]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case streamID = "stream_id"
        case lastSequence = "last_sequence"
        case eventLimit = "event_limit"
        case drainedEventCount = "drained_event_count"
        case requiresSnapshotResync = "requires_snapshot_resync"
        case droppedEvents = "dropped_events"
        case liveStreamOpen = "live_stream_open"
        case events
    }
}

private struct ControlEventStreamUnsubscribeResult: Encodable {
    let protocolVersion: String
    let streamID: String
    let unsubscribed: Bool
    let liveStreamOpen: Bool

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case streamID = "stream_id"
        case unsubscribed
        case liveStreamOpen = "live_stream_open"
    }
}

private struct ControlTerminalStreamOpenResult: Encodable {
    let protocolVersion: String
    let streamID: String
    let terminalID: String
    let generation: Int
    let mode: String
    let lastSequence: Int64
    let liveStreamOpen: Bool
    let highWatermarkBytes: Int
    let lowWatermarkBytes: Int
    let unackedBytes: Int
    let flowPaused: Bool

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case streamID = "stream_id"
        case terminalID = "terminal_id"
        case generation
        case mode
        case lastSequence = "last_sequence"
        case liveStreamOpen = "live_stream_open"
        case highWatermarkBytes = "high_watermark_bytes"
        case lowWatermarkBytes = "low_watermark_bytes"
        case unackedBytes = "unacked_bytes"
        case flowPaused = "flow_paused"
    }
}

private struct ControlTerminalStreamAckResult: Encodable {
    let terminalID: String
    let streamID: String
    let generation: Int
    let acknowledgedBytes: Int
    let remainingUnackedBytes: Int
    let highWatermarkBytes: Int
    let lowWatermarkBytes: Int
    let flowPaused: Bool

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case streamID = "stream_id"
        case generation
        case acknowledgedBytes = "acknowledged_bytes"
        case remainingUnackedBytes = "remaining_unacked_bytes"
        case highWatermarkBytes = "high_watermark_bytes"
        case lowWatermarkBytes = "low_watermark_bytes"
        case flowPaused = "flow_paused"
    }
}

private struct ControlTerminalStreamChunkRecord: Encodable {
    let streamKind = "terminal_chunk"
    let streamID: String
    let terminalID: String
    let generation: Int
    let frameID: String
    let parentFrameID: String?
    let deltaKind: String
    let content: String
    let contentLength: Int
    let changedRows: [ControlHarnessReadChangedRow]

    enum CodingKeys: String, CodingKey {
        case streamKind = "stream_kind"
        case streamID = "stream_id"
        case terminalID = "terminal_id"
        case generation
        case frameID = "frame_id"
        case parentFrameID = "parent_frame_id"
        case deltaKind = "delta_kind"
        case content
        case contentLength = "content_length"
        case changedRows = "changed_rows"
    }
}

private struct ControlTerminalSnapshotV2Result: Encodable {
    let terminalID: String
    let generation: Int
    let scope: String
    let snapshotFormat: String
    let capturedAt: String
    let cacheAgeMs: Int
    let frameID: String
    let parentFrameID: String?
    let content: String

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case generation
        case scope
        case snapshotFormat = "snapshot_format"
        case capturedAt = "captured_at"
        case cacheAgeMs = "cache_age_ms"
        case frameID = "frame_id"
        case parentFrameID = "parent_frame_id"
        case content
    }
}

private struct ControlTerminalSemanticV2Result: Encodable {
    let terminalID: String
    let generation: Int
    let scope: String
    let extractedAt: String
    let logicalLines: [String]
    let exactText: String
    let promptDetected: Bool

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case generation
        case scope
        case extractedAt = "extracted_at"
        case logicalLines = "logical_lines"
        case exactText = "exact_text"
        case promptDetected = "prompt_detected"
    }
}

private struct ControlTabCreatedEventPayload: Encodable {
    let parentTabID: String?
    let workingDirectory: String?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case parentTabID = "parent_tab_id"
        case workingDirectory = "working_directory"
        case title
    }
}

private struct ControlTabUpdatedEventPayload: Encodable {
    let title: String?
    let hasBell: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case hasBell = "has_bell"
    }
}

private struct ControlHarnessMutationFingerprint: Encodable {
    let protocolVersion: String?
    let command: String
    let date: String?
    let tabID: String?
    let parentTabID: String?
    let terminalID: String?
    let todoID: String?
    let windowNumber: Int?
    let panelID: String?
    let panelTabID: String?
    let scope: String?
    let text: String?
    let terminalKey: String?
    let commandText: String?
    let workingDirectory: String?
    let title: String?
    let notes: String?
    let environment: [String: String]?
    let force: Bool?
    let completed: Bool?
    let workspaceID: String?
    let includeCompleted: Bool?
    let expectedGeneration: Int?
    let sessionID: String?
    let taskID: String?
    let scheduleID: String?
    let capabilities: [String]?
    let leaseDurationSeconds: Double?
    let taskKind: String?
    let recurrenceMode: String?
    let intervalSeconds: Double?
    let priority: Int?
    let scheduledAt: String?
    let maxRetryCount: Int?
    let metadata: [String: String]?
    let taskState: String?
    let scheduleState: String?
    let errorSummary: String?
    let reason: String?
    let browserTabID: String?
    let browserContextID: String?
    let pageID: String?
    let frameName: String?
    let documentRevision: Int?
    let payload: [String: String]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case command
        case date
        case tabID = "tab_id"
        case parentTabID = "parent_tab_id"
        case terminalID = "terminal_id"
        case todoID = "todo_id"
        case windowNumber = "window_number"
        case panelID = "panel_id"
        case panelTabID = "panel_tab_id"
        case scope
        case text
        case terminalKey = "terminal_key"
        case commandText = "command_text"
        case workingDirectory = "working_directory"
        case title
        case notes
        case environment
        case force
        case completed
        case workspaceID = "workspace_id"
        case includeCompleted = "include_completed"
        case expectedGeneration = "expected_generation"
        case sessionID = "session_id"
        case taskID = "task_id"
        case scheduleID = "schedule_id"
        case capabilities
        case leaseDurationSeconds = "lease_duration_seconds"
        case taskKind = "task_kind"
        case recurrenceMode = "recurrence_mode"
        case intervalSeconds = "interval_seconds"
        case priority
        case scheduledAt = "scheduled_at"
        case maxRetryCount = "max_retry_count"
        case metadata
        case taskState = "task_state"
        case scheduleState = "schedule_state"
        case errorSummary = "error_summary"
        case reason
        case browserTabID = "browser_tab_id"
        case browserContextID = "browser_context_id"
        case pageID = "page_id"
        case frameName = "frame_name"
        case documentRevision = "document_revision"
        case payload
    }
}

private struct ControlAgentRuntimeSnapshotResult: Encodable {
    let settings: AgentRuntimeSettings
    let sessions: [AgentRuntimeSession]
    let tasks: [AgentRuntimeTask]
    let schedules: [AgentRuntimeSchedule]
}

private struct ControlAgentRuntimeSessionResult: Encodable {
    let session: AgentRuntimeSession
}

private struct ControlAgentRuntimeTaskClaimResult: Encodable {
    let task: AgentRuntimeTask?
}

private struct ControlAgentRuntimeTaskResult: Encodable {
    let task: AgentRuntimeTask
}

private struct ControlAgentRuntimeScheduleResult: Encodable {
    let schedule: AgentRuntimeSchedule
}

private struct ControlAuditRecord: Codable {
    let timestamp: String
    let requestID: String
    let command: String
    let client: String?
    let idempotencyKey: String?
    let expectedGeneration: Int?
    let tabID: String?
    let terminalID: String?
    let status: String
    let errorCode: String?
    let sequence: Int64?
    let durationMs: Double

    enum CodingKeys: String, CodingKey {
        case timestamp
        case requestID = "request_id"
        case command
        case client
        case idempotencyKey = "idempotency_key"
        case expectedGeneration = "expected_generation"
        case tabID = "tab_id"
        case terminalID = "terminal_id"
        case status
        case errorCode = "error_code"
        case sequence
        case durationMs = "duration_ms"
    }
}

final class ControlHarnessAuditLogger {
    private let queue = DispatchQueue(label: "com.leongong.ghodex.control-harness.audit")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let fileURL: URL
    private let fileManager = FileManager.default
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.leongong.ghodex",
        category: "ControlHarnessAudit"
    )

    init(bundleID: String) {
        self.fileURL = Self.baseDirectory(bundleID: bundleID)
            .appendingPathComponent("control-harness-audit.jsonl", isDirectory: false)
    }

    fileprivate func append(_ record: ControlAuditRecord) {
        queue.async { [fileURL, fileManager, encoder, logger] in
            do {
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                let data = try encoder.encode(record)
                if !fileManager.fileExists(atPath: fileURL.path) {
                    fileManager.createFile(atPath: fileURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data([0x0A]))
            } catch {
                logger.error("failed to write control audit record: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func baseDirectory(bundleID: String) -> URL {
        let fileManager = FileManager.default
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("ControlHarness", isDirectory: true)
    }
}

@MainActor
final class ControlHarnessCore {
    nonisolated static let protocolVersion = "1.0"
    nonisolated static let supportedCommands = ControlHarnessCommandAliases.allSupportedCommands
    private static let pendingTerminalInputEchoTimeoutDefaultMS = 1_500
    static let supportedTerminalKeys: Set<String> = [
        "backspace",
        "enter",
        "tab",
        "escape",
        "arrow_up",
        "arrow_down",
        "ctrl_c",
        "ctrl_d"
    ]
    static let supportedPanelIDs: Set<String> = ["settings", "ssh_connections"]
    static let supportedSettingsResetTargets: Set<String> = ["draft", "defaults"]
    static let supportedDiagnosticsLogSources: Set<String> = ["audit", "events", "runtime"]

    private weak var appDelegate: AppDelegate?
    private let auditLogger: ControlHarnessAuditLogger
    private let eventHub: ControlHarnessEventHub
    private let eventStreamRegistry: ControlEventStreamRegistry
    private let generations: ControlHarnessGenerationTracker
    private let idempotencyStore: ControlHarnessIdempotencyStore
    private let readStore: ControlHarnessTerminalReadStore
    private let readAfterWriteStore: ControlHarnessReadAfterWriteStore
    private let streamStore: ControlHarnessTerminalStreamStore
    private let sampleStore: ControlHarnessSampleStore
    private let surfaceResolver: @MainActor (UUID) -> (any ControlHarnessReadableSurface)?
    private let samplingActivityResolver: @MainActor (UUID) -> ControlHarnessSamplingActivityClass?
    private let streamPollInterval: TimeInterval
    private let now: @MainActor () -> Date
    private var terminalWindowBellObserver: NSObjectProtocol?
    private var lastReadFootprintProbeDate: Date?
    private var lastReadFootprintBytes: UInt64?
    private var lastReadMemoryThrottleLogDate: Date?
    private var settingsDraftValues: [String: String]?
    private var pendingTerminalInputEchoes: [String: String] = [:]
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.leongong.ghodex",
        category: "ControlHarnessCore"
    )
    private static let readMemoryPressureProbeIntervalSeconds: TimeInterval = 1.0
    private static let readMemoryThrottleLogIntervalSeconds: TimeInterval = 10.0
#if DEBUG
    private static let readPressureFootprintLimitBytes: UInt64 = 2 * 1024 * 1024 * 1024
#else
    private static let readPressureFootprintLimitBytes: UInt64 = 3 * 1024 * 1024 * 1024
#endif

    @MainActor
    convenience init(
        appDelegate: AppDelegate?,
        auditLogger: ControlHarnessAuditLogger,
        sampleStore: ControlHarnessSampleStore
    ) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.leongong.ghodex"
        self.init(
            appDelegate: appDelegate,
            auditLogger: auditLogger,
            eventHub: ControlHarnessEventHub(bundleID: bundleID),
            generations: ControlHarnessGenerationTracker(),
            idempotencyStore: ControlHarnessIdempotencyStore(),
            readStore: ControlHarnessTerminalReadStore(),
            readAfterWriteStore: ControlHarnessReadAfterWriteStore(),
            sampleStore: sampleStore
        )
    }

    init(
        appDelegate: AppDelegate?,
        auditLogger: ControlHarnessAuditLogger,
        eventHub: ControlHarnessEventHub,
        generations: ControlHarnessGenerationTracker,
        idempotencyStore: ControlHarnessIdempotencyStore,
        readStore: ControlHarnessTerminalReadStore,
        readAfterWriteStore: ControlHarnessReadAfterWriteStore,
        streamStore: ControlHarnessTerminalStreamStore = ControlHarnessTerminalStreamStore(),
        sampleStore: ControlHarnessSampleStore,
        surfaceResolver: (@MainActor (UUID) -> (any ControlHarnessReadableSurface)?)? = nil,
        samplingActivityResolver: (@MainActor (UUID) -> ControlHarnessSamplingActivityClass?)? = nil,
        streamPollInterval: TimeInterval = 0.08,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.appDelegate = appDelegate
        self.auditLogger = auditLogger
        self.eventHub = eventHub
        self.eventStreamRegistry = ControlEventStreamRegistry(eventHub: eventHub)
        self.generations = generations
        self.idempotencyStore = idempotencyStore
        self.readStore = readStore
        self.readAfterWriteStore = readAfterWriteStore
        self.streamStore = streamStore
        self.sampleStore = sampleStore
        self.surfaceResolver = surfaceResolver ?? { [weak appDelegate] terminalID in
            appDelegate?.controlHarnessReadableSurface(for: terminalID)
        }
        self.samplingActivityResolver = samplingActivityResolver ?? { [weak appDelegate] terminalID in
            appDelegate?.controlHarnessSamplingActivityClass(for: terminalID)
        }
        self.streamPollInterval = max(0.01, streamPollInterval)
        self.now = now
        self.terminalWindowBellObserver = NotificationCenter.default.addObserver(
            forName: .terminalWindowBellDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleTerminalWindowBellDidChange(notification)
            }
        }
    }

    deinit {
        if let terminalWindowBellObserver {
            NotificationCenter.default.removeObserver(terminalWindowBellObserver)
        }
    }

    func handleSubscription(
        _ request: ControlHarnessRequest,
        socketPath: String
    ) -> ControlHarnessSubscriptionEnvelope {
        let request = request.normalized()
        let started = DispatchTime.now()
        let response: ControlHarnessResponse
        let session: (any ControlHarnessSubscriptionSession)?

        do {
            try validateRequest(request)
            let prepared = try makeSubscription(request, socketPath: socketPath)
            response = .init(
                requestID: request.requestID,
                status: "ok",
                result: prepared.payload,
                errorCode: nil,
                errorMessage: nil
            )
            session = prepared.session
        } catch let error as ControlHarnessCoreError {
            response = .init(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: error.code,
                errorMessage: error.localizedDescription
            )
            session = nil
        } catch {
            logger.error("control harness subscription failed: \(error.localizedDescription, privacy: .public)")
            response = .init(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: ControlHarnessCoreError.internalFailure.code,
                errorMessage: error.localizedDescription
            )
            session = nil
        }

        let durationNs = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
        auditLogger.append(.init(
            timestamp: Self.iso8601(Date()),
            requestID: request.requestID,
            command: request.command,
            client: request.client,
            idempotencyKey: request.idempotencyKey,
            expectedGeneration: request.expectedGeneration,
            tabID: request.tabID,
            terminalID: request.terminalID,
            status: response.status,
            errorCode: response.errorCode,
            sequence: nil,
            durationMs: Double(durationNs) / 1_000_000
        ))

        return .init(response: response, session: session)
    }

    func handle(_ request: ControlHarnessRequest, socketPath: String) -> ControlHarnessResponse {
        let request = request.normalized()
        let started = DispatchTime.now()
        let response: ControlHarnessResponse
        var responseSequence: Int64?

        do {
            try validateRequest(request)
            let mutationFingerprint = try idempotencyFingerprint(for: request)
            if let token = request.idempotencyToken, let mutationFingerprint {
                switch idempotencyStore.lookup(token: token, fingerprint: mutationFingerprint) {
                case .miss:
                    break
                case .hit(let cachedResponse, let cachedSequence):
                    responseSequence = cachedSequence
                    response = cachedResponse
                    let durationNs = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                    auditLogger.append(.init(
                        timestamp: Self.iso8601(Date()),
                        requestID: request.requestID,
                        command: request.command,
                        client: request.client,
                        idempotencyKey: request.idempotencyKey,
                        expectedGeneration: request.expectedGeneration,
                        tabID: request.tabID,
                        terminalID: request.terminalID,
                        status: response.status,
                        errorCode: response.errorCode,
                        sequence: responseSequence,
                        durationMs: Double(durationNs) / 1_000_000
                    ))
                    return response
                case .conflict:
                    throw ControlHarnessCoreError.idempotencyConflict(token)
                }
            }

            let result = try dispatch(request, socketPath: socketPath)
            responseSequence = result.sequence
            response = .init(
                requestID: request.requestID,
                status: "ok",
                result: result.payload,
                errorCode: nil,
                errorMessage: nil
            )
            if let token = request.idempotencyToken, let mutationFingerprint {
                idempotencyStore.store(
                    response: response,
                    sequence: responseSequence,
                    token: token,
                    fingerprint: mutationFingerprint
                )
            }
        } catch let error as ControlHarnessCoreError {
            response = .init(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: error.code,
                errorMessage: error.localizedDescription
            )
            if case .idempotencyConflict = error {
                // Preserve the original response cached for this key.
            }
        } catch {
            logger.error("control harness request failed: \(error.localizedDescription, privacy: .public)")
            response = .init(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: ControlHarnessCoreError.internalFailure.code,
                errorMessage: error.localizedDescription
            )
        }

        let durationNs = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
        auditLogger.append(.init(
            timestamp: Self.iso8601(Date()),
            requestID: request.requestID,
            command: request.command,
            client: request.client,
            idempotencyKey: request.idempotencyKey,
            expectedGeneration: request.expectedGeneration,
            tabID: request.tabID,
            terminalID: request.terminalID,
            status: response.status,
            errorCode: response.errorCode,
            sequence: responseSequence,
            durationMs: Double(durationNs) / 1_000_000
        ))

        return response
    }

    @MainActor
    func handleAsync(_ request: ControlHarnessRequest, socketPath: String) async -> ControlHarnessResponse {
        let request = request.normalized()
        guard ControlHarnessBrowserCommandAdapter.isBrowserCommand(request.command) else {
            return handle(request, socketPath: socketPath)
        }

        let started = DispatchTime.now()
        let response: ControlHarnessResponse
        var responseSequence: Int64?

        do {
            try validateRequest(request)
            let mutationFingerprint = try idempotencyFingerprint(for: request)
            if let token = request.idempotencyToken, let mutationFingerprint {
                switch idempotencyStore.lookup(token: token, fingerprint: mutationFingerprint) {
                case .miss:
                    break
                case .hit(let cachedResponse, let cachedSequence):
                    responseSequence = cachedSequence
                    response = cachedResponse
                    let durationNs = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                    auditLogger.append(.init(
                        timestamp: Self.iso8601(Date()),
                        requestID: request.requestID,
                        command: request.command,
                        client: request.client,
                        idempotencyKey: request.idempotencyKey,
                        expectedGeneration: request.expectedGeneration,
                        tabID: request.tabID,
                        terminalID: request.terminalID,
                        status: response.status,
                        errorCode: response.errorCode,
                        sequence: responseSequence,
                        durationMs: Double(durationNs) / 1_000_000
                    ))
                    return response
                case .conflict:
                    throw ControlHarnessCoreError.idempotencyConflict(token)
                }
            }

            let result = try await dispatchAsync(request, socketPath: socketPath)
            responseSequence = result.sequence
            response = .init(
                requestID: request.requestID,
                status: "ok",
                result: result.payload,
                errorCode: nil,
                errorMessage: nil
            )
            if let token = request.idempotencyToken, let mutationFingerprint {
                idempotencyStore.store(
                    response: response,
                    sequence: responseSequence,
                    token: token,
                    fingerprint: mutationFingerprint
                )
            }
        } catch let error as ControlHarnessCoreError {
            response = .init(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: error.code,
                errorMessage: error.localizedDescription
            )
            if case .idempotencyConflict = error {
                // Preserve the original response cached for this key.
            }
        } catch {
            logger.error("control harness request failed: \(error.localizedDescription, privacy: .public)")
            response = .init(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: ControlHarnessCoreError.internalFailure.code,
                errorMessage: error.localizedDescription
            )
        }

        let durationNs = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
        auditLogger.append(.init(
            timestamp: Self.iso8601(Date()),
            requestID: request.requestID,
            command: request.command,
            client: request.client,
            idempotencyKey: request.idempotencyKey,
            expectedGeneration: request.expectedGeneration,
            tabID: request.tabID,
            terminalID: request.terminalID,
            status: response.status,
            errorCode: response.errorCode,
            sequence: responseSequence,
            durationMs: Double(durationNs) / 1_000_000
        ))

        return response
    }

    private func validateRequest(_ request: ControlHarnessRequest) throws {
        let requestID = request.requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestID.isEmpty else {
            throw ControlHarnessCoreError.invalidArgument("Missing request_id")
        }

        if let protocolVersion = request.protocolVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !protocolVersion.isEmpty,
           protocolVersion != Self.protocolVersion {
            throw ControlHarnessCoreError.unsupportedProtocolVersion(protocolVersion)
        }

        if let expectedGeneration = request.expectedGeneration, expectedGeneration < 1 {
            throw ControlHarnessCoreError.invalidArgument("expected_generation must be >= 1")
        }

        if let sinceSequence = request.sinceSequence, sinceSequence < 0 {
            throw ControlHarnessCoreError.invalidArgument("since_sequence must be >= 0")
        }

        if let eventLimit = request.eventLimit, eventLimit < 1 {
            throw ControlHarnessCoreError.invalidArgument("event_limit must be >= 1")
        }

        if let maxChars = request.maxChars, maxChars < 1 {
            throw ControlHarnessCoreError.invalidArgument("max_chars must be >= 1")
        }

        if let maxLines = request.maxLines, maxLines < 1 {
            throw ControlHarnessCoreError.invalidArgument("max_lines must be >= 1")
        }

        if request.command == "run-command",
           let commandText = request.commandText,
           !commandText.isEmpty,
           commandText.trimmingCharacters(in: .newlines).isEmpty {
            throw ControlHarnessCoreError.invalidArgument(
                "command_text must contain at least one non-newline character"
            )
        }

        if request.command == "send-key" {
            guard let terminalKey = request.terminalKey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                !terminalKey.isEmpty else {
                throw ControlHarnessCoreError.invalidArgument("send-key requires non-empty terminal_key")
            }
            guard Self.supportedTerminalKeys.contains(terminalKey) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported terminal_key: \(terminalKey)")
            }
        }

        if request.command == "read-terminal" {
            if let cursor = request.cursor?.trimmingCharacters(in: .whitespacesAndNewlines) {
                guard !cursor.isEmpty, let cursorValue = Int(cursor), cursorValue >= 0 else {
                    throw ControlHarnessCoreError.invalidArgument(
                        "cursor must be a non-negative integer"
                    )
                }
            }

            let mode = request.mode ?? "snapshot"
            if mode == "delta",
               request.sinceFrameID != nil,
               request.cursor != nil {
                throw ControlHarnessCoreError.invalidArgument(
                    "cursor cannot be combined with since_frame_id in delta mode"
                )
            }
        }

        if request.command == "terminal.stream.ack" {
            guard let ackBytes = request.ackBytes, ackBytes > 0 else {
                throw ControlHarnessCoreError.invalidArgument("terminal.stream.ack requires ack_bytes > 0")
            }
            if let lastAckSequence = request.lastAckSequence, lastAckSequence < 0 {
                throw ControlHarnessCoreError.invalidArgument("last_ack_sequence must be >= 0")
            }
        }

        if request.command == "terminal.stream.open" ||
            request.command == "terminal.stream.ack" ||
            request.command == "terminal.snapshot.v2" ||
            request.command == "terminal.semantic.v2" {
            guard let terminalID = request.terminalID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !terminalID.isEmpty,
                  UUID(uuidString: terminalID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("\(request.command) requires valid terminal_id")
            }
        }

        if let date = request.date?.trimmingCharacters(in: .whitespacesAndNewlines),
           !date.isEmpty,
           AITerminalTodoSettings.date(fromDayString: date) == nil {
            throw ControlHarnessCoreError.invalidArgument("Invalid todo date: \(date)")
        }

        if request.command == "events.stream.drain" || request.command == "events.stream.unsubscribe" {
            _ = try parseRequiredStreamID(request.streamID)
        }

        switch request.command {
        case "app.state.get", "window.list", "panel.list", "settings.schema.get", "settings.values.get",
            "diagnostics.metrics.get", "diagnostics.metrics.reset", "diagnostics.errors.recent",
            "diagnostics.eventBuffer.status":
            break

        case "app.relaunch":
            break

        case "window.focus", "window.show", "window.hide", "window.close", "window.tabOverview.toggle",
            "window.floatOnTop.set":
            guard request.windowNumber != nil else {
                throw ControlHarnessCoreError.invalidArgument("\(request.command) requires window_number")
            }
            if request.command == "window.floatOnTop.set" {
                guard let rawValue = normalizedOptionalString(request.payload?["enabled"]),
                      Self.parseBooleanString(rawValue) != nil else {
                    throw ControlHarnessCoreError.invalidArgument("window.floatOnTop.set requires payload.enabled=true|false")
                }
            }

        case "panel.open", "panel.focus", "panel.close", "panel.state.get":
            guard let panelID = normalizedOptionalString(request.panelID) else {
                throw ControlHarnessCoreError.invalidArgument("\(request.command) requires panel_id")
            }
            guard Self.supportedPanelIDs.contains(panelID) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported panel_id: \(panelID)")
            }
            if let panelTabID = normalizedOptionalString(request.panelTabID) {
                try validatePanelTabID(panelTabID, panelID: panelID)
            }

        case "panel.tab.select":
            guard let panelID = normalizedOptionalString(request.panelID) else {
                throw ControlHarnessCoreError.invalidArgument("panel.tab.select requires panel_id")
            }
            guard Self.supportedPanelIDs.contains(panelID) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported panel_id: \(panelID)")
            }
            guard let panelTabID = normalizedOptionalString(request.panelTabID) else {
                throw ControlHarnessCoreError.invalidArgument("panel.tab.select requires panel_tab_id")
            }
            try validatePanelTabID(panelTabID, panelID: panelID)

        case "settings.values.set", "settings.validate", "settings.apply":
            guard let payload = request.payload, !payload.isEmpty else {
                throw ControlHarnessCoreError.invalidArgument("\(request.command) requires a non-empty payload")
            }
            _ = try normalizedSettingsPatch(payload)

        case "settings.reset":
            if let resetTarget = normalizedOptionalString(request.payload?["target"]),
               Self.supportedSettingsResetTargets.contains(resetTarget) == false {
                throw ControlHarnessCoreError.invalidArgument("settings.reset target must be draft|defaults")
            }

        case "settings.diff":
            if let payload = request.payload, !payload.isEmpty {
                _ = try normalizedSettingsPatch(payload)
            }

        case "diagnostics.logs.tail":
            if let source = normalizedOptionalString(request.payload?["source"]),
               Self.supportedDiagnosticsLogSources.contains(source) == false {
                throw ControlHarnessCoreError.invalidArgument("diagnostics.logs.tail source must be audit|events|runtime")
            }

        case "diagnostics.audit.query":
            if let limit = request.maxLines, limit < 1 {
                throw ControlHarnessCoreError.invalidArgument("max_lines must be >= 1")
            }
            if let status = normalizedOptionalString(request.payload?["status"]),
               ["ok", "error"].contains(status) == false {
                throw ControlHarnessCoreError.invalidArgument("diagnostics.audit.query payload.status must be ok|error")
            }

        case "todo-snapshot", "todo-sync-stale":
            break

        case "todo-add":
            guard let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                throw ControlHarnessCoreError.invalidArgument("todo-add requires non-empty title")
            }

        case "todo-update":
            guard let todoID = request.todoID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !todoID.isEmpty,
                  UUID(uuidString: todoID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("todo-update requires valid todo_id")
            }
            if request.title == nil, request.notes == nil {
                throw ControlHarnessCoreError.invalidArgument("todo-update requires title or notes")
            }

        case "todo-complete":
            guard let todoID = request.todoID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !todoID.isEmpty,
                  UUID(uuidString: todoID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("todo-complete requires valid todo_id")
            }
            guard request.completed != nil else {
                throw ControlHarnessCoreError.invalidArgument("todo-complete requires completed=true|false")
            }

        case "todo-assign":
            guard let todoID = request.todoID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !todoID.isEmpty,
                  UUID(uuidString: todoID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("todo-assign requires valid todo_id")
            }
            if let workspaceID = request.workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !workspaceID.isEmpty,
               UUID(uuidString: workspaceID) == nil {
                throw ControlHarnessCoreError.invalidArgument("workspace_id must be a UUID when provided")
            }

        case "agent.runtime.snapshot":
            break

        case "agent.runtime.session.register":
            if let sessionID = request.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sessionID.isEmpty,
               UUID(uuidString: sessionID) == nil {
                throw ControlHarnessCoreError.invalidArgument("session_id must be a UUID when provided")
            }
            if let tabID = request.tabID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !tabID.isEmpty,
               UUID(uuidString: tabID) == nil {
                throw ControlHarnessCoreError.invalidArgument("tab_id must be a UUID when provided")
            }
            if let terminalID = request.terminalID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !terminalID.isEmpty,
               UUID(uuidString: terminalID) == nil {
                throw ControlHarnessCoreError.invalidArgument("terminal_id must be a UUID when provided")
            }
            if let workspaceID = request.workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !workspaceID.isEmpty,
               UUID(uuidString: workspaceID) == nil {
                throw ControlHarnessCoreError.invalidArgument("workspace_id must be a UUID when provided")
            }
            if let leaseDurationSeconds = request.leaseDurationSeconds,
               leaseDurationSeconds <= 0 {
                throw ControlHarnessCoreError.invalidArgument("lease_duration_seconds must be > 0")
            }

        case "agent.runtime.session.heartbeat", "agent.runtime.session.release", "agent.runtime.task.claim", "agent.runtime.task.claim_next":
            guard let sessionID = request.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sessionID.isEmpty,
                  UUID(uuidString: sessionID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid session_id is required")
            }
            if let leaseDurationSeconds = request.leaseDurationSeconds,
               leaseDurationSeconds <= 0 {
                throw ControlHarnessCoreError.invalidArgument("lease_duration_seconds must be > 0")
            }

        case "agent.runtime.task.enqueue":
            guard let taskKind = request.taskKind?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !taskKind.isEmpty,
                  AgentRuntimeTaskKind(rawValue: taskKind) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid task_kind is required")
            }
            if let scheduledAt = request.scheduledAt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !scheduledAt.isEmpty,
               Self.parseISO8601Date(scheduledAt) == nil {
                throw ControlHarnessCoreError.invalidArgument("scheduled_at must be ISO-8601")
            }
            if let maxRetryCount = request.maxRetryCount,
               maxRetryCount < 0 {
                throw ControlHarnessCoreError.invalidArgument("max_retry_count must be >= 0")
            }
            try validateAgentRuntimeTaskPayload(taskKind: taskKind, request: request)

        case "agent.runtime.task.update":
            guard let sessionID = request.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sessionID.isEmpty,
                  UUID(uuidString: sessionID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid session_id is required")
            }
            guard let taskID = request.taskID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !taskID.isEmpty,
                  UUID(uuidString: taskID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid task_id is required")
            }
            guard let taskState = request.taskState?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !taskState.isEmpty,
                  AgentRuntimeTaskState(rawValue: taskState) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid task_state is required")
            }

        case "agent.runtime.task.approve":
            guard let sessionID = request.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sessionID.isEmpty,
                  UUID(uuidString: sessionID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid session_id is required")
            }
            guard let taskID = request.taskID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !taskID.isEmpty,
                  UUID(uuidString: taskID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid task_id is required")
            }

        case "agent.runtime.task.cancel":
            guard let taskID = request.taskID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !taskID.isEmpty,
                  UUID(uuidString: taskID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid task_id is required")
            }
            if let sessionID = request.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sessionID.isEmpty,
               UUID(uuidString: sessionID) == nil {
                throw ControlHarnessCoreError.invalidArgument("session_id must be a UUID when provided")
            }
            if normalizedOptionalString(request.sessionID) == nil, request.force != true {
                throw ControlHarnessCoreError.invalidArgument("task.cancel requires session_id or force=true")
            }

        case "agent.runtime.schedule.enqueue":
            guard let taskKind = request.taskKind?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !taskKind.isEmpty,
                  AgentRuntimeTaskKind(rawValue: taskKind) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid task_kind is required")
            }
            if let scheduledAt = request.scheduledAt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !scheduledAt.isEmpty,
               Self.parseISO8601Date(scheduledAt) == nil {
                throw ControlHarnessCoreError.invalidArgument("scheduled_at must be ISO-8601")
            }
            if let recurrenceMode = normalizedOptionalString(request.recurrenceMode),
               AgentRuntimeScheduleRecurrence.Mode(rawValue: recurrenceMode) == nil {
                throw ControlHarnessCoreError.invalidArgument("recurrence_mode must be once|interval")
            }
            if let intervalSeconds = request.intervalSeconds,
               intervalSeconds <= 0 {
                throw ControlHarnessCoreError.invalidArgument("interval_seconds must be > 0")
            }
            if normalizedOptionalString(request.recurrenceMode) == AgentRuntimeScheduleRecurrence.Mode.interval.rawValue,
               request.intervalSeconds == nil {
                throw ControlHarnessCoreError.invalidArgument("interval recurrence requires interval_seconds")
            }
            if let maxRetryCount = request.maxRetryCount,
               maxRetryCount < 0 {
                throw ControlHarnessCoreError.invalidArgument("max_retry_count must be >= 0")
            }
            try validateAgentRuntimeTaskPayload(taskKind: taskKind, request: request)

        case "agent.runtime.schedule.update":
            guard let scheduleID = request.scheduleID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !scheduleID.isEmpty,
                  UUID(uuidString: scheduleID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid schedule_id is required")
            }
            if let scheduleState = normalizedOptionalString(request.scheduleState),
               AgentRuntimeScheduleState(rawValue: scheduleState) == nil {
                throw ControlHarnessCoreError.invalidArgument("schedule_state must be active|paused|completed|cancelled")
            }
            if let recurrenceMode = normalizedOptionalString(request.recurrenceMode),
               AgentRuntimeScheduleRecurrence.Mode(rawValue: recurrenceMode) == nil {
                throw ControlHarnessCoreError.invalidArgument("recurrence_mode must be once|interval")
            }
            if let scheduledAt = request.scheduledAt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !scheduledAt.isEmpty,
               Self.parseISO8601Date(scheduledAt) == nil {
                throw ControlHarnessCoreError.invalidArgument("scheduled_at must be ISO-8601")
            }
            if let intervalSeconds = request.intervalSeconds,
               intervalSeconds <= 0 {
                throw ControlHarnessCoreError.invalidArgument("interval_seconds must be > 0")
            }
            if request.intervalSeconds != nil,
               normalizedOptionalString(request.recurrenceMode) == nil {
                throw ControlHarnessCoreError.invalidArgument("interval_seconds requires recurrence_mode=interval")
            }
            if normalizedOptionalString(request.recurrenceMode) == AgentRuntimeScheduleRecurrence.Mode.interval.rawValue,
               request.intervalSeconds == nil {
                throw ControlHarnessCoreError.invalidArgument("interval recurrence requires interval_seconds")
            }

        case "agent.runtime.schedule.cancel":
            guard let scheduleID = request.scheduleID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !scheduleID.isEmpty,
                  UUID(uuidString: scheduleID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Valid schedule_id is required")
            }

        default:
            break
        }
    }

    private func idempotencyFingerprint(for request: ControlHarnessRequest) throws -> Data? {
        guard request.isMutation else { return nil }

        let fingerprint = ControlHarnessMutationFingerprint(
            protocolVersion: request.protocolVersion,
            command: request.command,
            date: request.date,
            tabID: request.tabID,
            parentTabID: request.parentTabID,
            terminalID: request.terminalID,
            todoID: request.todoID,
            windowNumber: request.windowNumber,
            panelID: request.panelID,
            panelTabID: request.panelTabID,
            scope: request.scope,
            text: request.text,
            terminalKey: request.terminalKey,
            commandText: request.commandText,
            workingDirectory: request.workingDirectory,
            title: request.title,
            notes: request.notes,
            environment: request.environment,
            force: request.force,
            completed: request.completed,
            workspaceID: request.workspaceID,
            includeCompleted: request.includeCompleted,
            expectedGeneration: request.expectedGeneration,
            sessionID: request.sessionID,
            taskID: request.taskID,
            scheduleID: request.scheduleID,
            capabilities: request.capabilities,
            leaseDurationSeconds: request.leaseDurationSeconds,
            taskKind: request.taskKind,
            recurrenceMode: request.recurrenceMode,
            intervalSeconds: request.intervalSeconds,
            priority: request.priority,
            scheduledAt: request.scheduledAt,
            maxRetryCount: request.maxRetryCount,
            metadata: request.metadata,
            taskState: request.taskState,
            scheduleState: request.scheduleState,
            errorSummary: request.errorSummary,
            reason: request.reason,
            browserTabID: request.browserTabID,
            browserContextID: request.browserContextID,
            pageID: request.pageID,
            frameName: request.frameName,
            documentRevision: request.documentRevision,
            payload: request.payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(fingerprint)
    }

    private func dispatch(
        _ request: ControlHarnessRequest,
        socketPath: String
    ) throws -> (payload: AnyEncodable, sequence: Int64?) {
        if ControlHarnessBrowserCommandAdapter.isBrowserCommand(request.command) {
            return (try ControlHarnessBrowserCommandAdapter.execute(request), nil)
        }

        switch request.command {
        case "handshake":
            return (
                AnyEncodable(ControlHandshakeResult(
                protocolVersion: Self.protocolVersion,
                socketPath: socketPath,
                    commands: Self.supportedCommands,
                    compatibility: makeCompatibilityMetadata(),
                    lastSequence: eventHub.currentSequence()
                )),
                nil
            )

        case "system.target.resolve":
            return (AnyEncodable(makeTargetResolveResult(socketPath: socketPath)), nil)

        case "system.capabilities.get":
            return (AnyEncodable(makeCapabilitiesResult()), nil)

        case "app.state.get":
            return (AnyEncodable(makeAppStateResult()), nil)

        case "app.relaunch":
            return (AnyEncodable(try relaunchApplication()), nil)

        case "snapshot":
            return (AnyEncodable(makeSnapshot()), nil)

        case "window.list":
            return (AnyEncodable(makeWindowListResult()), nil)

        case "window.focus":
            return (AnyEncodable(try focusWindow(from: request)), nil)

        case "window.show":
            return (AnyEncodable(try showWindow(from: request)), nil)

        case "window.hide":
            return (AnyEncodable(try hideWindow(from: request)), nil)

        case "window.close":
            return (AnyEncodable(try closeWindow(from: request)), nil)

        case "window.tabOverview.toggle":
            return (AnyEncodable(try toggleWindowTabOverview(from: request)), nil)

        case "window.floatOnTop.set":
            return (AnyEncodable(try setWindowFloatOnTop(from: request)), nil)

        case "panel.list":
            return (AnyEncodable(makePanelListResult()), nil)

        case "panel.open":
            return (AnyEncodable(try openPanel(from: request)), nil)

        case "panel.focus":
            return (AnyEncodable(try focusPanel(from: request)), nil)

        case "panel.close":
            return (AnyEncodable(try closePanel(from: request)), nil)

        case "panel.tab.select":
            return (AnyEncodable(try selectPanelTab(from: request)), nil)

        case "panel.state.get":
            return (AnyEncodable(try panelState(from: request)), nil)

        case "settings.schema.get":
            return (AnyEncodable(settingsSchemaResult()), nil)

        case "settings.values.get":
            return (AnyEncodable(settingsValuesResult()), nil)

        case "settings.values.set":
            return (AnyEncodable(try stageSettingsValues(from: request)), nil)

        case "settings.validate":
            return (AnyEncodable(try validateSettingsValues(from: request)), nil)

        case "settings.apply":
            return (AnyEncodable(try applySettingsValues(from: request)), nil)

        case "settings.reset":
            return (AnyEncodable(try resetSettingsValues(from: request)), nil)

        case "settings.diff":
            return (AnyEncodable(try settingsDiff(from: request)), nil)

        case "agent.runtime.snapshot":
            return (AnyEncodable(try agentRuntimeSnapshot()), nil)

        case "agent.runtime.session.register":
            return (AnyEncodable(try registerAgentRuntimeSession(from: request)), nil)

        case "agent.runtime.session.heartbeat":
            return (AnyEncodable(try heartbeatAgentRuntimeSession(from: request)), nil)

        case "agent.runtime.session.release":
            return (AnyEncodable(try releaseAgentRuntimeSession(from: request)), nil)

        case "agent.runtime.task.enqueue":
            return (AnyEncodable(try enqueueAgentRuntimeTask(from: request)), nil)

        case "agent.runtime.task.claim":
            return (AnyEncodable(try claimAgentRuntimeTask(from: request)), nil)

        case "agent.runtime.task.claim_next":
            return (AnyEncodable(try claimAgentRuntimeTask(from: request)), nil)

        case "agent.runtime.task.update":
            return (AnyEncodable(try updateAgentRuntimeTask(from: request)), nil)

        case "agent.runtime.task.approve":
            return (AnyEncodable(try approveAgentRuntimeTask(from: request)), nil)

        case "agent.runtime.task.cancel":
            return (AnyEncodable(try cancelAgentRuntimeTask(from: request)), nil)

        case "agent.runtime.schedule.enqueue":
            return (AnyEncodable(try enqueueAgentRuntimeSchedule(from: request)), nil)

        case "agent.runtime.schedule.update":
            return (AnyEncodable(try updateAgentRuntimeSchedule(from: request)), nil)

        case "agent.runtime.schedule.cancel":
            return (AnyEncodable(try cancelAgentRuntimeSchedule(from: request)), nil)

        case "new-tab":
            let result = try createTab(from: request)
            return (AnyEncodable(result), result.sequence)

        case "close-tab":
            let result = try closeTab(from: request)
            return (AnyEncodable(result), result.sequence)

        case "rename-tab":
            let result = try renameTab(from: request)
            return (AnyEncodable(result), result.sequence)

        case "send-text":
            let result = try sendText(from: request)
            return (AnyEncodable(result), result.sequence)

        case "send-key":
            let result = try sendKey(from: request)
            return (AnyEncodable(result), result.sequence)

        case "run-command":
            let result = try runCommand(from: request)
            return (AnyEncodable(result), result.sequence)

        case "read-terminal":
            return (AnyEncodable(try readTerminal(from: request)), nil)

        case "terminal.stream.ack":
            return (AnyEncodable(try acknowledgeTerminalStream(from: request)), nil)

        case "terminal.snapshot.v2":
            return (AnyEncodable(try terminalSnapshotV2(from: request)), nil)

        case "terminal.semantic.v2":
            return (AnyEncodable(try terminalSemanticV2(from: request)), nil)

        case "close-terminal":
            let result = try closeTerminal(from: request)
            return (AnyEncodable(result), result.sequence)

        case "todo-snapshot":
            return (AnyEncodable(try todoSnapshot(from: request)), nil)

        case "todo-add":
            return (AnyEncodable(try addTodo(from: request)), nil)

        case "todo-update":
            return (AnyEncodable(try updateTodo(from: request)), nil)

        case "todo-complete":
            return (AnyEncodable(try completeTodo(from: request)), nil)

        case "todo-assign":
            return (AnyEncodable(try assignTodo(from: request)), nil)

        case "todo-sync-stale":
            return (AnyEncodable(try syncStaleTodos(from: request)), nil)

        case "events.subscribe":
            return (
                AnyEncodable(makeEventSubscriptionResult(request, replayedEventCount: 0, liveStreamOpen: false)),
                nil
            )

        case "events.stream.subscribe":
            return (AnyEncodable(try subscribeToBufferedEvents(from: request)), nil)

        case "events.stream.drain":
            return (AnyEncodable(try drainBufferedEvents(from: request)), nil)

        case "events.stream.unsubscribe":
            return (AnyEncodable(try unsubscribeBufferedEvents(from: request)), nil)

        case "diagnostics.metrics.get":
            return (AnyEncodable(diagnosticsMetricsResult()), nil)

        case "diagnostics.metrics.reset":
            return (AnyEncodable(resetDiagnosticsMetrics()), nil)

        case "diagnostics.logs.tail":
            return (AnyEncodable(try diagnosticsLogsTail(from: request)), nil)

        case "diagnostics.errors.recent":
            return (AnyEncodable(diagnosticsRecentErrors()), nil)

        case "diagnostics.audit.query":
            return (AnyEncodable(try diagnosticsAuditQuery(from: request)), nil)

        case "diagnostics.eventBuffer.status":
            return (AnyEncodable(diagnosticsEventBufferStatus()), nil)

        default:
            throw ControlHarnessCoreError.unsupportedCommand(request.command)
        }
    }

    @MainActor
    private func dispatchAsync(
        _ request: ControlHarnessRequest,
        socketPath: String
    ) async throws -> (payload: AnyEncodable, sequence: Int64?) {
        if ControlHarnessBrowserCommandAdapter.isBrowserCommand(request.command) {
            return (try await ControlHarnessBrowserCommandAdapter.executeAsync(request), nil)
        }

        return try dispatch(request, socketPath: socketPath)
    }

    private func makeSnapshot() -> ControlSnapshotResult {
        let tabs = snapshotTerminalWindows().compactMap { window -> ControlTabSnapshot? in
            guard let controller = window.windowController as? TerminalController else { return nil }
            let tabID = controller.workspaceID.uuidString
            let terminals = controller.allSurfaces.map { surface in
                let terminalID = surface.id.uuidString
                return ControlTerminalSnapshot(
                    terminalID: terminalID,
                    generation: generations.currentTerminalGeneration(for: terminalID),
                    title: surface.title,
                    workingDirectory: surface.pwd,
                    isFocused: controller.focusedSurface?.id == surface.id,
                    isVisible: controller.visibleSurfaces.contains(where: { $0.id == surface.id })
                )
            }
            return ControlTabSnapshot(
                tabID: tabID,
                generation: generations.currentTabGeneration(for: tabID),
                windowNumber: (window.tabGroup?.selectedWindow ?? window).windowNumber,
                title: controller.titleOverride ?? window.title,
                isFocused: window.isKeyWindow,
                isMainWindow: window.isMainWindow,
                hasBell: controller.bell,
                terminals: terminals
            )
        }

        return ControlSnapshotResult(
            protocolVersion: Self.protocolVersion,
            generatedAt: Self.iso8601(Date()),
            lastSequence: eventHub.currentSequence(),
            tabs: tabs
        )
    }

    private func snapshotTerminalWindows() -> [NSWindow] {
        var seenWorkspaceIDs: Set<UUID> = []
        var windows: [NSWindow] = []

        for appWindow in NSApp.windows {
            let tabWindows = appWindow.tabGroup?.windows ?? [appWindow]
            for tabWindow in tabWindows {
                guard let controller = tabWindow.windowController as? TerminalController else { continue }
                guard seenWorkspaceIDs.insert(controller.workspaceID).inserted else { continue }
                windows.append(tabWindow)
            }
        }

        return windows
    }

    private func makeTargetResolveResult(socketPath: String) -> ControlTargetResolveResult {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.leongong.ghodex"
        let executablePath = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments.first
        return .init(
            protocolVersion: Self.protocolVersion,
            instance: .init(
                socketPath: socketPath,
                processID: ProcessInfo.processInfo.processIdentifier,
                bundleID: bundleID,
                executablePath: executablePath
            )
        )
    }

    private func makeCapabilitiesResult() -> ControlCapabilitiesResult {
        .init(
            protocolVersion: Self.protocolVersion,
            commands: Self.supportedCommands,
            backends: [
                "harness_local",
                "browser_ipc",
                "compat_legacy",
            ],
            features: [
                "app",
                "workspace",
                "terminal",
                "todo",
                "runtime",
                "browser",
                "events",
                "window",
                "panel",
                "settings",
                "diagnostics",
            ],
            compatibility: makeCompatibilityMetadata(),
            lastSequence: eventHub.currentSequence()
        )
    }

    private func makeCompatibilityMetadata() -> ControlCompatibilityMetadata {
        let browserMigrations = ControlHarnessBrowserCommandAdapter.compatibilityEntries.map { entry in
            ControlCommandMigrationNotice(
                command: entry.legacyCommand,
                replacementCommands: entry.replacementCommands,
                status: "legacy_supported",
                removalPhase: "not_scheduled",
                detail: entry.detail
            )
        }
        let migrationNotices: [ControlCommandMigrationNotice] = ([
            ControlCommandMigrationNotice(
                command: "events.subscribe",
                replacementCommands: [
                    "events.stream.subscribe",
                    "events.stream.drain",
                    "events.stream.unsubscribe",
                ],
                status: "legacy_supported",
                removalPhase: "not_scheduled",
                detail: "Use the buffered events.stream handle flow for new clients. events.subscribe remains only for long-lived compatibility transports."
            ),
        ] + browserMigrations).sorted { $0.command < $1.command }

        return .init(
            authority: "control_harness",
            legacyCommands: migrationNotices.map(\.command),
            migrations: migrationNotices
        )
    }

    private func makeAppStateResult() -> ControlAppStateResult {
        let panels = makePanelSummaries()
        return .init(
            protocolVersion: Self.protocolVersion,
            generatedAt: Self.iso8601(now()),
            isActive: NSApp.isActive,
            isHidden: NSApp.isHidden,
            frontmostWindowNumber: currentTopLevelWindow()?.windowNumber,
            windowCount: currentTopLevelWindows().count,
            panelCount: panels.count,
            settingsDraftPending: settingsDraftValues != nil
        )
    }

    private func syncMainActor<T>(
        _ body: @escaping @MainActor () throws -> T
    ) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try body()
            }
        }

        return try DispatchQueue.main.sync {
            try MainActor.assumeIsolated {
                try body()
            }
        }
    }

    @MainActor
    private func activateWindowForControlMutation(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        _ = NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)

        if !window.isKeyWindow || !NSApp.isActive {
            _ = NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeMain()
            window.makeKey()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func relaunchApplication() throws -> ControlAppStateResult {
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }
        return try syncMainActor {
            let result = self.makeAppStateResult()
            appDelegate.relaunchApplication()
            return result
        }
    }

    private func makeWindowListResult() -> ControlWindowListResult {
        .init(
            protocolVersion: Self.protocolVersion,
            windows: currentTopLevelWindows().map(makeWindowSummary)
        )
    }

    private func focusWindow(from request: ControlHarnessRequest) throws -> ControlWindowMutationResult {
        try syncMainActor {
            let window = try self.resolveWindow(windowNumber: request.windowNumber)
            self.activateWindowForControlMutation(window)
            return .init(window: self.makeWindowSummary(window), action: "focus")
        }
    }

    private func showWindow(from request: ControlHarnessRequest) throws -> ControlWindowMutationResult {
        try syncMainActor {
            let window = try self.resolveWindow(windowNumber: request.windowNumber)
            self.activateWindowForControlMutation(window)
            return .init(window: self.makeWindowSummary(window), action: "show")
        }
    }

    private func hideWindow(from request: ControlHarnessRequest) throws -> ControlWindowMutationResult {
        try syncMainActor {
            let window = try self.resolveWindow(windowNumber: request.windowNumber)
            window.orderOut(nil)
            return .init(window: self.makeWindowSummary(window), action: "hide")
        }
    }

    private func closeWindow(from request: ControlHarnessRequest) throws -> ControlWindowMutationResult {
        try syncMainActor {
            let window = try self.resolveWindow(windowNumber: request.windowNumber)
            let summaryBeforeClose = self.makeWindowSummary(window)
            window.performClose(nil)
            return .init(window: summaryBeforeClose, action: "close")
        }
    }

    private func toggleWindowTabOverview(from request: ControlHarnessRequest) throws -> ControlWindowMutationResult {
        try syncMainActor {
            let window = try self.resolveWindow(windowNumber: request.windowNumber)
            if let tabGroup = window.tabGroup {
                let targetVisible = !tabGroup.isOverviewVisible
                tabGroup.isOverviewVisible = targetVisible
                self.enforceTabOverviewVisibility(tabGroup, targetVisible: targetVisible)
            } else {
                window.toggleTabOverview(nil)
            }
            return .init(window: self.makeWindowSummary(window), action: "tab_overview_toggle")
        }
    }

    private func enforceTabOverviewVisibility(
        _ tabGroup: NSWindowTabGroup,
        targetVisible: Bool,
        attemptsRemaining: Int = 8
    ) {
        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak tabGroup, weak self] in
            guard let self, let tabGroup else { return }
            guard tabGroup.isOverviewVisible != targetVisible else { return }
            tabGroup.isOverviewVisible = targetVisible
            self.enforceTabOverviewVisibility(
                tabGroup,
                targetVisible: targetVisible,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func setWindowFloatOnTop(from request: ControlHarnessRequest) throws -> ControlWindowMutationResult {
        try syncMainActor {
            let window = try self.resolveWindow(windowNumber: request.windowNumber)
            let enabled = try self.parseRequiredPayloadBoolean(request, key: "enabled")
            window.level = enabled ? .floating : .normal
            return .init(window: self.makeWindowSummary(window), action: "float_on_top_set")
        }
    }

    private func makePanelListResult() -> ControlPanelListResult {
        .init(protocolVersion: Self.protocolVersion, panels: makePanelSummaries())
    }

    private func openPanel(from request: ControlHarnessRequest) throws -> ControlPanelMutationResult {
        try syncMainActor {
            let panel = try self.mutatePanel(
                panelID: request.panelID,
                panelTabID: request.panelTabID,
                action: "open"
            ) { panelID, panelTabID in
                try self.openPanel(panelID: panelID, panelTabID: panelTabID)
            }
            return .init(panel: panel, action: "open")
        }
    }

    private func focusPanel(from request: ControlHarnessRequest) throws -> ControlPanelMutationResult {
        try syncMainActor {
            let panel = try self.mutatePanel(
                panelID: request.panelID,
                panelTabID: request.panelTabID,
                action: "focus"
            ) { panelID, panelTabID in
                try self.openPanel(panelID: panelID, panelTabID: panelTabID)
            }
            return .init(panel: panel, action: "focus")
        }
    }

    private func closePanel(from request: ControlHarnessRequest) throws -> ControlPanelMutationResult {
        try syncMainActor {
            let panelID = try self.parsePanelID(request.panelID)
            switch panelID {
            case "settings":
                self.appDelegate?.settingsController.close(nil)
            case "ssh_connections":
                self.appDelegate?.sshConnectionsController.close(nil)
            default:
                break
            }
            return .init(panel: self.panelSummary(panelID: panelID), action: "close")
        }
    }

    private func selectPanelTab(from request: ControlHarnessRequest) throws -> ControlPanelMutationResult {
        try syncMainActor {
            let panelID = try self.parsePanelID(request.panelID)
            let panelTabID = try self.parseRequiredPanelTabID(request.panelTabID, panelID: panelID)
            try self.openPanel(panelID: panelID, panelTabID: panelTabID)
            return .init(panel: self.panelSummary(panelID: panelID), action: "tab_select")
        }
    }

    private func panelState(from request: ControlHarnessRequest) throws -> ControlPanelListResult {
        let panelID = try parsePanelID(request.panelID)
        return .init(protocolVersion: Self.protocolVersion, panels: [panelSummary(panelID: panelID)])
    }

    private func settingsSchemaResult() -> ControlSettingsSchemaResult {
        .init(protocolVersion: Self.protocolVersion, entries: settingsSchemaEntries())
    }

    private func settingsValuesResult() -> ControlSettingsValuesResult {
        .init(
            protocolVersion: Self.protocolVersion,
            values: currentSettingsValues(),
            stagedValues: settingsDraftValues
        )
    }

    private func stageSettingsValues(from request: ControlHarnessRequest) throws -> ControlSettingsMutationResult {
        let base = settingsDraftValues ?? currentSettingsValues()
        let patch = try normalizedSettingsPatch(request.payload)
        let nextValues = try applyingSettingsPatch(patch, to: base)
        settingsDraftValues = nextValues
        return .init(
            protocolVersion: Self.protocolVersion,
            values: currentSettingsValues(),
            stagedValues: nextValues,
            changedKeys: changedSettingKeys(from: base, to: nextValues)
        )
    }

    private func validateSettingsValues(from request: ControlHarnessRequest) throws -> ControlSettingsMutationResult {
        let base = settingsDraftValues ?? currentSettingsValues()
        let patch = try normalizedSettingsPatch(request.payload)
        let nextValues = try applyingSettingsPatch(patch, to: base)
        return .init(
            protocolVersion: Self.protocolVersion,
            values: currentSettingsValues(),
            stagedValues: nextValues,
            changedKeys: changedSettingKeys(from: base, to: nextValues)
        )
    }

    private func applySettingsValues(from request: ControlHarnessRequest) throws -> ControlSettingsMutationResult {
        let base = settingsDraftValues ?? currentSettingsValues()
        let patch = try normalizedSettingsPatch(request.payload)
        let nextValues = try applyingSettingsPatch(patch, to: base)
        try persistSettingsValues(nextValues)
        settingsDraftValues = nil
        let appliedValues = currentSettingsValues()
        return .init(
            protocolVersion: Self.protocolVersion,
            values: appliedValues,
            stagedValues: nil,
            changedKeys: changedSettingKeys(from: base, to: nextValues)
        )
    }

    private func resetSettingsValues(from request: ControlHarnessRequest) throws -> ControlSettingsMutationResult {
        let target = normalizedOptionalString(request.payload?["target"]) ?? "draft"
        switch target {
        case "draft":
            let current = currentSettingsValues()
            let previousDraft = settingsDraftValues
            settingsDraftValues = nil
            return .init(
                protocolVersion: Self.protocolVersion,
                values: current,
                stagedValues: nil,
                changedKeys: changedSettingKeys(from: previousDraft ?? current, to: current)
            )
        case "defaults":
            let defaults = defaultSettingsValues()
            let current = currentSettingsValues()
            try persistSettingsValues(defaults)
            settingsDraftValues = nil
            return .init(
                protocolVersion: Self.protocolVersion,
                values: currentSettingsValues(),
                stagedValues: nil,
                changedKeys: changedSettingKeys(from: current, to: defaults)
            )
        default:
            throw ControlHarnessCoreError.invalidArgument("settings.reset target must be draft|defaults")
        }
    }

    private func settingsDiff(from request: ControlHarnessRequest) throws -> ControlSettingsDiffResult {
        let current = currentSettingsValues()
        let nextValues: [String: String]
        if let payload = request.payload, payload.isEmpty == false {
            nextValues = try applyingSettingsPatch(
                try normalizedSettingsPatch(payload),
                to: settingsDraftValues ?? current
            )
        } else {
            nextValues = settingsDraftValues ?? current
        }
        let entries = changedSettingKeys(from: current, to: nextValues).map { key in
            ControlSettingsDiffEntry(
                key: key,
                currentValue: current[key] ?? "",
                nextValue: nextValues[key] ?? ""
            )
        }
        return .init(protocolVersion: Self.protocolVersion, entries: entries)
    }

    private func diagnosticsMetricsResult() -> ControlDiagnosticsMetricsResult {
        .init(
            protocolVersion: Self.protocolVersion,
            metrics: appDelegate?.controlHarnessPerformanceMonitor.snapshot() ?? .empty()
        )
    }

    private func resetDiagnosticsMetrics() -> ControlDiagnosticsMetricsResult {
        .init(
            protocolVersion: Self.protocolVersion,
            metrics: appDelegate?.controlHarnessPerformanceMonitor.reset() ?? .empty()
        )
    }

    private func diagnosticsLogsTail(from request: ControlHarnessRequest) throws -> ControlDiagnosticsLogsTailResult {
        let source = normalizedOptionalString(request.payload?["source"]) ?? "audit"
        guard let url = diagnosticsLogURL(source: source) else {
            return .init(protocolVersion: Self.protocolVersion, source: source, lines: [])
        }
        let limit = max(request.maxLines ?? 20, 1)
        let lines = try tailLogLines(at: url, source: source, limit: limit)
        return .init(protocolVersion: Self.protocolVersion, source: source, lines: lines)
    }

    private func diagnosticsRecentErrors() -> ControlDiagnosticsRecentErrorsResult {
        var errors = recentAuditErrors(limit: 10)
        if let gatewayError = appDelegate?.controlHarnessGateway.lastStartupError,
           gatewayError.isEmpty == false {
            errors.insert(.init(source: "gateway", timestamp: nil, code: "startup_error", message: gatewayError, command: nil), at: 0)
        }
        if let runtimeError = appDelegate?.aiTerminalManagerStore.lastError,
           runtimeError.isEmpty == false {
            errors.insert(.init(source: "runtime", timestamp: nil, code: "store_error", message: runtimeError, command: nil), at: 0)
        }
        return .init(protocolVersion: Self.protocolVersion, errors: Array(errors.prefix(20)))
    }

    private func diagnosticsAuditQuery(from request: ControlHarnessRequest) throws -> ControlDiagnosticsAuditQueryResult {
        let limit = max(request.maxLines ?? 50, 1)
        let statusFilter = normalizedOptionalString(request.payload?["status"])
        let commandFilter = normalizedOptionalString(request.payload?["command"])
        let errorCodeFilter = normalizedOptionalString(request.payload?["error_code"])
        let clientFilter = normalizedOptionalString(request.payload?["client"])
        let sourceURL = diagnosticsLogURL(source: "audit")
        guard let sourceURL else {
            return .init(protocolVersion: Self.protocolVersion, records: [])
        }
        let records = try readAuditRecords(at: sourceURL)
            .filter { record in
                if let statusFilter, record.status != statusFilter { return false }
                if let commandFilter, record.command != commandFilter { return false }
                if let errorCodeFilter, record.errorCode != errorCodeFilter { return false }
                if let clientFilter, record.client != clientFilter { return false }
                return true
            }
        return .init(protocolVersion: Self.protocolVersion, records: Array(records.suffix(limit)))
    }

    private func diagnosticsEventBufferStatus() -> ControlDiagnosticsEventBufferStatusResult {
        let snapshot = eventStreamRegistry.statusSnapshot()
        return .init(
            protocolVersion: Self.protocolVersion,
            status: .init(
                subscriptionCount: snapshot.subscriptionCount,
                liveSubscriptionCount: snapshot.liveSubscriptionCount,
                bufferedEventCount: snapshot.bufferedEventCount,
                bufferedBytes: snapshot.bufferedBytes,
                subscriptionsRequiringSnapshotResync: snapshot.subscriptionsRequiringSnapshotResync,
                droppedEvents: snapshot.droppedEvents,
                maxBufferedEvents: snapshot.maxBufferedEvents,
                maxBufferedBytes: snapshot.maxBufferedBytes
            )
        )
    }

    private func agentRuntimeSnapshot() throws -> ControlAgentRuntimeSnapshotResult {
        let store = try runtimeStore()
        let snapshot = store.agentRuntimeSnapshot(now: now())
        return .init(
            settings: snapshot.settings,
            sessions: snapshot.sessions,
            tasks: snapshot.tasks,
            schedules: snapshot.schedules
        )
    }

    private func registerAgentRuntimeSession(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeSessionResult {
        let store = try runtimeStore()
        do {
            let session = try store.registerAgentRuntimeSession(
                clientKind: .codexTab,
                tabID: try parseOptionalUUID(request.tabID, field: "tab_id"),
                terminalID: try parseOptionalUUID(request.terminalID, field: "terminal_id"),
                hostWorkspaceID: try parseOptionalUUID(request.workspaceID, field: "workspace_id"),
                capabilities: request.capabilities ?? [],
                existingSessionID: try parseOptionalUUID(request.sessionID, field: "session_id"),
                leaseDurationSeconds: request.leaseDurationSeconds,
                now: now()
            )
            return .init(session: session)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func heartbeatAgentRuntimeSession(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeSessionResult {
        let store = try runtimeStore()
        do {
            let session = try store.heartbeatAgentRuntimeSession(
                try parseRequiredUUID(request.sessionID, field: "session_id"),
                leaseDurationSeconds: request.leaseDurationSeconds,
                now: now()
            )
            return .init(session: session)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func releaseAgentRuntimeSession(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeSessionResult {
        let store = try runtimeStore()
        do {
            let session = try store.releaseAgentRuntimeSession(
                try parseRequiredUUID(request.sessionID, field: "session_id"),
                reason: normalizedOptionalString(request.reason),
                now: now()
            )
            return .init(session: session)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func claimAgentRuntimeTask(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeTaskClaimResult {
        let store = try runtimeStore()
        do {
            let task = try store.claimNextAgentRuntimeTask(
                sessionID: try parseRequiredUUID(request.sessionID, field: "session_id"),
                allowedKinds: try parseOptionalRuntimeTaskKinds(request),
                now: now()
            )
            return .init(task: task)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func enqueueAgentRuntimeTask(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeTaskResult {
        let store = try runtimeStore()
        do {
            let task = try store.enqueueAgentRuntimeTask(
                kind: try parseRuntimeTaskKind(request.taskKind),
                priority: request.priority ?? 0,
                capabilityRequirements: request.capabilities ?? [],
                payload: .init(
                    command: normalizedOptionalString(request.commandText),
                    text: normalizedOptionalString(request.text),
                    metadata: request.metadata ?? [:]
                ),
                scheduledAt: try parseOptionalISO8601Date(request.scheduledAt),
                maxRetryCount: request.maxRetryCount ?? 0,
                now: now()
            )
            return .init(task: task)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func updateAgentRuntimeTask(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeTaskResult {
        let store = try runtimeStore()
        do {
            let task = try store.updateAgentRuntimeTask(
                sessionID: try parseRequiredUUID(request.sessionID, field: "session_id"),
                taskID: try parseRequiredUUID(request.taskID, field: "task_id"),
                state: try parseRuntimeTaskState(request.taskState),
                errorSummary: normalizedOptionalString(request.errorSummary),
                now: now()
            )
            return .init(task: task)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func approveAgentRuntimeTask(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeTaskResult {
        let store = try runtimeStore()
        do {
            let task = try store.approveAgentRuntimeTask(
                sessionID: try parseRequiredUUID(request.sessionID, field: "session_id"),
                taskID: try parseRequiredUUID(request.taskID, field: "task_id"),
                now: now()
            )
            return .init(task: task)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func cancelAgentRuntimeTask(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeTaskResult {
        let store = try runtimeStore()
        do {
            let task = try store.cancelAgentRuntimeTask(
                taskID: try parseRequiredUUID(request.taskID, field: "task_id"),
                sessionID: try parseOptionalUUID(request.sessionID, field: "session_id"),
                reason: normalizedOptionalString(request.reason),
                force: request.force == true,
                now: now()
            )
            return .init(task: task)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func enqueueAgentRuntimeSchedule(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeScheduleResult {
        let store = try runtimeStore()
        let recurrence = AgentRuntimeScheduleRecurrence(
            mode: try parseRuntimeScheduleRecurrenceMode(request.recurrenceMode),
            intervalSeconds: request.intervalSeconds
        )
        do {
            let schedule = try store.enqueueAgentRuntimeSchedule(
                taskKind: try parseRuntimeTaskKind(request.taskKind),
                priority: request.priority ?? 0,
                capabilityRequirements: request.capabilities ?? [],
                payload: .init(
                    command: normalizedOptionalString(request.commandText),
                    text: normalizedOptionalString(request.text),
                    metadata: request.metadata ?? [:]
                ),
                startAt: try parseOptionalISO8601Date(request.scheduledAt),
                recurrence: recurrence,
                maxRetryCount: request.maxRetryCount ?? 0,
                now: now()
            )
            return .init(schedule: schedule)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func updateAgentRuntimeSchedule(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeScheduleResult {
        let store = try runtimeStore()
        do {
            let recurrence: AgentRuntimeScheduleRecurrence? = if normalizedOptionalString(request.recurrenceMode) != nil {
                .init(
                    mode: try parseRuntimeScheduleRecurrenceMode(request.recurrenceMode),
                    intervalSeconds: request.intervalSeconds
                )
            } else {
                nil
            }

            let schedule = try store.updateAgentRuntimeSchedule(
                scheduleID: try parseRequiredUUID(request.scheduleID, field: "schedule_id"),
                state: try parseOptionalRuntimeScheduleState(request.scheduleState),
                startAt: try parseOptionalISO8601Date(request.scheduledAt),
                recurrence: recurrence,
                now: now()
            )
            return .init(schedule: schedule)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func cancelAgentRuntimeSchedule(
        from request: ControlHarnessRequest
    ) throws -> ControlAgentRuntimeScheduleResult {
        let store = try runtimeStore()
        do {
            let schedule = try store.cancelAgentRuntimeSchedule(
                scheduleID: try parseRequiredUUID(request.scheduleID, field: "schedule_id"),
                now: now()
            )
            return .init(schedule: schedule)
        } catch let error as AgentRuntimeStoreError {
            throw mapAgentRuntimeError(error)
        }
    }

    private func createTab(from request: ControlHarnessRequest) throws -> ControlCreateTabResult {
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }

        return try syncMainActor {
            try self.validateWorkingDirectory(request.workingDirectory)
            let parentWindow = try self.resolveParentWindow(parentTabID: request.parentTabID)
            let config = self.buildSurfaceConfiguration(from: request)
            guard let controller = TerminalController.newTab(
                appDelegate.ghostty,
                from: parentWindow,
                withBaseConfig: config
            ) else {
                throw ControlHarnessCoreError.operationFailed("Failed to create a new tab")
            }

            if let title = self.normalizedTabTitleOverride(request.title) {
                controller.titleOverride = title
            }

            let tabID = controller.workspaceID.uuidString
            let tabGeneration = self.generations.currentTabGeneration(for: tabID)
            let terminalID = controller.surfaceTree.leftmostActiveSurface()?.id.uuidString
            let terminalGeneration = terminalID.map { self.generations.currentTerminalGeneration(for: $0) }
            let sequence = self.eventHub.emit(
                event: "tab.created",
                requestID: request.requestID,
                resource: .init(type: "tab", id: tabID, generation: tabGeneration),
                payload: AnyEncodable(ControlTabCreatedEventPayload(
                    parentTabID: request.parentTabID,
                    workingDirectory: request.workingDirectory,
                    title: request.title
                ))
            )
            return ControlCreateTabResult(
                tabID: tabID,
                tabGeneration: tabGeneration,
                terminalID: terminalID,
                terminalGeneration: terminalGeneration,
                sequence: sequence
            )
        }
    }

    private func closeTab(from request: ControlHarnessRequest) throws -> ControlTabCloseResult {
        try syncMainActor {
            let controller = try self.resolveTabController(tabID: request.tabID)
            let tabID = controller.workspaceID.uuidString
            let currentGeneration = self.generations.currentTabGeneration(for: tabID)
            try self.generations.assertExpectedGeneration(
                request.expectedGeneration,
                resourceType: "tab",
                resourceID: tabID,
                currentGeneration: currentGeneration
            )
            if request.force != true,
               let confirmation = self.closeTabConfirmation(for: controller) {
                return .init(
                    tabID: tabID,
                    generation: currentGeneration,
                    sequence: self.eventHub.currentSequence(),
                    closed: false,
                    requiresConfirmation: true,
                    confirmationTitle: confirmation.title,
                    confirmationMessage: confirmation.message
                )
            }
            if request.force == true {
                controller.closeTabImmediately()
            } else {
                controller.closeTab(nil)
            }
            let generation = self.generations.advanceTabGeneration(for: tabID)
            let sequence = self.eventHub.emit(
                event: "tab.closed",
                requestID: request.requestID,
                resource: .init(type: "tab", id: tabID, generation: generation),
                payload: AnyEncodable(["force": request.force == true])
            )
            return .init(
                tabID: tabID,
                generation: generation,
                sequence: sequence,
                closed: true,
                requiresConfirmation: false,
                confirmationTitle: nil,
                confirmationMessage: nil
            )
        }
    }

    private func renameTab(from request: ControlHarnessRequest) throws -> ControlTabMutationResult {
        try syncMainActor {
            let controller = try self.resolveTabController(tabID: request.tabID)
            let tabID = controller.workspaceID.uuidString
            let currentGeneration = self.generations.currentTabGeneration(for: tabID)
            try self.generations.assertExpectedGeneration(
                request.expectedGeneration,
                resourceType: "tab",
                resourceID: tabID,
                currentGeneration: currentGeneration
            )

            let normalizedTitle = self.normalizedTabTitleOverride(request.title)
            controller.titleOverride = normalizedTitle

            let generation = self.generations.advanceTabGeneration(for: tabID)
            let sequence = self.eventHub.emit(
                event: "tab.updated",
                requestID: request.requestID,
                resource: .init(type: "tab", id: tabID, generation: generation),
                payload: AnyEncodable(ControlTabUpdatedEventPayload(title: normalizedTitle, hasBell: controller.bell))
            )

            return .init(
                tabID: tabID,
                generation: generation,
                sequence: sequence,
                title: normalizedTitle,
                closed: false,
                requiresConfirmation: false,
                confirmationTitle: nil,
                confirmationMessage: nil
            )
        }
    }

    @MainActor
    private func closeTabConfirmation(for controller: TerminalController) -> (title: String, message: String)? {
        let needsConfirmQuit = controller.allSurfaces.contains(where: { $0.needsConfirmQuit })
        let tabCount = controller.window?.tabGroup?.windows.count ?? 1
        guard let confirmation = ControlTabCloseConfirmation.resolve(
            hasMultipleTabs: tabCount > 1,
            needsConfirmQuit: needsConfirmQuit
        ) else {
            return nil
        }
        return (confirmation.title, confirmation.message)
    }

    private func sendText(from request: ControlHarnessRequest) throws -> ControlTerminalMutationResult {
        try syncMainActor {
            guard let text = request.text, !text.isEmpty else {
                throw ControlHarnessCoreError.invalidArgument("Missing text payload")
            }
            let terminalID = try self.parseTerminalID(request.terminalID)
            let terminalIDString = terminalID.uuidString
            let currentGeneration = self.generations.currentTerminalGeneration(for: terminalIDString)
            try self.generations.assertExpectedGeneration(
                request.expectedGeneration,
                resourceType: "terminal",
                resourceID: terminalIDString,
                currentGeneration: currentGeneration
            )
            guard let appDelegate = self.appDelegate else {
                throw ControlHarnessCoreError.appUnavailable
            }
            guard appDelegate.controlHarnessSendText(text, to: terminalID) else {
                throw ControlHarnessCoreError.terminalNotFound(terminalID.uuidString)
            }
            self.pendingTerminalInputEchoes[terminalIDString, default: ""] += text
            let generation = self.generations.advanceTerminalGeneration(for: terminalIDString)
            let sequence = self.eventHub.emit(
                event: "terminal.input.sent",
                requestID: request.requestID,
                resource: .init(type: "terminal", id: terminalIDString, generation: generation),
                payload: AnyEncodable(["text_length": text.count])
            )
            self.sampleStore.removeTerminal(terminalIDString)
            let writeID = Self.writeID(forSequence: sequence)
            self.readAfterWriteStore.recordTextWrite(
                terminalID: terminalIDString,
                writeID: writeID,
                sequence: sequence,
                visibleFrameID: self.readStore.latestFrameID(for: terminalIDString, scope: "visible"),
                screenFrameID: self.readStore.latestFrameID(for: terminalIDString, scope: "screen")
            )
            return .init(
                terminalID: terminalIDString,
                generation: generation,
                sequence: sequence,
                operation: "send-text",
                acknowledged: true,
                writeID: writeID
            )
        }
    }

    private func pendingTerminalInputEchoTimeout(from request: ControlHarnessRequest) -> TimeInterval {
        let payloadTimeoutMS = request.payload.flatMap { payload in
            if let rawTimeout = payload["timeoutMS"] ?? payload["timeout_ms"],
               let timeoutMS = Int(rawTimeout.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return timeoutMS
            }
            return nil
        }
        let timeoutMS = request.options?.timeoutMS
            ?? payloadTimeoutMS
            ?? Self.pendingTerminalInputEchoTimeoutDefaultMS
        return TimeInterval(max(0, timeoutMS)) / 1000.0
    }

    private func sendKey(from request: ControlHarnessRequest) throws -> ControlTerminalMutationResult {
        try syncMainActor {
            guard let terminalKey = request.terminalKey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                !terminalKey.isEmpty else {
                throw ControlHarnessCoreError.invalidArgument("Missing terminal_key payload")
            }
            guard Self.supportedTerminalKeys.contains(terminalKey) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported terminal_key: \(terminalKey)")
            }
            let terminalID = try self.parseTerminalID(request.terminalID)
            let terminalIDString = terminalID.uuidString
            let currentGeneration = self.generations.currentTerminalGeneration(for: terminalIDString)
            try self.generations.assertExpectedGeneration(
                request.expectedGeneration,
                resourceType: "terminal",
                resourceID: terminalIDString,
                currentGeneration: currentGeneration
            )
            guard let appDelegate = self.appDelegate else {
                throw ControlHarnessCoreError.appUnavailable
            }
            switch terminalKey {
            case "enter":
                if let pendingText = self.pendingTerminalInputEchoes[terminalIDString],
                   pendingText.isEmpty == false {
                    let timeout = self.pendingTerminalInputEchoTimeout(from: request)
                    guard appDelegate.controlHarnessAwaitTextEcho(
                        pendingText,
                        to: terminalID,
                        timeout: timeout
                    ) else {
                        throw ControlHarnessCoreError.operationFailed(
                            "Timed out waiting \(Int(timeout * 1000))ms for typed input to echo before sending enter for terminal_id=\(terminalIDString)"
                        )
                    }
                    self.pendingTerminalInputEchoes.removeValue(forKey: terminalIDString)
                } else {
                    self.pendingTerminalInputEchoes.removeValue(forKey: terminalIDString)
                }
            case "backspace":
                if var pendingText = self.pendingTerminalInputEchoes[terminalIDString], pendingText.isEmpty == false {
                    pendingText.removeLast()
                    self.pendingTerminalInputEchoes[terminalIDString] = pendingText
                }
            case "tab":
                self.pendingTerminalInputEchoes[terminalIDString, default: ""] += "\t"
            default:
                self.pendingTerminalInputEchoes.removeValue(forKey: terminalIDString)
            }
            guard appDelegate.controlHarnessSendKey(terminalKey, to: terminalID) else {
                throw ControlHarnessCoreError.terminalNotFound(terminalID.uuidString)
            }
            let generation = self.generations.advanceTerminalGeneration(for: terminalIDString)
            let sequence = self.eventHub.emit(
                event: "terminal.key.sent",
                requestID: request.requestID,
                resource: .init(type: "terminal", id: terminalIDString, generation: generation),
                payload: AnyEncodable(["terminal_key": terminalKey])
            )
            self.sampleStore.removeTerminal(terminalIDString)
            let writeID = Self.writeID(forSequence: sequence)
            self.readAfterWriteStore.recordTextWrite(
                terminalID: terminalIDString,
                writeID: writeID,
                sequence: sequence,
                visibleFrameID: self.readStore.latestFrameID(for: terminalIDString, scope: "visible"),
                screenFrameID: self.readStore.latestFrameID(for: terminalIDString, scope: "screen")
            )
            return .init(
                terminalID: terminalIDString,
                generation: generation,
                sequence: sequence,
                operation: "send-key",
                acknowledged: true,
                writeID: writeID
            )
        }
    }

    private func runCommand(from request: ControlHarnessRequest) throws -> ControlTerminalMutationResult {
        try syncMainActor {
            guard let commandText = request.commandText, !commandText.isEmpty else {
                throw ControlHarnessCoreError.invalidArgument("Missing command_text payload")
            }
            let terminalID = try self.parseTerminalID(request.terminalID)
            let terminalIDString = terminalID.uuidString
            let currentGeneration = self.generations.currentTerminalGeneration(for: terminalIDString)
            try self.generations.assertExpectedGeneration(
                request.expectedGeneration,
                resourceType: "terminal",
                resourceID: terminalIDString,
                currentGeneration: currentGeneration
            )
            guard let appDelegate = self.appDelegate else {
                throw ControlHarnessCoreError.appUnavailable
            }
            guard appDelegate.controlHarnessRunCommand(commandText, to: terminalID) else {
                throw ControlHarnessCoreError.terminalNotFound(terminalID.uuidString)
            }
            self.pendingTerminalInputEchoes.removeValue(forKey: terminalIDString)
            let generation = self.generations.advanceTerminalGeneration(for: terminalIDString)
            let sequence = self.eventHub.emit(
                event: "terminal.command.sent",
                requestID: request.requestID,
                resource: .init(type: "terminal", id: terminalIDString, generation: generation),
                payload: AnyEncodable(["command_length": commandText.count])
            )
            self.sampleStore.removeTerminal(terminalIDString)
            let writeID = Self.writeID(forSequence: sequence)
            self.readAfterWriteStore.recordCommandWrite(
                terminalID: terminalIDString,
                writeID: writeID,
                sequence: sequence,
                commandText: commandText,
                visibleFrameID: self.readStore.latestFrameID(for: terminalIDString, scope: "visible"),
                screenFrameID: self.readStore.latestFrameID(for: terminalIDString, scope: "screen")
            )
            return .init(
                terminalID: terminalIDString,
                generation: generation,
                sequence: sequence,
                operation: "run-command",
                acknowledged: true,
                writeID: writeID
            )
        }
    }

    private func readTerminal(from request: ControlHarnessRequest) throws -> ControlReadTerminalResult {
        let terminalID = try parseTerminalID(request.terminalID)
        let terminalIDString = terminalID.uuidString
        let generation = generations.currentTerminalGeneration(for: terminalIDString)
        try generations.assertExpectedGeneration(
            request.expectedGeneration,
            resourceType: "terminal",
            resourceID: terminalIDString,
            currentGeneration: generation
        )

        let scope = request.scope ?? "visible"
        switch scope {
        case "visible", "screen":
            break
        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported read scope: \(scope)")
        }

        let mode = request.mode ?? "snapshot"
        switch mode {
        case "snapshot", "delta":
            break
        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported read mode: \(mode)")
        }

        let observedWriteID = request.readAfterWriteID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let forceFreshRead = request.force == true
            || observedWriteID?.isEmpty == false
            || mode == "delta"
            || request.sinceFrameID != nil
        let snapshot = try captureTerminalSnapshot(
            terminalID: terminalID,
            terminalIDString: terminalIDString,
            scope: scope,
            forceFresh: forceFreshRead
        )

        // read-terminal is now a compatibility adapter over the V2 snapshot
        // capture path so V2 remains the single read source of truth.
        let delta = readStore.delta(from: request.sinceFrameID, to: snapshot.frame.frameID)
        let window = readStore.window(
            frameID: snapshot.frame.frameID,
            cursor: request.cursor,
            maxLines: request.maxLines,
            maxChars: request.maxChars
        )
        let changedRows = mode == "delta"
            ? delta.changedRows
            : Self.applyChangedRowBudget(delta.changedRows, maxLines: request.maxLines)

        let contentKind: String
        switch mode {
        case "snapshot":
            contentKind = "snapshot"
        case "delta":
            switch delta.kind {
            case "append", "rows", "none":
                contentKind = "delta"
            default:
                contentKind = "snapshot"
            }
        default:
            contentKind = "snapshot"
        }

        let readAfterReady: Bool?
        if let observedWriteID, !observedWriteID.isEmpty {
            let targetSequence = try Self.parseWriteID(observedWriteID)
            let sequenceReady = eventHub.currentSequence() >= targetSequence
            readAfterReady = sequenceReady && readAfterWriteStore.readiness(
                for: observedWriteID,
                terminalID: terminalIDString,
                scope: scope,
                currentSequence: eventHub.currentSequence(),
                frame: snapshot.frame,
                delta: delta
            )
        } else {
            readAfterReady = nil
        }

        return ControlReadTerminalResult(
            terminalID: terminalIDString,
            generation: generation,
            scope: scope,
            mode: mode,
            contentKind: contentKind,
            consistency: snapshot.consistency,
            capturedAt: Self.iso8601(snapshot.capturedAt),
            cacheAgeMs: snapshot.cacheAgeMs,
            lastSequence: eventHub.currentSequence(),
            frameID: snapshot.frame.frameID,
            parentFrameID: snapshot.frame.parentFrameID,
            hasChanges: delta.hasChanges,
            deltaKind: delta.kind,
            deltaText: delta.text.isEmpty ? nil : Self.applyTextBudget(delta.text, maxChars: request.maxChars),
            changedRows: changedRows,
            totalLines: window.totalLines,
            returnedLines: window.returnedLines,
            truncated: mode == "snapshot" ? window.truncated : false,
            nextCursor: mode == "snapshot" ? window.nextCursor : nil,
            observedWriteID: observedWriteID,
            readAfterReady: readAfterReady,
            // Keep `content` authoritative so delta consumers can fall back to
            // a full replace when row-level merge is unsafe or lineage resets.
            content: window.text
        )
    }

    private func acknowledgeTerminalStream(from request: ControlHarnessRequest) throws -> ControlTerminalStreamAckResult {
        let terminalID = try parseTerminalID(request.terminalID)
        let terminalIDString = terminalID.uuidString
        let generation = generations.currentTerminalGeneration(for: terminalIDString)
        try generations.assertExpectedGeneration(
            request.expectedGeneration,
            resourceType: "terminal",
            resourceID: terminalIDString,
            currentGeneration: generation
        )
        guard let ackBytes = request.ackBytes, ackBytes > 0 else {
            throw ControlHarnessCoreError.invalidArgument("terminal.stream.ack requires ack_bytes > 0")
        }

        let normalizedStreamID = request.streamID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let streamID = (normalizedStreamID?.isEmpty == false) ? normalizedStreamID : nil
        guard let ackState = streamStore.acknowledge(
            terminalID: terminalIDString,
            streamID: streamID,
            ackBytes: ackBytes
        ) else {
            throw ControlHarnessCoreError.invalidArgument(
                "No active stream exists for terminal_id=\(terminalIDString)"
            )
        }

        return .init(
            terminalID: terminalIDString,
            streamID: ackState.streamID,
            generation: generation,
            acknowledgedBytes: ackState.ackedBytes,
            remainingUnackedBytes: ackState.remainingUnackedBytes,
            highWatermarkBytes: ackState.highWatermarkBytes,
            lowWatermarkBytes: ackState.lowWatermarkBytes,
            flowPaused: ackState.flowPaused
        )
    }

    private func terminalSnapshotV2(from request: ControlHarnessRequest) throws -> ControlTerminalSnapshotV2Result {
        let terminalID = try parseTerminalID(request.terminalID)
        let terminalIDString = terminalID.uuidString
        let generation = generations.currentTerminalGeneration(for: terminalIDString)
        try generations.assertExpectedGeneration(
            request.expectedGeneration,
            resourceType: "terminal",
            resourceID: terminalIDString,
            currentGeneration: generation
        )

        let scope = request.scope ?? "visible"
        switch scope {
        case "visible", "screen":
            break
        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported read scope: \(scope)")
        }

        let snapshot = try captureTerminalSnapshot(
            terminalID: terminalID,
            terminalIDString: terminalIDString,
            scope: scope,
            forceFresh: false
        )

        return .init(
            terminalID: terminalIDString,
            generation: generation,
            scope: scope,
            snapshotFormat: "ansi_text",
            capturedAt: Self.iso8601(snapshot.capturedAt),
            cacheAgeMs: snapshot.cacheAgeMs,
            frameID: snapshot.frame.frameID,
            parentFrameID: snapshot.frame.parentFrameID,
            content: snapshot.content
        )
    }

    private func terminalSemanticV2(from request: ControlHarnessRequest) throws -> ControlTerminalSemanticV2Result {
        let snapshot = try terminalSnapshotV2(from: request)
        let projection = controlHarnessSemanticProjection(
            from: snapshot.content,
            profile: currentSemanticProfile()
        )

        return .init(
            terminalID: snapshot.terminalID,
            generation: snapshot.generation,
            scope: snapshot.scope,
            extractedAt: snapshot.capturedAt,
            logicalLines: projection.logicalLines,
            exactText: projection.exactText,
            promptDetected: projection.promptDetected
        )
    }

    private func currentSemanticProfile() -> ControlHarnessSemanticProfile {
        appDelegate?.controlHarnessGatewaySettings.semanticProfileValue ?? .defaultValue
    }

    private func captureTerminalSnapshot(
        terminalID: UUID,
        terminalIDString: String,
        scope: String,
        forceFresh: Bool
    ) throws -> ControlTerminalSnapshotCapture {
        guard let surface = surfaceResolver(terminalID) else {
            if appDelegate == nil {
                throw ControlHarnessCoreError.appUnavailable
            }
            throw ControlHarnessCoreError.terminalNotFound(terminalID.uuidString)
        }

        let read = try resolveTerminalRead(
            terminalUUID: terminalID,
            terminalID: terminalIDString,
            scope: scope,
            surface: surface,
            forceFresh: forceFresh
        )
        let frame = readStore.capture(terminalID: terminalIDString, scope: scope, content: read.content)
        return .init(
            content: read.content,
            consistency: read.consistency,
            cacheAgeMs: read.cacheAgeMs,
            capturedAt: read.capturedAt,
            frame: frame
        )
    }

    private func closeTerminal(from request: ControlHarnessRequest) throws -> ControlTerminalMutationResult {
        try syncMainActor {
            let terminalID = try self.parseTerminalID(request.terminalID)
            let terminalIDString = terminalID.uuidString
            let currentGeneration = self.generations.currentTerminalGeneration(for: terminalIDString)
            try self.generations.assertExpectedGeneration(
                request.expectedGeneration,
                resourceType: "terminal",
                resourceID: terminalIDString,
                currentGeneration: currentGeneration
            )
            guard let appDelegate = self.appDelegate else {
                throw ControlHarnessCoreError.appUnavailable
            }
            guard appDelegate.controlHarnessCloseTerminal(terminalID) else {
                throw ControlHarnessCoreError.terminalNotFound(terminalID.uuidString)
            }
            self.pendingTerminalInputEchoes.removeValue(forKey: terminalIDString)
            self.sampleStore.removeTerminal(terminalIDString)
            self.readStore.removeTerminal(terminalIDString)
            self.readAfterWriteStore.removeTerminal(terminalIDString)
            self.streamStore.removeTerminal(terminalIDString)
            let generation = self.generations.advanceTerminalGeneration(for: terminalIDString)
            let sequence = self.eventHub.emit(
                event: "terminal.closed",
                requestID: request.requestID,
                resource: .init(type: "terminal", id: terminalIDString, generation: generation),
                payload: nil
            )
            return .init(
                terminalID: terminalIDString,
                generation: generation,
                sequence: sequence,
                operation: "close-terminal",
                acknowledged: true,
                writeID: nil
            )
        }
    }

    private struct TerminalReadResolution {
        let content: String
        let consistency: String
        let cacheAgeMs: Int
        let capturedAt: Date
    }

    private func resolveTerminalRead(
        terminalUUID: UUID,
        terminalID: String,
        scope: String,
        surface: any ControlHarnessReadableSurface,
        forceFresh: Bool
    ) throws -> TerminalReadResolution {
        let currentTime = now()
        let activityClass = samplingActivityResolver(terminalUUID)
            ?? sampleStore.sample(for: terminalID, scope: scope)?.activityClass
            ?? .observed
        let existingSample = sampleStore.sample(for: terminalID, scope: scope)
        let sampleIsFresh = existingSample.map {
            sampleStore.isFresh($0, activityClass: activityClass, now: currentTime)
        } ?? false

        if !forceFresh,
           let sample = existingSample,
           sampleIsFresh {
            return TerminalReadResolution(
                content: sample.content,
                consistency: sample.consistency,
                cacheAgeMs: sample.cacheAgeMs,
                capturedAt: sample.capturedAt
            )
        }

        let shouldForceRefresh = shouldForceFreshRead(
            requested: forceFresh || !sampleIsFresh,
            terminalID: terminalID,
            scope: scope,
            activityClass: activityClass,
            now: currentTime
        )
        let read: (content: String, cacheAgeMs: Int)
        switch scope {
        case "visible":
            read = surface.controlHarnessReadVisibleText(refresh: shouldForceRefresh)
        case "screen":
            read = surface.controlHarnessReadScreenText(refresh: shouldForceRefresh)
        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported read scope: \(scope)")
        }

        let sample = sampleStore.store(
            terminalID: terminalID,
            scope: scope,
            content: read.content,
            consistency: shouldForceRefresh ? "fresh_\(scope)" : "sampled_\(scope)",
            cacheAgeMs: read.cacheAgeMs,
            capturedAt: currentTime,
            activityClass: activityClass,
            forcedFresh: shouldForceRefresh
        )
        return TerminalReadResolution(
            content: sample.content,
            consistency: sample.consistency,
            cacheAgeMs: sample.cacheAgeMs,
            capturedAt: sample.capturedAt
        )
    }

    private func shouldForceFreshRead(
        requested: Bool,
        terminalID: String,
        scope: String,
        activityClass: ControlHarnessSamplingActivityClass,
        now: Date
    ) -> Bool {
        guard requested else {
            return false
        }
        guard let footprintBytes = currentReadPhysicalFootprintBytes(now: now) else {
            return true
        }
        guard footprintBytes >= Self.readPressureFootprintLimitBytes else {
            return true
        }

        maybeLogReadMemoryThrottle(
            terminalID: terminalID,
            scope: scope,
            activityClass: activityClass,
            now: now,
            footprintBytes: footprintBytes
        )
        return false
    }

    private func currentReadPhysicalFootprintBytes(now: Date) -> UInt64? {
        if let lastReadFootprintProbeDate,
           let lastReadFootprintBytes,
           now.timeIntervalSince(lastReadFootprintProbeDate) < Self.readMemoryPressureProbeIntervalSeconds {
            return lastReadFootprintBytes
        }

        var vmInfo = task_vm_info_data_t()
        var vmInfoCount = mach_msg_type_number_t(
            MemoryLayout.size(ofValue: vmInfo) / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &vmInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmInfoCount)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &vmInfoCount)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }

        let footprintBytes = UInt64(vmInfo.phys_footprint)
        lastReadFootprintProbeDate = now
        lastReadFootprintBytes = footprintBytes
        return footprintBytes
    }

    private func maybeLogReadMemoryThrottle(
        terminalID: String,
        scope: String,
        activityClass: ControlHarnessSamplingActivityClass,
        now: Date,
        footprintBytes: UInt64
    ) {
        if let lastReadMemoryThrottleLogDate,
           now.timeIntervalSince(lastReadMemoryThrottleLogDate) < Self.readMemoryThrottleLogIntervalSeconds {
            return
        }
        lastReadMemoryThrottleLogDate = now

        RuntimeDiagnosticsLogger.log(
            component: "control_harness.core",
            event: "fresh_read_degraded_for_memory_pressure",
            details: [
                "terminal_id": terminalID,
                "scope": scope,
                "activity_class": activityClass.rawValue,
                "threshold_bytes": "\(Self.readPressureFootprintLimitBytes)",
                "physical_footprint_bytes": "\(footprintBytes)",
            ]
        )
    }

    private func todoSnapshot(from request: ControlHarnessRequest) throws -> ControlTodoSnapshotResult {
        let date = try parseTodoDate(request.date)
        return try makeTodoSnapshot(for: date, includeCompleted: request.includeCompleted ?? true)
    }

    private func addTodo(from request: ControlHarnessRequest) throws -> ControlTodoMutationResult {
        guard let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw ControlHarnessCoreError.invalidArgument("todo-add requires non-empty title")
        }

        let date = try parseTodoDate(request.date)
        let store = try todoStore()
        guard store.addTodoItem(title: title, notes: request.notes ?? "", for: date) != nil else {
            throw ControlHarnessCoreError.operationFailed(store.lastError ?? "Failed to add todo item")
        }

        let snapshot = try makeTodoSnapshot(for: date, includeCompleted: true)
        return .init(
            operation: "todo-add",
            date: snapshot.date,
            mutatedTodoID: snapshot.items.last?.todoID,
            syncedCount: nil,
            snapshot: snapshot
        )
    }

    private func updateTodo(from request: ControlHarnessRequest) throws -> ControlTodoMutationResult {
        let todoID = try parseTodoID(request.todoID)
        let date = try parseTodoDate(request.date)
        let currentSnapshot = try makeTodoSnapshot(for: date, includeCompleted: true)
        guard let existingItem = currentSnapshot.items.first(where: { $0.todoID == todoID.uuidString }) else {
            throw ControlHarnessCoreError.operationFailed("No todo exists for todo_id=\(todoID.uuidString)")
        }

        let store = try todoStore()
        let title = request.title ?? existingItem.title
        let notes = request.notes ?? existingItem.notes
        guard store.updateTodoItem(id: todoID, title: title, notes: notes, for: date) != nil else {
            throw ControlHarnessCoreError.operationFailed(store.lastError ?? "Failed to update todo item")
        }

        let snapshot = try makeTodoSnapshot(for: date, includeCompleted: true)
        return .init(
            operation: "todo-update",
            date: snapshot.date,
            mutatedTodoID: todoID.uuidString,
            syncedCount: nil,
            snapshot: snapshot
        )
    }

    private func completeTodo(from request: ControlHarnessRequest) throws -> ControlTodoMutationResult {
        let todoID = try parseTodoID(request.todoID)
        guard let completed = request.completed else {
            throw ControlHarnessCoreError.invalidArgument("todo-complete requires completed=true|false")
        }

        let date = try parseTodoDate(request.date)
        let store = try todoStore()
        guard store.setTodoItemCompleted(id: todoID, isCompleted: completed, for: date) != nil else {
            throw ControlHarnessCoreError.operationFailed(store.lastError ?? "Failed to update todo completion state")
        }

        let snapshot = try makeTodoSnapshot(for: date, includeCompleted: true)
        return .init(
            operation: "todo-complete",
            date: snapshot.date,
            mutatedTodoID: todoID.uuidString,
            syncedCount: nil,
            snapshot: snapshot
        )
    }

    private func assignTodo(from request: ControlHarnessRequest) throws -> ControlTodoMutationResult {
        let todoID = try parseTodoID(request.todoID)
        let workspaceID = try parseWorkspaceID(request.workspaceID)
        let date = try parseTodoDate(request.date)
        let store = try todoStore()
        guard store.assignTodoItem(id: todoID, to: workspaceID, for: date) != nil else {
            throw ControlHarnessCoreError.operationFailed(store.lastError ?? "Failed to assign todo item")
        }

        let snapshot = try makeTodoSnapshot(for: date, includeCompleted: true)
        return .init(
            operation: "todo-assign",
            date: snapshot.date,
            mutatedTodoID: todoID.uuidString,
            syncedCount: nil,
            snapshot: snapshot
        )
    }

    private func syncStaleTodos(from request: ControlHarnessRequest) throws -> ControlTodoMutationResult {
        let date = try parseTodoDate(request.date)
        let store = try todoStore()
        guard let syncedCount = store.syncIncompleteTodoPointers(into: date) else {
            throw ControlHarnessCoreError.operationFailed(store.lastError ?? "Failed to sync stale todo pointers")
        }

        let snapshot = try makeTodoSnapshot(for: date, includeCompleted: true)
        return .init(
            operation: "todo-sync-stale",
            date: snapshot.date,
            mutatedTodoID: nil,
            syncedCount: syncedCount,
            snapshot: snapshot
        )
    }

    private func handleTerminalWindowBellDidChange(_ notification: Notification) {
        guard let controller = notification.object as? TerminalController else {
            return
        }

        let tabID = controller.workspaceID.uuidString
        let generation = generations.advanceTabGeneration(for: tabID)
        let hasBell = (notification.userInfo?[Notification.Name.terminalWindowHasBellKey] as? Bool) ?? controller.bell
        _ = eventHub.emit(
            event: "tab.updated",
            requestID: nil,
            resource: .init(type: "tab", id: tabID, generation: generation),
            payload: AnyEncodable(ControlTabUpdatedEventPayload(title: nil, hasBell: hasBell))
        )
    }

    private static func applyChangedRowBudget(
        _ rows: [ControlHarnessReadChangedRow],
        maxLines: Int?
    ) -> [ControlHarnessReadChangedRow] {
        guard let maxLines else { return rows }
        guard rows.count > maxLines else { return rows }
        return Array(rows.suffix(maxLines))
    }

    private static func applyTextBudget(_ text: String, maxChars: Int?) -> String {
        guard let maxChars else { return text }
        guard text.count > maxChars else { return text }
        return String(text.suffix(maxChars))
    }

    private static func writeID(forSequence sequence: Int64) -> String {
        "seq_\(sequence)"
    }

    private static func parseWriteID(_ writeID: String) throws -> Int64 {
        guard writeID.hasPrefix("seq_"), let sequence = Int64(writeID.dropFirst(4)) else {
            throw ControlHarnessCoreError.invalidArgument("Invalid read_after_write_id: \(writeID)")
        }
        return sequence
    }

    private struct ControlTerminalStreamDeltaSnapshot {
        let frameID: String
        let parentFrameID: String?
        let deltaKind: String
        let content: String
        let changedRows: [ControlHarnessReadChangedRow]
        let hasChanges: Bool
    }

    private nonisolated static func syncMainActor<T>(
        _ body: @escaping @MainActor () -> T
    ) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        Task { @MainActor in
            result = body()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private func terminalStreamScope(from request: ControlHarnessRequest) throws -> String {
        let scope = request.scope ?? "visible"
        switch scope {
        case "visible", "screen":
            return scope
        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported read scope: \(scope)")
        }
    }

    private func captureTerminalStreamDelta(
        terminalUUID: UUID,
        terminalID: String,
        scope: String,
        sinceFrameID: String?
    ) throws -> ControlTerminalStreamDeltaSnapshot {
        guard let surface = surfaceResolver(terminalUUID) else {
            if appDelegate == nil {
                throw ControlHarnessCoreError.appUnavailable
            }
            throw ControlHarnessCoreError.terminalNotFound(terminalID)
        }

        let read = try resolveTerminalRead(
            terminalUUID: terminalUUID,
            terminalID: terminalID,
            scope: scope,
            surface: surface,
            forceFresh: true
        )
        let frame = readStore.capture(terminalID: terminalID, scope: scope, content: read.content)
        let delta = readStore.delta(from: sinceFrameID, to: frame.frameID)
        return .init(
            frameID: frame.frameID,
            parentFrameID: frame.parentFrameID,
            deltaKind: delta.kind,
            content: delta.text,
            changedRows: delta.changedRows,
            hasChanges: delta.hasChanges
        )
    }

    private func encodeTerminalStreamChunk(_ payload: ControlTerminalStreamChunkPayload) throws -> Data {
        let record = ControlTerminalStreamChunkRecord(
            streamID: payload.streamID,
            terminalID: payload.terminalID,
            generation: payload.generation,
            frameID: payload.frameID,
            parentFrameID: payload.parentFrameID,
            deltaKind: payload.deltaKind,
            content: payload.content,
            contentLength: payload.content.utf8.count,
            changedRows: payload.changedRows
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)
        return data
    }

    private func pollTerminalStreamChunk(
        terminalUUID: UUID,
        terminalID: String,
        streamID: String,
        generation: Int,
        scope: String,
        sinceFrameID: String?
    ) -> ControlHarnessTerminalStreamPollChunk? {
        guard let flowState = streamStore.flowState(
            terminalID: terminalID,
            streamID: streamID
        ) else {
            return nil
        }
        guard flowState.flowPaused == false else {
            return nil
        }

        let delta: ControlTerminalStreamDeltaSnapshot
        do {
            delta = try captureTerminalStreamDelta(
                terminalUUID: terminalUUID,
                terminalID: terminalID,
                scope: scope,
                sinceFrameID: sinceFrameID
            )
        } catch {
            return nil
        }
        guard delta.hasChanges else {
            return nil
        }

        let payload: Data
        do {
            payload = try encodeTerminalStreamChunk(
                .init(
                    streamID: streamID,
                    terminalID: terminalID,
                    generation: generation,
                    frameID: delta.frameID,
                    parentFrameID: delta.parentFrameID,
                    deltaKind: delta.deltaKind,
                    content: delta.content,
                    changedRows: delta.changedRows
                )
            )
        } catch {
            return nil
        }

        guard let produceState = streamStore.produce(
            terminalID: terminalID,
            streamID: streamID,
            chunkBytes: delta.content.utf8.count
        ), produceState.accepted else {
            return nil
        }

        return .init(frameID: delta.frameID, payload: payload)
    }

    private func makeEventSubscription(
        _ request: ControlHarnessRequest,
        socketPath: String
    ) throws -> (result: ControlEventSubscriptionResult, session: (any ControlHarnessSubscriptionSession)?) {
        guard request.command == "events.subscribe" else {
            throw ControlHarnessCoreError.unsupportedCommand(request.command)
        }

        let replay = eventHub.replay(afterSequence: request.sinceSequence, limit: request.eventLimit)
        let session = ControlHarnessEventSubscriptionSession(
            eventHub: eventHub,
            replayEvents: replay,
            eventLimit: request.eventLimit
        )
        let liveStreamOpen = session.shouldStreamLive
        return (
            makeEventSubscriptionResult(
                request,
                replayedEventCount: replay.count,
                liveStreamOpen: liveStreamOpen
            ),
            liveStreamOpen ? session : nil
        )
    }

    private func makeTerminalStreamSubscription(
        _ request: ControlHarnessRequest
    ) throws -> (result: ControlTerminalStreamOpenResult, session: (any ControlHarnessSubscriptionSession)?) {
        let terminalID = try parseTerminalID(request.terminalID)
        let terminalIDString = terminalID.uuidString
        let generation = generations.currentTerminalGeneration(for: terminalIDString)
        try generations.assertExpectedGeneration(
            request.expectedGeneration,
            resourceType: "terminal",
            resourceID: terminalIDString,
            currentGeneration: generation
        )
        guard surfaceResolver(terminalID) != nil else {
            if appDelegate == nil {
                throw ControlHarnessCoreError.appUnavailable
            }
            throw ControlHarnessCoreError.terminalNotFound(terminalIDString)
        }

        let scope = try terminalStreamScope(from: request)
        let streamState = streamStore.openStream(terminalID: terminalIDString, generation: generation)
        do {
            let seedDelta = try captureTerminalStreamDelta(
                terminalUUID: terminalID,
                terminalID: terminalIDString,
                scope: scope,
                sinceFrameID: nil
            )
            let seedPayload = try encodeTerminalStreamChunk(
                .init(
                    streamID: streamState.streamID,
                    terminalID: terminalIDString,
                    generation: generation,
                    frameID: seedDelta.frameID,
                    parentFrameID: seedDelta.parentFrameID,
                    deltaKind: "reset",
                    content: seedDelta.content,
                    changedRows: seedDelta.changedRows
                )
            )
            let streamStore = self.streamStore
            let streamID = streamState.streamID
            let session = ControlHarnessTerminalStreamSubscriptionSession(
                replayEvents: [seedPayload],
                initialFrameID: seedDelta.frameID,
                pollInterval: streamPollInterval,
                pollChunk: { [weak self] sinceFrameID in
                    guard let self else { return nil }
                    return Self.syncMainActor {
                        self.pollTerminalStreamChunk(
                            terminalUUID: terminalID,
                            terminalID: terminalIDString,
                            streamID: streamID,
                            generation: generation,
                            scope: scope,
                            sinceFrameID: sinceFrameID
                        )
                    } ?? nil
                },
                onClose: {
                    streamStore.removeStream(streamID)
                }
            )

            let result = ControlTerminalStreamOpenResult(
                protocolVersion: Self.protocolVersion,
                streamID: streamState.streamID,
                terminalID: terminalIDString,
                generation: generation,
                mode: "stream",
                lastSequence: eventHub.currentSequence(),
                liveStreamOpen: true,
                highWatermarkBytes: streamState.highWatermarkBytes,
                lowWatermarkBytes: streamState.lowWatermarkBytes,
                unackedBytes: streamState.unackedBytes,
                flowPaused: streamState.flowPaused
            )
            return (result, session)
        } catch {
            streamStore.removeStream(streamState.streamID)
            throw error
        }
    }

    private func makeSubscription(
        _ request: ControlHarnessRequest,
        socketPath: String
    ) throws -> (payload: AnyEncodable, session: (any ControlHarnessSubscriptionSession)?) {
        _ = socketPath
        switch request.command {
        case "events.subscribe":
            let prepared = try makeEventSubscription(request, socketPath: socketPath)
            return (AnyEncodable(prepared.result), prepared.session)
        case "terminal.stream.open":
            let prepared = try makeTerminalStreamSubscription(request)
            return (AnyEncodable(prepared.result), prepared.session)
        default:
            throw ControlHarnessCoreError.unsupportedCommand(request.command)
        }
    }

    private func makeEventSubscriptionResult(
        _ request: ControlHarnessRequest,
        streamID: String? = nil,
        replayedEventCount: Int,
        liveStreamOpen: Bool
    ) -> ControlEventSubscriptionResult {
        .init(
            protocolVersion: Self.protocolVersion,
            subscribed: true,
            streamID: streamID,
            lastSequence: eventHub.currentSequence(),
            sinceSequence: request.sinceSequence,
            eventLimit: request.eventLimit,
            replayedEventCount: replayedEventCount,
            liveStreamOpen: liveStreamOpen
        )
    }

    private func subscribeToBufferedEvents(
        from request: ControlHarnessRequest
    ) throws -> ControlEventSubscriptionResult {
        let kinds = normalizedBufferedEventKinds(from: request)
        let subscription = eventStreamRegistry.subscribe(
            sinceSequence: request.sinceSequence,
            eventLimit: request.eventLimit,
            kinds: kinds
        )
        return makeEventSubscriptionResult(
            request,
            streamID: subscription.streamID,
            replayedEventCount: subscription.replayedEventCount,
            liveStreamOpen: subscription.liveStreamOpen
        )
    }

    private func drainBufferedEvents(
        from request: ControlHarnessRequest
    ) throws -> ControlBufferedEventStreamDrainResult {
        let streamID = try parseRequiredStreamID(request.streamID)
        guard let drained = eventStreamRegistry.drain(streamID: streamID, limit: request.eventLimit) else {
            throw ControlHarnessCoreError.invalidArgument(
                "No active event stream exists for stream_id=\(streamID)"
            )
        }

        return .init(
            protocolVersion: Self.protocolVersion,
            streamID: drained.streamID,
            lastSequence: eventHub.currentSequence(),
            eventLimit: request.eventLimit,
            drainedEventCount: drained.payloads.count,
            requiresSnapshotResync: drained.requiresSnapshotResync,
            droppedEvents: drained.droppedEvents,
            liveStreamOpen: drained.liveStreamOpen,
            events: try drained.payloads.map(Self.decodeBufferedEventPayload)
        )
    }

    private func unsubscribeBufferedEvents(
        from request: ControlHarnessRequest
    ) throws -> ControlEventStreamUnsubscribeResult {
        let streamID = try parseRequiredStreamID(request.streamID)
        guard eventStreamRegistry.unsubscribe(streamID: streamID) else {
            throw ControlHarnessCoreError.invalidArgument(
                "No active event stream exists for stream_id=\(streamID)"
            )
        }

        return .init(
            protocolVersion: Self.protocolVersion,
            streamID: streamID,
            unsubscribed: true,
            liveStreamOpen: false
        )
    }

    private func normalizedBufferedEventKinds(from request: ControlHarnessRequest) -> Set<String> {
        guard let rawKinds = request.payload?["kinds"]?
            .split(separator: ",")
            .map({
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            })
            .filter({ !$0.isEmpty }),
              rawKinds.isEmpty == false else {
            return []
        }
        return Set(rawKinds)
    }

    private func parseRequiredStreamID(_ rawValue: String?) throws -> String {
        try parseRequiredUUID(rawValue, field: "stream_id").uuidString
    }

    private static func decodeBufferedEventPayload(_ payload: Data) throws -> ControlHarnessJSONValue {
        let trimmedPayload: Data
        if payload.last == 0x0A {
            trimmedPayload = Data(payload.dropLast())
        } else {
            trimmedPayload = payload
        }
        return try JSONDecoder().decode(ControlHarnessJSONValue.self, from: trimmedPayload)
    }

    private func resolveParentWindow(parentTabID: String?) throws -> NSWindow? {
        guard let parentTabID else {
            return TerminalController.preferredParent?.window
        }
        return try resolveTabController(tabID: parentTabID).window
    }

    private func resolveTabController(tabID: String?) throws -> TerminalController {
        guard let tabID, let uuid = UUID(uuidString: tabID) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid tab_id")
        }
        guard let controller = TerminalController.all.first(where: { $0.workspaceID == uuid }) else {
            throw ControlHarnessCoreError.tabNotFound(tabID)
        }
        return controller
    }

    private func parseTerminalID(_ rawValue: String?) throws -> UUID {
        guard let rawValue, let uuid = UUID(uuidString: rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid terminal_id")
        }
        return uuid
    }

    private func parseRequiredUUID(_ rawValue: String?, field: String) throws -> UUID {
        guard let rawValue = normalizedOptionalString(rawValue),
              let uuid = UUID(uuidString: rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid \(field)")
        }
        return uuid
    }

    private func parseOptionalUUID(_ rawValue: String?, field: String) throws -> UUID? {
        guard let rawValue = normalizedOptionalString(rawValue) else { return nil }
        guard let uuid = UUID(uuidString: rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid \(field)")
        }
        return uuid
    }

    private func parseTodoID(_ rawValue: String?) throws -> UUID {
        guard let rawValue else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid todo_id")
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid todo_id")
        }
        return uuid
    }

    private func parseWorkspaceID(_ rawValue: String?) throws -> UUID? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let uuid = UUID(uuidString: trimmed) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid workspace_id")
        }
        return uuid
    }

    private func parseTodoDate(_ rawValue: String?) throws -> Date {
        guard let rawValue else { return .now }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .now }
        guard let date = AITerminalTodoSettings.date(fromDayString: trimmed) else {
            throw ControlHarnessCoreError.invalidArgument("Invalid todo date: \(trimmed)")
        }
        return date
    }

    private func parseRuntimeTaskState(_ rawValue: String?) throws -> AgentRuntimeTaskState {
        guard let rawValue = normalizedOptionalString(rawValue),
              let state = AgentRuntimeTaskState(rawValue: rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid task_state")
        }
        return state
    }

    private func parseRuntimeTaskKind(_ rawValue: String?) throws -> AgentRuntimeTaskKind {
        guard let rawValue = normalizedOptionalString(rawValue),
              let kind = AgentRuntimeTaskKind(rawValue: rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid task_kind")
        }
        return kind
    }

    private func parseOptionalRuntimeTaskKinds(
        _ request: ControlHarnessRequest
    ) throws -> Set<AgentRuntimeTaskKind>? {
        var parsedKinds: [AgentRuntimeTaskKind] = []

        if let taskKind = normalizedOptionalString(request.taskKind) {
            guard let parsed = AgentRuntimeTaskKind(rawValue: taskKind) else {
                throw ControlHarnessCoreError.invalidArgument("Missing or invalid task_kind")
            }
            parsedKinds.append(parsed)
        }

        for rawValue in request.taskKinds ?? [] {
            guard let normalized = normalizedOptionalString(rawValue),
                  let parsed = AgentRuntimeTaskKind(rawValue: normalized) else {
                throw ControlHarnessCoreError.invalidArgument("Missing or invalid task_kinds")
            }
            parsedKinds.append(parsed)
        }

        guard !parsedKinds.isEmpty else { return nil }
        return Set(parsedKinds)
    }

    private func parseOptionalRuntimeScheduleState(_ rawValue: String?) throws -> AgentRuntimeScheduleState? {
        guard let rawValue = normalizedOptionalString(rawValue) else { return nil }
        guard let state = AgentRuntimeScheduleState(rawValue: rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid schedule_state")
        }
        return state
    }

    private func parseRuntimeScheduleRecurrenceMode(_ rawValue: String?) throws -> AgentRuntimeScheduleRecurrence.Mode {
        let rawValue = normalizedOptionalString(rawValue) ?? AgentRuntimeScheduleRecurrence.Mode.once.rawValue
        guard let mode = AgentRuntimeScheduleRecurrence.Mode(rawValue: rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid recurrence_mode")
        }
        return mode
    }

    private func parseOptionalISO8601Date(_ rawValue: String?) throws -> Date? {
        guard let rawValue = normalizedOptionalString(rawValue) else { return nil }
        guard let parsed = Self.parseISO8601Date(rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("scheduled_at must be ISO-8601")
        }
        return parsed
    }

    private func parsePanelID(_ rawValue: String?) throws -> String {
        guard let panelID = normalizedOptionalString(rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid panel_id")
        }
        guard Self.supportedPanelIDs.contains(panelID) else {
            throw ControlHarnessCoreError.invalidArgument("Unsupported panel_id: \(panelID)")
        }
        return panelID
    }

    private func parseRequiredPanelTabID(_ rawValue: String?, panelID: String) throws -> String {
        guard let panelTabID = normalizedOptionalString(rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid panel_tab_id")
        }
        try validatePanelTabID(panelTabID, panelID: panelID)
        return panelTabID
    }

    private func validatePanelTabID(_ panelTabID: String, panelID: String) throws {
        switch panelID {
        case "settings":
            guard settingsTab(from: panelTabID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported panel_tab_id \(panelTabID) for settings")
            }
        case "ssh_connections":
            guard SSHConnectionsPanelTab(rawValue: panelTabID) != nil else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported panel_tab_id \(panelTabID) for ssh_connections")
            }
        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported panel_id: \(panelID)")
        }
    }

    private func parseRequiredPayloadBoolean(_ request: ControlHarnessRequest, key: String) throws -> Bool {
        guard let rawValue = normalizedOptionalString(request.payload?[key]),
              let parsed = Self.parseBooleanString(rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("payload.\(key) must be true|false")
        }
        return parsed
    }

    private func resolveWindow(windowNumber: Int?) throws -> NSWindow {
        guard let windowNumber else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid window_number")
        }
        guard let window = currentTopLevelWindows().first(where: { $0.windowNumber == windowNumber }) else {
            throw ControlHarnessCoreError.operationFailed("No window exists for window_number=\(windowNumber)")
        }
        return window
    }

    private func currentTopLevelWindow() -> NSWindow? {
        let candidates = [
            NSApp.keyWindow,
            NSApp.mainWindow,
        ].compactMap { $0?.tabGroup?.selectedWindow ?? $0 }
        return candidates.first ?? currentTopLevelWindows().first
    }

    private func currentTopLevelWindows() -> [NSWindow] {
        var seen: Set<Int> = []
        return NSApp.windows.compactMap { window in
            let topLevel = window.tabGroup?.selectedWindow ?? window
            guard seen.insert(topLevel.windowNumber).inserted else { return nil }
            return topLevel
        }.sorted { lhs, rhs in
            lhs.windowNumber < rhs.windowNumber
        }
    }

    private func makeWindowSummary(_ window: NSWindow) -> ControlWindowSummary {
        .init(
            windowNumber: window.windowNumber,
            kind: windowKind(window),
            title: window.title,
            isVisible: window.isVisible,
            isFocused: window.isKeyWindow,
            isMainWindow: window.isMainWindow,
            isMiniaturized: window.isMiniaturized,
            isFloatingOnTop: window.level == .floating,
            tabbedWindowCount: window.tabGroup?.windows.count ?? 1,
            tabOverviewVisible: window.tabGroup?.isOverviewVisible ?? false
        )
    }

    private func windowKind(_ window: NSWindow) -> String {
        switch window.windowController {
        case is SettingsController:
            return "settings"
        case is SSHConnectionsController:
            return "ssh_connections"
        case is BrowserTabController:
            return "browser"
        case is TerminalController:
            return "terminal"
        default:
            return "other"
        }
    }

    private func makePanelSummaries() -> [ControlPanelSummary] {
        ["settings", "ssh_connections"].map(panelSummary)
    }

    private func panelSummary(panelID: String) -> ControlPanelSummary {
        switch panelID {
        case "settings":
            let selectedTab = appDelegate.map { settingsPanelTabID($0.settingsController.selectedTab) }
            return .init(
                panelID: panelID,
                title: "Settings",
                isVisible: appDelegate?.settingsController.isVisible ?? false,
                selectedTabID: selectedTab,
                supportedTabIDs: SettingsView.SettingsTab.allCases.map(settingsPanelTabID),
                windowNumber: appDelegate?.settingsController.window?.windowNumber
            )
        case "ssh_connections":
            return .init(
                panelID: panelID,
                title: L10n.SSHConnections.windowTitle,
                isVisible: appDelegate?.sshConnectionsController.isVisible ?? false,
                selectedTabID: appDelegate?.sshConnectionsController.selectedTab.rawValue,
                supportedTabIDs: SSHConnectionsPanelTab.allCases.map(\.rawValue),
                windowNumber: appDelegate?.sshConnectionsController.window?.windowNumber
            )
        default:
            return .init(panelID: panelID, title: panelID, isVisible: false, selectedTabID: nil, supportedTabIDs: [], windowNumber: nil)
        }
    }

    private func mutatePanel(
        panelID rawPanelID: String?,
        panelTabID rawPanelTabID: String?,
        action _: String,
        body: (String, String?) throws -> Void
    ) throws -> ControlPanelSummary {
        let panelID = try parsePanelID(rawPanelID)
        let panelTabID = normalizedOptionalString(rawPanelTabID)
        if let panelTabID {
            try validatePanelTabID(panelTabID, panelID: panelID)
        }
        try body(panelID, panelTabID)
        return panelSummary(panelID: panelID)
    }

    private func openPanel(panelID: String, panelTabID: String?) throws {
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }
        switch panelID {
        case "settings":
            appDelegate.settingsController.show(tab: settingsTab(from: panelTabID) ?? .general)
        case "ssh_connections":
            appDelegate.sshConnectionsController.show(tab: SSHConnectionsPanelTab(rawValue: panelTabID ?? "") ?? .connections)
        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported panel_id: \(panelID)")
        }
    }

    private func settingsPanelTabID(_ tab: SettingsView.SettingsTab) -> String {
        switch tab {
        case .general:
            return "general"
        case .appearance:
            return "appearance"
        case .gateway:
            return "gateway"
        }
    }

    private func settingsTab(from rawValue: String?) -> SettingsView.SettingsTab? {
        switch normalizedOptionalString(rawValue) {
        case "general":
            return .general
        case "appearance":
            return .appearance
        case "gateway":
            return .gateway
        default:
            return nil
        }
    }

    private func settingsSchemaEntries() -> [ControlSettingsSchemaEntry] {
        let defaults = defaultSettingsValues()
        return [
            .init(key: "app.language", valueType: "enum", defaultValue: defaults["app.language"] ?? "", enumValues: AppLanguageSetting.allCases.map(\.rawValue), description: "Desktop UI language override."),
            .init(key: "appearance.icon", valueType: "enum", defaultValue: defaults["appearance.icon"] ?? "", enumValues: Ghostty.MacOSIcon.builtInOptions.map(\.rawValue) + [Ghostty.MacOSIcon.custom.rawValue, Ghostty.MacOSIcon.customStyle.rawValue], description: "App icon preset."),
            .init(key: "appearance.icon.custom_path", valueType: "path", defaultValue: defaults["appearance.icon.custom_path"] ?? "", enumValues: nil, description: "Custom ICNS path."),
            .init(key: "appearance.icon.frame", valueType: "enum", defaultValue: defaults["appearance.icon.frame"] ?? "", enumValues: [Ghostty.MacOSIconFrame.aluminum.rawValue, Ghostty.MacOSIconFrame.beige.rawValue, Ghostty.MacOSIconFrame.plastic.rawValue, Ghostty.MacOSIconFrame.chrome.rawValue], description: "Custom style icon frame."),
            .init(key: "appearance.icon.ghost_color_hex", valueType: "color", defaultValue: defaults["appearance.icon.ghost_color_hex"] ?? "", enumValues: nil, description: "Ghost color hex."),
            .init(key: "appearance.icon.screen_colors", valueType: "csv_colors", defaultValue: defaults["appearance.icon.screen_colors"] ?? "", enumValues: nil, description: "Comma separated screen colors."),
            .init(key: "browser.profile_path", valueType: "path", defaultValue: defaults["browser.profile_path"] ?? "", enumValues: nil, description: "Browser profile override path."),
            .init(key: "browser.runtime_path", valueType: "path", defaultValue: defaults["browser.runtime_path"] ?? "", enumValues: nil, description: "Browser runtime override path."),
            .init(key: "gateway.enabled", valueType: "bool", defaultValue: defaults["gateway.enabled"] ?? "", enumValues: ["true", "false"], description: "Control gateway enable flag."),
            .init(key: "gateway.listen_host", valueType: "string", defaultValue: defaults["gateway.listen_host"] ?? "", enumValues: nil, description: "Gateway listen host."),
            .init(key: "gateway.listen_port", valueType: "u16", defaultValue: defaults["gateway.listen_port"] ?? "", enumValues: nil, description: "Gateway listen port."),
            .init(key: "gateway.pairing_advertise_host", valueType: "string", defaultValue: defaults["gateway.pairing_advertise_host"] ?? "", enumValues: nil, description: "Gateway pairing advertise host."),
            .init(key: "gateway.show_pairing_qr_on_launch", valueType: "bool", defaultValue: defaults["gateway.show_pairing_qr_on_launch"] ?? "", enumValues: ["true", "false"], description: "Show pairing QR after launch."),
            .init(key: "gateway.semantic_profile", valueType: "enum", defaultValue: defaults["gateway.semantic_profile"] ?? "", enumValues: ControlHarnessSemanticProfile.allCases.map(\.rawValue), description: "Gateway semantic profile."),
            .init(key: "todo.enabled", valueType: "bool", defaultValue: defaults["todo.enabled"] ?? "", enumValues: ["true", "false"], description: "Todo workspace enable flag."),
            .init(key: "todo.workspace_root_path", valueType: "path", defaultValue: defaults["todo.workspace_root_path"] ?? "", enumValues: nil, description: "Todo workspace root."),
            .init(key: "todo.show_completed_items", valueType: "bool", defaultValue: defaults["todo.show_completed_items"] ?? "", enumValues: ["true", "false"], description: "Show completed todo items."),
            .init(key: "todo.selected_date_anchor", valueType: "date", defaultValue: defaults["todo.selected_date_anchor"] ?? "", enumValues: nil, description: "Todo anchor day."),
            .init(key: "todo.sidebar_edge", valueType: "enum", defaultValue: defaults["todo.sidebar_edge"] ?? "", enumValues: AITerminalTodoSidebarEdge.allCases.map(\.rawValue), description: "Todo sidebar edge."),
            .init(key: "todo.workspace_overlay_visible", valueType: "bool", defaultValue: defaults["todo.workspace_overlay_visible"] ?? "", enumValues: ["true", "false"], description: "Workspace overlay visibility."),
            .init(key: "todo.workspace_overlay_corner", valueType: "enum", defaultValue: defaults["todo.workspace_overlay_corner"] ?? "", enumValues: AITerminalTodoOverlayCorner.allCases.map(\.rawValue), description: "Workspace overlay corner."),
            .init(key: "learning.enabled", valueType: "bool", defaultValue: defaults["learning.enabled"] ?? "", enumValues: ["true", "false"], description: "Learning workspace enable flag."),
            .init(key: "learning.prefer_tab_working_directory", valueType: "bool", defaultValue: defaults["learning.prefer_tab_working_directory"] ?? "", enumValues: ["true", "false"], description: "Prefer tab working directory."),
            .init(key: "learning.default_project_path", valueType: "path", defaultValue: defaults["learning.default_project_path"] ?? "", enumValues: nil, description: "Learning project root."),
            .init(key: "learning.notes_relative_path", valueType: "string", defaultValue: defaults["learning.notes_relative_path"] ?? "", enumValues: nil, description: "Relative notes path."),
            .init(key: "learning.command_template", valueType: "string", defaultValue: defaults["learning.command_template"] ?? "", enumValues: nil, description: "Learning command template."),
            .init(key: "heartbeat.enabled", valueType: "bool", defaultValue: defaults["heartbeat.enabled"] ?? "", enumValues: ["true", "false"], description: "Heartbeat queue enable flag."),
            .init(key: "heartbeat.interval_seconds", valueType: "double", defaultValue: defaults["heartbeat.interval_seconds"] ?? "", enumValues: nil, description: "Heartbeat interval seconds."),
            .init(key: "heartbeat.max_concurrent_tasks", valueType: "int", defaultValue: defaults["heartbeat.max_concurrent_tasks"] ?? "", enumValues: nil, description: "Heartbeat max concurrency."),
            .init(key: "heartbeat.allow_external_inbox_mutations", valueType: "bool", defaultValue: defaults["heartbeat.allow_external_inbox_mutations"] ?? "", enumValues: ["true", "false"], description: "Allow external inbox edits."),
            .init(key: "runtime.enabled", valueType: "bool", defaultValue: defaults["runtime.enabled"] ?? "", enumValues: ["true", "false"], description: "Agent runtime enable flag."),
            .init(key: "runtime.default_lease_duration_seconds", valueType: "double", defaultValue: defaults["runtime.default_lease_duration_seconds"] ?? "", enumValues: nil, description: "Default runtime lease duration."),
            .init(key: "runtime.stale_task_policy", valueType: "enum", defaultValue: defaults["runtime.stale_task_policy"] ?? "", enumValues: AgentRuntimeStaleTaskPolicy.allCases.map(\.rawValue), description: "Runtime stale task policy."),
        ]
    }

    private func currentSettingsValues() -> [String: String] {
        var values = defaultSettingsValues()
        if let appDelegate {
            values["app.language"] = AppLanguageSetting.storedSelection().rawValue

            let iconSettings = appDelegate.appIconSettings.sanitized
            values["appearance.icon"] = iconSettings.icon.rawValue
            values["appearance.icon.custom_path"] = iconSettings.customIconPath
            values["appearance.icon.frame"] = iconSettings.frame.rawValue
            values["appearance.icon.ghost_color_hex"] = iconSettings.ghostColorHex
            values["appearance.icon.screen_colors"] = iconSettings.screenColorHexes.joined(separator: ",")

            values["browser.profile_path"] = appDelegate.browserProfilePathOverride ?? ""
            values["browser.runtime_path"] = appDelegate.browserRuntimePathOverride ?? ""

            let gateway = appDelegate.controlHarnessGatewaySettings.sanitized()
            values["gateway.enabled"] = Self.booleanString(gateway.isEnabled)
            values["gateway.listen_host"] = gateway.listenHost
            values["gateway.listen_port"] = String(gateway.listenPort)
            values["gateway.pairing_advertise_host"] = gateway.pairingAdvertiseHost
            values["gateway.show_pairing_qr_on_launch"] = Self.booleanString(gateway.showPairingQrOnLaunch)
            values["gateway.semantic_profile"] = gateway.semanticProfile

            let store = appDelegate.aiTerminalManagerStore
            let todo = store.todoSettings
            values["todo.enabled"] = Self.booleanString(todo.enabled)
            values["todo.workspace_root_path"] = todo.workspaceRootPath
            values["todo.show_completed_items"] = Self.booleanString(todo.showCompletedItems)
            values["todo.selected_date_anchor"] = todo.selectedDateAnchor
            values["todo.sidebar_edge"] = todo.sidebarEdge.rawValue
            values["todo.workspace_overlay_visible"] = Self.booleanString(todo.workspaceOverlayVisible)
            values["todo.workspace_overlay_corner"] = todo.workspaceOverlayCorner.rawValue

            let learning = store.learningSettings
            values["learning.enabled"] = Self.booleanString(learning.enabled)
            values["learning.prefer_tab_working_directory"] = Self.booleanString(learning.preferTabWorkingDirectory)
            values["learning.default_project_path"] = learning.defaultProjectPath
            values["learning.notes_relative_path"] = learning.notesRelativePath
            values["learning.command_template"] = learning.commandTemplate

            let heartbeat = store.heartbeatQueueSettings
            values["heartbeat.enabled"] = Self.booleanString(heartbeat.enabled)
            values["heartbeat.interval_seconds"] = Self.doubleString(heartbeat.heartbeatIntervalSeconds)
            values["heartbeat.max_concurrent_tasks"] = String(heartbeat.maxConcurrentTasks)
            values["heartbeat.allow_external_inbox_mutations"] = Self.booleanString(heartbeat.allowExternalInboxMutations)

            let runtime = store.agentRuntimeSettings.sanitized()
            values["runtime.enabled"] = Self.booleanString(runtime.enabled)
            values["runtime.default_lease_duration_seconds"] = Self.doubleString(runtime.defaultLeaseDurationSeconds)
            values["runtime.stale_task_policy"] = runtime.staleTaskPolicy.rawValue
        }
        return values
    }

    private func defaultSettingsValues() -> [String: String] {
        let iconDefaults = AppIconSettings().sanitized
        let gatewayDefaults = ControlHarnessGatewayAppSettings().sanitized()
        let todoDefaults = AITerminalTodoSettings()
        let learningDefaults = AITerminalLearningSettings()
        let heartbeatDefaults = AITerminalHeartbeatQueueSettings()
        let runtimeDefaults = AgentRuntimeSettings().sanitized()
        return [
            "app.language": AppLanguageSetting.system.rawValue,
            "appearance.icon": iconDefaults.icon.rawValue,
            "appearance.icon.custom_path": iconDefaults.customIconPath,
            "appearance.icon.frame": iconDefaults.frame.rawValue,
            "appearance.icon.ghost_color_hex": iconDefaults.ghostColorHex,
            "appearance.icon.screen_colors": iconDefaults.screenColorHexes.joined(separator: ","),
            "browser.profile_path": "",
            "browser.runtime_path": "",
            "gateway.enabled": Self.booleanString(gatewayDefaults.isEnabled),
            "gateway.listen_host": gatewayDefaults.listenHost,
            "gateway.listen_port": String(gatewayDefaults.listenPort),
            "gateway.pairing_advertise_host": gatewayDefaults.pairingAdvertiseHost,
            "gateway.show_pairing_qr_on_launch": Self.booleanString(gatewayDefaults.showPairingQrOnLaunch),
            "gateway.semantic_profile": gatewayDefaults.semanticProfile,
            "todo.enabled": Self.booleanString(todoDefaults.enabled),
            "todo.workspace_root_path": todoDefaults.workspaceRootPath,
            "todo.show_completed_items": Self.booleanString(todoDefaults.showCompletedItems),
            "todo.selected_date_anchor": todoDefaults.selectedDateAnchor,
            "todo.sidebar_edge": todoDefaults.sidebarEdge.rawValue,
            "todo.workspace_overlay_visible": Self.booleanString(todoDefaults.workspaceOverlayVisible),
            "todo.workspace_overlay_corner": todoDefaults.workspaceOverlayCorner.rawValue,
            "learning.enabled": Self.booleanString(learningDefaults.enabled),
            "learning.prefer_tab_working_directory": Self.booleanString(learningDefaults.preferTabWorkingDirectory),
            "learning.default_project_path": learningDefaults.defaultProjectPath,
            "learning.notes_relative_path": learningDefaults.notesRelativePath,
            "learning.command_template": learningDefaults.commandTemplate,
            "heartbeat.enabled": Self.booleanString(heartbeatDefaults.enabled),
            "heartbeat.interval_seconds": Self.doubleString(heartbeatDefaults.heartbeatIntervalSeconds),
            "heartbeat.max_concurrent_tasks": String(heartbeatDefaults.maxConcurrentTasks),
            "heartbeat.allow_external_inbox_mutations": Self.booleanString(heartbeatDefaults.allowExternalInboxMutations),
            "runtime.enabled": Self.booleanString(runtimeDefaults.enabled),
            "runtime.default_lease_duration_seconds": Self.doubleString(runtimeDefaults.defaultLeaseDurationSeconds),
            "runtime.stale_task_policy": runtimeDefaults.staleTaskPolicy.rawValue,
        ]
    }

    private func normalizedSettingsPatch(_ payload: [String: String]?) throws -> [String: String] {
        guard let payload, payload.isEmpty == false else {
            throw ControlHarnessCoreError.invalidArgument("settings payload must not be empty")
        }
        var normalized: [String: String] = [:]
        for key in payload.keys.sorted() {
            guard let rawValue = payload[key] else { continue }
            normalized[key] = try normalizeSettingValue(key: key, rawValue: rawValue)
        }
        return normalized
    }

    private func applyingSettingsPatch(_ patch: [String: String], to base: [String: String]) throws -> [String: String] {
        var next = base
        for key in patch.keys.sorted() {
            next[key] = patch[key]
        }
        return next
    }

    private func normalizeSettingValue(key: String, rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "app.language":
            guard let value = AppLanguageSetting(rawValue: trimmed) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported app.language value: \(rawValue)")
            }
            return value.rawValue

        case "appearance.icon":
            guard let value = Ghostty.MacOSIcon(rawValue: trimmed) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported appearance.icon value: \(rawValue)")
            }
            return value.rawValue

        case "appearance.icon.custom_path":
            return trimmed.isEmpty ? AppIconSettings.defaultCustomIconPath : (trimmed as NSString).standardizingPath

        case "appearance.icon.frame":
            guard let value = Ghostty.MacOSIconFrame(rawValue: trimmed) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported appearance.icon.frame value: \(rawValue)")
            }
            return value.rawValue

        case "appearance.icon.ghost_color_hex":
            guard let normalized = NSColor(hex: trimmed)?.hexString else {
                throw ControlHarnessCoreError.invalidArgument("appearance.icon.ghost_color_hex must be a hex color")
            }
            return normalized

        case "appearance.icon.screen_colors":
            let colors = try normalizeScreenColors(trimmed)
            return colors.joined(separator: ",")

        case "browser.profile_path", "browser.runtime_path":
            return trimmed.isEmpty ? "" : (trimmed as NSString).standardizingPath

        case "gateway.enabled", "gateway.show_pairing_qr_on_launch", "todo.enabled", "todo.show_completed_items",
            "todo.workspace_overlay_visible", "learning.enabled", "learning.prefer_tab_working_directory",
            "heartbeat.enabled", "heartbeat.allow_external_inbox_mutations", "runtime.enabled":
            guard let value = Self.parseBooleanString(trimmed) else {
                throw ControlHarnessCoreError.invalidArgument("\(key) must be true|false")
            }
            return Self.booleanString(value)

        case "gateway.listen_host":
            return trimmed.isEmpty ? ControlHarnessGatewayAppSettings.defaultListenHost : trimmed

        case "gateway.listen_port":
            guard let port = ControlHarnessGatewayAppSettings.parseListenPort(trimmed) else {
                throw ControlHarnessCoreError.invalidArgument("gateway.listen_port must be a valid TCP port")
            }
            return String(port)

        case "gateway.pairing_advertise_host":
            return trimmed

        case "gateway.semantic_profile":
            guard let value = ControlHarnessSemanticProfile(rawValue: trimmed) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported gateway.semantic_profile value: \(rawValue)")
            }
            return value.rawValue

        case "todo.workspace_root_path":
            return trimmed.isEmpty ? AITerminalTodoSettings.defaultWorkspaceRootPath : (trimmed as NSString).standardizingPath

        case "todo.selected_date_anchor":
            guard AITerminalTodoSettings.date(fromDayString: trimmed) != nil else {
                throw ControlHarnessCoreError.invalidArgument("todo.selected_date_anchor must be YYYY-MM-DD")
            }
            return AITerminalTodoSettings.normalizedDateAnchor(trimmed)

        case "todo.sidebar_edge":
            guard let value = AITerminalTodoSidebarEdge(rawValue: trimmed) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported todo.sidebar_edge value: \(rawValue)")
            }
            return value.rawValue

        case "todo.workspace_overlay_corner":
            guard let value = AITerminalTodoOverlayCorner(rawValue: trimmed) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported todo.workspace_overlay_corner value: \(rawValue)")
            }
            return value.rawValue

        case "learning.default_project_path":
            return trimmed.isEmpty ? AITerminalLearningSettings.defaultLearnWorkspacePath : (trimmed as NSString).standardizingPath

        case "learning.notes_relative_path":
            return trimmed.isEmpty ? AITerminalLearningSettings.defaultNotesRelativePath : trimmed

        case "learning.command_template":
            return AITerminalLearningSettings.normalizedCommandTemplate(trimmed)

        case "heartbeat.interval_seconds", "runtime.default_lease_duration_seconds":
            guard let value = Double(trimmed), value > 0 else {
                throw ControlHarnessCoreError.invalidArgument("\(key) must be a positive number")
            }
            return Self.doubleString(value)

        case "heartbeat.max_concurrent_tasks":
            guard let value = Int(trimmed), value > 0 else {
                throw ControlHarnessCoreError.invalidArgument("heartbeat.max_concurrent_tasks must be a positive integer")
            }
            return String(value)

        case "runtime.stale_task_policy":
            guard let value = AgentRuntimeStaleTaskPolicy(rawValue: trimmed) else {
                throw ControlHarnessCoreError.invalidArgument("Unsupported runtime.stale_task_policy value: \(rawValue)")
            }
            return value.rawValue

        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported settings key: \(key)")
        }
    }

    private func normalizeScreenColors(_ rawValue: String) throws -> [String] {
        let parts = rawValue
            .split { $0 == "," || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty {
            return AppIconSettings.defaultScreenColorHexes
        }
        let normalized = parts.compactMap { NSColor(hex: $0)?.hexString }
        guard normalized.count == parts.count else {
            throw ControlHarnessCoreError.invalidArgument("appearance.icon.screen_colors must be comma-separated hex colors")
        }
        return Array(normalized.prefix(AppIconSettings.maxScreenColorCount))
    }

    private func persistSettingsValues(_ values: [String: String]) throws {
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }

        guard let language = AppLanguageSetting(rawValue: requiredSettingValue("app.language", from: values)) else {
            throw ControlHarnessCoreError.invalidArgument("Missing app.language")
        }
        language.apply()

        guard let icon = Ghostty.MacOSIcon(rawValue: requiredSettingValue("appearance.icon", from: values)) else {
            throw ControlHarnessCoreError.invalidArgument("Missing appearance.icon")
        }
        guard let frame = Ghostty.MacOSIconFrame(rawValue: requiredSettingValue("appearance.icon.frame", from: values)) else {
            throw ControlHarnessCoreError.invalidArgument("Missing appearance.icon.frame")
        }
        let iconSettings = AppIconSettings(
            icon: icon,
            customIconPath: requiredSettingValue("appearance.icon.custom_path", from: values),
            frame: frame,
            ghostColorHex: requiredSettingValue("appearance.icon.ghost_color_hex", from: values),
            screenColorHexes: try normalizeScreenColors(requiredSettingValue("appearance.icon.screen_colors", from: values))
        )
        do {
            try appDelegate.saveVisualAppIconSettings(iconSettings)
            try appDelegate.saveBrowserSettings(
                profilePath: requiredSettingValue("browser.profile_path", from: values),
                runtimePath: requiredSettingValue("browser.runtime_path", from: values)
            )
        } catch {
            throw ControlHarnessCoreError.operationFailed(error.localizedDescription)
        }

        let gatewaySettings = ControlHarnessGatewayAppSettings(
            isEnabled: try requiredSettingBoolean("gateway.enabled", from: values),
            listenHost: requiredSettingValue("gateway.listen_host", from: values),
            listenPort: UInt16(requiredSettingValue("gateway.listen_port", from: values)) ?? ControlHarnessGatewayAppSettings.defaultListenPort,
            pairingAdvertiseHost: requiredSettingValue("gateway.pairing_advertise_host", from: values),
            showPairingQrOnLaunch: try requiredSettingBoolean("gateway.show_pairing_qr_on_launch", from: values),
            semanticProfile: requiredSettingValue("gateway.semantic_profile", from: values)
        )
        appDelegate.saveControlHarnessGatewaySettings(gatewaySettings)

        let store = appDelegate.aiTerminalManagerStore
        store.saveTodoSettings(.init(
            enabled: try requiredSettingBoolean("todo.enabled", from: values),
            workspaceRootPath: requiredSettingValue("todo.workspace_root_path", from: values),
            showCompletedItems: try requiredSettingBoolean("todo.show_completed_items", from: values),
            selectedDateAnchor: requiredSettingValue("todo.selected_date_anchor", from: values),
            sidebarEdge: AITerminalTodoSidebarEdge(rawValue: requiredSettingValue("todo.sidebar_edge", from: values)) ?? .leading,
            workspaceOverlayVisible: try requiredSettingBoolean("todo.workspace_overlay_visible", from: values),
            workspaceOverlayCorner: AITerminalTodoOverlayCorner(rawValue: requiredSettingValue("todo.workspace_overlay_corner", from: values)) ?? .topLeading
        ))
        store.saveLearningSettings(.init(
            enabled: try requiredSettingBoolean("learning.enabled", from: values),
            preferTabWorkingDirectory: try requiredSettingBoolean("learning.prefer_tab_working_directory", from: values),
            defaultProjectPath: requiredSettingValue("learning.default_project_path", from: values),
            notesRelativePath: requiredSettingValue("learning.notes_relative_path", from: values),
            commandTemplate: requiredSettingValue("learning.command_template", from: values),
            fastModel: AITerminalLearningSettings.defaultFastModel,
            promptTemplate: AITerminalLearningSettings.defaultPromptTemplate
        ))
        store.saveHeartbeatQueueSettings(.init(
            enabled: try requiredSettingBoolean("heartbeat.enabled", from: values),
            heartbeatIntervalSeconds: Double(requiredSettingValue("heartbeat.interval_seconds", from: values)) ?? 5,
            maxConcurrentTasks: Int(requiredSettingValue("heartbeat.max_concurrent_tasks", from: values)) ?? 4,
            allowExternalInboxMutations: try requiredSettingBoolean("heartbeat.allow_external_inbox_mutations", from: values)
        ))
        store.saveAgentRuntimeSettings(.init(
            enabled: try requiredSettingBoolean("runtime.enabled", from: values),
            defaultLeaseDurationSeconds: Double(requiredSettingValue("runtime.default_lease_duration_seconds", from: values)) ?? AgentRuntimeSettings().defaultLeaseDurationSeconds,
            staleTaskPolicy: AgentRuntimeStaleTaskPolicy(rawValue: requiredSettingValue("runtime.stale_task_policy", from: values)) ?? .requeueClaimedWork
        ))
    }

    private func requiredSettingValue(_ key: String, from values: [String: String]) -> String {
        values[key] ?? ""
    }

    private func requiredSettingBoolean(_ key: String, from values: [String: String]) throws -> Bool {
        guard let rawValue = values[key], let parsed = Self.parseBooleanString(rawValue) else {
            throw ControlHarnessCoreError.invalidArgument("Missing or invalid \(key)")
        }
        return parsed
    }

    private func changedSettingKeys(from previous: [String: String], to next: [String: String]) -> [String] {
        Array(Set(previous.keys).union(next.keys)).sorted().filter { previous[$0] != next[$0] }
    }

    private func diagnosticsLogURL(source: String) -> URL? {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.leongong.ghodex"
        let baseDirectory = ControlHarnessAuditLogger.baseDirectory(bundleID: bundleID)
        switch source {
        case "audit":
            return baseDirectory.appendingPathComponent("control-harness-audit.jsonl", isDirectory: false)
        case "events":
            return baseDirectory.appendingPathComponent("control-harness-events.jsonl", isDirectory: false)
        case "runtime":
            return baseDirectory.appendingPathComponent("runtime-memory-diagnostics.jsonl", isDirectory: false)
        default:
            return nil
        }
    }

    private func tailLogLines(at url: URL, source: String, limit: Int) throws -> [ControlDiagnosticsLogLine] {
        let lines = try readUTF8Lines(at: url)
        let slice = Array(lines.suffix(limit))
        let startIndex = max(lines.count - slice.count, 0)
        return slice.enumerated().map { offset, rawLine in
            .init(source: source, lineNumber: startIndex + offset + 1, raw: rawLine)
        }
    }

    private func readAuditRecords(at url: URL) throws -> [ControlAuditRecord] {
        try readUTF8Lines(at: url).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ControlAuditRecord.self, from: data)
        }
    }

    private func recentAuditErrors(limit: Int) -> [ControlDiagnosticsRecentError] {
        guard let url = diagnosticsLogURL(source: "audit"),
              let records = try? readAuditRecords(at: url) else {
            return []
        }
        return records
            .filter { $0.status == "error" || $0.errorCode != nil }
            .suffix(limit)
            .map {
                .init(
                    source: "audit",
                    timestamp: $0.timestamp,
                    code: $0.errorCode,
                    message: $0.errorCode ?? "control_harness_error",
                    command: $0.command
                )
            }
    }

    private func readUTF8Lines(at url: URL) throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ControlHarnessCoreError.operationFailed("Unable to decode log file at \(url.path)")
        }
        return text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func parseBooleanString(_ rawValue: String?) -> Bool? {
        guard let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              normalized.isEmpty == false else {
            return nil
        }
        switch normalized {
        case "true", "1", "yes", "on":
            return true
        case "false", "0", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func booleanString(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func doubleString(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.000_000_1 {
            return String(Int(rounded))
        }
        return String(value)
    }

    private func normalizedOptionalString(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func todoStore() throws -> AITerminalManagerStore {
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }
        return appDelegate.aiTerminalManagerStore
    }

    private func runtimeStore() throws -> AITerminalManagerStore {
        try todoStore()
    }

    private func makeTodoSnapshot(for date: Date, includeCompleted: Bool) throws -> ControlTodoSnapshotResult {
        let store = try todoStore()
        let document = store.todoDocument(for: date)
        let orderedItems = document.orderedItems
        let returnedItems = includeCompleted ? orderedItems : orderedItems.filter { !$0.isCompleted }
        let completedCount = document.items.filter(\.isCompleted).count
        let totalCount = document.items.count

        return .init(
            date: document.date,
            includeCompleted: includeCompleted,
            updatedAt: Self.iso8601(document.updatedAt),
            completionRate: document.completionRate,
            totalCount: totalCount,
            completedCount: completedCount,
            remainingCount: max(totalCount - completedCount, 0),
            returnedCount: returnedItems.count,
            items: returnedItems.map(todoRecord(from:))
        )
    }

    private func todoRecord(from item: AITerminalTodoItem) -> ControlTodoItemRecord {
        .init(
            todoID: item.id.uuidString,
            sourceDay: item.sourceItem?.day,
            sourceItemID: item.sourceItem?.itemID.uuidString,
            title: item.title,
            notes: item.notes,
            assignedWorkspaceID: item.assignedWorkspaceID?.uuidString,
            isCompleted: item.isCompleted,
            completedAt: item.completedAt.map(Self.iso8601),
            createdAt: Self.iso8601(item.createdAt),
            updatedAt: Self.iso8601(item.updatedAt),
            sortOrder: item.sortOrder,
            isCarryForwardPointer: item.isCarryForwardPointer
        )
    }

    private func validateWorkingDirectory(_ workingDirectory: String?) throws {
        guard let workingDirectory, !workingDirectory.isEmpty else { return }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ControlHarnessCoreError.invalidArgument(
                "Working directory does not exist: \(workingDirectory)"
            )
        }
    }

    private func normalizedTabTitleOverride(_ title: String?) -> String? {
        guard let title else {
            return nil
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func buildSurfaceConfiguration(from request: ControlHarnessRequest) -> Ghostty.SurfaceConfiguration {
        var config = Ghostty.SurfaceConfiguration()
        config.initialInput = buildInitialInput(from: request)
        if let environment = request.environment {
            for (key, value) in environment {
                config.environmentVariables[key] = value
            }
        }
        return config
    }

    private func buildInitialInput(from request: ControlHarnessRequest) -> String? {
        var lines: [String] = []

        if let workingDirectory = request.workingDirectory, !workingDirectory.isEmpty {
            // Use a shell-level `cd` instead of the surface workingDirectory field so
            // protected locations such as Desktop/Documents do not stall surface creation.
            lines.append("cd -- \(shellSingleQuoted(workingDirectory))")
        }

        if let commandText = request.commandText, !commandText.isEmpty {
            if commandText.hasSuffix("\n") {
                lines.append(String(commandText.dropLast()))
            } else {
                lines.append(commandText)
            }
        }

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n") + "\n"
    }

    private func validateAgentRuntimeTaskPayload(
        taskKind rawTaskKind: String,
        request: ControlHarnessRequest
    ) throws {
        let metadata = request.metadata ?? [:]
        let normalizedMetadata = metadata.reduce(into: [String: String]()) { partial, entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            partial[key] = value
        }
        switch AgentRuntimeTaskKind(rawValue: rawTaskKind) {
        case .terminalCommand:
            guard let commandText = normalizedOptionalString(request.commandText),
                  !commandText.isEmpty else {
                throw ControlHarnessCoreError.invalidArgument("terminal_command requires non-empty command_text")
            }
        case .terminalText:
            guard let text = normalizedOptionalString(request.text),
                  !text.isEmpty else {
                throw ControlHarnessCoreError.invalidArgument("terminal_text requires non-empty text")
            }
        case .browserNavigation:
            guard normalizedOptionalString(request.text) != nil ||
                    normalizedMetadata["url"] != nil else {
                throw ControlHarnessCoreError.invalidArgument("browser_navigation requires text or metadata.url")
            }
        case .browserInteraction:
            guard normalizedMetadata["action"] != nil else {
                throw ControlHarnessCoreError.invalidArgument("browser_interaction requires metadata.action")
            }
        case .visionAutomation:
            guard normalizedOptionalString(request.text) != nil ||
                    normalizedMetadata["instruction"] != nil else {
                throw ControlHarnessCoreError.invalidArgument("vision_automation requires text or metadata.instruction")
            }
        case .hostWorkflow, .approvalCheckpoint, .systemMaintenance:
            break
        case nil:
            break
        }
    }

    private func shellSingleQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func mapAgentRuntimeError(_ error: AgentRuntimeStoreError) -> ControlHarnessCoreError {
        switch error {
        case .runtimeDisabled:
            return .runtimeDisabled
        case .sessionNotFound(let sessionID):
            return .runtimeSessionNotFound(sessionID.uuidString)
        case .sessionExpired(let sessionID):
            return .runtimeSessionExpired(sessionID.uuidString)
        case .sessionAlreadyHasActiveTask(let sessionID):
            return .runtimeSessionBusy(sessionID.uuidString)
        case .taskNotFound(let taskID):
            return .runtimeTaskNotFound(taskID.uuidString)
        case .taskOwnershipMismatch(let taskID, let sessionID):
            return .runtimeTaskOwnershipMismatch(
                taskID: taskID.uuidString,
                sessionID: sessionID.uuidString
            )
        case .invalidTaskTransition(let from, let to):
            return .runtimeTaskTransitionRejected(from: from.rawValue, to: to.rawValue)
        case .scheduleNotFound(let scheduleID):
            return .runtimeScheduleNotFound(scheduleID.uuidString)
        case .invalidScheduleTransition(let from, let to):
            return .runtimeScheduleTransitionRejected(from: from.rawValue, to: to.rawValue)
        }
    }

    nonisolated static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    nonisolated private static func parseISO8601Date(_ rawValue: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: rawValue) {
            return parsed
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }
}

enum ControlHarnessCoreError: LocalizedError {
    case appUnavailable
    case invalidArgument(String)
    case unsupportedProtocolVersion(String)
    case unsupportedCommand(String)
    case tabNotFound(String)
    case terminalNotFound(String)
    case operationFailed(String)
    case staleTarget(resourceType: String, resourceID: String, expected: Int, actual: Int)
    case idempotencyConflict(String)
    case runtimeDisabled
    case runtimeSessionNotFound(String)
    case runtimeSessionExpired(String)
    case runtimeSessionBusy(String)
    case runtimeTaskNotFound(String)
    case runtimeTaskOwnershipMismatch(taskID: String, sessionID: String)
    case runtimeTaskTransitionRejected(from: String, to: String)
    case runtimeScheduleNotFound(String)
    case runtimeScheduleTransitionRejected(from: String, to: String)
    case internalFailure

    var code: String {
        switch self {
        case .appUnavailable:
            return "app_unavailable"
        case .invalidArgument:
            return "invalid_argument"
        case .unsupportedProtocolVersion:
            return "unsupported_protocol_version"
        case .unsupportedCommand:
            return "unsupported_command"
        case .tabNotFound:
            return "tab_not_found"
        case .terminalNotFound:
            return "terminal_not_found"
        case .operationFailed:
            return "operation_failed"
        case .staleTarget:
            return "stale_target"
        case .idempotencyConflict:
            return "idempotency_conflict"
        case .runtimeDisabled:
            return "runtime_disabled"
        case .runtimeSessionNotFound:
            return "runtime_session_not_found"
        case .runtimeSessionExpired:
            return "runtime_session_expired"
        case .runtimeSessionBusy:
            return "runtime_session_busy"
        case .runtimeTaskNotFound:
            return "runtime_task_not_found"
        case .runtimeTaskOwnershipMismatch:
            return "runtime_task_ownership_mismatch"
        case .runtimeTaskTransitionRejected:
            return "runtime_task_transition_rejected"
        case .runtimeScheduleNotFound:
            return "runtime_schedule_not_found"
        case .runtimeScheduleTransitionRejected:
            return "runtime_schedule_transition_rejected"
        case .internalFailure:
            return "internal_failure"
        }
    }

    var errorDescription: String? {
        switch self {
        case .appUnavailable:
            return "The running GhoDex application is unavailable"
        case .invalidArgument(let message):
            return message
        case .unsupportedProtocolVersion(let protocolVersion):
            return "Unsupported protocol_version=\(protocolVersion)"
        case .unsupportedCommand(let command):
            return "Unsupported control command: \(command)"
        case .tabNotFound(let tabID):
            return "No tab exists for tab_id=\(tabID)"
        case .terminalNotFound(let terminalID):
            return "No terminal exists for terminal_id=\(terminalID)"
        case .operationFailed(let message):
            return message
        case .staleTarget(let resourceType, let resourceID, let expected, let actual):
            return "The \(resourceType) \(resourceID) is at generation \(actual), not \(expected)"
        case .idempotencyConflict(let token):
            return "The idempotency key \(token) was reused with different request parameters"
        case .runtimeDisabled:
            return "Agent runtime is disabled."
        case .runtimeSessionNotFound(let sessionID):
            return "Agent runtime session \(sessionID.lowercased()) was not found."
        case .runtimeSessionExpired(let sessionID):
            return "Agent runtime session \(sessionID.lowercased()) is expired."
        case .runtimeSessionBusy(let sessionID):
            return "Agent runtime session \(sessionID.lowercased()) already has an active task."
        case .runtimeTaskNotFound(let taskID):
            return "Agent runtime task \(taskID.lowercased()) was not found."
        case .runtimeTaskOwnershipMismatch(let taskID, let sessionID):
            return "Agent runtime task \(taskID.lowercased()) is not owned by session \(sessionID.lowercased())."
        case .runtimeTaskTransitionRejected(let from, let to):
            return "Invalid agent runtime task transition: \(from) -> \(to)."
        case .runtimeScheduleNotFound(let scheduleID):
            return "Agent runtime schedule \(scheduleID.lowercased()) was not found."
        case .runtimeScheduleTransitionRejected(let from, let to):
            return "Invalid agent runtime schedule transition: \(from) -> \(to)."
        case .internalFailure:
            return "An internal control harness failure occurred"
        }
    }
}
