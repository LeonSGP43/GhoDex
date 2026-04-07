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
    let scope: String?
    let text: String?
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
    let pairingCode: String?
    let requestedScopes: [String]?

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
        case scope
        case text
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
        case pairingCode = "pairing_code"
        case requestedScopes = "requested_scopes"
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
        scope: String?,
        text: String?,
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
        pairingCode: String? = nil,
        requestedScopes: [String]? = nil
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
        self.scope = scope
        self.text = text
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
        self.pairingCode = pairingCode
        self.requestedScopes = requestedScopes
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
    let lastSequence: Int64

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case socketPath = "socket_path"
        case commands
        case lastSequence = "last_sequence"
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
    let lastSequence: Int64
    let sinceSequence: Int64?
    let eventLimit: Int?
    let replayedEventCount: Int
    let liveStreamOpen: Bool

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case subscribed
        case lastSequence = "last_sequence"
        case sinceSequence = "since_sequence"
        case eventLimit = "event_limit"
        case replayedEventCount = "replayed_event_count"
        case liveStreamOpen = "live_stream_open"
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
    let scope: String?
    let text: String?
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

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case command
        case date
        case tabID = "tab_id"
        case parentTabID = "parent_tab_id"
        case terminalID = "terminal_id"
        case todoID = "todo_id"
        case scope
        case text
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
    }
}

private struct ControlAuditRecord: Encodable {
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
    static let supportedCommands = [
        "handshake",
        "snapshot",
        "new-tab",
        "close-tab",
        "rename-tab",
        "send-text",
        "run-command",
        "read-terminal",
        "close-terminal",
        "todo-snapshot",
        "todo-add",
        "todo-update",
        "todo-complete",
        "todo-assign",
        "todo-sync-stale",
        "events.subscribe"
    ]

    private weak var appDelegate: AppDelegate?
    private let auditLogger: ControlHarnessAuditLogger
    private let eventHub: ControlHarnessEventHub
    private let generations: ControlHarnessGenerationTracker
    private let idempotencyStore: ControlHarnessIdempotencyStore
    private let readStore: ControlHarnessTerminalReadStore
    private let readAfterWriteStore: ControlHarnessReadAfterWriteStore
    private let sampleStore: ControlHarnessSampleStore
    private let surfaceResolver: @MainActor (UUID) -> (any ControlHarnessReadableSurface)?
    private let samplingActivityResolver: @MainActor (UUID) -> ControlHarnessSamplingActivityClass?
    private let now: @MainActor () -> Date
    private var terminalWindowBellObserver: NSObjectProtocol?
    private var lastReadFootprintProbeDate: Date?
    private var lastReadFootprintBytes: UInt64?
    private var lastReadMemoryThrottleLogDate: Date?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.leongong.ghodex",
        category: "ControlHarnessCore"
    )
    private static let readMemoryPressureProbeIntervalSeconds: TimeInterval = 1.0
    private static let readMemoryThrottleLogIntervalSeconds: TimeInterval = 10.0
#if DEBUG
    private static let readMemoryPressureFootprintThresholdBytes: UInt64 = 2 * 1024 * 1024 * 1024
