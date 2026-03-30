import Darwin
import Foundation
import CryptoKit
import Testing
@testable import GhoDex

private struct ControlHarnessSubscriptionAckEnvelope: Decodable {
    let requestID: String
    let status: String
    let result: ControlHarnessSubscriptionAckResult?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case result
    }
}

private struct ControlHarnessSubscriptionAckResult: Decodable {
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

private struct ControlHarnessDecodedEventRecord: Decodable {
    let eventID: String
    let sequence: Int64
    let event: String
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case sequence
        case event
        case requestID = "request_id"
    }
}

private struct ControlHarnessHandshakeEnvelope: Decodable {
    let requestID: String
    let status: String
    let result: ControlHarnessHandshakePayload?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case result
    }
}

private struct ControlHarnessHandshakePayload: Decodable {
    let protocolVersion: String
    let lastSequence: Int64

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case lastSequence = "last_sequence"
    }
}

private struct ControlHarnessGatewayStatusEnvelope: Decodable {
    let streamKind: String
    let event: String
    let gap: Bool
    let requiresSnapshotResync: Bool
    let droppedEvents: Int

    enum CodingKeys: String, CodingKey {
        case streamKind = "stream_kind"
        case event
        case gap
        case requiresSnapshotResync = "requires_snapshot_resync"
        case droppedEvents = "dropped_events"
    }
}

private struct ControlHarnessResponseEnvelope: Decodable {
    let requestID: String
    let status: String
    let errorCode: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

private struct ControlHarnessResponseResultEnvelope<Result: Decodable>: Decodable {
    let requestID: String
    let status: String
    let result: Result?
    let errorCode: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case result
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

private struct ControlHarnessPairingBeginPayload: Decodable {
    let pairingCode: String
    let client: String
    let scopes: [String]

    enum CodingKeys: String, CodingKey {
        case pairingCode = "pairing_code"
        case client
        case scopes
    }
}

private struct ControlHarnessTokenIssuePayload: Decodable {
    let token: String
    let tokenID: String
    let client: String
    let scopes: [String]
    let desktopID: String
    let desktopLabel: String
    let preferredDesktopID: String
    let transportMode: String
    let publicEndpoint: String?
    let transportSharedSecret: String?

    enum CodingKeys: String, CodingKey {
        case token
        case tokenID = "token_id"
        case client
        case scopes
        case desktopID = "desktop_id"
        case desktopLabel = "desktop_label"
        case preferredDesktopID = "preferred_desktop_id"
        case transportMode = "transport_mode"
        case publicEndpoint = "public_endpoint"
        case transportSharedSecret = "transport_shared_secret"
    }
}

private struct ControlHarnessTokenStatusPayload: Decodable {
    let tokenID: String
    let client: String
    let scopes: [String]
    let revokedAt: String?
    let desktopID: String
    let desktopLabel: String
    let preferredDesktopID: String
    let transportMode: String

    enum CodingKeys: String, CodingKey {
        case tokenID = "token_id"
        case client
        case scopes
        case revokedAt = "revoked_at"
        case desktopID = "desktop_id"
        case desktopLabel = "desktop_label"
        case preferredDesktopID = "preferred_desktop_id"
        case transportMode = "transport_mode"
    }
}

private struct ControlHarnessSecureEnvelopePayload: Codable, Equatable {
    let requestID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
    }
}

private struct ControlHarnessDeviceRegistryPayload: Decodable, Equatable {
    let deviceID: String
    let displayLabel: String
    let trustState: String
    let lastSeenAt: String?
    let currentConnectionState: String
    let transportMode: String
    let capabilityFlags: [String]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case displayLabel = "display_label"
        case trustState = "trust_state"
        case lastSeenAt = "last_seen_at"
        case currentConnectionState = "current_connection_state"
        case transportMode = "transport_mode"
        case capabilityFlags = "capability_flags"
    }
}

private struct ControlHarnessDeviceRegistryListPayload: Decodable {
    let devices: [ControlHarnessDeviceRegistryPayload]
}

