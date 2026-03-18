import Darwin
import Foundation
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

    static func readLine(from fd: Int32) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            let amount = Darwin.read(fd, &byte, 1)
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
            if errno == EINTR {
                continue
            }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
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
}

struct ControlHarnessTests {
    @MainActor
    private final class RecordingAppDelegate: AppDelegate {
        var executedCommands: [(terminalID: UUID, command: String)] = []

        override func controlHarnessRunCommand(_ command: String, to terminalID: UUID) -> Bool {
            executedCommands.append((terminalID, command))
            return true
        }
    }

    @Test @MainActor func runCommandUsesDedicatedExecutionPath() {
        let delegate = RecordingAppDelegate()
        let bundleID = "ghdx.tests.run-command"
        let core = ControlHarnessCore(
            appDelegate: delegate,
            auditLogger: ControlHarnessAuditLogger(bundleID: bundleID),
            eventHub: ControlHarnessEventHub(bundleID: bundleID),
            generations: ControlHarnessGenerationTracker(),
            idempotencyStore: ControlHarnessIdempotencyStore(),
            readStore: ControlHarnessTerminalReadStore(),
            readAfterWriteStore: ControlHarnessReadAfterWriteStore()
        )
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

    @Test func eventsSubscribeStreamsReplayAndLiveEvents() async throws {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
        let bundleID = "ghdx.tests.\(suffix)"
        let (eventHub, core) = await MainActor.run {
            let auditLogger = ControlHarnessAuditLogger(bundleID: bundleID)
            let eventHub = ControlHarnessEventHub(bundleID: bundleID)
            let core = ControlHarnessCore(
                appDelegate: nil,
                auditLogger: auditLogger,
                eventHub: eventHub,
                generations: ControlHarnessGenerationTracker(),
                idempotencyStore: ControlHarnessIdempotencyStore(),
                readStore: ControlHarnessTerminalReadStore(),
                readAfterWriteStore: ControlHarnessReadAfterWriteStore()
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
            let eventHub = ControlHarnessEventHub(bundleID: bundleID)
            let core = ControlHarnessCore(
                appDelegate: nil,
                auditLogger: auditLogger,
                eventHub: eventHub,
                generations: ControlHarnessGenerationTracker(),
                idempotencyStore: ControlHarnessIdempotencyStore(),
                readStore: ControlHarnessTerminalReadStore(),
                readAfterWriteStore: ControlHarnessReadAfterWriteStore()
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