#else
    private static let readMemoryPressureFootprintThresholdBytes: UInt64 = 3 * 1024 * 1024 * 1024
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
        sampleStore: ControlHarnessSampleStore,
        surfaceResolver: (@MainActor (UUID) -> (any ControlHarnessReadableSurface)?)? = nil,
        samplingActivityResolver: (@MainActor (UUID) -> ControlHarnessSamplingActivityClass?)? = nil,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.appDelegate = appDelegate
        self.auditLogger = auditLogger
        self.eventHub = eventHub
        self.generations = generations
        self.idempotencyStore = idempotencyStore
        self.readStore = readStore
        self.readAfterWriteStore = readAfterWriteStore
        self.sampleStore = sampleStore
        self.surfaceResolver = surfaceResolver ?? { [weak appDelegate] terminalID in
            appDelegate?.controlHarnessReadableSurface(for: terminalID)
        }
        self.samplingActivityResolver = samplingActivityResolver ?? { [weak appDelegate] terminalID in
            appDelegate?.controlHarnessSamplingActivityClass(for: terminalID)
        }
        self.now = now
        self.terminalWindowBellObserver = NotificationCenter.default.addObserver(
            forName: .terminalWindowBellDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleTerminalWindowBellDidChange(notification)
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
        let started = DispatchTime.now()
        let response: ControlHarnessResponse
        let session: ControlHarnessEventSubscriptionSession?

        do {
            try validateRequest(request)
            let prepared = try makeEventSubscription(request, socketPath: socketPath)
            response = .init(
                requestID: request.requestID,
                status: "ok",
                result: AnyEncodable(prepared.result),
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
            } else if let token = request.idempotencyToken, let mutationFingerprint = try? idempotencyFingerprint(for: request) {
                idempotencyStore.store(
                    response: response,
                    sequence: responseSequence,
                    token: token,
                    fingerprint: mutationFingerprint
                )
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
            if let token = request.idempotencyToken, let mutationFingerprint = try? idempotencyFingerprint(for: request) {
                idempotencyStore.store(
                    response: response,
                    sequence: responseSequence,
                    token: token,
                    fingerprint: mutationFingerprint
                )
            }
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

        if let date = request.date?.trimmingCharacters(in: .whitespacesAndNewlines),
           !date.isEmpty,
           AITerminalTodoSettings.date(fromDayString: date) == nil {
            throw ControlHarnessCoreError.invalidArgument("Invalid todo date: \(date)")
        }

        switch request.command {
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
            scope: request.scope,
            text: request.text,
            commandText: request.commandText,
            workingDirectory: request.workingDirectory,
            title: request.title,
            notes: request.notes,
            environment: request.environment,
            force: request.force,
            completed: request.completed,
            workspaceID: request.workspaceID,
            includeCompleted: request.includeCompleted,
            expectedGeneration: request.expectedGeneration
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(fingerprint)
    }

    private func dispatch(
        _ request: ControlHarnessRequest,
        socketPath: String
    ) throws -> (payload: AnyEncodable, sequence: Int64?) {
        switch request.command {
        case "handshake":
            return (
                AnyEncodable(ControlHandshakeResult(
                protocolVersion: Self.protocolVersion,
                socketPath: socketPath,
                    commands: Self.supportedCommands,
                    lastSequence: eventHub.currentSequence()
                )),
                nil
            )

        case "snapshot":
            return (AnyEncodable(makeSnapshot()), nil)

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

        case "run-command":
            let result = try runCommand(from: request)
            return (AnyEncodable(result), result.sequence)

        case "read-terminal":
            return (AnyEncodable(try readTerminal(from: request)), nil)

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

        default:
            throw ControlHarnessCoreError.unsupportedCommand(request.command)
        }
    }

    private func makeSnapshot() -> ControlSnapshotResult {
        let tabs = TerminalController.all.compactMap { controller -> ControlTabSnapshot? in
            guard let window = controller.window else { return nil }
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
                windowNumber: window.windowNumber,
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

    private func createTab(from request: ControlHarnessRequest) throws -> ControlCreateTabResult {
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }

        try validateWorkingDirectory(request.workingDirectory)
        let parentWindow = try resolveParentWindow(parentTabID: request.parentTabID)
        let config = buildSurfaceConfiguration(from: request)
        guard let controller = TerminalController.newTab(
            appDelegate.ghostty,
            from: parentWindow,
            withBaseConfig: config
        ) else {
            throw ControlHarnessCoreError.operationFailed("Failed to create a new tab")
        }

        if let title = normalizedTabTitleOverride(request.title) {
            controller.titleOverride = title
        }

        let tabID = controller.workspaceID.uuidString
        let tabGeneration = generations.currentTabGeneration(for: tabID)
        let terminalID = controller.surfaceTree.leftmostActiveSurface()?.id.uuidString
        let terminalGeneration = terminalID.map { generations.currentTerminalGeneration(for: $0) }
        let sequence = eventHub.emit(
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

    private func closeTab(from request: ControlHarnessRequest) throws -> ControlTabCloseResult {
        let controller = try resolveTabController(tabID: request.tabID)
        let tabID = controller.workspaceID.uuidString
        let currentGeneration = generations.currentTabGeneration(for: tabID)
        try generations.assertExpectedGeneration(
            request.expectedGeneration,
            resourceType: "tab",
            resourceID: tabID,
            currentGeneration: currentGeneration
        )
        if request.force != true,
           let confirmation = closeTabConfirmation(for: controller) {
            return .init(
                tabID: tabID,
                generation: currentGeneration,
                sequence: eventHub.currentSequence(),
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
        let generation = generations.advanceTabGeneration(for: tabID)
        let sequence = eventHub.emit(
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

    private func renameTab(from request: ControlHarnessRequest) throws -> ControlTabMutationResult {
        let controller = try resolveTabController(tabID: request.tabID)
        let tabID = controller.workspaceID.uuidString
        let currentGeneration = generations.currentTabGeneration(for: tabID)
        try generations.assertExpectedGeneration(
            request.expectedGeneration,
            resourceType: "tab",
            resourceID: tabID,
            currentGeneration: currentGeneration
        )

        let normalizedTitle = normalizedTabTitleOverride(request.title)
        controller.titleOverride = normalizedTitle

        let generation = generations.advanceTabGeneration(for: tabID)
        let sequence = eventHub.emit(
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
        guard let text = request.text, !text.isEmpty else {
            throw ControlHarnessCoreError.invalidArgument("Missing text payload")
        }
        let terminalID = try parseTerminalID(request.terminalID)
        let terminalIDString = terminalID.uuidString
        let currentGeneration = generations.currentTerminalGeneration(for: terminalIDString)
        try generations.assertExpectedGeneration(
            request.expectedGeneration,
            resourceType: "terminal",
            resourceID: terminalIDString,
            currentGeneration: currentGeneration
        )
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }
        guard appDelegate.controlHarnessSendText(text, to: terminalID) else {
            throw ControlHarnessCoreError.terminalNotFound(terminalID.uuidString)
        }
        let generation = generations.advanceTerminalGeneration(for: terminalIDString)
        let sequence = eventHub.emit(
            event: "terminal.input.sent",
            requestID: request.requestID,
            resource: .init(type: "terminal", id: terminalIDString, generation: generation),
            payload: AnyEncodable(["text_length": text.count])
        )
        sampleStore.removeTerminal(terminalIDString)
        let writeID = Self.writeID(forSequence: sequence)
        readAfterWriteStore.recordTextWrite(
            terminalID: terminalIDString,
            writeID: writeID,
            sequence: sequence,
            visibleFrameID: readStore.latestFrameID(for: terminalIDString, scope: "visible"),
            screenFrameID: readStore.latestFrameID(for: terminalIDString, scope: "screen")
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

    private func runCommand(from request: ControlHarnessRequest) throws -> ControlTerminalMutationResult {
        guard let commandText = request.commandText, !commandText.isEmpty else {
            throw ControlHarnessCoreError.invalidArgument("Missing command_text payload")
        }
        let terminalID = try parseTerminalID(request.terminalID)
        let terminalIDString = terminalID.uuidString
        let currentGeneration = generations.currentTerminalGeneration(for: terminalIDString)
        try generations.assertExpectedGeneration(
            request.expectedGeneration,
            resourceType: "terminal",
            resourceID: terminalIDString,
            currentGeneration: currentGeneration
        )
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }
        guard appDelegate.controlHarnessRunCommand(commandText, to: terminalID) else {
            throw ControlHarnessCoreError.terminalNotFound(terminalID.uuidString)
        }
        let generation = generations.advanceTerminalGeneration(for: terminalIDString)
        let sequence = eventHub.emit(
            event: "terminal.command.sent",
            requestID: request.requestID,
            resource: .init(type: "terminal", id: terminalIDString, generation: generation),
            payload: AnyEncodable(["command_length": commandText.count])
        )
        sampleStore.removeTerminal(terminalIDString)
        let writeID = Self.writeID(forSequence: sequence)
        readAfterWriteStore.recordCommandWrite(
            terminalID: terminalIDString,
            writeID: writeID,
            sequence: sequence,
            commandText: commandText,
            visibleFrameID: readStore.latestFrameID(for: terminalIDString, scope: "visible"),
            screenFrameID: readStore.latestFrameID(for: terminalIDString, scope: "screen")
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
        guard let surface = surfaceResolver(terminalID) else {
            if appDelegate == nil {
                throw ControlHarnessCoreError.appUnavailable
            }
            throw ControlHarnessCoreError.terminalNotFound(terminalID.uuidString)
        }

        let scope = request.scope ?? "visible"
        let mode = request.mode ?? "snapshot"
        let observedWriteID = request.readAfterWriteID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let forceFreshRead = observedWriteID?.isEmpty == false
            || mode == "delta"
            || request.sinceFrameID != nil
        let read = try resolveTerminalRead(
            terminalUUID: terminalID,
            terminalID: terminalIDString,
            scope: scope,
            surface: surface,
            forceFresh: forceFreshRead
        )
        let content = read.content
        let consistency = read.consistency
        let cacheAgeMs = read.cacheAgeMs

        switch scope {
        case "visible", "screen":
            break
        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported read scope: \(scope)")
        }

        switch mode {
        case "snapshot", "delta":
            break
        default:
            throw ControlHarnessCoreError.invalidArgument("Unsupported read mode: \(mode)")
        }

        let frame = readStore.capture(terminalID: terminalIDString, scope: scope, content: content)
        let delta = readStore.delta(from: request.sinceFrameID, to: frame.frameID)
        let window = readStore.window(
            frameID: frame.frameID,
            cursor: request.cursor,
            maxLines: request.maxLines,
            maxChars: request.maxChars
        )
        let changedRows = mode == "delta"
            ? delta.changedRows
            : Self.applyChangedRowBudget(delta.changedRows, maxLines: request.maxLines)

        let responseContent: String
        let contentKind: String
        switch mode {
        case "snapshot":
            responseContent = window.text
            contentKind = "snapshot"
        case "delta":
            responseContent = Self.applyTextBudget(
                delta.text,
                maxChars: request.maxChars
            )
            contentKind = "delta"
        default:
            responseContent = window.text
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
                frame: frame,
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
            consistency: consistency,
            capturedAt: Self.iso8601(read.capturedAt),
            cacheAgeMs: cacheAgeMs,
            lastSequence: eventHub.currentSequence(),
            frameID: frame.frameID,
            parentFrameID: frame.parentFrameID,
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
            content: responseContent
        )
    }

    private func closeTerminal(from request: ControlHarnessRequest) throws -> ControlTerminalMutationResult {
        let terminalID = try parseTerminalID(request.terminalID)
        let terminalIDString = terminalID.uuidString
        let currentGeneration = generations.currentTerminalGeneration(for: terminalIDString)
        try generations.assertExpectedGeneration(
            request.expectedGeneration,
            resourceType: "terminal",
            resourceID: terminalIDString,
            currentGeneration: currentGeneration
        )
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }
        guard appDelegate.controlHarnessCloseTerminal(terminalID) else {
            throw ControlHarnessCoreError.terminalNotFound(terminalID.uuidString)
        }
        sampleStore.removeTerminal(terminalIDString)
        readStore.removeTerminal(terminalIDString)
        readAfterWriteStore.removeTerminal(terminalIDString)
        let generation = generations.advanceTerminalGeneration(for: terminalIDString)
        let sequence = eventHub.emit(
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

    private func resolveTerminalRead(
        terminalUUID: UUID,
        terminalID: String,
        scope: String,
        surface: any ControlHarnessReadableSurface,
        forceFresh: Bool
    ) throws -> (content: String, consistency: String, cacheAgeMs: Int, capturedAt: Date) {
        let currentTime = now()
        let activityClass = samplingActivityResolver(terminalUUID)
            ?? sampleStore.sample(for: terminalID, scope: scope)?.activityClass
            ?? .observed

        if !forceFresh,
           let sample = sampleStore.sample(for: terminalID, scope: scope),
           sampleStore.isFresh(sample, activityClass: activityClass, now: currentTime) {
            return (
                content: sample.content,
                consistency: sample.consistency,
                cacheAgeMs: sample.cacheAgeMs,
                capturedAt: sample.capturedAt
            )
        }

        let shouldForceRefresh = shouldForceFreshRead(
            requested: forceFresh,
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
        return (
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
        guard footprintBytes >= Self.readMemoryPressureFootprintThresholdBytes else {
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
                "threshold_bytes": "\(Self.readMemoryPressureFootprintThresholdBytes)",
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

    private func makeEventSubscription(
        _ request: ControlHarnessRequest,
        socketPath: String
    ) throws -> (result: ControlEventSubscriptionResult, session: ControlHarnessEventSubscriptionSession?) {
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

    private func makeEventSubscriptionResult(
        _ request: ControlHarnessRequest,
        replayedEventCount: Int,
        liveStreamOpen: Bool
    ) -> ControlEventSubscriptionResult {
        .init(
            protocolVersion: Self.protocolVersion,
            subscribed: true,
            lastSequence: eventHub.currentSequence(),
            sinceSequence: request.sinceSequence,
            eventLimit: request.eventLimit,
            replayedEventCount: replayedEventCount,
            liveStreamOpen: liveStreamOpen
        )
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

    private func todoStore() throws -> AITerminalManagerStore {
        guard let appDelegate else {
            throw ControlHarnessCoreError.appUnavailable
        }
        return appDelegate.aiTerminalManagerStore
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

    private func shellSingleQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    nonisolated static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
        case .internalFailure:
            return "An internal control harness failure occurred"
        }
    }
}