private enum ControlHarnessSocketSupport {
    static func connect(to path: String) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        do {
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
            guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            guard setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(path.utf8)
            guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
                throw POSIXError(.ENAMETOOLONG)
            }
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                buffer.initializeMemory(as: UInt8.self, repeating: 0)
                pathBytes.withUnsafeBytes { bytes in
                    buffer.copyBytes(from: bytes)
                }
            }

            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(fd, baseAddress.advanced(by: offset), rawBuffer.count - offset)
                if written >= 0 {
                    offset += written
                    continue
                }
                if errno == EINTR {
                    continue
                }
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
    }

    static func readLine(
        from fd: Int32,
        timeoutSeconds: TimeInterval = 2.0
    ) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            let amount = Darwin.recv(fd, &byte, 1, MSG_DONTWAIT)
            if amount == 1 {
                data.append(byte)
                if byte == 0x0A {
                    return data
                }
                continue
            }
            if amount == 0 {
                return data
            }
            switch errno {
            case EINTR:
                continue
            case EAGAIN, EWOULDBLOCK:
                usleep(10_000)
                continue
            default:
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }

        throw POSIXError(.ETIMEDOUT)
    }

    static func readAll(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let amount = Darwin.read(fd, &buffer, buffer.count)
            if amount > 0 {
                data.append(buffer, count: amount)
                continue
            }
            if amount == 0 {
                return data
            }
            if errno == EINTR {
                continue
            }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    static func waitForDisconnect(
        from fd: Int32,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var probe: UInt8 = 0

        while Date() < deadline {
            let count = Darwin.recv(fd, &probe, 1, MSG_PEEK | MSG_DONTWAIT)
            if count == 0 {
                return true
            }
            if count > 0 {
                return false
            }

            switch errno {
            case EAGAIN, EWOULDBLOCK:
                usleep(20_000)
                continue
            case EINTR:
                continue
            default:
                return true
            }
        }

        return false
    }

    static func connectTCP(host: String, port: UInt16) throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        do {
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
            guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            guard setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            let parseResult = withUnsafeMutablePointer(to: &address.sin_addr) {
                inet_pton(AF_INET, host, UnsafeMutableRawPointer($0).assumingMemoryBound(to: Int8.self))
            }
            guard parseResult == 1 else {
                throw POSIXError(.EADDRNOTAVAIL)
            }

            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    static func readHTTPHeaders(from fd: Int32) throws -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        let terminator = Data("\r\n\r\n".utf8)

        while data.range(of: terminator) == nil {
            let amount = Darwin.read(fd, &buffer, buffer.count)
            if amount > 0 {
                data.append(buffer, count: amount)
                continue
            }
            if amount == 0 {
                break
            }
            if errno == EINTR {
                continue
            }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        guard let headers = String(data: data, encoding: .utf8) else {
            throw POSIXError(.EIO)
        }
        return headers
    }

    static func performWebSocketHandshake(
        host: String,
        port: UInt16
    ) throws -> Int32 {
        let fd = try connectTCP(host: host, port: port)

        do {
            let key = Data("test-websocket-key".utf8).base64EncodedString()
            let request = Data(
                (
                    "GET /control-harness HTTP/1.1\r\n" +
                    "Host: \(host):\(port)\r\n" +
                    "Upgrade: websocket\r\n" +
                    "Connection: Upgrade\r\n" +
                    "Sec-WebSocket-Key: \(key)\r\n" +
                    "Sec-WebSocket-Version: 13\r\n" +
                    "\r\n"
                ).utf8
            )
            try writeAll(request, to: fd)
            let response = try readHTTPHeaders(from: fd)
            guard response.contains("101 Switching Protocols") else {
                throw POSIXError(.EPROTO)
            }
            let expectedAccept = Data(
                Insecure.SHA1.hash(
                    data: Data("\(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11".utf8)
                )
            ).base64EncodedString()
            guard response.contains("Sec-WebSocket-Accept: \(expectedAccept)") else {
                throw POSIXError(.EPROTO)
            }
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    static func writeWebSocketTextFrame(_ payload: Data, to fd: Int32) throws {
        var frame = Data()
        frame.append(0x81)

        let payloadLength = payload.count
        if payloadLength <= 125 {
            frame.append(UInt8(payloadLength | 0x80))
        } else if payloadLength <= 65_535 {
            frame.append(126 | 0x80)
            frame.append(UInt8((payloadLength >> 8) & 0xFF))
            frame.append(UInt8(payloadLength & 0xFF))
        } else {
            frame.append(127 | 0x80)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((UInt64(payloadLength) >> UInt64(shift)) & 0xFF))
            }
        }

        let mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        frame.append(contentsOf: mask)
        for (index, byte) in payload.enumerated() {
            frame.append(byte ^ mask[index % 4])
        }

        try writeAll(frame, to: fd)
    }

    static func readWebSocketTextFrame(from fd: Int32) throws -> Data {
        let header = try readExactly(2, from: fd)
        let opcode = header[0] & 0x0F
        guard opcode == 0x1 else {
            throw POSIXError(.EPROTO)
        }

        var payloadLength = Int(header[1] & 0x7F)
        if payloadLength == 126 {
            let extended = try readExactly(2, from: fd)
            payloadLength = Int(UInt16(extended[0]) << 8 | UInt16(extended[1]))
        } else if payloadLength == 127 {
            let extended = try readExactly(8, from: fd)
            payloadLength = extended.reduce(0) { (partial, byte) in
                (partial << 8) | Int(byte)
            }
        }

        return try readExactly(payloadLength, from: fd)
    }

    static func readExactly(_ count: Int, from fd: Int32) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < count {
                let amount = Darwin.read(fd, baseAddress.advanced(by: offset), count - offset)
                if amount > 0 {
                    offset += amount
                    continue
                }
                if amount == 0 {
                    throw POSIXError(.EIO)
                }
                if errno == EINTR {
                    continue
                }
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
        return data
    }
}

struct ControlHarnessTests {
    @Test func gatewayConfigurationDefaultsToDisabledLoopback() {
        let configuration = ControlHarnessGateway.Configuration.environment([:])

        #expect(configuration.isEnabled == false)
        #expect(configuration.listenHost == "127.0.0.1")
        #expect(configuration.listenPort == 0)
        #expect(configuration.maxBufferedEvents == 256)
        #expect(configuration.maxBufferedBytes == 1_048_576)
        #expect(configuration.authToken == nil)
        #expect(configuration.maxConcurrentSessionsPerIdentity == 2)
        #expect(configuration.maxGlobalRequestsPerMinute == 240)
        #expect(configuration.maxCommandsPerMinute == 60)
        #expect(configuration.maxSnapshotRequestsPerMinute == 30)
        #expect(configuration.maxResyncAttemptsPerMinute == 30)
    }

    @Test func gatewayConfigurationParsesEnvironmentOverrides() {
        let configuration = ControlHarnessGateway.Configuration.environment([
            "GHODEX_CONTROL_HARNESS_GATEWAY_ENABLED": "true",
            "GHODEX_CONTROL_HARNESS_GATEWAY_HOST": " 0.0.0.0 ",
            "GHODEX_CONTROL_HARNESS_GATEWAY_PORT": "4040",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_BUFFERED_EVENTS": "64",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_BUFFERED_BYTES": "8192",
            "GHODEX_CONTROL_HARNESS_GATEWAY_AUTH_TOKEN": "test-secret",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_CONCURRENT_SESSIONS_PER_IDENTITY": "3",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_GLOBAL_REQUESTS_PER_MINUTE": "120",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_COMMANDS_PER_MINUTE": "40",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_SNAPSHOT_REQUESTS_PER_MINUTE": "20",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_RESYNC_ATTEMPTS_PER_MINUTE": "10",
        ])

        #expect(configuration.isEnabled == true)
        #expect(configuration.listenHost == "0.0.0.0")
        #expect(configuration.listenPort == 4040)
        #expect(configuration.maxBufferedEvents == 64)
        #expect(configuration.maxBufferedBytes == 8192)
        #expect(configuration.authToken == "test-secret")
        #expect(configuration.maxConcurrentSessionsPerIdentity == 3)
        #expect(configuration.maxGlobalRequestsPerMinute == 120)
        #expect(configuration.maxCommandsPerMinute == 40)
        #expect(configuration.maxSnapshotRequestsPerMinute == 20)
        #expect(configuration.maxResyncAttemptsPerMinute == 10)
    }

    @Test func gatewayConfigurationClampsOrIgnoresInvalidEnvironmentOverrides() {
        let configuration = ControlHarnessGateway.Configuration.environment([
            "GHODEX_CONTROL_HARNESS_GATEWAY_ENABLED": "maybe",
            "GHODEX_CONTROL_HARNESS_GATEWAY_HOST": "   ",
            "GHODEX_CONTROL_HARNESS_GATEWAY_PORT": "70000",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_BUFFERED_EVENTS": "0",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_BUFFERED_BYTES": "-1",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_CONCURRENT_SESSIONS_PER_IDENTITY": "0",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_GLOBAL_REQUESTS_PER_MINUTE": "0",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_COMMANDS_PER_MINUTE": "-1",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_SNAPSHOT_REQUESTS_PER_MINUTE": "0",
            "GHODEX_CONTROL_HARNESS_GATEWAY_MAX_RESYNC_ATTEMPTS_PER_MINUTE": "-1",
        ])

        #expect(configuration.isEnabled == false)
        #expect(configuration.listenHost == "127.0.0.1")
        #expect(configuration.listenPort == 0)
        #expect(configuration.maxBufferedEvents == 1)
        #expect(configuration.maxBufferedBytes == 1)
        #expect(configuration.maxConcurrentSessionsPerIdentity == 1)
        #expect(configuration.maxGlobalRequestsPerMinute == 1)
        #expect(configuration.maxCommandsPerMinute == 1)
        #expect(configuration.maxSnapshotRequestsPerMinute == 1)
        #expect(configuration.maxResyncAttemptsPerMinute == 1)
    }

    @MainActor
    private final class RecordingReadableSurface: ControlHarnessReadableSurface {
        let id: UUID
        var visibleReads: [(refresh: Bool, content: String, cacheAgeMs: Int)] = []
        var screenReads: [(refresh: Bool, content: String, cacheAgeMs: Int)] = []

        init(id: UUID = UUID()) {
            self.id = id
        }

        func controlHarnessReadVisibleText(refresh: Bool) -> (content: String, cacheAgeMs: Int) {
            if let index = visibleReads.firstIndex(where: { $0.refresh == refresh }) {
                let read = visibleReads.remove(at: index)
                return (read.content, read.cacheAgeMs)
            }

            if let read = visibleReads.first {
                return (read.content, read.cacheAgeMs)
            }

            return ("", 0)
        }

        func controlHarnessReadScreenText(refresh: Bool) -> (content: String, cacheAgeMs: Int) {
            if let index = screenReads.firstIndex(where: { $0.refresh == refresh }) {
                let read = screenReads.remove(at: index)
                return (read.content, read.cacheAgeMs)
            }

            if let read = screenReads.first {
                return (read.content, read.cacheAgeMs)
            }

            return ("", 0)
        }
    }

    private final class CounterBox: @unchecked Sendable {
        private let queue = DispatchQueue(label: "ControlHarnessTests.CounterBox")
        private var storage = 0

        func increment() {
            queue.sync {
                storage += 1
            }
        }

        func value() -> Int {
            queue.sync { storage }
        }
    }

    private final class MutableClock: @unchecked Sendable {
        private let queue = DispatchQueue(label: "ControlHarnessTests.MutableClock")
        private var currentDate: Date

        init(_ currentDate: Date) {
            self.currentDate = currentDate
        }

        func now() -> Date {
            queue.sync { currentDate }
        }

        func advance(by interval: TimeInterval) {
            queue.sync {
                currentDate = currentDate.addingTimeInterval(interval)
            }
        }
    }

    @MainActor
    private final class RecordingAppDelegate: AppDelegate {
        var unavailableTerminals: Set<UUID> = []
        var managedStates: [UUID: AITerminalManagedState] = [:]
        var sentInputs: [(terminalID: UUID, text: String)] = []
        var executedCommands: [(terminalID: UUID, command: String)] = []
        var closedTerminals: [UUID] = []
        var readableSurfaces: [UUID: any ControlHarnessReadableSurface] = [:]

        @MainActor
        override func controlHarnessReadableSurface(for terminalID: UUID) -> (any ControlHarnessReadableSurface)? {
            readableSurfaces[terminalID] ?? super.controlHarnessReadableSurface(for: terminalID)
        }

        @MainActor
        override func controlHarnessManagedState(for terminalID: UUID) -> AITerminalManagedState? {
            managedStates[terminalID] ?? super.controlHarnessManagedState(for: terminalID)
        }

        override func controlHarnessSendText(_ text: String, to terminalID: UUID) -> Bool {
            guard !unavailableTerminals.contains(terminalID) else {
                return false
            }

            sentInputs.append((terminalID, text))
            return true
        }

        override func controlHarnessRunCommand(_ command: String, to terminalID: UUID) -> Bool {
            guard !unavailableTerminals.contains(terminalID) else {
                return false
            }

            executedCommands.append((terminalID, command))
            return true
        }

        override func controlHarnessCloseTerminal(_ terminalID: UUID) -> Bool {
            guard !unavailableTerminals.contains(terminalID) else {
                return false
            }

            closedTerminals.append(terminalID)
            return true
        }
    }

    @MainActor
    private func makeFreshEventHub(bundleID: String) -> ControlHarnessEventHub {
        let eventsFileURL = ControlHarnessAuditLogger.baseDirectory(bundleID: bundleID)
            .appendingPathComponent("control-harness-events.jsonl", isDirectory: false)
        try? FileManager.default.removeItem(at: eventsFileURL)
        return ControlHarnessEventHub(bundleID: bundleID)
    }

    @MainActor
    private func makeCore(
        delegate: AppDelegate? = nil,
        bundleID: String = "ghdx.tests.control-harness",
        readStore: ControlHarnessTerminalReadStore? = nil,
        readAfterWriteStore: ControlHarnessReadAfterWriteStore? = nil,
        sampleStore: ControlHarnessSampleStore? = nil,
        surfaceResolver: (@MainActor (UUID) -> (any ControlHarnessReadableSurface)?)? = nil,
        samplingActivityResolver: (@MainActor (UUID) -> ControlHarnessSamplingActivityClass?)? = nil,
        now: @escaping @MainActor () -> Date = Date.init
    ) -> (
        core: ControlHarnessCore,
        eventHub: ControlHarnessEventHub,
        generations: ControlHarnessGenerationTracker
    ) {
        let eventHub = makeFreshEventHub(bundleID: bundleID)
        let generations = ControlHarnessGenerationTracker()
        let resolvedSampleStore = sampleStore ?? ControlHarnessSampleStore()
        let resolvedReadStore = readStore ?? ControlHarnessTerminalReadStore()
        let resolvedReadAfterWriteStore = readAfterWriteStore ?? ControlHarnessReadAfterWriteStore()
        let core = ControlHarnessCore(
            appDelegate: delegate,
            auditLogger: ControlHarnessAuditLogger(bundleID: bundleID),
            eventHub: eventHub,
            generations: generations,
            idempotencyStore: ControlHarnessIdempotencyStore(),
            readStore: resolvedReadStore,
            readAfterWriteStore: resolvedReadAfterWriteStore,
            sampleStore: resolvedSampleStore,
            surfaceResolver: surfaceResolver,
            samplingActivityResolver: samplingActivityResolver,
            now: now
        )
        return (core, eventHub, generations)
    }

    @Test func authExpiresPairingCodesAndPersistsIssuedTokens() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = tempDirectory.appendingPathComponent("auth.json", isDirectory: false)
        let clock = MutableClock(Date(timeIntervalSince1970: 1_710_000_000))
        let auth = ControlHarnessAuth(
            storageURL: storageURL,
            configuration: .init(pairingCodeTTLSeconds: 5, tokenTTLSeconds: 60),
            now: { clock.now() }
        )

        let pairing = try await auth.beginPairing(
            client: "android-persist",
            requestedScopes: ["mutate"]
        )
        let issued = try await auth.exchangePairingCode(pairing.pairingCode)

        let restored = ControlHarnessAuth(
            storageURL: storageURL,
            configuration: .init(pairingCodeTTLSeconds: 5, tokenTTLSeconds: 60),
            now: { clock.now() }
        )
        switch await restored.validate(token: issued.token, requiredScope: .mutate) {
        case .allow(let grant):
            #expect(grant.client == "android-persist")
            #expect(grant.scopes.contains(.observe))
            #expect(grant.scopes.contains(.mutate))
        case .deny(let errorCode, let errorMessage):
            Issue.record("persisted token should validate: \(errorCode) \(errorMessage)")
        }

        let expiringPairing = try await auth.beginPairing(
            client: "android-expire",
            requestedScopes: ["observe"]
        )
        clock.advance(by: 6)
        do {
            _ = try await auth.exchangePairingCode(expiringPairing.pairingCode)
            Issue.record("expired pairing code should not exchange")
        } catch {
            #expect(error.localizedDescription.contains("expired"))
        }
    }

    @Test func authPairingExchangeReturnsStableDesktopIdentity() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = tempDirectory.appendingPathComponent("auth.json", isDirectory: false)
        let auth = ControlHarnessAuth(
            storageURL: storageURL,
            configuration: .init(pairingCodeTTLSeconds: 5, tokenTTLSeconds: 60)
        )

        let pairing = try await auth.beginPairing(
            client: "android-identity",
            requestedScopes: ["observe"]
        )
        let issued = try await auth.exchangePairingCode(pairing.pairingCode)
        let status = try await auth.tokenStatus(for: issued.token)

        #expect(issued.desktopID.isEmpty == false)
        #expect(issued.desktopLabel.isEmpty == false)
        #expect(issued.preferredDesktopID == issued.desktopID)
        #expect(issued.transportMode == "lan")

        #expect(status.desktopID == issued.desktopID)
        #expect(status.desktopLabel == issued.desktopLabel)
        #expect(status.preferredDesktopID == issued.preferredDesktopID)
        #expect(status.transportMode == issued.transportMode)
    }

    @Test func authRestoresDesktopIdentityAcrossReload() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = tempDirectory.appendingPathComponent("auth.json", isDirectory: false)
        let clock = MutableClock(Date(timeIntervalSince1970: 1_710_000_000))
        let auth = ControlHarnessAuth(
            storageURL: storageURL,
            configuration: .init(pairingCodeTTLSeconds: 5, tokenTTLSeconds: 60),
            now: { clock.now() }
        )

        let pairing = try await auth.beginPairing(
            client: "android-reload",
            requestedScopes: ["mutate"]
        )
        let issued = try await auth.exchangePairingCode(pairing.pairingCode)

        let restored = ControlHarnessAuth(
            storageURL: storageURL,
            configuration: .init(pairingCodeTTLSeconds: 5, tokenTTLSeconds: 60),
            now: { clock.now() }
        )
        let restoredStatus = try await restored.tokenStatus(for: issued.token)

        #expect(restoredStatus.desktopID == issued.desktopID)
        #expect(restoredStatus.desktopLabel == issued.desktopLabel)
        #expect(restoredStatus.preferredDesktopID == issued.preferredDesktopID)
        #expect(restoredStatus.transportMode == "lan")
    }

    @Test func gatewaySecureChannelRoundTripsEncryptedRequest() throws {
        let request = ControlHarnessRequest(
            requestID: "public-req-1",
            protocolVersion: nil,
            authToken: "token-1",
            command: "snapshot",
            date: nil,
            tabID: nil,
            parentTabID: nil,
            terminalID: nil,
            todoID: nil,
            scope: nil,
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            notes: nil,
            environment: nil,
            force: nil,
            completed: nil,
            workspaceID: nil,
            includeCompleted: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil,
            pairingCode: nil,
            requestedScopes: nil
        )
        let sharedSecret = try ControlHarnessGatewaySecureChannel.makeTransportSharedSecret()

        let encrypted = try ControlHarnessGatewaySecureChannel.encryptRequest(
            request,
            authToken: "token-1",
            transportSharedSecret: sharedSecret
        )

        #expect(encrypted.command == "gateway.encrypted")
        #expect(encrypted.transportMode == "relay")
        #expect(encrypted.authToken == "token-1")
        #expect(encrypted.encryptedPayload.contains("snapshot") == false)

        let decoded = try ControlHarnessGatewaySecureChannel.decryptRequest(
            encrypted,
            transportSharedSecret: sharedSecret
        )

        #expect(decoded.requestID == request.requestID)
        #expect(decoded.command == request.command)
        #expect(decoded.authToken == request.authToken)
    }

    @Test func gatewaySecureChannelRoundTripsEncryptedEnvelope() throws {
        let payload = ControlHarnessSecureEnvelopePayload(
            requestID: "public-res-1",
            status: "ok"
        )
        let sharedSecret = try ControlHarnessGatewaySecureChannel.makeTransportSharedSecret()

        let encrypted = try ControlHarnessGatewaySecureChannel.encryptEnvelope(
            payload,
            transportSharedSecret: sharedSecret
        )

        #expect(encrypted.transportMode == "relay")
        #expect(encrypted.encryptedPayload.contains("public-res-1") == false)

        let decoded = try ControlHarnessGatewaySecureChannel.decryptEnvelope(
            encrypted,
            transportSharedSecret: sharedSecret,
            as: ControlHarnessSecureEnvelopePayload.self
        )

        #expect(decoded == payload)
    }

    @Test func tabCloseConfirmationUsesTabCopyWhenMultipleTabsRemain() {
        let confirmation = ControlTabCloseConfirmation.resolve(
            hasMultipleTabs: true,
            needsConfirmQuit: true
        )

        #expect(confirmation?.title == "Close Tab?")
        #expect(confirmation?.message == "The terminal still has a running process. If you close the tab the process will be killed.")
    }

    @Test func tabCloseConfirmationUsesWindowCopyWhenLastTabWouldCloseWindow() {
        let confirmation = ControlTabCloseConfirmation.resolve(
            hasMultipleTabs: false,
            needsConfirmQuit: true
        )

        #expect(confirmation?.title == "Close Window?")
        #expect(confirmation?.message == "All terminal sessions in this window will be terminated.")
    }

    @Test func tabCloseConfirmationSkipsPromptWhenNoRunningProcessNeedsQuitConfirmation() {
        let confirmation = ControlTabCloseConfirmation.resolve(
            hasMultipleTabs: true,
            needsConfirmQuit: false
        )

        #expect(confirmation == nil)
    }

    private func responseJSON(_ response: ControlHarnessResponse) throws -> [String: Any] {
        let data = try JSONEncoder().encode(response)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeAcceptanceArtifact(_ filename: String, data: Data) throws {
        let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: .atomic)
    }

    private func requestGatewayMetrics(port: UInt16, requestID: String) throws -> (
        data: Data,
        snapshot: ControlHarnessPerformanceSnapshot
    ) {
        let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
        defer { Darwin.close(clientFD) }

        let payload = #"{"request_id":"\#(requestID)","command":"gateway.metrics"}"#
        try ControlHarnessSocketSupport.writeAll(Data(payload.utf8), to: clientFD)
        guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let data = try ControlHarnessSocketSupport.readAll(from: clientFD)
        let envelope = try JSONDecoder().decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessPerformanceSnapshot>.self,
            from: data
        )
        let snapshot = try #require(envelope.result)
        return (data, snapshot)
    }

    @Test @MainActor func runCommandUsesDedicatedExecutionPath() {
        let delegate = RecordingAppDelegate()
        let bundleID = "ghdx.tests.run-command"
        let (core, _, _) = makeCore(delegate: delegate, bundleID: bundleID)
        let terminalID = UUID()
        let request = ControlHarnessRequest(
            requestID: "req-run-command",
            protocolVersion: nil,
            command: "run-command",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: nil,
            text: nil,
            commandText: "printf '__COLD_START__\\n'",
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")

        #expect(response.status == "ok")
        #expect(delegate.executedCommands.count == 1)
        #expect(delegate.executedCommands[0].terminalID == terminalID)
        #expect(delegate.executedCommands[0].command == "printf '__COLD_START__\\n'")
    }

    @Test @MainActor func sendTextRejectsMissingTerminalWithoutEmittingEvents() {
        let delegate = RecordingAppDelegate()
        let terminalID = UUID()
        delegate.unavailableTerminals = [terminalID]
        let (core, eventHub, generations) = makeCore(delegate: delegate, bundleID: "ghdx.tests.send-text-missing")
        let request = ControlHarnessRequest(
            requestID: "req-send-text-missing",
            protocolVersion: nil,
            command: "send-text",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: nil,
            text: "echo fail",
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")

        #expect(response.status == "error")
        #expect(response.errorCode == "terminal_not_found")
        #expect(response.errorMessage?.contains(terminalID.uuidString) == true)
        #expect(delegate.sentInputs.isEmpty)
        #expect(eventHub.currentSequence() == 0)
        #expect(generations.currentTerminalGeneration(for: terminalID.uuidString) == 1)
    }

    @Test @MainActor func runCommandRejectsNewlineOnlyPayloadWithoutEmittingEvents() {
        let delegate = RecordingAppDelegate()
        let terminalID = UUID()
        let (core, eventHub, generations) = makeCore(delegate: delegate, bundleID: "ghdx.tests.run-command-newline")
        let request = ControlHarnessRequest(
            requestID: "req-run-command-newline",
            protocolVersion: nil,
            command: "run-command",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: nil,
            text: nil,
            commandText: "\n\r\n",
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")

        #expect(response.status == "error")
        #expect(response.errorCode == "invalid_argument")
        #expect(response.errorMessage == "command_text must contain at least one non-newline character")
        #expect(delegate.executedCommands.isEmpty)
        #expect(eventHub.currentSequence() == 0)
        #expect(generations.currentTerminalGeneration(for: terminalID.uuidString) == 1)
    }

    @Test @MainActor func closeTerminalRejectsMissingTerminalWithoutEmittingEvents() {
        let delegate = RecordingAppDelegate()
        let terminalID = UUID()
        delegate.unavailableTerminals = [terminalID]
        let (core, eventHub, generations) = makeCore(delegate: delegate, bundleID: "ghdx.tests.close-terminal-missing")
        let request = ControlHarnessRequest(
            requestID: "req-close-terminal-missing",
            protocolVersion: nil,
            command: "close-terminal",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: nil,
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")

        #expect(response.status == "error")
        #expect(response.errorCode == "terminal_not_found")
        #expect(response.errorMessage?.contains(terminalID.uuidString) == true)
        #expect(delegate.closedTerminals.isEmpty)
        #expect(eventHub.currentSequence() == 0)
        #expect(generations.currentTerminalGeneration(for: terminalID.uuidString) == 1)
    }

    @Test @MainActor func closeTerminalClearsReadRetentionState() {
        let delegate = RecordingAppDelegate()
        let terminalID = UUID()
        let readStore = ControlHarnessTerminalReadStore()
        let readAfterWriteStore = ControlHarnessReadAfterWriteStore()
        let sampleStore = ControlHarnessSampleStore()

        _ = readStore.capture(
            terminalID: terminalID.uuidString,
            scope: "visible",
            content: "before close"
        )
        sampleStore.store(
            terminalID: terminalID.uuidString,
            scope: "visible",
            content: "sample",
            consistency: "fresh_visible",
            cacheAgeMs: 0,
            capturedAt: Date(),
            activityClass: .observed,
            forcedFresh: true
        )
        readAfterWriteStore.recordCommandWrite(
            terminalID: terminalID.uuidString,
            writeID: "write-close",
            sequence: 7,
            commandText: "echo close",
            visibleFrameID: nil,
            screenFrameID: nil
        )

        let (core, eventHub, generations) = makeCore(
            delegate: delegate,
            bundleID: "ghdx.tests.close-terminal-cleanup",
            readStore: readStore,
            readAfterWriteStore: readAfterWriteStore,
            sampleStore: sampleStore
        )
        let request = ControlHarnessRequest(
            requestID: "req-close-terminal-cleanup",
            protocolVersion: nil,
            command: "close-terminal",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: nil,
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")

        #expect(response.status == "ok")
        #expect(delegate.closedTerminals == [terminalID])
        #expect(readStore.debugSnapshot().totalFrameCount == 0)
        #expect(readAfterWriteStore.debugEntryCount() == 0)
        #expect(sampleStore.sample(for: terminalID.uuidString, scope: "visible") == nil)
        #expect(eventHub.currentSequence() == 1)
        #expect(generations.currentTerminalGeneration(for: terminalID.uuidString) == 2)
    }

    @Test @MainActor func readTerminalRejectsInvalidCursorBeforeTouchingTheApp() {
        let terminalID = UUID()
        let (core, eventHub, generations) = makeCore(bundleID: "ghdx.tests.read-invalid-cursor")
        let request = ControlHarnessRequest(
            requestID: "req-read-invalid-cursor",
            protocolVersion: nil,
            command: "read-terminal",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: nil,
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: "snapshot",
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: "not-a-number",
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")

        #expect(response.status == "error")
        #expect(response.errorCode == "invalid_argument")
        #expect(response.errorMessage == "cursor must be a non-negative integer")
        #expect(eventHub.currentSequence() == 0)
        #expect(generations.currentTerminalGeneration(for: terminalID.uuidString) == 1)
    }

    @Test @MainActor func readTerminalRejectsCursorWithSinceFrameInDeltaMode() {
        let terminalID = UUID()
        let (core, eventHub, generations) = makeCore(bundleID: "ghdx.tests.read-cursor-since")
        let request = ControlHarnessRequest(
            requestID: "req-read-cursor-since",
            protocolVersion: nil,
            command: "read-terminal",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: nil,
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: "delta",
            sinceFrameID: "frm_7",
            maxChars: nil,
            maxLines: nil,
            cursor: "120",
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")

        #expect(response.status == "error")
        #expect(response.errorCode == "invalid_argument")
        #expect(response.errorMessage == "cursor cannot be combined with since_frame_id in delta mode")
        #expect(eventHub.currentSequence() == 0)
        #expect(generations.currentTerminalGeneration(for: terminalID.uuidString) == 1)
    }

    @Test @MainActor func readAfterWriteRequiresDistinctPostEchoFrameAndStaysReady() {
        let readStore = ControlHarnessTerminalReadStore()
        let readinessStore = ControlHarnessReadAfterWriteStore()
        let terminalID = UUID().uuidString
        let writeID = "seq_7"

        let baseline = readStore.capture(
            terminalID: terminalID,
            scope: "visible",
            content: "$ "
        )

        readinessStore.recordCommandWrite(
            terminalID: terminalID,
            writeID: writeID,
            sequence: 7,
            commandText: "printf '__READY__\\n'",
            visibleFrameID: baseline.frameID,
            screenFrameID: nil
        )

        let echoed = readStore.capture(
            terminalID: terminalID,
            scope: "visible",
            content: "$ printf '__READY__\\n'"
        )

        #expect(
            readinessStore.readiness(
                for: writeID,
                terminalID: terminalID,
                scope: "visible",
                currentSequence: 7,
                frame: echoed,
                delta: echoed.delta
            ) == false
        )
        #expect(
            readinessStore.readiness(
                for: writeID,
                terminalID: terminalID,
                scope: "visible",
                currentSequence: 7,
                frame: echoed,
                delta: echoed.delta
            ) == false
        )

        let completed = readStore.capture(
            terminalID: terminalID,
            scope: "visible",
            content: "$ printf '__READY__\\n'\n__READY__\n$ "
        )

        #expect(
            readinessStore.readiness(
                for: writeID,
                terminalID: terminalID,
                scope: "visible",
                currentSequence: 7,
                frame: completed,
                delta: completed.delta
            ) == true
        )
        #expect(
            readinessStore.readiness(
                for: writeID,
                terminalID: terminalID,
                scope: "visible",
                currentSequence: 7,
                frame: completed,
                delta: completed.delta
            ) == true
        )
    }

    @Test @MainActor func readStoreRemoveTerminalClearsRetainedFrames() {
        let readStore = ControlHarnessTerminalReadStore()
        let removedTerminalID = UUID().uuidString
        let keptTerminalID = UUID().uuidString

        let removedVisible = readStore.capture(
            terminalID: removedTerminalID,
            scope: "visible",
            content: "line 1\nline 2"
        )
        _ = readStore.capture(
            terminalID: removedTerminalID,
            scope: "screen",
            content: "screen 1\nscreen 2"
        )
        let keptVisible = readStore.capture(
            terminalID: keptTerminalID,
            scope: "visible",
            content: "kept"
        )

        #expect(readStore.debugSnapshot().totalFrameCount == 3)

        readStore.removeTerminal(removedTerminalID)

        let snapshot = readStore.debugSnapshot()
        #expect(snapshot.keyCount == 1)
        #expect(snapshot.totalFrameCount == 1)
        #expect(readStore.latestFrameID(for: removedTerminalID, scope: "visible") == nil)
        #expect(readStore.latestFrameID(for: removedTerminalID, scope: "screen") == nil)
        #expect(readStore.latestFrameID(for: keptTerminalID, scope: "visible") == keptVisible.frameID)
        #expect(
            readStore.window(
                frameID: removedVisible.frameID,
                cursor: nil,
                maxLines: nil,
                maxChars: nil
            ).text.isEmpty
        )
    }

    @Test @MainActor func readStoreGlobalFrameLimitEvictsOldestFramesAcrossKeys() {
        let readStore = ControlHarnessTerminalReadStore(
            maxFramesPerKey: 32,
            maxTotalFrames: 2,
            maxTotalContentBytes: 1_000_000
        )
        let firstTerminalID = UUID().uuidString
        let secondTerminalID = UUID().uuidString
        let thirdTerminalID = UUID().uuidString

        let firstFrame = readStore.capture(
            terminalID: firstTerminalID,
            scope: "visible",
            content: "first"
        )
        let secondFrame = readStore.capture(
            terminalID: secondTerminalID,
            scope: "visible",
            content: "second"
        )
        let thirdFrame = readStore.capture(
            terminalID: thirdTerminalID,
            scope: "visible",
            content: "third"
        )

        let snapshot = readStore.debugSnapshot()
        #expect(snapshot.totalFrameCount == 2)
        #expect(readStore.latestFrameID(for: firstTerminalID, scope: "visible") == nil)
        #expect(readStore.latestFrameID(for: secondTerminalID, scope: "visible") == secondFrame.frameID)
        #expect(readStore.latestFrameID(for: thirdTerminalID, scope: "visible") == thirdFrame.frameID)
        #expect(
            readStore.window(
                frameID: firstFrame.frameID,
                cursor: nil,
                maxLines: nil,
                maxChars: nil
            ).text.isEmpty
        )
    }

    @Test @MainActor func readStoreGlobalByteLimitPrefersLatestFrameForActiveKey() {
        let readStore = ControlHarnessTerminalReadStore(
            maxFramesPerKey: 32,
            maxTotalFrames: 32,
            maxTotalContentBytes: 8
        )
        let terminalID = UUID().uuidString

        let firstFrame = readStore.capture(
            terminalID: terminalID,
            scope: "visible",
            content: "1234"
        )
        let secondFrame = readStore.capture(
            terminalID: terminalID,
            scope: "visible",
            content: "12345678"
        )

        let snapshot = readStore.debugSnapshot()
        #expect(snapshot.totalFrameCount == 1)
        #expect(snapshot.totalContentBytes == 8)
        #expect(readStore.latestFrameID(for: terminalID, scope: "visible") == secondFrame.frameID)
        #expect(
            readStore.window(
                frameID: firstFrame.frameID,
                cursor: nil,
                maxLines: nil,
                maxChars: nil
            ).text.isEmpty
        )
        #expect(
            readStore.window(
                frameID: secondFrame.frameID,
                cursor: nil,
                maxLines: nil,
                maxChars: nil
            ).text == "12345678"
        )
    }

    @Test @MainActor func readTerminalDeltaPreservesCompleteChangedRowsWhenMaxLinesIsSmall() throws {
        let terminalID = UUID()
        let surface = RecordingReadableSurface(id: terminalID)
        surface.visibleReads = [
            (refresh: true, content: "A\nB\nC\nD", cacheAgeMs: 0),
            (refresh: true, content: "A\nD", cacheAgeMs: 0),
        ]

        let (core, _, _) = makeCore(
            bundleID: "ghdx.tests.read-delta-complete-rows",
            surfaceResolver: { requestedID in
                requestedID == terminalID ? surface : nil
            }
        )

        let baselineResponse = core.handle(
            ControlHarnessRequest(
                requestID: "req-read-delta-baseline",
                protocolVersion: nil,
                command: "read-terminal",
                tabID: nil,
                parentTabID: nil,
                terminalID: terminalID.uuidString,
                scope: "visible",
                text: nil,
                commandText: nil,
                workingDirectory: nil,
                title: nil,
                environment: nil,
                force: nil,
                client: nil,
                idempotencyKey: nil,
                expectedGeneration: nil,
                sinceSequence: nil,
                eventLimit: nil,
                mode: "snapshot",
                sinceFrameID: nil,
                maxChars: nil,
                maxLines: 1,
                cursor: nil,
                readAfterWriteID: nil
            ),
            socketPath: "/tmp/control-harness-test.sock"
        )

        let baselineJSON = try responseJSON(baselineResponse)
        let baselineResult = try #require(baselineJSON["result"] as? [String: Any])
        let baselineFrameID = try #require(baselineResult["frame_id"] as? String)

        let deltaResponse = core.handle(
            ControlHarnessRequest(
                requestID: "req-read-delta-follow-up",
                protocolVersion: nil,
                command: "read-terminal",
                tabID: nil,
                parentTabID: nil,
                terminalID: terminalID.uuidString,
                scope: "visible",
                text: nil,
                commandText: nil,
                workingDirectory: nil,
                title: nil,
                environment: nil,
                force: nil,
                client: nil,
                idempotencyKey: nil,
                expectedGeneration: nil,
                sinceSequence: nil,
                eventLimit: nil,
                mode: "delta",
                sinceFrameID: baselineFrameID,
                maxChars: nil,
                maxLines: 1,
                cursor: nil,
                readAfterWriteID: nil
            ),
            socketPath: "/tmp/control-harness-test.sock"
        )

        let deltaJSON = try responseJSON(deltaResponse)
        let deltaResult = try #require(deltaJSON["result"] as? [String: Any])
        let changedRows = try #require(deltaResult["changed_rows"] as? [[String: Any]])

        #expect(deltaResult["delta_kind"] as? String == "rows")
        #expect(changedRows.count == 3)
        #expect(changedRows.compactMap { $0["kind"] as? String } == ["update", "delete", "delete"])
    }

    @Test @MainActor func readTerminalDeltaFallsBackToResetWhenSinceFrameWasEvicted() throws {
        let terminalID = UUID()
        let surface = RecordingReadableSurface(id: terminalID)
        surface.visibleReads = [
            (refresh: true, content: "A", cacheAgeMs: 0),
            (refresh: true, content: "A\nB", cacheAgeMs: 0),
            (refresh: true, content: "A\nB\nC", cacheAgeMs: 0),
        ]
        let clock = MutableClock(Date(timeIntervalSince1970: 10))
        let readStore = ControlHarnessTerminalReadStore(
            maxFramesPerKey: 1,
            maxTotalFrames: 16,
            maxTotalContentBytes: 1024 * 1024
        )

        let (core, _, _) = makeCore(
            bundleID: "ghdx.tests.read-delta-reset",
            readStore: readStore,
            surfaceResolver: { requestedID in
                requestedID == terminalID ? surface : nil
            },
            now: { clock.now() }
        )

        let firstResponse = core.handle(
            ControlHarnessRequest(
                requestID: "req-read-first",
                protocolVersion: nil,
                command: "read-terminal",
                tabID: nil,
                parentTabID: nil,
                terminalID: terminalID.uuidString,
                scope: "visible",
                text: nil,
                commandText: nil,
                workingDirectory: nil,
                title: nil,
                environment: nil,
                force: nil,
                client: nil,
                idempotencyKey: nil,
                expectedGeneration: nil,
                sinceSequence: nil,
                eventLimit: nil,
                mode: "snapshot",
                sinceFrameID: nil,
                maxChars: nil,
                maxLines: nil,
                cursor: nil,
                readAfterWriteID: nil
            ),
            socketPath: "/tmp/control-harness-test.sock"
        )
        let firstJSON = try responseJSON(firstResponse)
        let firstResult = try #require(firstJSON["result"] as? [String: Any])
        let firstFrameID = try #require(firstResult["frame_id"] as? String)
        clock.advance(by: 1.0)

        _ = core.handle(
            ControlHarnessRequest(
                requestID: "req-read-second",
                protocolVersion: nil,
                command: "read-terminal",
                tabID: nil,
                parentTabID: nil,
                terminalID: terminalID.uuidString,
                scope: "visible",
                text: nil,
                commandText: nil,
                workingDirectory: nil,
                title: nil,
                environment: nil,
                force: nil,
                client: nil,
                idempotencyKey: nil,
                expectedGeneration: nil,
                sinceSequence: nil,
                eventLimit: nil,
                mode: "snapshot",
                sinceFrameID: nil,
                maxChars: nil,
                maxLines: nil,
                cursor: nil,
                readAfterWriteID: nil
            ),
            socketPath: "/tmp/control-harness-test.sock"
        )
        clock.advance(by: 1.0)

        let deltaResponse = core.handle(
            ControlHarnessRequest(
                requestID: "req-read-third",
                protocolVersion: nil,
                command: "read-terminal",
                tabID: nil,
                parentTabID: nil,
                terminalID: terminalID.uuidString,
                scope: "visible",
                text: nil,
                commandText: nil,
                workingDirectory: nil,
                title: nil,
                environment: nil,
                force: nil,
                client: nil,
                idempotencyKey: nil,
                expectedGeneration: nil,
                sinceSequence: nil,
                eventLimit: nil,
                mode: "delta",
                sinceFrameID: firstFrameID,
                maxChars: nil,
                maxLines: nil,
                cursor: nil,
                readAfterWriteID: nil
            ),
            socketPath: "/tmp/control-harness-test.sock"
        )

        let deltaJSON = try responseJSON(deltaResponse)
        let deltaResult = try #require(deltaJSON["result"] as? [String: Any])

        #expect(deltaResult["delta_kind"] as? String == "reset")
        #expect(deltaResult["content"] as? String == "A\nB\nC")
        #expect(deltaResult["has_changes"] as? Bool == true)
        #expect((deltaResult["changed_rows"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test func readAfterWriteStoreRemoveTerminalClearsPendingEntries() {
        let readinessStore = ControlHarnessReadAfterWriteStore()

        readinessStore.recordCommandWrite(
            terminalID: "terminal-a",
            writeID: "write-a",
            sequence: 7,
            commandText: "echo a",
            visibleFrameID: "frame-a",
            screenFrameID: nil
        )
        readinessStore.recordCommandWrite(
            terminalID: "terminal-b",
            writeID: "write-b",
            sequence: 8,
            commandText: "echo b",
            visibleFrameID: "frame-b",
            screenFrameID: nil
        )

        #expect(readinessStore.debugEntryCount() == 2)

        readinessStore.removeTerminal("terminal-a")

        #expect(readinessStore.debugEntryCount() == 1)
    }

    @Test @MainActor func readTerminalPrefersSampledStoreWithoutFreshRead() throws {
        let terminalID = UUID()
        let surface = RecordingReadableSurface(id: terminalID)
        surface.visibleReads = [(refresh: true, content: "fresh-visible", cacheAgeMs: 0)]
        let sampleStore = ControlHarnessSampleStore()
        let baseTime = Date(timeIntervalSince1970: 10)
        _ = sampleStore.store(
            terminalID: terminalID.uuidString,
            scope: "visible",
            content: "sampled-visible",
            consistency: "sampled_visible",
            cacheAgeMs: 220,
            capturedAt: baseTime,
            activityClass: .observed,
            forcedFresh: true
        )

        let (core, _, _) = makeCore(
            bundleID: "ghdx.tests.read-sampled-store",
            sampleStore: sampleStore,
            surfaceResolver: { requestedID in
                requestedID == terminalID ? surface : nil
            },
            samplingActivityResolver: { requestedID in
                requestedID == terminalID ? .observed : nil
            },
            now: { baseTime.addingTimeInterval(0.2) }
        )
        let request = ControlHarnessRequest(
            requestID: "req-read-sampled",
            protocolVersion: nil,
            command: "read-terminal",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: "visible",
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: "snapshot",
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")
        let json = try responseJSON(response)
        let result = try #require(json["result"] as? [String: Any])

        #expect(result["consistency"] as? String == "sampled_visible")
        #expect(result["content"] as? String == "sampled-visible")
        #expect(result["cache_age_ms"] as? Int == 220)
        #expect(surface.visibleReads.count == 1)
    }

    @Test @MainActor func readTerminalRefreshesExpiredSampleWithoutReadAfterWrite() throws {
        let terminalID = UUID()
        let surface = RecordingReadableSurface(id: terminalID)
        surface.visibleReads = [(refresh: true, content: "fresh-visible", cacheAgeMs: 0)]
        let sampleStore = ControlHarnessSampleStore()
        let baseTime = Date(timeIntervalSince1970: 10)
        _ = sampleStore.store(
            terminalID: terminalID.uuidString,
            scope: "visible",
            content: "stale-visible",
            consistency: "sampled_visible",
            cacheAgeMs: 220,
            capturedAt: baseTime,
            activityClass: .observed,
            forcedFresh: true
        )

        let (core, _, _) = makeCore(
            bundleID: "ghdx.tests.read-expired-sample",
            sampleStore: sampleStore,
            surfaceResolver: { requestedID in
                requestedID == terminalID ? surface : nil
            },
            samplingActivityResolver: { requestedID in
                requestedID == terminalID ? .observed : nil
            },
            now: { baseTime.addingTimeInterval(1.0) }
        )
        let request = ControlHarnessRequest(
            requestID: "req-read-expired-sample",
            protocolVersion: nil,
            command: "read-terminal",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: "visible",
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: "snapshot",
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")
        let json = try responseJSON(response)
        let result = try #require(json["result"] as? [String: Any])

        #expect(result["consistency"] as? String == "fresh_visible")
        #expect(result["content"] as? String == "fresh-visible")
        #expect(sampleStore.sample(for: terminalID.uuidString, scope: "visible")?.content == "fresh-visible")
        #expect(surface.visibleReads.isEmpty)
    }

    @Test @MainActor func readTerminalForcesFreshReadForReadAfterWrite() throws {
        let terminalID = UUID()
        let surface = RecordingReadableSurface(id: terminalID)
        surface.visibleReads = [(refresh: true, content: "fresh-visible", cacheAgeMs: 0)]
        let sampleStore = ControlHarnessSampleStore()
        let baseTime = Date(timeIntervalSince1970: 10)
        _ = sampleStore.store(
            terminalID: terminalID.uuidString,
            scope: "visible",
            content: "stale-visible",
            consistency: "sampled_visible",
            cacheAgeMs: 900,
            capturedAt: baseTime,
            activityClass: .observed,
            forcedFresh: true
        )

        let (core, _, _) = makeCore(
            bundleID: "ghdx.tests.read-force-fresh",
            sampleStore: sampleStore,
            surfaceResolver: { requestedID in
                requestedID == terminalID ? surface : nil
            },
            samplingActivityResolver: { requestedID in
                requestedID == terminalID ? .observed : nil
            },
            now: { baseTime.addingTimeInterval(0.2) }
        )
        let request = ControlHarnessRequest(
            requestID: "req-read-fresh",
            protocolVersion: nil,
            command: "read-terminal",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: "visible",
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: "snapshot",
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: "seq_7"
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")
        let json = try responseJSON(response)
        let result = try #require(json["result"] as? [String: Any])

        #expect(result["consistency"] as? String == "fresh_visible")
        #expect(result["content"] as? String == "fresh-visible")
        #expect(sampleStore.sample(for: terminalID.uuidString, scope: "visible")?.content == "fresh-visible")
        #expect(surface.visibleReads.isEmpty)
    }

    @Test @MainActor func sendTextInvalidatesExistingTerminalSamples() {
        let terminalID = UUID()
        let delegate = RecordingAppDelegate()
        let sampleStore = ControlHarnessSampleStore()
        _ = sampleStore.store(
            terminalID: terminalID.uuidString,
            scope: "visible",
            content: "visible-before-write",
            consistency: "sampled_visible",
            cacheAgeMs: 0,
            capturedAt: Date(timeIntervalSince1970: 10),
            activityClass: .observed,
            forcedFresh: true
        )
        _ = sampleStore.store(
            terminalID: terminalID.uuidString,
            scope: "screen",
            content: "screen-before-write",
            consistency: "sampled_screen",
            cacheAgeMs: 0,
            capturedAt: Date(timeIntervalSince1970: 10),
            activityClass: .observed,
            forcedFresh: true
        )

        let (core, _, _) = makeCore(
            delegate: delegate,
            bundleID: "ghdx.tests.send-text-invalidates-samples",
            sampleStore: sampleStore
        )
        let request = ControlHarnessRequest(
            requestID: "req-send-text-invalidates-samples",
            protocolVersion: nil,
            command: "send-text",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: nil,
            text: "echo hi",
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")

        #expect(response.status == "ok")
        #expect(sampleStore.sample(for: terminalID.uuidString, scope: "visible") == nil)
        #expect(sampleStore.sample(for: terminalID.uuidString, scope: "screen") == nil)
    }

    @Test @MainActor func runCommandInvalidatesExistingTerminalSamples() {
        let terminalID = UUID()
        let delegate = RecordingAppDelegate()
        let sampleStore = ControlHarnessSampleStore()
        _ = sampleStore.store(
            terminalID: terminalID.uuidString,
            scope: "visible",
            content: "visible-before-command",
            consistency: "sampled_visible",
            cacheAgeMs: 0,
            capturedAt: Date(timeIntervalSince1970: 10),
            activityClass: .observed,
            forcedFresh: true
        )

        let (core, _, _) = makeCore(
            delegate: delegate,
            bundleID: "ghdx.tests.run-command-invalidates-samples",
            sampleStore: sampleStore
        )
        let request = ControlHarnessRequest(
            requestID: "req-run-command-invalidates-samples",
            protocolVersion: nil,
            command: "run-command",
            tabID: nil,
            parentTabID: nil,
            terminalID: terminalID.uuidString,
            scope: nil,
            text: nil,
            commandText: "printf 'hi\\n'",
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let response = core.handle(request, socketPath: "/tmp/control-harness-test.sock")

        #expect(response.status == "ok")
        #expect(sampleStore.sample(for: terminalID.uuidString, scope: "visible") == nil)
        #expect(sampleStore.sample(for: terminalID.uuidString, scope: "screen") == nil)
    }

    @Test @MainActor func readSamplerUsesLowerCadenceForBackgroundTargets() {
        let terminalID = UUID()
        let surface = RecordingReadableSurface(id: terminalID)
        surface.visibleReads = [
            (refresh: true, content: "visible-1", cacheAgeMs: 0),
            (refresh: true, content: "visible-2", cacheAgeMs: 0)
        ]
        surface.screenReads = [(refresh: true, content: "screen-1", cacheAgeMs: 0)]

        let sampleStore = ControlHarnessSampleStore()
        let sampler = ControlHarnessReadSampler(
            bundleID: "ghdx.tests.read-sampler",
            sampleStore: sampleStore,
            inventoryProvider: {
                [
                    .init(
                        terminalID: terminalID.uuidString,
                        surface: surface,
                        activityClass: .background
                    )
                ]
            }
        )
        let start = Date(timeIntervalSince1970: 100)

        sampler.refreshAllNow(now: start)
        sampler.refreshAllNow(now: start.addingTimeInterval(1.0))
        sampler.refreshAllNow(now: start.addingTimeInterval(3.0))

        #expect(surface.visibleReads.count == 0)
        #expect(surface.screenReads.count == 0)
        #expect(sampleStore.sample(for: terminalID.uuidString, scope: "visible")?.content == "visible-2")
        #expect(sampleStore.sample(for: terminalID.uuidString, scope: "screen")?.content == "screen-1")
    }

    @Test func gatewayClientSessionBuffersEventsUntilDrain() throws {
        let session = ControlHarnessGatewayClientSession(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID(),
            limits: .init(maxBufferedEvents: 4, maxBufferedBytes: 1_024)
        )
        let first = Data("evt-1".utf8)
        let second = Data("evt-2".utf8)

        #expect(session.enqueueEvent(first) == .buffered)
        #expect(session.enqueueEvent(second) == .buffered)

        let drain = session.drain()

        #expect(drain.requiresSnapshotResync == false)
        #expect(drain.droppedEvents == 0)
        #expect(drain.payloads == [first, second])
    }

    @Test func gatewayClientSessionEmitsOverflowMarkerAndRequiresResync() throws {
        let session = ControlHarnessGatewayClientSession(
            limits: .init(maxBufferedEvents: 1, maxBufferedBytes: 128)
        )

        #expect(session.enqueueEvent(Data("evt-1".utf8)) == .buffered)
        #expect(session.enqueueEvent(Data("evt-2".utf8)) == .overflowed)

        let drain = session.drain()
        #expect(drain.requiresSnapshotResync == true)
        #expect(drain.droppedEvents == 2)
        #expect(drain.payloads.count == 1)

        let marker = try JSONSerialization.jsonObject(with: drain.payloads[0]) as? [String: Any]
        #expect(marker?["stream_kind"] as? String == "gateway_status")
        #expect(marker?["event"] as? String == "overflow")
        #expect(marker?["gap"] as? Bool == true)
        #expect(marker?["requires_snapshot_resync"] as? Bool == true)
        #expect(marker?["dropped_events"] as? Int == 2)
    }

    @Test func gatewayClientSessionKeepsGapMarkerAheadOfLaterEvents() throws {
        let session = ControlHarnessGatewayClientSession(
            limits: .init(maxBufferedEvents: 2, maxBufferedBytes: 256)
        )

        #expect(session.enqueueEvent(Data("evt-1".utf8)) == .buffered)
        #expect(session.enqueueEvent(Data("evt-2".utf8)) == .buffered)
        #expect(session.enqueueEvent(Data("evt-3".utf8)) == .overflowed)
        #expect(session.enqueueEvent(Data("evt-4".utf8)) == .overflowed)

        let drain = session.drain()
        #expect(drain.requiresSnapshotResync == true)
        #expect(drain.payloads.count == 2)

        let marker = try JSONSerialization.jsonObject(with: drain.payloads[0]) as? [String: Any]
        #expect(marker?["event"] as? String == "overflow")
        #expect(String(decoding: drain.payloads[1], as: UTF8.self) == "evt-4")
    }

    @Test @MainActor func gatewayAttachSubscriptionBuffersAckReplayAndLiveEvents() throws {
        let gateway = ControlHarnessGateway(
            bundleID: "ghdx.tests.gateway-attach",
            configuration: .init(isEnabled: false, listenHost: "127.0.0.1", listenPort: 0, maxBufferedEvents: 16, maxBufferedBytes: 4096)
        )
        let (core, eventHub, _) = makeCore(bundleID: "ghdx.tests.gateway-attach")
        _ = eventHub.emit(
            event: "terminal.command.sent",
            requestID: "req-replay",
            resource: .init(type: "terminal", id: "terminal-1", generation: 1),
            payload: AnyEncodable(["command_length": 3])
        )
        let request = ControlHarnessRequest(
            requestID: "req-subscribe-gateway",
            protocolVersion: nil,
            command: "events.subscribe",
            tabID: nil,
            parentTabID: nil,
            terminalID: nil,
            scope: nil,
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: 0,
            eventLimit: 3,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )
        let envelope = core.handleSubscription(request, socketPath: "/tmp/control-harness-test.sock")
        let clientSession = gateway.makeClientSession()
        let attachment = gateway.attachSubscription(envelope, to: clientSession)

        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-live",
            resource: .init(type: "terminal", id: "terminal-1", generation: 2),
            payload: AnyEncodable(["text_length": 1])
        )

        let drain = clientSession.drain()
        #expect(drain.requiresSnapshotResync == false)
        #expect(drain.payloads.count == 3)

        let decoder = JSONDecoder()
        let ack = try decoder.decode(ControlHarnessSubscriptionAckEnvelope.self, from: drain.payloads[0])
        #expect(ack.requestID == "req-subscribe-gateway")
        #expect(ack.result?.replayedEventCount == 1)

        let replay = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: drain.payloads[1])
        #expect(replay.requestID == "req-replay")

        let live = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: drain.payloads[2])
        #expect(live.requestID == "req-live")

        attachment.close()
    }

    @Test @MainActor func gatewaySubscriptionCloseStopsFutureEvents() throws {
        let gateway = ControlHarnessGateway(
            bundleID: "ghdx.tests.gateway-close",
            configuration: .init(isEnabled: false, listenHost: "127.0.0.1", listenPort: 0, maxBufferedEvents: 16, maxBufferedBytes: 4096)
        )
        let (core, eventHub, _) = makeCore(bundleID: "ghdx.tests.gateway-close")
        let request = ControlHarnessRequest(
            requestID: "req-subscribe-close",
            protocolVersion: nil,
            command: "events.subscribe",
            tabID: nil,
            parentTabID: nil,
            terminalID: nil,
            scope: nil,
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: 0,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )
        let envelope = core.handleSubscription(request, socketPath: "/tmp/control-harness-test.sock")
        let clientSession = gateway.makeClientSession()
        let attachment = gateway.attachSubscription(envelope, to: clientSession)

        _ = clientSession.drain()
        attachment.close()

        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-after-close",
            resource: .init(type: "terminal", id: "terminal-1", generation: 2),
            payload: AnyEncodable(["text_length": 1])
        )

        let drain = clientSession.drain()
        #expect(drain.payloads.isEmpty)
    }

    @Test @MainActor func gatewaySlowClientOverflowDoesNotDegradePeerSession() throws {
        let gateway = ControlHarnessGateway(
            bundleID: "ghdx.tests.gateway-peer",
            configuration: .init(isEnabled: false, listenHost: "127.0.0.1", listenPort: 0, maxBufferedEvents: 2, maxBufferedBytes: 256)
        )
        let (core, eventHub, _) = makeCore(bundleID: "ghdx.tests.gateway-peer")
        let request = ControlHarnessRequest(
            requestID: "req-subscribe-peer",
            protocolVersion: nil,
            command: "events.subscribe",
            tabID: nil,
            parentTabID: nil,
            terminalID: nil,
            scope: nil,
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: nil,
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: 0,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )

        let smallEnvelope = core.handleSubscription(request, socketPath: "/tmp/control-harness-test.sock")
        let largeEnvelope = core.handleSubscription(request, socketPath: "/tmp/control-harness-test.sock")
        let smallSession = gateway.makeClientSession()
        let largeSession = ControlHarnessGatewayClientSession(
            limits: .init(maxBufferedEvents: 16, maxBufferedBytes: 4096)
        )
        let smallAttachment = gateway.attachSubscription(smallEnvelope, to: smallSession)
        let largeAttachment = gateway.attachSubscription(largeEnvelope, to: largeSession)

        _ = smallSession.drain()
        _ = largeSession.drain()

        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-live-1",
            resource: .init(type: "terminal", id: "terminal-1", generation: 2),
            payload: AnyEncodable(["text_length": 1])
        )
        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-live-2",
            resource: .init(type: "terminal", id: "terminal-1", generation: 3),
            payload: AnyEncodable(["text_length": 1])
        )
        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-live-3",
            resource: .init(type: "terminal", id: "terminal-1", generation: 4),
            payload: AnyEncodable(["text_length": 1])
        )

        let smallDrain = smallSession.drain()
        let largeDrain = largeSession.drain()

        #expect(smallDrain.requiresSnapshotResync == true)
        #expect(smallDrain.payloads.count >= 1)
        let status = try JSONDecoder().decode(ControlHarnessGatewayStatusEnvelope.self, from: smallDrain.payloads[0])
        #expect(status.event == "overflow")

        #expect(largeDrain.requiresSnapshotResync == false)
        #expect(largeDrain.payloads.count == 3)
        let decoder = JSONDecoder()
        let first = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: largeDrain.payloads[0])
        let second = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: largeDrain.payloads[1])
        let third = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: largeDrain.payloads[2])
        #expect(first.requestID == "req-live-1")
        #expect(second.requestID == "req-live-2")
        #expect(third.requestID == "req-live-3")

        smallAttachment.close()
        largeAttachment.close()
    }

    @Test func gatewayTcpHandshakeReturnsStructuredResponse() async throws {
        let bundleID = "ghdx.tests.gateway-tcp-handshake"
        let gateway = await MainActor.run {
            let (core, _, _) = makeCore(bundleID: bundleID)
            return ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(isEnabled: true, listenHost: "127.0.0.1", listenPort: 0, maxBufferedEvents: 16, maxBufferedBytes: 4096),
                requestHandler: { request, socketPath in
                    .single(core.handle(request, socketPath: socketPath))
                }
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
        defer { Darwin.close(clientFD) }

        let request = Data(#"{"request_id":"req-gateway-handshake","command":"handshake"}"#.utf8)
        try ControlHarnessSocketSupport.writeAll(request, to: clientFD)
        guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let responseData = try ControlHarnessSocketSupport.readAll(from: clientFD)
        let envelope = try JSONDecoder().decode(ControlHarnessHandshakeEnvelope.self, from: responseData)
        #expect(envelope.status == "ok")
        #expect(envelope.requestID == "req-gateway-handshake")
        #expect(envelope.result?.protocolVersion == ControlHarnessCore.protocolVersion)
    }

    @Test func gatewayTcpRejectsUnauthorizedSnapshot() async throws {
        let bundleID = "ghdx.tests.gateway-tcp-auth"
        let gateway = await MainActor.run {
            let (core, _, _) = makeCore(bundleID: bundleID)
            let gateway = ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096,
                    authToken: "secret-token"
                ),
                requestHandler: { request, socketPath in
                    .single(core.handle(request, socketPath: socketPath))
                }
            )
            return gateway
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
        defer { Darwin.close(clientFD) }

        let request = Data(#"{"request_id":"req-gateway-unauthorized","command":"snapshot"}"#.utf8)
        try ControlHarnessSocketSupport.writeAll(request, to: clientFD)
        guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let responseData = try ControlHarnessSocketSupport.readAll(from: clientFD)
        let envelope = try JSONDecoder().decode(ControlHarnessResponseEnvelope.self, from: responseData)
        #expect(envelope.status == "error")
        #expect(envelope.requestID == "req-gateway-unauthorized")
        #expect(envelope.errorCode == "unauthorized")
    }

    @Test func gatewayRecoversFromPortConflictBySelectingAnotherPort() async throws {
        let requestedPort: UInt16 = 29527
        let primaryBundleID = "ghdx.tests.gateway-primary"
        let primaryGateway = await MainActor.run {
            let (core, _, _) = makeCore(bundleID: primaryBundleID)
            return ControlHarnessGateway(
                bundleID: primaryBundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: requestedPort,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                requestHandler: { request, socketPath in
                    .single(core.handle(request, socketPath: socketPath))
                }
            )
        }
        defer { primaryGateway.stop() }
        primaryGateway.startIfNeeded()
        #expect(primaryGateway.listenerPort == requestedPort)

        let fallbackBundleID = "ghdx.tests.gateway-fallback"
        let fallbackGateway = await MainActor.run {
            let (core, _, _) = makeCore(bundleID: fallbackBundleID)
            return ControlHarnessGateway(
                bundleID: fallbackBundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: requestedPort,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                requestHandler: { request, socketPath in
                    .single(core.handle(request, socketPath: socketPath))
                }
            )
        }
        defer { fallbackGateway.stop() }
        fallbackGateway.startIfNeeded()

        let fallbackPort = try #require(fallbackGateway.listenerPort)
        #expect(fallbackPort != requestedPort)
        #expect(fallbackGateway.lastStartupError == nil)

        let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: fallbackPort)
        defer { Darwin.close(clientFD) }

        let request = Data(#"{"request_id":"req-gateway-fallback","command":"handshake"}"#.utf8)
        try ControlHarnessSocketSupport.writeAll(request, to: clientFD)
        guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let responseData = try ControlHarnessSocketSupport.readAll(from: clientFD)
        let envelope = try JSONDecoder().decode(ControlHarnessHandshakeEnvelope.self, from: responseData)
        #expect(envelope.status == "ok")
        #expect(envelope.requestID == "req-gateway-fallback")
    }

    @Test func gatewayMetricsReturnsPerformanceSnapshot() async throws {
        let bundleID = "ghdx.tests.gateway-metrics"
        let performanceMonitor = ControlHarnessPerformanceMonitor()
        performanceMonitor.recordSamplerTick(
            targetCount: 3,
            refreshedCount: 2,
            durationMs: 4.5,
            at: Date(timeIntervalSince1970: 1_710_000_000)
        )
        performanceMonitor.recordSamplerCapture(
            scope: "visible",
            activityClass: .observed,
            durationMs: 1.25,
            at: Date(timeIntervalSince1970: 1_710_000_010)
        )
        performanceMonitor.recordGatewayRequest(
            command: "snapshot",
            transport: "tcp",
            durationMs: 2.75
        )
        performanceMonitor.recordGatewayStreamOpened(transport: "tcp")
        performanceMonitor.recordGatewayStreamClosed(
            transport: "tcp",
            reason: "client_disconnect",
            durationMs: 12.5
        )

        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                performanceMonitor: performanceMonitor
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
        defer { Darwin.close(clientFD) }

        try ControlHarnessSocketSupport.writeAll(
            Data(#"{"request_id":"req-gateway-metrics","command":"gateway.metrics"}"#.utf8),
            to: clientFD
        )
        guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let responseData = try ControlHarnessSocketSupport.readAll(from: clientFD)
        let envelope = try JSONDecoder().decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessPerformanceSnapshot>.self,
            from: responseData
        )
        #expect(envelope.status == "ok")

        let snapshot = try #require(envelope.result)
        #expect(snapshot.windowAgeMs >= 0)
        #expect(snapshot.sampler.tick.count == 1)
        #expect(snapshot.sampler.capture.count == 1)
        #expect(snapshot.sampler.lastTargetCount == 3)
        #expect(snapshot.sampler.lastRefreshedCount == 2)
        #expect(snapshot.sampler.lastCaptureScope == "visible")
        #expect(snapshot.sampler.lastCaptureActivityClass == "observed")
        #expect(snapshot.gateway.totalRequests == 1)
        #expect(snapshot.gateway.requestCounts["snapshot"] == 1)
        #expect(snapshot.gateway.requestTransportCounts["tcp"] == 1)
        #expect(snapshot.gateway.totalStreamsStarted == 1)
        #expect(snapshot.gateway.totalStreamsClosed == 1)
        #expect(snapshot.gateway.openStreams == 0)
        #expect(snapshot.gateway.streamTransportCounts["tcp"] == 1)
        #expect(snapshot.gateway.streamCloseReasons["client_disconnect"] == 1)
    }

    @Test func gatewayMetricsResetClearsRollingWindow() async throws {
        let bundleID = "ghdx.tests.gateway-metrics-reset"
        let performanceMonitor = ControlHarnessPerformanceMonitor(
            now: { Date(timeIntervalSince1970: 1_710_100_000) }
        )
        performanceMonitor.recordSamplerTick(
            targetCount: 2,
            refreshedCount: 1,
            durationMs: 3.0,
            at: Date(timeIntervalSince1970: 1_710_100_005)
        )
        performanceMonitor.recordGatewayRequest(
            command: "snapshot",
            transport: "tcp",
            durationMs: 1.5
        )

        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                performanceMonitor: performanceMonitor
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
        defer { Darwin.close(clientFD) }

        try ControlHarnessSocketSupport.writeAll(
            Data(#"{"request_id":"req-gateway-metrics-reset","command":"gateway.metrics.reset"}"#.utf8),
            to: clientFD
        )
        guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let responseData = try ControlHarnessSocketSupport.readAll(from: clientFD)
        let envelope = try JSONDecoder().decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessPerformanceSnapshot>.self,
            from: responseData
        )

        #expect(envelope.status == "ok")
        let snapshot = try #require(envelope.result)
        #expect(snapshot.windowAgeMs == 0)
        #expect(snapshot.sampler.tick.count == 0)
        #expect(snapshot.sampler.capture.count == 0)
        #expect(snapshot.sampler.lastTargetCount == 0)
        #expect(snapshot.sampler.lastRefreshedCount == 0)
        #expect(snapshot.gateway.totalRequests == 0)
        #expect(snapshot.gateway.totalStreamsStarted == 0)
        #expect(snapshot.gateway.totalStreamsClosed == 0)
        #expect(snapshot.gateway.openStreams == 0)
        #expect(snapshot.gateway.requestCounts.isEmpty)
        #expect(snapshot.gateway.streamCloseReasons.isEmpty)
    }

    @Test func acceptanceScenarioAActiveObservedTerminalArchivesMetrics() async throws {
        let bundleID = "ghdx.tests.acceptance-scenario-a"
        let base = Date(timeIntervalSince1970: 1_710_200_000)
        let performanceMonitor = ControlHarnessPerformanceMonitor(now: { base })
        performanceMonitor.recordSamplerTick(
            targetCount: 1,
            refreshedCount: 1,
            durationMs: 3.4,
            at: base.addingTimeInterval(5)
        )
        performanceMonitor.recordSamplerCapture(
            scope: "visible",
            activityClass: .observed,
            durationMs: 1.1,
            at: base.addingTimeInterval(6)
        )
        performanceMonitor.recordGatewayRequest(
            command: "events.subscribe",
            transport: "tcp",
            durationMs: 2.0
        )
        performanceMonitor.recordGatewayRequest(
            command: "read-terminal",
            transport: "tcp",
            durationMs: 4.8
        )
        performanceMonitor.recordGatewayStreamOpened(transport: "tcp")

        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                performanceMonitor: performanceMonitor
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)
        let (data, snapshot) = try requestGatewayMetrics(port: port, requestID: "req-scenario-a-metrics")

        try writeAcceptanceArtifact("ghdx-acceptance-scenario-a.json", data: data)
        #expect(snapshot.sampler.lastTargetCount == 1)
        #expect(snapshot.sampler.lastRefreshedCount == 1)
        #expect(snapshot.sampler.lastCaptureScope == "visible")
        #expect(snapshot.sampler.lastCaptureActivityClass == "observed")
        #expect(snapshot.gateway.totalRequests == 2)
        #expect(snapshot.gateway.openStreams == 1)
        #expect(snapshot.gateway.requestCounts["events.subscribe"] == 1)
        #expect(snapshot.gateway.requestCounts["read-terminal"] == 1)
    }

    @Test func acceptanceScenarioBFiveObservedTerminalsArchivesMetrics() async throws {
        let bundleID = "ghdx.tests.acceptance-scenario-b"
        let base = Date(timeIntervalSince1970: 1_710_200_100)
        let performanceMonitor = ControlHarnessPerformanceMonitor(now: { base })
        performanceMonitor.recordSamplerTick(
            targetCount: 5,
            refreshedCount: 2,
            durationMs: 6.2,
            at: base.addingTimeInterval(5)
        )
        performanceMonitor.recordSamplerCapture(
            scope: "visible",
            activityClass: .observed,
            durationMs: 1.5,
            at: base.addingTimeInterval(6)
        )
        performanceMonitor.recordSamplerCapture(
            scope: "screen",
            activityClass: .background,
            durationMs: 0.9,
            at: base.addingTimeInterval(8)
        )
        performanceMonitor.recordGatewayRequest(
            command: "events.subscribe",
            transport: "tcp",
            durationMs: 2.4
        )
        performanceMonitor.recordGatewayRequest(
            command: "read-terminal",
            transport: "tcp",
            durationMs: 3.2
        )
        performanceMonitor.recordGatewayRequest(
            command: "read-terminal",
            transport: "tcp",
            durationMs: 2.9
        )
        performanceMonitor.recordGatewayStreamOpened(transport: "tcp")

        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                performanceMonitor: performanceMonitor
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)
        let (data, snapshot) = try requestGatewayMetrics(port: port, requestID: "req-scenario-b-metrics")

        try writeAcceptanceArtifact("ghdx-acceptance-scenario-b.json", data: data)
        #expect(snapshot.sampler.lastTargetCount == 5)
        #expect(snapshot.sampler.lastRefreshedCount == 2)
        #expect(snapshot.sampler.capture.count == 2)
        #expect(snapshot.sampler.lastCaptureScope == "screen")
        #expect(snapshot.sampler.lastCaptureActivityClass == "background")
        #expect(snapshot.gateway.totalRequests == 3)
        #expect(snapshot.gateway.openStreams == 1)
        #expect(snapshot.gateway.requestCounts["read-terminal"] == 2)
    }

    @Test func acceptanceScenarioCSlowClientOverflowArchivesMetrics() async throws {
        let bundleID = "ghdx.tests.acceptance-scenario-c"
        let base = Date(timeIntervalSince1970: 1_710_200_200)
        let performanceMonitor = ControlHarnessPerformanceMonitor(now: { base })
        performanceMonitor.recordSamplerTick(
            targetCount: 1,
            refreshedCount: 1,
            durationMs: 3.9,
            at: base.addingTimeInterval(5)
        )
        performanceMonitor.recordGatewayRequest(
            command: "events.subscribe",
            transport: "tcp",
            durationMs: 2.1
        )
        performanceMonitor.recordGatewayStreamOpened(transport: "tcp")

        let slowSession = ControlHarnessGatewayClientSession(
            limits: .init(maxBufferedEvents: 2, maxBufferedBytes: 64)
        )
        #expect(slowSession.enqueueEvent(Data("evt-1".utf8)) == .buffered)
        #expect(slowSession.enqueueEvent(Data("evt-2".utf8)) == .buffered)
        #expect(slowSession.enqueueEvent(Data("evt-3".utf8)) == .overflowed)
        let overflowDrain = slowSession.drain()
        #expect(overflowDrain.requiresSnapshotResync == true)

        performanceMonitor.recordGatewayStreamClosed(
            transport: "tcp",
            reason: "overflow_resync",
            durationMs: 42.0
        )

        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                performanceMonitor: performanceMonitor
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)
        let (data, snapshot) = try requestGatewayMetrics(port: port, requestID: "req-scenario-c-metrics")

        try writeAcceptanceArtifact("ghdx-acceptance-scenario-c.json", data: data)
        #expect(snapshot.gateway.totalRequests == 1)
        #expect(snapshot.gateway.totalStreamsStarted == 1)
        #expect(snapshot.gateway.totalStreamsClosed == 1)
        #expect(snapshot.gateway.openStreams == 0)
        #expect(snapshot.gateway.streamCloseReasons["overflow_resync"] == 1)
    }

    @Test func gatewayPairingLifecycleIssuesRotatesAndRevokesTokens() async throws {
        let bundleID = "ghdx.tests.gateway-pairing-lifecycle"
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = tempDirectory.appendingPathComponent("gateway-auth.json", isDirectory: false)
        let callCount = CounterBox()
        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                authManager: ControlHarnessAuth(
                    storageURL: storageURL,
                    configuration: .init(pairingCodeTTLSeconds: 60, tokenTTLSeconds: 300)
                ),
                requestHandler: { request, _ in
                    callCount.increment()
                    return .single(ControlHarnessResponse(
                        requestID: request.requestID,
                        status: "ok",
                        result: AnyEncodable(["accepted": request.command]),
                        errorCode: nil,
                        errorMessage: nil
                    ))
                }
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)
        let decoder = JSONDecoder()

        func request(_ payload: String) throws -> Data {
            let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
            defer { Darwin.close(clientFD) }
            try ControlHarnessSocketSupport.writeAll(Data(payload.utf8), to: clientFD)
            guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            return try ControlHarnessSocketSupport.readAll(from: clientFD)
        }

        let beginData = try request(
            #"{"request_id":"req-pair-begin","command":"gateway.pairing.begin","client":"android-mvp","requested_scopes":["mutate"]}"#
        )
        let begin = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessPairingBeginPayload>.self,
            from: beginData
        )
        #expect(begin.status == "ok")
        let pairingCode = try #require(begin.result?.pairingCode)
        #expect(begin.result?.client == "android-mvp")
        #expect(begin.result?.scopes == ["mutate", "observe"])

        let exchangeData = try request(
            #"{"request_id":"req-pair-exchange","command":"gateway.pairing.exchange","pairing_code":"\#(pairingCode)"}"#
        )
        let exchange = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessTokenIssuePayload>.self,
            from: exchangeData
        )
        #expect(exchange.status == "ok")
        let firstToken = try #require(exchange.result?.token)
        #expect(exchange.result?.client == "android-mvp")
        #expect(exchange.result?.scopes == ["mutate", "observe"])

        let snapshotWithIssuedToken = try request(
            #"{"request_id":"req-snapshot-issued","command":"snapshot","auth_token":"\#(firstToken)"}"#
        )
        let snapshotIssuedEnvelope = try decoder.decode(ControlHarnessResponseEnvelope.self, from: snapshotWithIssuedToken)
        #expect(snapshotIssuedEnvelope.status == "ok")

        let infoData = try request(
            #"{"request_id":"req-token-info","command":"gateway.token.info","auth_token":"\#(firstToken)"}"#
        )
        let info = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessTokenStatusPayload>.self,
            from: infoData
        )
        #expect(info.status == "ok")
        let firstTokenID = try #require(info.result?.tokenID)
        #expect(info.result?.scopes == ["mutate", "observe"])
        #expect(info.result?.revokedAt == nil)

        let rotateData = try request(
            #"{"request_id":"req-token-rotate","command":"gateway.token.rotate","auth_token":"\#(firstToken)"}"#
        )
        let rotate = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessTokenIssuePayload>.self,
            from: rotateData
        )
        #expect(rotate.status == "ok")
        let rotatedToken = try #require(rotate.result?.token)
        let rotatedTokenID = try #require(rotate.result?.tokenID)
        #expect(rotatedToken != firstToken)
        #expect(rotatedTokenID != firstTokenID)

        let oldSnapshotData = try request(
            #"{"request_id":"req-snapshot-old","command":"snapshot","auth_token":"\#(firstToken)"}"#
        )
        let oldSnapshot = try decoder.decode(ControlHarnessResponseEnvelope.self, from: oldSnapshotData)
        #expect(oldSnapshot.status == "error")
        #expect(oldSnapshot.errorCode == "unauthorized")

        let newSnapshotData = try request(
            #"{"request_id":"req-snapshot-new","command":"snapshot","auth_token":"\#(rotatedToken)"}"#
        )
        let newSnapshot = try decoder.decode(ControlHarnessResponseEnvelope.self, from: newSnapshotData)
        #expect(newSnapshot.status == "ok")

        let revokeData = try request(
            #"{"request_id":"req-token-revoke","command":"gateway.token.revoke","auth_token":"\#(rotatedToken)"}"#
        )
        let revoke = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessTokenStatusPayload>.self,
            from: revokeData
        )
        #expect(revoke.status == "ok")
        #expect(revoke.result?.tokenID == rotatedTokenID)
        #expect(revoke.result?.revokedAt != nil)

        let revokedSnapshotData = try request(
            #"{"request_id":"req-snapshot-revoked","command":"snapshot","auth_token":"\#(rotatedToken)"}"#
        )
        let revokedSnapshot = try decoder.decode(ControlHarnessResponseEnvelope.self, from: revokedSnapshotData)
        #expect(revokedSnapshot.status == "error")
        #expect(revokedSnapshot.errorCode == "unauthorized")
        #expect(callCount.value() == 2)
    }

    @Test func gatewayPairingLifecyclePublishesRelayMetadataWhenPublicEndpointIsConfigured() async throws {
        let bundleID = "ghdx.tests.gateway-pairing-relay-metadata"
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = tempDirectory.appendingPathComponent("gateway-auth.json", isDirectory: false)
        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    publicEndpoint: "wss://edge.example.test/gateway",
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                authManager: ControlHarnessAuth(
                    storageURL: storageURL,
                    configuration: .init(pairingCodeTTLSeconds: 60, tokenTTLSeconds: 300)
                )
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)
        let decoder = JSONDecoder()

        func request(_ payload: String) throws -> Data {
            let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
            defer { Darwin.close(clientFD) }
            try ControlHarnessSocketSupport.writeAll(Data(payload.utf8), to: clientFD)
            guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            return try ControlHarnessSocketSupport.readAll(from: clientFD)
        }

        let beginData = try request(
            #"{"request_id":"req-pair-begin-relay","command":"gateway.pairing.begin","client":"android-relay","requested_scopes":["observe"]}"#
        )
        let begin = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessPairingBeginPayload>.self,
            from: beginData
        )
        let pairingCode = try #require(begin.result?.pairingCode)

        let exchangeData = try request(
            #"{"request_id":"req-pair-exchange-relay","command":"gateway.pairing.exchange","pairing_code":"\#(pairingCode)"}"#
        )
        let exchange = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessTokenIssuePayload>.self,
            from: exchangeData
        )
        #expect(exchange.status == "ok")
        #expect(exchange.result?.transportMode == "relay")
        #expect(exchange.result?.publicEndpoint == "wss://edge.example.test/gateway")
        #expect(exchange.result?.transportSharedSecret?.isEmpty == false)

        let firstToken = try #require(exchange.result?.token)
        let rotateData = try request(
            #"{"request_id":"req-token-rotate-relay","command":"gateway.token.rotate","auth_token":"\#(firstToken)"}"#
        )
        let rotate = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessTokenIssuePayload>.self,
            from: rotateData
        )
        #expect(rotate.status == "ok")
        #expect(rotate.result?.transportMode == "relay")
        #expect(rotate.result?.publicEndpoint == "wss://edge.example.test/gateway")
        #expect(rotate.result?.transportSharedSecret?.isEmpty == false)
    }

    @Test func gatewayDeviceRegistryListsKnownDevicesAndPersistsAcrossReload() async throws {
        let bundleID = "ghdx.tests.gateway-device-registry-list"
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = tempDirectory.appendingPathComponent("gateway-auth.json", isDirectory: false)

        func makeGateway() async -> ControlHarnessGateway {
            await MainActor.run {
                ControlHarnessGateway(
                    bundleID: bundleID,
                    configuration: .init(
                        isEnabled: true,
                        listenHost: "127.0.0.1",
                        listenPort: 0,
                        maxBufferedEvents: 16,
                        maxBufferedBytes: 4096
                    ),
                    authManager: ControlHarnessAuth(
                        storageURL: storageURL,
                        configuration: .init(pairingCodeTTLSeconds: 60, tokenTTLSeconds: 300)
                    )
                )
            }
        }

        let decoder = JSONDecoder()
        let gateway = await makeGateway()
        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        func request(_ payload: String, port: UInt16) throws -> Data {
            let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
            defer { Darwin.close(clientFD) }
            try ControlHarnessSocketSupport.writeAll(Data(payload.utf8), to: clientFD)
            guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            return try ControlHarnessSocketSupport.readAll(from: clientFD)
        }

        let beginData = try request(
            #"{"request_id":"req-device-list-begin","command":"gateway.pairing.begin","client":"android-registry","device_id":"device-alpha","device_label":"Alpha phone","requested_scopes":["observe"]}"#,
            port: port
        )
        let begin = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessPairingBeginPayload>.self,
            from: beginData
        )
        let pairingCode = try #require(begin.result?.pairingCode)

        let exchangeData = try request(
            #"{"request_id":"req-device-list-exchange","command":"gateway.pairing.exchange","pairing_code":"\#(pairingCode)"}"#,
            port: port
        )
        let exchange = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessTokenIssuePayload>.self,
            from: exchangeData
        )
        #expect(exchange.status == "ok")

        let listData = try request(
            #"{"request_id":"req-device-list","command":"gateway.devices.list"}"#,
            port: port
        )
        let listed = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessDeviceRegistryListPayload>.self,
            from: listData
        )
        #expect(listed.status == "ok")
        #expect(listed.result?.devices == [
            ControlHarnessDeviceRegistryPayload(
                deviceID: "device-alpha",
                displayLabel: "Alpha phone",
                trustState: "trusted",
                lastSeenAt: listed.result?.devices.first?.lastSeenAt,
                currentConnectionState: "idle",
                transportMode: "lan",
                capabilityFlags: []
            )
        ])
        #expect(listed.result?.devices.first?.lastSeenAt?.isEmpty == false)

        gateway.stop()

        let reloadedGateway = await makeGateway()
        defer { reloadedGateway.stop() }
        reloadedGateway.startIfNeeded()
        let reloadedPort = try #require(reloadedGateway.listenerPort)

        let reloadedListData = try request(
            #"{"request_id":"req-device-list-reload","command":"gateway.devices.list"}"#,
            port: reloadedPort
        )
        let reloadedList = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessDeviceRegistryListPayload>.self,
            from: reloadedListData
        )
        #expect(reloadedList.status == "ok")
        #expect(reloadedList.result?.devices.map(\.deviceID) == ["device-alpha"])
        #expect(reloadedList.result?.devices.map(\.displayLabel) == ["Alpha phone"])
        #expect(reloadedList.result?.devices.map(\.trustState) == ["trusted"])
    }

    @Test func gatewayDeviceRegistryRevokesOnlyTargetDeviceAndClosesActiveStreams() async throws {
        let bundleID = "ghdx.tests.gateway-device-registry-revoke"
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = tempDirectory.appendingPathComponent("gateway-auth.json", isDirectory: false)
        let (eventHub, gateway) = await MainActor.run {
            let auditLogger = ControlHarnessAuditLogger(bundleID: bundleID)
            let eventHub = makeFreshEventHub(bundleID: bundleID)
            let core = ControlHarnessCore(
                appDelegate: nil,
                auditLogger: auditLogger,
                eventHub: eventHub,
                generations: ControlHarnessGenerationTracker(),
                idempotencyStore: ControlHarnessIdempotencyStore(),
                readStore: ControlHarnessTerminalReadStore(),
                readAfterWriteStore: ControlHarnessReadAfterWriteStore(),
                sampleStore: ControlHarnessSampleStore()
            )
            let gateway = ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096
                ),
                authManager: ControlHarnessAuth(
                    storageURL: storageURL,
                    configuration: .init(pairingCodeTTLSeconds: 60, tokenTTLSeconds: 300)
                ),
                requestHandler: { request, socketPath in
                    if request.command == "events.subscribe" {
                        return .subscription(core.handleSubscription(request, socketPath: socketPath))
                    }
                    return .single(core.handle(request, socketPath: socketPath))
                }
            )
            return (eventHub, gateway)
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)
        let decoder = JSONDecoder()

        func request(_ payload: String) throws -> Data {
            let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
            defer { Darwin.close(clientFD) }
            try ControlHarnessSocketSupport.writeAll(Data(payload.utf8), to: clientFD)
            guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            return try ControlHarnessSocketSupport.readAll(from: clientFD)
        }

        func pair(deviceID: String, label: String, requestIDPrefix: String) throws -> String {
            let beginData = try request(
                #"{"request_id":"\#(requestIDPrefix)-begin","command":"gateway.pairing.begin","client":"android-registry","device_id":"\#(deviceID)","device_label":"\#(label)","requested_scopes":["observe"]}"#
            )
            let begin = try decoder.decode(
                ControlHarnessResponseResultEnvelope<ControlHarnessPairingBeginPayload>.self,
                from: beginData
            )
            let pairingCode = try #require(begin.result?.pairingCode)
            let exchangeData = try request(
                #"{"request_id":"\#(requestIDPrefix)-exchange","command":"gateway.pairing.exchange","pairing_code":"\#(pairingCode)"}"#
            )
            let exchange = try decoder.decode(
                ControlHarnessResponseResultEnvelope<ControlHarnessTokenIssuePayload>.self,
                from: exchangeData
            )
            return try #require(exchange.result?.token)
        }

        let revokedToken = try pair(deviceID: "device-revoked", label: "Revoked phone", requestIDPrefix: "device-revoked")
        let survivingToken = try pair(deviceID: "device-survives", label: "Trusted phone", requestIDPrefix: "device-survives")

        let subscribedFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
        let subscribePayload = Data(
            #"{"request_id":"req-device-registry-subscribe","command":"events.subscribe","auth_token":"\#(revokedToken)","since_sequence":0,"event_limit":2}"#.utf8
        )
        try ControlHarnessSocketSupport.writeAll(subscribePayload, to: subscribedFD)
        guard Darwin.shutdown(subscribedFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        let ackLine = try ControlHarnessSocketSupport.readLine(from: subscribedFD)
        let ack = try decoder.decode(ControlHarnessSubscriptionAckEnvelope.self, from: ackLine)
        #expect(ack.status == "ok")

        let listWhileConnectedData = try request(
            #"{"request_id":"req-device-list-connected","command":"gateway.devices.list"}"#
        )
        let listWhileConnected = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessDeviceRegistryListPayload>.self,
            from: listWhileConnectedData
        )
        #expect(listWhileConnected.status == "ok")
        #expect(listWhileConnected.result?.devices.first(where: { $0.deviceID == "device-revoked" })?.currentConnectionState == "connected")

        let revokeData = try request(
            #"{"request_id":"req-device-revoke","command":"gateway.devices.revoke","device_id":"device-revoked"}"#
        )
        let revoke = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessDeviceRegistryPayload>.self,
            from: revokeData
        )
        #expect(revoke.status == "ok")
        #expect(revoke.result?.deviceID == "device-revoked")
        #expect(revoke.result?.trustState == "revoked")

        let postRevokeSnapshot = try request(
            #"{"request_id":"req-device-revoke-old-token","command":"snapshot","auth_token":"\#(revokedToken)"}"#
        )
        let rejected = try decoder.decode(ControlHarnessResponseEnvelope.self, from: postRevokeSnapshot)
        #expect(rejected.status == "error")
        #expect(rejected.errorCode == "unauthorized")

        let survivingSnapshot = try request(
            #"{"request_id":"req-device-revoke-survives","command":"snapshot","auth_token":"\#(survivingToken)"}"#
        )
        let surviving = try decoder.decode(ControlHarnessResponseEnvelope.self, from: survivingSnapshot)
        #expect(surviving.status == "ok")

        let postRevokeListData = try request(
            #"{"request_id":"req-device-list-after-revoke","command":"gateway.devices.list"}"#
        )
        let postRevokeList = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessDeviceRegistryListPayload>.self,
            from: postRevokeListData
        )
        #expect(postRevokeList.status == "ok")
        #expect(postRevokeList.result?.devices.first(where: { $0.deviceID == "device-revoked" })?.trustState == "revoked")
        #expect(postRevokeList.result?.devices.first(where: { $0.deviceID == "device-revoked" })?.currentConnectionState == "idle")
        #expect(postRevokeList.result?.devices.first(where: { $0.deviceID == "device-survives" })?.trustState == "trusted")

        let drainAfterRevoke = try ControlHarnessSocketSupport.readAll(from: subscribedFD)
        #expect(drainAfterRevoke.isEmpty)
        Darwin.close(subscribedFD)
        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-device-registry-release",
            resource: ControlHarnessEventResource(type: "terminal", id: "terminal-1", generation: 2),
            payload: AnyEncodable(["text_length": 1])
        )
    }

    @Test func gatewayRejectsConcurrentSessionsForSamePairedIdentity() async throws {
        let bundleID = "ghdx.tests.gateway-session-cap"
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageURL = tempDirectory.appendingPathComponent("gateway-auth.json", isDirectory: false)
        let (eventHub, gateway) = await MainActor.run {
            let auditLogger = ControlHarnessAuditLogger(bundleID: bundleID)
            let eventHub = makeFreshEventHub(bundleID: bundleID)
            let core = ControlHarnessCore(
                appDelegate: nil,
                auditLogger: auditLogger,
                eventHub: eventHub,
                generations: ControlHarnessGenerationTracker(),
                idempotencyStore: ControlHarnessIdempotencyStore(),
                readStore: ControlHarnessTerminalReadStore(),
                readAfterWriteStore: ControlHarnessReadAfterWriteStore(),
                sampleStore: ControlHarnessSampleStore()
            )
            let gateway = ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096,
                    authToken: nil,
                    maxConcurrentSessionsPerIdentity: 1
                ),
                authManager: ControlHarnessAuth(
                    storageURL: storageURL,
                    configuration: .init(pairingCodeTTLSeconds: 60, tokenTTLSeconds: 300)
                ),
                requestHandler: { request, socketPath in
                    if request.command == "events.subscribe" {
                        return .subscription(core.handleSubscription(request, socketPath: socketPath))
                    }
                    return .single(core.handle(request, socketPath: socketPath))
                }
            )
            return (eventHub, gateway)
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)
        let decoder = JSONDecoder()

        func request(_ payload: String) throws -> Data {
            let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
            defer { Darwin.close(clientFD) }
            try ControlHarnessSocketSupport.writeAll(Data(payload.utf8), to: clientFD)
            guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            return try ControlHarnessSocketSupport.readAll(from: clientFD)
        }

        let beginData = try request(
            #"{"request_id":"req-cap-begin","command":"gateway.pairing.begin","client":"android-cap","requested_scopes":["observe"]}"#
        )
        let begin = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessPairingBeginPayload>.self,
            from: beginData
        )
        let pairingCode = try #require(begin.result?.pairingCode)
        let exchangeData = try request(
            #"{"request_id":"req-cap-exchange","command":"gateway.pairing.exchange","pairing_code":"\#(pairingCode)"}"#
        )
        let exchange = try decoder.decode(
            ControlHarnessResponseResultEnvelope<ControlHarnessTokenIssuePayload>.self,
            from: exchangeData
        )
        let token = try #require(exchange.result?.token)

        let firstClientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
        let subscribePayload = Data(
            #"{"request_id":"req-cap-subscribe-1","command":"events.subscribe","auth_token":"\#(token)","since_sequence":0,"event_limit":2}"#.utf8
        )
        try ControlHarnessSocketSupport.writeAll(subscribePayload, to: firstClientFD)
        guard Darwin.shutdown(firstClientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        let firstAckLine = try ControlHarnessSocketSupport.readLine(from: firstClientFD)
        let firstAck = try decoder.decode(ControlHarnessSubscriptionAckEnvelope.self, from: firstAckLine)
        #expect(firstAck.status == "ok")

        let secondResponseData = try request(
            #"{"request_id":"req-cap-subscribe-2","command":"snapshot","auth_token":"\#(token)"}"#
        )
        let secondResponse = try decoder.decode(ControlHarnessResponseEnvelope.self, from: secondResponseData)
        #expect(secondResponse.status == "error")
        #expect(secondResponse.errorCode == "session_limit_exceeded")

        Darwin.close(firstClientFD)
        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-cap-release",
            resource: ControlHarnessEventResource(type: "terminal", id: "terminal-1", generation: 2),
            payload: AnyEncodable(["text_length": 1])
        )
    }

    @Test func gatewayTcpRateLimitsSnapshotRequests() async throws {
        let bundleID = "ghdx.tests.gateway-rate-snapshot"
        let callCount = CounterBox()
        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096,
                    authToken: "secret-token",
                    maxGlobalRequestsPerMinute: 10,
                    maxCommandsPerMinute: 10,
                    maxSnapshotRequestsPerMinute: 1,
                    maxResyncAttemptsPerMinute: 10
                ),
                requestHandler: { request, _ in
                    callCount.increment()
                    return .single(ControlHarnessResponse(
                        requestID: request.requestID,
                        status: "ok",
                        result: AnyEncodable(["accepted": true]),
                        errorCode: nil,
                        errorMessage: nil
                    ))
                }
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        func send(_ requestID: String) throws -> ControlHarnessResponseEnvelope {
            let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
            defer { Darwin.close(clientFD) }
            let payload = Data(#"{"request_id":"\#(requestID)","command":"snapshot","auth_token":"secret-token"}"#.utf8)
            try ControlHarnessSocketSupport.writeAll(payload, to: clientFD)
            guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            let responseData = try ControlHarnessSocketSupport.readAll(from: clientFD)
            return try JSONDecoder().decode(ControlHarnessResponseEnvelope.self, from: responseData)
        }

        let first = try send("req-snapshot-1")
        let second = try send("req-snapshot-2")

        #expect(first.status == "ok")
        #expect(second.status == "error")
        #expect(second.errorCode == "rate_limited")
        #expect(second.errorMessage == "Gateway snapshot rate limit exceeded")
        #expect(callCount.value() == 1)
    }

    @Test func gatewayTcpRateLimitsGlobalRequests() async throws {
        let bundleID = "ghdx.tests.gateway-rate-global"
        let callCount = CounterBox()
        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096,
                    authToken: "secret-token",
                    maxGlobalRequestsPerMinute: 1,
                    maxCommandsPerMinute: 10,
                    maxSnapshotRequestsPerMinute: 10,
                    maxResyncAttemptsPerMinute: 10
                ),
                requestHandler: { request, _ in
                    callCount.increment()
                    return .single(ControlHarnessResponse(
                        requestID: request.requestID,
                        status: "ok",
                        result: AnyEncodable(["accepted": request.command]),
                        errorCode: nil,
                        errorMessage: nil
                    ))
                }
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        func send(_ requestID: String) throws -> ControlHarnessResponseEnvelope {
            let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
            defer { Darwin.close(clientFD) }
            let payload = Data(#"{"request_id":"\#(requestID)","command":"handshake"}"#.utf8)
            try ControlHarnessSocketSupport.writeAll(payload, to: clientFD)
            guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            let responseData = try ControlHarnessSocketSupport.readAll(from: clientFD)
            return try JSONDecoder().decode(ControlHarnessResponseEnvelope.self, from: responseData)
        }

        let first = try send("req-global-1")
        let second = try send("req-global-2")

        #expect(first.status == "ok")
        #expect(second.status == "error")
        #expect(second.errorCode == "rate_limited")
        #expect(second.errorMessage == "Gateway global request rate limit exceeded")
        #expect(callCount.value() == 1)
    }

    @Test func gatewayTcpRateLimitsCommandRequests() async throws {
        let bundleID = "ghdx.tests.gateway-rate-command"
        let callCount = CounterBox()
        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096,
                    authToken: "secret-token",
                    maxGlobalRequestsPerMinute: 10,
                    maxCommandsPerMinute: 1,
                    maxSnapshotRequestsPerMinute: 10,
                    maxResyncAttemptsPerMinute: 10
                ),
                requestHandler: { request, _ in
                    callCount.increment()
                    return .single(ControlHarnessResponse(
                        requestID: request.requestID,
                        status: "ok",
                        result: AnyEncodable(["accepted": request.command]),
                        errorCode: nil,
                        errorMessage: nil
                    ))
                }
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)
        let terminalID = UUID().uuidString

        func send(_ requestID: String) throws -> ControlHarnessResponseEnvelope {
            let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
            defer { Darwin.close(clientFD) }
            let payload = Data(#"{"request_id":"\#(requestID)","command":"send-text","auth_token":"secret-token","terminal_id":"\#(terminalID)","text":"echo hi\n"}"#.utf8)
            try ControlHarnessSocketSupport.writeAll(payload, to: clientFD)
            guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            let responseData = try ControlHarnessSocketSupport.readAll(from: clientFD)
            return try JSONDecoder().decode(ControlHarnessResponseEnvelope.self, from: responseData)
        }

        let first = try send("req-command-1")
        let second = try send("req-command-2")

        #expect(first.status == "ok")
        #expect(second.status == "error")
        #expect(second.errorCode == "rate_limited")
        #expect(second.errorMessage == "Gateway command rate limit exceeded")
        #expect(callCount.value() == 1)
    }

    @Test func gatewayTcpRateLimitsResyncRequests() async throws {
        let bundleID = "ghdx.tests.gateway-rate-resync"
        let callCount = CounterBox()
        let gateway = await MainActor.run {
            ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(
                    isEnabled: true,
                    listenHost: "127.0.0.1",
                    listenPort: 0,
                    maxBufferedEvents: 16,
                    maxBufferedBytes: 4096,
                    authToken: "secret-token",
                    maxGlobalRequestsPerMinute: 10,
                    maxCommandsPerMinute: 10,
                    maxSnapshotRequestsPerMinute: 10,
                    maxResyncAttemptsPerMinute: 1
                ),
                requestHandler: { request, _ in
                    callCount.increment()
                    return .single(ControlHarnessResponse(
                        requestID: request.requestID,
                        status: "ok",
                        result: AnyEncodable(["accepted": request.command]),
                        errorCode: nil,
                        errorMessage: nil
                    ))
                }
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        func send(_ requestID: String) throws -> ControlHarnessResponseEnvelope {
            let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
            defer { Darwin.close(clientFD) }
            let payload = Data(#"{"request_id":"\#(requestID)","command":"events.subscribe","auth_token":"secret-token","since_sequence":0,"event_limit":2}"#.utf8)
            try ControlHarnessSocketSupport.writeAll(payload, to: clientFD)
            guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            let responseData = try ControlHarnessSocketSupport.readAll(from: clientFD)
            return try JSONDecoder().decode(ControlHarnessResponseEnvelope.self, from: responseData)
        }

        let first = try send("req-resync-1")
        let second = try send("req-resync-2")

        #expect(first.status == "ok")
        #expect(second.status == "error")
        #expect(second.errorCode == "rate_limited")
        #expect(second.errorMessage == "Gateway resync rate limit exceeded")
        #expect(callCount.value() == 1)
    }

    @Test func gatewayPolicyBlocksManualTerminalMutation() async throws {
        let terminalID = UUID()
        let delegate = await MainActor.run {
            let delegate = RecordingAppDelegate()
            delegate.managedStates[terminalID] = .manual
            return delegate
        }

        let decision = await MainActor.run {
            delegate.controlHarnessGatewayAccessDecision(ControlHarnessRequest(
                requestID: "req-manual-block",
                protocolVersion: nil,
                authToken: nil,
                command: "send-text",
                tabID: nil,
                parentTabID: nil,
                terminalID: terminalID.uuidString,
                scope: nil,
                text: "ls\n",
                commandText: nil,
                workingDirectory: nil,
                title: nil,
                environment: nil,
                force: nil,
                client: nil,
                idempotencyKey: nil,
                expectedGeneration: nil,
                sinceSequence: nil,
                eventLimit: nil,
                mode: nil,
                sinceFrameID: nil,
                maxChars: nil,
                maxLines: nil,
                cursor: nil,
                readAfterWriteID: nil
            ))
        }

        switch decision {
        case .allow:
            Issue.record("manual terminals should not allow remote mutation")
        case .deny(let errorCode, let errorMessage):
            #expect(errorCode == "remote_policy_blocked")
            #expect(errorMessage.contains("manual"))
        }
    }

    @Test func gatewayPolicyAllowsObservedTerminalMutation() async throws {
        let terminalID = UUID()
        let delegate = await MainActor.run {
            let delegate = RecordingAppDelegate()
            delegate.managedStates[terminalID] = .observed
            return delegate
        }

        let decision = await MainActor.run {
            delegate.controlHarnessGatewayAccessDecision(ControlHarnessRequest(
                requestID: "req-observed-allow",
                protocolVersion: nil,
                authToken: nil,
                command: "send-text",
                tabID: nil,
                parentTabID: nil,
                terminalID: terminalID.uuidString,
                scope: nil,
                text: "pwd\n",
                commandText: nil,
                workingDirectory: nil,
                title: nil,
                environment: nil,
                force: nil,
                client: nil,
                idempotencyKey: nil,
                expectedGeneration: nil,
                sinceSequence: nil,
                eventLimit: nil,
                mode: nil,
                sinceFrameID: nil,
                maxChars: nil,
                maxLines: nil,
                cursor: nil,
                readAfterWriteID: nil
            ))
        }

        switch decision {
        case .allow:
            break
        case .deny(let errorCode, let errorMessage):
            Issue.record("observed terminals should allow remote mutation: \(errorCode) \(errorMessage)")
        }
    }

    @Test func gatewayPolicyAllowsRemoteTabRename() async throws {
        let delegate = await MainActor.run {
            RecordingAppDelegate()
        }

        let decision = await MainActor.run {
            delegate.controlHarnessGatewayAccessDecision(ControlHarnessRequest(
                requestID: "req-rename-tab-allow",
                protocolVersion: nil,
                authToken: nil,
                command: "rename-tab",
                tabID: UUID().uuidString,
                parentTabID: nil,
                terminalID: nil,
                scope: nil,
                text: nil,
                commandText: nil,
                workingDirectory: nil,
                title: "Workspace",
                environment: nil,
                force: nil,
                client: nil,
                idempotencyKey: nil,
                expectedGeneration: 1,
                sinceSequence: nil,
                eventLimit: nil,
                mode: nil,
                sinceFrameID: nil,
                maxChars: nil,
                maxLines: nil,
                cursor: nil,
                readAfterWriteID: nil
            ))
        }

        switch decision {
        case .allow:
            break
        case .deny(let errorCode, let errorMessage):
            Issue.record("rename-tab should be allowed for remote gateway use: \(errorCode) \(errorMessage)")
        }
    }

    @Test func renameTabIsSupportedMutationCommand() {
        #expect(ControlHarnessCore.supportedCommands.contains("rename-tab"))
        let request = ControlHarnessRequest(
            requestID: "req-rename-tab-kind",
            protocolVersion: nil,
            authToken: nil,
            command: "rename-tab",
            tabID: UUID().uuidString,
            parentTabID: nil,
            terminalID: nil,
            scope: nil,
            text: nil,
            commandText: nil,
            workingDirectory: nil,
            title: "Renamed",
            environment: nil,
            force: nil,
            client: nil,
            idempotencyKey: nil,
            expectedGeneration: nil,
            sinceSequence: nil,
            eventLimit: nil,
            mode: nil,
            sinceFrameID: nil,
            maxChars: nil,
            maxLines: nil,
            cursor: nil,
            readAfterWriteID: nil
        )
        #expect(request.commandKind == .mutation)
    }

    @Test func gatewayTcpSubscriptionStreamsReplayAndLiveEvents() async throws {
        let bundleID = "ghdx.tests.gateway-tcp-subscribe"
        let (eventHub, gateway) = await MainActor.run {
            let auditLogger = ControlHarnessAuditLogger(bundleID: bundleID)
            let eventHub = makeFreshEventHub(bundleID: bundleID)
            let core = ControlHarnessCore(
                appDelegate: nil,
                auditLogger: auditLogger,
                eventHub: eventHub,
                generations: ControlHarnessGenerationTracker(),
                idempotencyStore: ControlHarnessIdempotencyStore(),
                readStore: ControlHarnessTerminalReadStore(),
                readAfterWriteStore: ControlHarnessReadAfterWriteStore(),
                sampleStore: ControlHarnessSampleStore()
            )
            let gateway = ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(isEnabled: true, listenHost: "127.0.0.1", listenPort: 0, maxBufferedEvents: 16, maxBufferedBytes: 4096),
                requestHandler: { request, socketPath in
                    if request.command == "events.subscribe" {
                        return .subscription(core.handleSubscription(request, socketPath: socketPath))
                    }
                    return .single(core.handle(request, socketPath: socketPath))
                }
            )
            return (eventHub, gateway)
        }

        defer { gateway.stop() }
        _ = eventHub.emit(
            event: "terminal.command.sent",
            requestID: "req-gateway-replay",
            resource: .init(type: "terminal", id: "terminal-1", generation: 1),
            payload: AnyEncodable(["command_length": 3])
        )
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
        defer { Darwin.close(clientFD) }

        let request = Data(#"{"request_id":"req-gateway-subscribe","command":"events.subscribe","since_sequence":0,"event_limit":2}"#.utf8)
        try ControlHarnessSocketSupport.writeAll(request, to: clientFD)
        guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let decoder = JSONDecoder()
        let ackLine = try ControlHarnessSocketSupport.readLine(from: clientFD)
        let ack = try decoder.decode(ControlHarnessSubscriptionAckEnvelope.self, from: ackLine)
        #expect(ack.status == "ok")
        #expect(ack.requestID == "req-gateway-subscribe")
        #expect(ack.result?.replayedEventCount == 1)

        let replayLine = try ControlHarnessSocketSupport.readLine(from: clientFD)
        let replay = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: replayLine)
        #expect(replay.requestID == "req-gateway-replay")

        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-gateway-live",
            resource: .init(type: "terminal", id: "terminal-1", generation: 2),
            payload: AnyEncodable(["text_length": 1])
        )

        let liveLine = try ControlHarnessSocketSupport.readLine(from: clientFD)
        let live = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: liveLine)
        #expect(live.requestID == "req-gateway-live")
    }

    @Test func gatewayWebSocketHandshakeAndSnapshotRequest() async throws {
        let bundleID = "ghdx.tests.gateway-ws-snapshot"
        let gateway = await MainActor.run {
            let (core, _, _) = makeCore(bundleID: bundleID)
            return ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(isEnabled: true, listenHost: "127.0.0.1", listenPort: 0, maxBufferedEvents: 16, maxBufferedBytes: 4096),
                requestHandler: { request, socketPath in
                    .single(core.handle(request, socketPath: socketPath))
                }
            )
        }

        defer { gateway.stop() }
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        let clientFD = try ControlHarnessSocketSupport.performWebSocketHandshake(host: "127.0.0.1", port: port)
        defer { Darwin.close(clientFD) }

        try ControlHarnessSocketSupport.writeWebSocketTextFrame(
            Data(#"{"request_id":"req-ws-snapshot","command":"snapshot"}"#.utf8),
            to: clientFD
        )

        let responseData = try ControlHarnessSocketSupport.readWebSocketTextFrame(from: clientFD)
        let envelope = try JSONDecoder().decode(ControlHarnessResponseEnvelope.self, from: responseData)
        #expect(envelope.status == "ok")
        #expect(envelope.requestID == "req-ws-snapshot")
    }

    @Test func gatewayWebSocketSubscriptionStreamsReplayAndLiveEvents() async throws {
        let bundleID = "ghdx.tests.gateway-ws-subscribe"
        let (eventHub, gateway) = await MainActor.run {
            let auditLogger = ControlHarnessAuditLogger(bundleID: bundleID)
            let eventHub = makeFreshEventHub(bundleID: bundleID)
            let core = ControlHarnessCore(
                appDelegate: nil,
                auditLogger: auditLogger,
                eventHub: eventHub,
                generations: ControlHarnessGenerationTracker(),
                idempotencyStore: ControlHarnessIdempotencyStore(),
                readStore: ControlHarnessTerminalReadStore(),
                readAfterWriteStore: ControlHarnessReadAfterWriteStore(),
                sampleStore: ControlHarnessSampleStore()
            )
            let gateway = ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(isEnabled: true, listenHost: "127.0.0.1", listenPort: 0, maxBufferedEvents: 16, maxBufferedBytes: 4096),
                requestHandler: { request, socketPath in
                    if request.command == "events.subscribe" {
                        return .subscription(core.handleSubscription(request, socketPath: socketPath))
                    }
                    return .single(core.handle(request, socketPath: socketPath))
                }
            )
            return (eventHub, gateway)
        }

        defer { gateway.stop() }
        _ = eventHub.emit(
            event: "terminal.command.sent",
            requestID: "req-ws-replay",
            resource: .init(type: "terminal", id: "terminal-1", generation: 1),
            payload: AnyEncodable(["command_length": 3])
        )
        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)

        let clientFD = try ControlHarnessSocketSupport.performWebSocketHandshake(host: "127.0.0.1", port: port)
        defer { Darwin.close(clientFD) }

        try ControlHarnessSocketSupport.writeWebSocketTextFrame(
            Data(#"{"request_id":"req-ws-subscribe","command":"events.subscribe","since_sequence":0,"event_limit":2}"#.utf8),
            to: clientFD
        )

        let decoder = JSONDecoder()
        let ackData = try ControlHarnessSocketSupport.readWebSocketTextFrame(from: clientFD)
        let ack = try decoder.decode(ControlHarnessSubscriptionAckEnvelope.self, from: ackData)
        #expect(ack.status == "ok")
        #expect(ack.requestID == "req-ws-subscribe")
        #expect(ack.result?.replayedEventCount == 1)

        let replayData = try ControlHarnessSocketSupport.readWebSocketTextFrame(from: clientFD)
        let replay = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: replayData)
        #expect(replay.requestID == "req-ws-replay")

        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-ws-live",
            resource: .init(type: "terminal", id: "terminal-1", generation: 2),
            payload: AnyEncodable(["text_length": 1])
        )

        let liveData = try ControlHarnessSocketSupport.readWebSocketTextFrame(from: clientFD)
        let live = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: liveData)
        #expect(live.requestID == "req-ws-live")
    }

    @Test func gatewayStopClosesLiveTcpSubscription() async throws {
        let bundleID = "ghdx.tests.gateway-stop-stream"
        let (eventHub, gateway) = await MainActor.run {
            let auditLogger = ControlHarnessAuditLogger(bundleID: bundleID)
            let eventHub = makeFreshEventHub(bundleID: bundleID)
            let core = ControlHarnessCore(
                appDelegate: nil,
                auditLogger: auditLogger,
                eventHub: eventHub,
                generations: ControlHarnessGenerationTracker(),
                idempotencyStore: ControlHarnessIdempotencyStore(),
                readStore: ControlHarnessTerminalReadStore(),
                readAfterWriteStore: ControlHarnessReadAfterWriteStore(),
                sampleStore: ControlHarnessSampleStore()
            )
            let gateway = ControlHarnessGateway(
                bundleID: bundleID,
                configuration: .init(isEnabled: true, listenHost: "127.0.0.1", listenPort: 0, maxBufferedEvents: 16, maxBufferedBytes: 4096),
                requestHandler: { request, socketPath in
                    if request.command == "events.subscribe" {
                        return .subscription(core.handleSubscription(request, socketPath: socketPath))
                    }
                    return .single(core.handle(request, socketPath: socketPath))
                }
            )
            return (eventHub, gateway)
        }

        gateway.startIfNeeded()
        let port = try #require(gateway.listenerPort)
        let clientFD = try ControlHarnessSocketSupport.connectTCP(host: "127.0.0.1", port: port)
        defer { Darwin.close(clientFD) }

        let request = Data(#"{"request_id":"req-stop-subscribe","command":"events.subscribe","since_sequence":0,"event_limit":2}"#.utf8)
        try ControlHarnessSocketSupport.writeAll(request, to: clientFD)
        guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let decoder = JSONDecoder()
        let ackLine = try ControlHarnessSocketSupport.readLine(from: clientFD)
        let ack = try decoder.decode(ControlHarnessSubscriptionAckEnvelope.self, from: ackLine)
        #expect(ack.status == "ok")

        gateway.stop()
        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-stop-release",
            resource: .init(type: "terminal", id: "terminal-1", generation: 1),
            payload: AnyEncodable(["text_length": 1])
        )

        #expect(ControlHarnessSocketSupport.waitForDisconnect(from: clientFD, timeoutSeconds: 2.0))
    }

    @Test func eventsSubscribeStreamsReplayAndLiveEvents() async throws {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
        let bundleID = "ghdx.tests.\(suffix)"
        let (eventHub, core) = await MainActor.run {
            let auditLogger = ControlHarnessAuditLogger(bundleID: bundleID)
            let eventHub = makeFreshEventHub(bundleID: bundleID)
            let core = ControlHarnessCore(
                appDelegate: nil,
                auditLogger: auditLogger,
                eventHub: eventHub,
                generations: ControlHarnessGenerationTracker(),
                idempotencyStore: ControlHarnessIdempotencyStore(),
                readStore: ControlHarnessTerminalReadStore(),
                readAfterWriteStore: ControlHarnessReadAfterWriteStore(),
                sampleStore: ControlHarnessSampleStore()
            )
            return (eventHub, core)
        }
        let service = ControlHarnessService(
            bundleID: bundleID,
            requestHandler: { request, socketPath in
                if request.command == "events.subscribe" {
                    return .subscription(core.handleSubscription(request, socketPath: socketPath))
                }
                return .single(core.handle(request, socketPath: socketPath))
            }
        )

        let socketAddress = sockaddr_un()
        #expect(service.socketURL.path.utf8.count < MemoryLayout.size(ofValue: socketAddress.sun_path))

        let cacheRoot = service.socketURL.deletingLastPathComponent().deletingLastPathComponent()
        let supportRoot = ControlHarnessAuditLogger.baseDirectory(bundleID: bundleID)
            .deletingLastPathComponent()

        defer {
            service.stop()
            try? FileManager.default.removeItem(at: cacheRoot)
            try? FileManager.default.removeItem(at: supportRoot)
        }

        _ = eventHub.emit(
            event: "terminal.command.sent",
            requestID: "req-replay",
            resource: .init(type: "terminal", id: "terminal-1", generation: 1),
            payload: AnyEncodable(["command_length": 3])
        )

        service.startIfNeeded()

        let clientFD = try ControlHarnessSocketSupport.connect(to: service.socketURL.path)
        defer { Darwin.close(clientFD) }

        let requestData = Data(#"{"request_id":"req-subscribe","command":"events.subscribe","since_sequence":0,"event_limit":2}"#.utf8)
        try ControlHarnessSocketSupport.writeAll(requestData, to: clientFD)
        guard Darwin.shutdown(clientFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let decoder = JSONDecoder()

        let ackLine = try ControlHarnessSocketSupport.readLine(from: clientFD)
        let ack = try decoder.decode(ControlHarnessSubscriptionAckEnvelope.self, from: ackLine)
        #expect(ack.status == "ok")
        #expect(ack.requestID == "req-subscribe")
        #expect(ack.result?.replayedEventCount == 1)
        #expect(ack.result?.liveStreamOpen == true)

        let replayLine = try ControlHarnessSocketSupport.readLine(from: clientFD)
        let replayEvent = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: replayLine)
        #expect(replayEvent.event == "terminal.command.sent")
        #expect(replayEvent.requestID == "req-replay")

        _ = eventHub.emit(
            event: "terminal.input.sent",
            requestID: "req-live",
            resource: .init(type: "terminal", id: "terminal-1", generation: 2),
            payload: AnyEncodable(["text_length": 1])
        )

        let liveLine = try ControlHarnessSocketSupport.readLine(from: clientFD)
        let liveEvent = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: liveLine)
        #expect(liveEvent.event == "terminal.input.sent")
        #expect(liveEvent.requestID == "req-live")

        let trailing = try ControlHarnessSocketSupport.readLine(from: clientFD)
        #expect(trailing.isEmpty)
    }

    @Test func eventsSubscribeKeepsServiceResponsiveWhileStreamIsOpen() async throws {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
        let bundleID = "ghdx.tests.\(suffix)"
        let (eventHub, core) = await MainActor.run {
            let auditLogger = ControlHarnessAuditLogger(bundleID: bundleID)
            let eventHub = makeFreshEventHub(bundleID: bundleID)
            let core = ControlHarnessCore(
                appDelegate: nil,
                auditLogger: auditLogger,
                eventHub: eventHub,
                generations: ControlHarnessGenerationTracker(),
                idempotencyStore: ControlHarnessIdempotencyStore(),
                readStore: ControlHarnessTerminalReadStore(),
                readAfterWriteStore: ControlHarnessReadAfterWriteStore(),
                sampleStore: ControlHarnessSampleStore()
            )
            return (eventHub, core)
        }
        let service = ControlHarnessService(
            bundleID: bundleID,
            requestHandler: { request, socketPath in
                if request.command == "events.subscribe" {
                    return .subscription(core.handleSubscription(request, socketPath: socketPath))
                }
                return .single(core.handle(request, socketPath: socketPath))
            }
        )

        let cacheRoot = service.socketURL.deletingLastPathComponent().deletingLastPathComponent()
        let supportRoot = ControlHarnessAuditLogger.baseDirectory(bundleID: bundleID)
            .deletingLastPathComponent()

        defer {
            service.stop()
            try? FileManager.default.removeItem(at: cacheRoot)
            try? FileManager.default.removeItem(at: supportRoot)
        }

        _ = eventHub.emit(
            event: "terminal.command.sent",
            requestID: "req-replay",
            resource: .init(type: "terminal", id: "terminal-1", generation: 1),
            payload: AnyEncodable(["command_length": 3])
        )

        service.startIfNeeded()

        let subscribeFD = try ControlHarnessSocketSupport.connect(to: service.socketURL.path)
        defer { Darwin.close(subscribeFD) }

        let subscribeRequest = Data(#"{"request_id":"req-subscribe-open","command":"events.subscribe","since_sequence":0,"event_limit":2}"#.utf8)
        try ControlHarnessSocketSupport.writeAll(subscribeRequest, to: subscribeFD)
        guard Darwin.shutdown(subscribeFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let decoder = JSONDecoder()
        let ackLine = try ControlHarnessSocketSupport.readLine(from: subscribeFD)
        let ack = try decoder.decode(ControlHarnessSubscriptionAckEnvelope.self, from: ackLine)
        #expect(ack.status == "ok")
        #expect(ack.result?.replayedEventCount == 1)

        let replayLine = try ControlHarnessSocketSupport.readLine(from: subscribeFD)
        let replayEvent = try decoder.decode(ControlHarnessDecodedEventRecord.self, from: replayLine)
        #expect(replayEvent.requestID == "req-replay")

        let handshakeFD = try ControlHarnessSocketSupport.connect(to: service.socketURL.path)
        defer { Darwin.close(handshakeFD) }

        let handshakeRequest = Data(#"{"request_id":"req-handshake-open","command":"handshake"}"#.utf8)
        try ControlHarnessSocketSupport.writeAll(handshakeRequest, to: handshakeFD)
        guard Darwin.shutdown(handshakeFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        let handshakeData = try ControlHarnessSocketSupport.readAll(from: handshakeFD)
        let handshake = try decoder.decode(ControlHarnessHandshakeEnvelope.self, from: handshakeData)
        #expect(handshake.status == "ok")
        #expect(handshake.requestID == "req-handshake-open")
        #expect(handshake.result?.protocolVersion == ControlHarnessCore.protocolVersion)
        #expect(handshake.result?.lastSequence == 1)
    }
}
