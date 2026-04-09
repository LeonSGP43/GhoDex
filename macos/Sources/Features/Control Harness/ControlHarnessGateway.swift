import Darwin
import CryptoKit
import Foundation
import OSLog

// swiftlint:disable:next type_name
private struct ControlHarnessGatewayRegisteredDevicePayload: Encodable {
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

// swiftlint:disable:next type_name
private struct ControlHarnessGatewayRegisteredDeviceListPayload: Encodable {
    let devices: [ControlHarnessGatewayRegisteredDevicePayload]
}

private struct ControlHarnessGatewayDesktopRoutePayload: Encodable {
    let desktopID: String
    let desktopLabel: String
    let upstreamHost: String
    let upstreamPort: UInt16
    let source: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case desktopID = "desktop_id"
        case desktopLabel = "desktop_label"
        case upstreamHost = "upstream_host"
        case upstreamPort = "upstream_port"
        case source
        case updatedAt = "updated_at"
    }
}

// swiftlint:disable:next type_name
private struct ControlHarnessGatewayDesktopRouteListPayload: Encodable {
    let desktops: [ControlHarnessGatewayDesktopRoutePayload]
}

// swiftlint:disable:next type_name
private struct ControlHarnessGatewayRouteRegistrationPayload: Encodable {
    let desktopID: String
    let desktopLabel: String
    let upstreamHost: String
    let upstreamPort: UInt16
    let registered: Bool

    enum CodingKeys: String, CodingKey {
        case desktopID = "desktop_id"
        case desktopLabel = "desktop_label"
        case upstreamHost = "upstream_host"
        case upstreamPort = "upstream_port"
        case registered
    }
}

private struct ControlHarnessGatewayPingPayload: Codable {
    let component: String
    let supportsDesktopRouting: Bool
    let listenerPort: UInt16?
    let desktopID: String?
    let desktopLabel: String?

    enum CodingKeys: String, CodingKey {
        case component
        case supportsDesktopRouting = "supports_desktop_routing"
        case listenerPort = "listener_port"
        case desktopID = "desktop_id"
        case desktopLabel = "desktop_label"
    }
}

// swiftlint:disable:next type_name
private struct ControlHarnessGatewayLocalCommandEnvelope: Decodable {
    let status: String
    let errorCode: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case status
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

// swiftlint:disable:next type_name
private struct ControlHarnessGatewayLocalCommandResultEnvelope<Result: Decodable>: Decodable {
    let status: String
    let errorCode: String?
    let errorMessage: String?
    let result: Result?

    enum CodingKeys: String, CodingKey {
        case status
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case result
    }
}

private enum ControlHarnessGatewayDeviceRegistryError: LocalizedError {
    case invalidDeviceID
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .invalidDeviceID:
            return "A valid device_id is required"
        case .deviceNotFound:
            return "The requested device is not registered"
        }
    }
}

private enum ControlHarnessGatewayRouteRegistryError: LocalizedError {
    case invalidDesktopID
    case invalidUpstreamHost
    case invalidUpstreamPort
    case nonLoopbackUpstreamHost
    case upstreamProbeFailed
    case upstreamDesktopIDMismatch

    var errorDescription: String? {
        switch self {
        case .invalidDesktopID:
            return "A valid desktop_id is required"
        case .invalidUpstreamHost:
            return "A valid upstream_host is required"
        case .invalidUpstreamPort:
            return "A valid upstream_port is required"
        case .nonLoopbackUpstreamHost:
            return "upstream_host must be a local loopback address"
        case .upstreamProbeFailed:
            return "Unable to verify upstream gateway route target"
        case .upstreamDesktopIDMismatch:
            return "upstream gateway desktop identity does not match desktop_id"
        }
    }
}

final class ControlHarnessGateway {
    private enum GatewayCommand {
        case pairingBegin
        case pairingExchange
        case tokenInfo
        case tokenRotate
        case tokenRevoke
        case devicesList
        case devicesRevoke
        case metrics
        case metricsReset
        case instancePing
        case desktopRegister
        case desktopUnregister
        case desktopsList
    }

    struct Configuration: Sendable, Equatable {
        var isEnabled = false
        var listenHost = "127.0.0.1"
        var listenPort: UInt16 = 0
        var publicEndpoint: String?
        var maxBufferedEvents = 256
        var maxBufferedBytes = 1_048_576
        var authToken: String?
        var maxConcurrentSessionsPerIdentity = 2
        var maxGlobalRequestsPerMinute = 240
        var maxCommandsPerMinute = 60
        var maxInputEventsPerMinute = 6_000
        var maxSnapshotRequestsPerMinute = 30
        var maxResyncAttemptsPerMinute = 1_800
        var semanticProfile: ControlHarnessSemanticProfile = .defaultValue

        static func environment(
            _ environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Self {
            var configuration = Self()

            if let value = parseBool(environment["GHODEX_CONTROL_HARNESS_GATEWAY_ENABLED"]) {
                configuration.isEnabled = value
            }
            if let value = parseString(environment["GHODEX_CONTROL_HARNESS_GATEWAY_HOST"]) {
                configuration.listenHost = value
            }
            if let value = parseUInt16(environment["GHODEX_CONTROL_HARNESS_GATEWAY_PORT"]) {
                configuration.listenPort = value
            }
            if let value = parseString(environment["GHODEX_CONTROL_HARNESS_GATEWAY_PUBLIC_ENDPOINT"]) {
                configuration.publicEndpoint = value
            }
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_BUFFERED_EVENTS"]) {
                configuration.maxBufferedEvents = max(1, value)
            }
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_BUFFERED_BYTES"]) {
                configuration.maxBufferedBytes = max(1, value)
            }
            if let value = parseString(environment["GHODEX_CONTROL_HARNESS_GATEWAY_AUTH_TOKEN"]) {
                configuration.authToken = value
            }
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_CONCURRENT_SESSIONS_PER_IDENTITY"]) {
                configuration.maxConcurrentSessionsPerIdentity = max(1, value)
            }
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_GLOBAL_REQUESTS_PER_MINUTE"]) {
                configuration.maxGlobalRequestsPerMinute = max(1, value)
            }
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_COMMANDS_PER_MINUTE"]) {
                configuration.maxCommandsPerMinute = max(1, value)
            }
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_INPUT_EVENTS_PER_MINUTE"]) {
                configuration.maxInputEventsPerMinute = max(1, value)
            }
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_SNAPSHOT_REQUESTS_PER_MINUTE"]) {
                configuration.maxSnapshotRequestsPerMinute = max(1, value)
            }
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_RESYNC_ATTEMPTS_PER_MINUTE"]) {
                configuration.maxResyncAttemptsPerMinute = max(1, value)
            }
            if let value = parseString(environment["GHODEX_CONTROL_HARNESS_SEMANTIC_PROFILE"]) {
                configuration.semanticProfile = ControlHarnessSemanticProfile.parse(value)
            }

            return configuration
        }

        private static func parseString(_ rawValue: String?) -> String? {
            guard let rawValue else { return nil }
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            return trimmed
        }

        private static func parseBool(_ rawValue: String?) -> Bool? {
            guard let normalized = parseString(rawValue)?.lowercased() else { return nil }
            switch normalized {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        }

        private static func parseUInt16(_ rawValue: String?) -> UInt16? {
            guard let normalized = parseString(rawValue) else { return nil }
            return UInt16(normalized)
        }

        private static func parseInt(_ rawValue: String?) -> Int? {
            guard let normalized = parseString(rawValue) else { return nil }
            return Int(normalized)
        }
    }

    enum RequestAuthorization {
        case allow
        case deny(errorCode: String, errorMessage: String)
    }

    private enum AuthorizationResult {
        case allow(sessionIdentity: String?)
        case deny(ControlHarnessResponse)
    }

    private enum RouteDecision {
        case local
        case proxy(DesktopRoute)
        case notFound
    }

    private struct ActiveStream {
        let sessionIdentity: String?
        let command: String
        let startedAt: Date
        let close: @Sendable () -> Void
    }

    private struct DesktopRoute: Sendable {
        let desktopID: String
        let desktopLabel: String
        let upstreamHost: String
        let upstreamPort: UInt16
        let source: String
        let updatedAt: Date
    }

    private struct PassiveGatewayRegistration: Sendable {
        let desktopID: String
        let desktopLabel: String
        let ownerHost: String
        let ownerPort: UInt16
        let upstreamHost: String
        let upstreamPort: UInt16
    }

    private struct LocalGatewayCommandRequest: Encodable {
        let requestID: String
        let command: String
        let desktopID: String?
        let desktopLabel: String?
        let upstreamHost: String?
        let upstreamPort: UInt16?

        enum CodingKeys: String, CodingKey {
            case requestID = "request_id"
            case command
            case desktopID = "desktop_id"
            case desktopLabel = "desktop_label"
            case upstreamHost = "upstream_host"
            case upstreamPort = "upstream_port"
        }
    }

    private let bundleID: String
    private let authManager: ControlHarnessAuth?
    private let requestHandler: (@MainActor (ControlHarnessRequest, String) -> ControlHarnessServiceReply)?
    private let requestAuthorizer: (@MainActor (ControlHarnessRequest) -> RequestAuthorization)?
    private var rateLimiter: ControlHarnessGatewayRateLimiter
    private var sessionRegistry: ControlHarnessGatewaySessionRegistry
    private let performanceMonitor: ControlHarnessPerformanceMonitor?
    private let logger: Logger
    private let lifecycleQueue = DispatchQueue(
        label: "com.leongong.ghodex.control-harness.gateway.lifecycle",
        qos: .utility
    )
    private let acceptQueue = DispatchQueue(
        label: "com.leongong.ghodex.control-harness.gateway.accept",
        qos: .userInitiated
    )
    private let clientQueue = DispatchQueue(
        label: "com.leongong.ghodex.control-harness.gateway.client",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let outboundQueue = DispatchQueue(
        label: "com.leongong.ghodex.control-harness.gateway.outbound",
        qos: .utility,
        attributes: .concurrent
    )
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private(set) var configuration: Configuration
    private(set) var listenerPort: UInt16?
    private(set) var lastStartupError: String?

    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var activeStreams: [UUID: ActiveStream] = [:]
    private var activeStreamIDsByIdentity: [String: Set<UUID>] = [:]
    private var desktopRoutesByID: [String: DesktopRoute] = [:]
    private var passiveRegistration: PassiveGatewayRegistration?
    private var pendingPassiveRegistration: PassiveGatewayRegistration?

    init(
        bundleID: String,
        configuration: Configuration = .init(),
        authManager: ControlHarnessAuth? = nil,
        requestHandler: (@MainActor (ControlHarnessRequest, String) -> ControlHarnessServiceReply)? = nil,
        requestAuthorizer: (@MainActor (ControlHarnessRequest) -> RequestAuthorization)? = nil,
        performanceMonitor: ControlHarnessPerformanceMonitor? = nil
    ) {
        self.bundleID = bundleID
        self.authManager = authManager
        self.requestHandler = requestHandler
        self.requestAuthorizer = requestAuthorizer
        self.rateLimiter = ControlHarnessGatewayRateLimiter(configuration: configuration)
        self.sessionRegistry = ControlHarnessGatewaySessionRegistry(
            maxConcurrentSessionsPerIdentity: configuration.maxConcurrentSessionsPerIdentity
        )
        self.performanceMonitor = performanceMonitor
        self.logger = Logger(subsystem: bundleID, category: "ControlHarnessGateway")
        self.configuration = configuration
    }

    func makeClientSession(id: UUID = UUID()) -> ControlHarnessGatewayClientSession {
        ControlHarnessGatewayClientSession(
            id: id,
            limits: .init(
                maxBufferedEvents: configuration.maxBufferedEvents,
                maxBufferedBytes: configuration.maxBufferedBytes
            )
        )
    }

    func attachSubscription(
        _ envelope: ControlHarnessSubscriptionEnvelope,
        to clientSession: ControlHarnessGatewayClientSession
    ) -> ControlHarnessGatewaySubscription {
        let liveSession = envelope.session
        let subscriberID = liveSession?.addSubscriber(
            sink: { data in
                _ = clientSession.enqueueEvent(data)
                return true
            },
            onFinish: {
                clientSession.close()
            }
        )

        if let responseData = try? encodeResponse(envelope.response) {
            _ = clientSession.enqueueEvent(responseData)
        }

        if let liveSession {
            for event in liveSession.replayEvents {
                _ = clientSession.enqueueEvent(event)
            }
            liveSession.completeReplay()
        } else {
            clientSession.close()
        }

        return ControlHarnessGatewaySubscription(
            subscriptionSession: liveSession,
            subscriberID: subscriberID
        )
    }

    func startIfNeeded() {
        guard configuration.isEnabled else {
            lastStartupError = nil
            logger.debug("control harness gateway transport is disabled")
            return
        }
        guard listenerFD == -1 else { return }

        do {
            let requestedPort = configuration.listenPort
            let listener = try makeListenerWithPortConflictRouting(
                host: configuration.listenHost,
                requestedPort: requestedPort
            )
            listenerFD = listener.fd
            listenerPort = listener.port
            lastStartupError = nil
            let source = DispatchSource.makeReadSource(fileDescriptor: listener.fd, queue: acceptQueue)
            source.setEventHandler { [weak self] in
                self?.acceptAvailableConnections()
            }
            source.setCancelHandler { [listenerFD = listener.fd] in
                if listenerFD >= 0 {
                    Darwin.close(listenerFD)
                }
            }
            source.resume()
            acceptSource = source
            registerPendingPassiveRouteIfNeeded()
            if requestedPort > 0, listener.port != requestedPort {
                if let passive = passiveRegistration {
                    logger.notice(
                        "control harness gateway running in passive mode on \(listener.port); owner \(passive.ownerHost, privacy: .public):\(passive.ownerPort)"
                    )
                } else {
                    logger.notice(
                        "control harness gateway port \(requestedPort) was unavailable; recovered on \(listener.port)"
                    )
                }
            }
            logger.notice(
                "control harness gateway listening at \(self.configuration.listenHost, privacy: .public):\(listener.port)"
            )
        } catch {
            lastStartupError = error.localizedDescription
            logger.error("failed to start control harness gateway: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    func applyConfiguration(_ configuration: Configuration) {
        stop()
        self.configuration = configuration
        self.rateLimiter = ControlHarnessGatewayRateLimiter(configuration: configuration)
        self.sessionRegistry = ControlHarnessGatewaySessionRegistry(
            maxConcurrentSessionsPerIdentity: configuration.maxConcurrentSessionsPerIdentity
        )
        self.lastStartupError = nil
        startIfNeeded()
    }

    func stop() {
        pendingPassiveRegistration = nil
        unregisterPassiveRouteIfNeeded()

        let activeStreams = lifecycleQueue.sync {
            let streams = Array(self.activeStreams.values)
            self.activeStreams.removeAll()
            self.activeStreamIDsByIdentity.removeAll()
            self.desktopRoutesByID.removeAll()
            return streams
        }
        for stream in activeStreams {
            stream.close()
        }

        if let acceptSource {
            self.acceptSource = nil
            acceptSource.cancel()
            listenerFD = -1
            listenerPort = nil
            return
        }

        if listenerFD >= 0 {
            Darwin.close(listenerFD)
            listenerFD = -1
        }
        listenerPort = nil
        outboundQueue.async {}
    }

    private func makeListenerWithPortConflictRouting(
        host: String,
        requestedPort: UInt16
    ) throws -> (fd: Int32, port: UInt16) {
        do {
            return try makeListener(host: host, port: requestedPort)
        } catch let error as POSIXError
            where error.code == .EADDRINUSE && requestedPort > 0 {
            do {
                if let passiveListener = try makePassiveListenerRegisteringToExistingGateway(
                    host: host,
                    requestedPort: requestedPort
                ) {
                    return passiveListener
                }
            } catch {
                logger.debug("port conflict owner probe failed, using fallback listener recovery: \(error.localizedDescription, privacy: .public)")
            }

            for candidatePort in Self.portConflictRecoveryCandidates(startingAt: requestedPort) {
                do {
                    return try makeListener(host: host, port: candidatePort)
                } catch let candidateError as POSIXError where candidateError.code == .EADDRINUSE {
                    continue
                }
            }

            return try makeListener(host: host, port: 0)
        }
    }

    private func makePassiveListenerRegisteringToExistingGateway(
        host: String,
        requestedPort: UInt16
    ) throws -> (fd: Int32, port: UInt16)? {
        guard let desktopIdentity = currentDesktopIdentity() else {
            return nil
        }

        let ownerHost = Self.localProbeHost(from: host)
        let supportsRouting = try waitForGatewayOwnerRoutingSupport(
            host: ownerHost,
            port: requestedPort
        )
        guard supportsRouting else {
            return nil
        }

        let listener = try makeListener(host: host, port: 0)
        let registration = PassiveGatewayRegistration(
            desktopID: desktopIdentity.desktopID,
            desktopLabel: desktopIdentity.desktopLabel,
            ownerHost: ownerHost,
            ownerPort: requestedPort,
            upstreamHost: Self.localProbeHost(from: host),
            upstreamPort: listener.port
        )

        pendingPassiveRegistration = registration
        return listener
    }

    private func gatewayOwnerSupportsDesktopRouting(
        host: String,
        port: UInt16
    ) throws -> Bool {
        let payload = try queryGatewayPingPayload(host: host, port: port)
        return payload.supportsDesktopRouting
    }

    private func waitForGatewayOwnerRoutingSupport(
        host: String,
        port: UInt16
    ) throws -> Bool {
        let deadline = Date().addingTimeInterval(0.5)
        var lastError: Error?

        repeat {
            do {
                return try gatewayOwnerSupportsDesktopRouting(host: host, port: port)
            } catch {
                guard Self.shouldRetryLocalGatewayCommand(error) else {
                    throw error
                }
                lastError = error
                Thread.sleep(forTimeInterval: 0.01)
            }
        } while Date() < deadline

        if let lastError {
            throw lastError
        }
        return false
    }

    private func queryGatewayPingPayload(
        host: String,
        port: UInt16
    ) throws -> ControlHarnessGatewayPingPayload {
        let request = LocalGatewayCommandRequest(
            requestID: "gateway-owner-ping-\(UUID().uuidString.lowercased())",
            command: "gateway.instance.ping",
            desktopID: nil,
            desktopLabel: nil,
            upstreamHost: nil,
            upstreamPort: nil
        )
        let envelope = try Self.sendLocalGatewayCommandResult(
            request,
            host: host,
            port: port,
            payloadType: ControlHarnessGatewayPingPayload.self
        )
        guard envelope.status == "ok", let payload = envelope.result else {
            throw ControlHarnessGatewayRouteRegistryError.upstreamProbeFailed
        }
        return payload
    }

    private func registerPassiveRoute(_ registration: PassiveGatewayRegistration) throws {
        let request = LocalGatewayCommandRequest(
            requestID: "gateway-route-register-\(UUID().uuidString.lowercased())",
            command: "gateway.desktop.register",
            desktopID: registration.desktopID,
            desktopLabel: registration.desktopLabel,
            upstreamHost: registration.upstreamHost,
            upstreamPort: registration.upstreamPort
        )
        let envelope = try Self.sendLocalGatewayCommandEnvelope(
            request,
            host: registration.ownerHost,
            port: registration.ownerPort
        )
        guard envelope.status == "ok" else {
            throw POSIXError(.ECONNREFUSED)
        }
    }

    private func registerPassiveRouteWithRetry(_ registration: PassiveGatewayRegistration) throws {
        let deadline = Date().addingTimeInterval(0.5)
        var lastError: Error?

        repeat {
            do {
                try registerPassiveRoute(registration)
                return
            } catch {
                guard Self.shouldRetryLocalGatewayCommand(error) else {
                    throw error
                }
                lastError = error
                Thread.sleep(forTimeInterval: 0.01)
            }
        } while Date() < deadline

        if let lastError {
            throw lastError
        }
    }

    private func registerPendingPassiveRouteIfNeeded() {
        guard let registration = pendingPassiveRegistration else {
            return
        }

        do {
            try registerPassiveRouteWithRetry(registration)
            passiveRegistration = registration
            pendingPassiveRegistration = nil
        } catch {
            pendingPassiveRegistration = nil
            logger.error("failed to register passive desktop route: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func unregisterPassiveRouteIfNeeded() {
        guard let registration = passiveRegistration else {
            return
        }
        passiveRegistration = nil

        do {
            let request = LocalGatewayCommandRequest(
                requestID: "gateway-route-unregister-\(UUID().uuidString.lowercased())",
                command: "gateway.desktop.unregister",
                desktopID: registration.desktopID,
                desktopLabel: nil,
                upstreamHost: nil,
                upstreamPort: nil
            )
            _ = try Self.sendLocalGatewayCommandEnvelope(
                request,
                host: registration.ownerHost,
                port: registration.ownerPort
            )
        } catch {
            logger.debug("passive desktop route unregister skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func sendLocalGatewayCommandData(
        _ request: LocalGatewayCommandRequest,
        host: String,
        port: UInt16
    ) throws -> Data {
        let fd = try connectTCP(host: host, port: port)
        defer { Darwin.close(fd) }

        try setBlocking(fd)
        try setNoDelay(fd)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(request)
        try writeAll(payload, to: fd)
        guard Darwin.shutdown(fd, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        return try readAll(from: fd)
    }

    private static func sendLocalGatewayCommandEnvelope(
        _ request: LocalGatewayCommandRequest,
        host: String,
        port: UInt16
    ) throws -> ControlHarnessGatewayLocalCommandEnvelope {
        let responseData = try sendLocalGatewayCommandData(
            request,
            host: host,
            port: port
        )
        return try JSONDecoder().decode(ControlHarnessGatewayLocalCommandEnvelope.self, from: responseData)
    }

    private static func sendLocalGatewayCommandResult<ResultPayload: Decodable>(
        _ request: LocalGatewayCommandRequest,
        host: String,
        port: UInt16,
        payloadType: ResultPayload.Type
    ) throws -> ControlHarnessGatewayLocalCommandResultEnvelope<ResultPayload> {
        _ = payloadType
        let responseData = try sendLocalGatewayCommandData(
            request,
            host: host,
            port: port
        )
        return try JSONDecoder()
            .decode(ControlHarnessGatewayLocalCommandResultEnvelope<ResultPayload>.self, from: responseData)
    }

    private func acceptAvailableConnections() {
        while true {
            let clientFD = Darwin.accept(listenerFD, nil, nil)
            if clientFD == -1 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }
                logger.error("failed to accept control harness gateway connection: \(String(cString: strerror(errno)), privacy: .public)")
                return
            }

            do {
                try Self.setBlocking(clientFD)
                try Self.setNoDelay(clientFD)
            } catch {
                logger.error("failed to configure control harness gateway client socket: \(error.localizedDescription, privacy: .public)")
                Darwin.close(clientFD)
                continue
            }

            clientQueue.async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ clientFD: Int32) {
        defer { Darwin.close(clientFD) }
        let peerDescription = Self.peerDescription(for: clientFD)
        let started = DispatchTime.now()
        var requestCommand = "unknown"
        var requestRecorded = false

        do {
            try Self.setBlocking(clientFD)
            try? Self.setNoDelay(clientFD)
            let initialData = try Self.readInitialClientData(from: clientFD)
            if Self.looksLikeWebSocketHandshake(initialData) {
                try handleWebSocketClient(
                    clientFD,
                    peerDescription: peerDescription,
                    initialData: initialData
                )
                return
            }

            var requestData = initialData
            requestData.append(try Self.readAll(from: clientFD))
            if let proxied = try proxyRawRequestIfNeeded(requestData) {
                requestCommand = proxied.command
                try Self.writeAll(proxied.responseData, to: clientFD)
                recordRequestIfNeeded()
                return
            }
            let decoded = try decodeGatewayRequest(from: requestData)
            let request = decoded.request
            let transportSharedSecret = decoded.transportSharedSecret
            requestCommand = request.normalizedCommand

            func recordRequestIfNeeded() {
                guard !requestRecorded else { return }
                requestRecorded = true
                performanceMonitor?.recordGatewayRequest(
                    command: requestCommand,
                    transport: "tcp",
                    durationMs: Self.elapsedMilliseconds(since: started)
                )
            }

            switch authorize(request, peerDescription: peerDescription) {
            case .deny(let response):
                try Self.writeAll(try encodeResponse(response, transportSharedSecret: transportSharedSecret), to: clientFD)
                recordRequestIfNeeded()
                return
            case .allow(let sessionIdentity):
                try withSessionReservation(
                    request: request,
                    peerDescription: peerDescription,
                    sessionIdentity: sessionIdentity,
                    responseWriter: { response in
                        try Self.writeAll(
                            try encodeResponse(response, transportSharedSecret: transportSharedSecret),
                            to: clientFD
                        )
                        recordRequestIfNeeded()
                    },
                    operation: {
                    let reply = handleGatewayCommand(request).map(ControlHarnessServiceReply.single)
                        ?? callRequestHandler(request)
                    switch reply {
                    case .single(let response):
                        try Self.writeAll(
                            try encodeResponse(response, transportSharedSecret: transportSharedSecret),
                            to: clientFD
                        )
                        recordRequestIfNeeded()
                    case .subscription(let envelope):
                        try streamSubscription(
                            envelope,
                            command: request.normalizedCommand,
                            to: clientFD,
                            transport: "tcp",
                            closeReason: "client_disconnect",
                            transportSharedSecret: transportSharedSecret,
                            sessionIdentity: sessionIdentity
                        )
                    }
                    }
                )
            }
        } catch {
            logger.error("failed to process control harness gateway client: \(error.localizedDescription, privacy: .public)")
            let fallback = ControlHarnessResponse(
                requestID: "unknown",
                status: "error",
                result: nil,
                errorCode: "decode_failure",
                errorMessage: error.localizedDescription
            )
            if let data = try? encodeResponse(fallback) {
                try? Self.writeAll(data, to: clientFD)
            }
            if !requestRecorded {
                performanceMonitor?.recordGatewayRequest(
                    command: requestCommand,
                    transport: "tcp",
                    durationMs: Self.elapsedMilliseconds(since: started)
                )
            }
        }
    }

    private func handleWebSocketClient(
        _ clientFD: Int32,
        peerDescription: String,
        initialData: Data = Data()
    ) throws {
        let handshake = try Self.readHTTPHeaders(from: clientFD, initialData: initialData)
        if let requestedDesktopID = Self.parseRequestedDesktopID(fromWebSocketHandshake: handshake.headers) {
            switch resolveRouteDecision(for: requestedDesktopID) {
            case .local:
                break
            case .proxy(let route):
                var initialData = handshake.headers
                initialData.append(handshake.remainder)
                do {
                    try proxyWebSocketClient(
                        clientFD,
                        initialData: initialData,
                        route: route
                    )
                } catch {
                    evictDesktopRoute(
                        route.desktopID,
                        reason: "websocket handshake proxy failed: \(error.localizedDescription)"
                    )
                    try Self.writeAll(Self.httpBadGatewayResponse(), to: clientFD)
                }
                return
            case .notFound:
                try Self.writeAll(Self.httpNotFoundResponse(), to: clientFD)
                return
            }
        }

        let key = try Self.parseWebSocketKey(from: handshake.headers)
        try Self.writeAll(Self.webSocketHandshakeResponse(for: key), to: clientFD)

        var bufferedBytes = handshake.remainder
        while true {
            let requestStarted = DispatchTime.now()
            let requestData = try Self.readWebSocketFrame(from: clientFD, bufferedBytes: &bufferedBytes)
            if requestData.isEmpty {
                return
            }

            let decoded = try decodeGatewayRequest(from: requestData)
            let request = decoded.request
            let transportSharedSecret = decoded.transportSharedSecret
            var requestRecorded = false
            var shouldCloseAfterRequest = false

            func recordRequestIfNeeded() {
                guard !requestRecorded else { return }
                requestRecorded = true
                performanceMonitor?.recordGatewayRequest(
                    command: request.normalizedCommand,
                    transport: "websocket",
                    durationMs: Self.elapsedMilliseconds(since: requestStarted)
                )
            }

            if transportSharedSecret == nil,
               let proxiedResponse = try proxyWebSocketRequestIfNeeded(
                rawRequestData: requestData,
                request: request
               ) {
                try Self.writeAll(proxiedResponse, to: clientFD)
                recordRequestIfNeeded()
                continue
            }

            switch authorize(request, peerDescription: peerDescription) {
            case .deny(let response):
                try Self.writeAll(
                    try encodeWebSocketResponse(response, transportSharedSecret: transportSharedSecret),
                    to: clientFD
                )
                recordRequestIfNeeded()
            case .allow(let sessionIdentity):
                try withSessionReservation(
                    request: request,
                    peerDescription: peerDescription,
                    sessionIdentity: sessionIdentity,
                    responseWriter: { response in
                        try Self.writeAll(
                            try encodeWebSocketResponse(response, transportSharedSecret: transportSharedSecret),
                            to: clientFD
                        )
                        recordRequestIfNeeded()
                    },
                    operation: {
                    let reply = handleGatewayCommand(request).map(ControlHarnessServiceReply.single)
                        ?? callRequestHandler(request)
                    switch reply {
                    case .single(let response):
                        try Self.writeAll(
                            try encodeWebSocketResponse(response, transportSharedSecret: transportSharedSecret),
                            to: clientFD
                        )
                        recordRequestIfNeeded()
                    case .subscription(let envelope):
                        recordRequestIfNeeded()
                        try streamWebSocketSubscription(
                            envelope,
                            command: request.normalizedCommand,
                            to: clientFD,
                            transport: "websocket",
                            closeReason: "client_disconnect",
                            transportSharedSecret: transportSharedSecret,
                            sessionIdentity: sessionIdentity
                        )
                        shouldCloseAfterRequest = true
                    }
                }
                )
            }

            if shouldCloseAfterRequest {
                return
            }
        }
    }

    private func decodeGatewayRequest(
        from requestData: Data
    ) throws -> (request: ControlHarnessRequest, transportSharedSecret: String?) {
        let request = try JSONDecoder().decode(ControlHarnessRequest.self, from: requestData)
        guard request.command == "gateway.encrypted" else {
            return (request, nil)
        }
        guard let authManager else {
            throw ControlHarnessAuthError.invalidToken
        }
        guard let authToken = request.authToken,
              let encryptedPayload = request.encryptedPayload else {
            throw ControlHarnessGatewaySecureChannelError.invalidEncryptedRequest
        }

        let sharedSecret: String
        switch withAuthManager(authManager, operation: {
            try await authManager.transportSharedSecret(for: authToken)
        }) {
        case .success(let secret):
            sharedSecret = secret
        case .failure:
            throw ControlHarnessAuthError.invalidToken
        }

        let encryptedRequest = ControlHarnessEncryptedGatewayRequest(
            requestID: request.requestID,
            command: request.command,
            authToken: authToken,
            transportMode: request.transportMode ?? "relay",
            encryptedPayload: encryptedPayload
        )
        let decryptedRequest = try ControlHarnessGatewaySecureChannel.decryptRequest(
            encryptedRequest,
            transportSharedSecret: sharedSecret
        )
        return (decryptedRequest, sharedSecret)
    }

    private func rateLimit(
        _ request: ControlHarnessRequest,
        peerDescription: String
    ) -> ControlHarnessResponse? {
        let decision = rateLimiter.evaluate(
            request: request,
            identity: rateLimitIdentity(for: request, peerDescription: peerDescription)
        )

        switch decision {
        case .allow:
            return nil
        case .deny(let errorCode, let errorMessage):
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: errorCode,
                errorMessage: errorMessage
            )
        }
    }

    private func authorize(
        _ request: ControlHarnessRequest,
        peerDescription: String
    ) -> AuthorizationResult {
        if let routingValidation = validateDesktopRouting(request) {
            return .deny(routingValidation)
        }

        if let gatewayCommand = gatewayCommand(for: request) {
            return authorizeGatewayCommand(
                gatewayCommand,
                request: request,
                peerDescription: peerDescription
            )
        }

        if request.normalizedCommand == "handshake" {
            return .allow(sessionIdentity: nil)
        }

        if let authToken = configuration.authToken, request.authToken == authToken {
            return .allow(sessionIdentity: "static:\(authToken)")
        }

        if let requiredScope = requiredScope(for: request) {
            guard let authManager else {
                if configuration.authToken == nil {
                    return continueAuthorization(
                        request: request,
                        requestAuthorizer: requestAuthorizer,
                        sessionIdentity: nil
                    )
                }
                return .deny(ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: "unauthorized",
                    errorMessage: "A valid gateway auth token is required"
                ))
            }

            switch validateToken(
                request.authToken,
                requiredScope: requiredScope,
                authManager: authManager,
                transportMode: request.transportMode
            ) {
            case .allow(let grant):
                return continueAuthorization(
                    request: request,
                    requestAuthorizer: requestAuthorizer,
                    sessionIdentity: "paired:\(grant.subjectID)"
                )
            case .deny(let errorCode, let errorMessage):
                return .deny(ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: errorCode,
                    errorMessage: errorMessage
                ))
            }
        }

        return continueAuthorization(
            request: request,
            requestAuthorizer: requestAuthorizer,
            sessionIdentity: nil
        )
    }

    private func validateDesktopRouting(_ request: ControlHarnessRequest) -> ControlHarnessResponse? {
        if gatewayCommand(for: request) != nil {
            return nil
        }
        guard let requestedDesktopID = request.desktopID?.trimmingCharacters(in: .whitespacesAndNewlines),
              requestedDesktopID.isEmpty == false,
              let authManager else {
            return nil
        }

        let desktopIdentityResult: ControlHarnessDesktopIdentityResult
        switch withAuthManager(authManager, operation: {
            await authManager.desktopIdentityResult()
        }) {
        case .success(let result):
            desktopIdentityResult = result
        case .failure:
            return nil
        }

        guard requestedDesktopID == desktopIdentityResult.desktopID else {
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: "desktop_id_mismatch",
                errorMessage: "Gateway desktop_id does not match this desktop instance"
            )
        }

        return nil
    }

    private func continueAuthorization(
        request: ControlHarnessRequest,
        requestAuthorizer: (@MainActor (ControlHarnessRequest) -> RequestAuthorization)?,
        sessionIdentity: String?
    ) -> AuthorizationResult {
        guard let requestAuthorizer else { return .allow(sessionIdentity: sessionIdentity) }
        let authorization = syncMainActor {
            requestAuthorizer(request)
        }

        switch authorization ?? .allow {
        case .allow:
            return .allow(sessionIdentity: sessionIdentity)
        case .deny(let errorCode, let errorMessage):
            return .deny(ControlHarnessResponse(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: errorCode,
                errorMessage: errorMessage
            ))
        }
    }

    private func authorizeGatewayCommand(
        _ gatewayCommand: GatewayCommand,
        request: ControlHarnessRequest,
        peerDescription: String
    ) -> AuthorizationResult {
        switch gatewayCommand {
        case .pairingBegin:
            guard Self.isLoopbackPeer(peerDescription) else {
                return .deny(ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: "pairing_requires_local_origin",
                    errorMessage: "Pairing can only be started from a local desktop client"
                ))
            }
            return .allow(sessionIdentity: nil)

        case .pairingExchange:
            return .allow(sessionIdentity: nil)

        case .devicesList, .devicesRevoke, .metrics, .metricsReset,
                .instancePing, .desktopRegister, .desktopUnregister, .desktopsList:
            guard Self.isLoopbackPeer(peerDescription) else {
                return .deny(ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: gatewayLocalOriginErrorCode(for: gatewayCommand),
                    errorMessage: gatewayLocalOriginErrorMessage(for: gatewayCommand)
                ))
            }
            return .allow(sessionIdentity: nil)

        case .tokenInfo, .tokenRotate, .tokenRevoke:
            guard let authManager else {
                return .deny(ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: "unauthorized",
                    errorMessage: "A valid gateway auth token is required"
                ))
            }
            switch validateToken(
                request.authToken,
                requiredScope: nil,
                authManager: authManager,
                transportMode: request.transportMode
            ) {
            case .allow(let grant):
                return .allow(sessionIdentity: "paired:\(grant.subjectID)")
            case .deny(let errorCode, let errorMessage):
                return .deny(ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: errorCode,
                    errorMessage: errorMessage
                ))
            }
        }
    }

    private func gatewayLocalOriginErrorCode(for command: GatewayCommand) -> String {
        switch command {
        case .metrics, .metricsReset:
            return "metrics_requires_local_origin"
        case .devicesList, .devicesRevoke:
            return "device_registry_requires_local_origin"
        case .instancePing, .desktopRegister, .desktopUnregister, .desktopsList:
            return "desktop_route_requires_local_origin"
        case .pairingBegin:
            return "pairing_requires_local_origin"
        case .pairingExchange, .tokenInfo, .tokenRotate, .tokenRevoke:
            return "unauthorized"
        }
    }

    private func gatewayLocalOriginErrorMessage(for command: GatewayCommand) -> String {
        switch command {
        case .metrics, .metricsReset:
            return "Gateway metrics can only be requested from a local desktop client"
        case .devicesList, .devicesRevoke:
            return "Device registry commands can only be requested from a local desktop client"
        case .instancePing:
            return "Gateway instance commands can only be requested from a local desktop client"
        case .desktopRegister, .desktopUnregister, .desktopsList:
            return "Desktop route commands can only be requested from a local desktop client"
        case .pairingBegin:
            return "Pairing can only be started from a local desktop client"
        case .pairingExchange, .tokenInfo, .tokenRotate, .tokenRevoke:
            return "A valid gateway auth token is required"
        }
    }

    private func handleGatewayCommand(_ request: ControlHarnessRequest) -> ControlHarnessResponse? {
        guard let gatewayCommand = gatewayCommand(for: request) else { return nil }

        switch gatewayCommand {
        case .metrics:
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "ok",
                result: AnyEncodable(
                    performanceMonitor?.snapshot()
                        ?? ControlHarnessPerformanceSnapshot.empty()
                ),
                errorCode: nil,
                errorMessage: nil
            )
        case .metricsReset:
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "ok",
                result: AnyEncodable(
                    performanceMonitor?.reset()
                        ?? ControlHarnessPerformanceSnapshot.empty()
                ),
                errorCode: nil,
                errorMessage: nil
            )
        case .instancePing:
            let desktopIdentity = currentDesktopIdentity()
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "ok",
                result: AnyEncodable(ControlHarnessGatewayPingPayload(
                    component: "ghodex.control-harness.gateway",
                    supportsDesktopRouting: true,
                    listenerPort: listenerPort,
                    desktopID: desktopIdentity?.desktopID,
                    desktopLabel: desktopIdentity?.desktopLabel
                )),
                errorCode: nil,
                errorMessage: nil
            )
        case .desktopRegister:
            do {
                let payload = try upsertDesktopRoute(from: request, source: "local_register")
                return ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "ok",
                    result: AnyEncodable(payload),
                    errorCode: nil,
                    errorMessage: nil
                )
            } catch {
                let mapped = gatewayCommandErrorPayload(for: error)
                return ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: mapped.code,
                    errorMessage: mapped.message
                )
            }
        case .desktopUnregister:
            do {
                let payload = try removeDesktopRoute(from: request)
                return ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "ok",
                    result: AnyEncodable(payload),
                    errorCode: nil,
                    errorMessage: nil
                )
            } catch {
                let mapped = gatewayCommandErrorPayload(for: error)
                return ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: mapped.code,
                    errorMessage: mapped.message
                )
            }
        case .desktopsList:
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "ok",
                result: AnyEncodable(makeDesktopRouteListPayload()),
                errorCode: nil,
                errorMessage: nil
            )
        default:
            break
        }

        guard let authManager else {
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: "gateway_auth_unavailable",
                errorMessage: "The gateway auth manager is unavailable"
            )
        }

        let result: Result<AnyEncodable, Error> = withAuthManager(authManager) { [self] in
            switch gatewayCommand {
            case .pairingBegin:
                let pairing = try await authManager.beginPairing(
                    client: request.client,
                    requestedScopes: request.requestedScopes,
                    deviceID: request.deviceID,
                    deviceLabel: request.deviceLabel
                )
                return AnyEncodable(pairing)
            case .pairingExchange:
                guard let pairingCode = request.pairingCode?.trimmingCharacters(in: .whitespacesAndNewlines),
                      pairingCode.isEmpty == false else {
                    throw ControlHarnessAuthError.invalidPairingCode
                }
                let issued = try await authManager.exchangePairingCode(pairingCode)
                return AnyEncodable(applyPublicTransportMetadata(to: issued))
            case .tokenInfo:
                guard let token = request.authToken else {
                    throw ControlHarnessAuthError.invalidToken
                }
                return AnyEncodable(try await authManager.tokenStatus(for: token))
            case .tokenRotate:
                guard let token = request.authToken else {
                    throw ControlHarnessAuthError.invalidToken
                }
                let rotated = try await authManager.rotate(token: token)
                return AnyEncodable(applyPublicTransportMetadata(to: rotated))
            case .tokenRevoke:
                guard let token = request.authToken else {
                    throw ControlHarnessAuthError.invalidToken
                }
                return AnyEncodable(try await authManager.revoke(token: token))
            case .devicesList:
                let devices = await authManager.listDevices()
                return AnyEncodable(makeRegisteredDeviceListPayload(devices))
            case .devicesRevoke:
                guard let deviceID = request.deviceID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      deviceID.isEmpty == false else {
                    throw ControlHarnessGatewayDeviceRegistryError.invalidDeviceID
                }
                let revoked = try await authManager.revokeDevice(deviceID: deviceID)
                closeActiveStreams(identity: "paired:\(revoked.deviceID)")
                waitForSessionDrain(identity: "paired:\(revoked.deviceID)")
                return AnyEncodable(makeRegisteredDevicePayload(revoked))
            case .metrics:
                return AnyEncodable(
                    self.performanceMonitor?.snapshot()
                        ?? ControlHarnessPerformanceSnapshot.empty()
                )
            case .metricsReset:
                return AnyEncodable(
                    self.performanceMonitor?.reset()
                        ?? ControlHarnessPerformanceSnapshot.empty()
                )
            case .instancePing, .desktopRegister, .desktopUnregister, .desktopsList:
                return AnyEncodable([String: String]())
            }
        }

        switch result {
        case .success(let payload):
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "ok",
                result: payload,
                errorCode: nil,
                errorMessage: nil
            )
        case .failure(let error):
            let errorPayload = gatewayCommandErrorPayload(for: error)
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: errorPayload.code,
                errorMessage: errorPayload.message
            )
        }
    }

    private func applyPublicTransportMetadata(
        to result: ControlHarnessTokenIssueResult
    ) -> ControlHarnessTokenIssueResult {
        let publicEndpoint = resolvedPublicEndpoint()
        return ControlHarnessTokenIssueResult(
            token: result.token,
            tokenID: result.tokenID,
            client: result.client,
            scopes: result.scopes,
            desktopID: result.desktopID,
            desktopLabel: result.desktopLabel,
            preferredDesktopID: result.preferredDesktopID,
            transportMode: publicEndpoint == nil ? result.transportMode : "relay",
            publicEndpoint: publicEndpoint,
            transportSharedSecret: result.transportSharedSecret,
            issuedAt: result.issuedAt,
            expiresAt: result.expiresAt
        )
    }

    private func resolvedPublicEndpoint() -> String? {
        guard let endpoint = configuration.publicEndpoint?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              endpoint.isEmpty == false,
              endpoint.hasPrefix("wss://") else {
            return nil
        }
        return endpoint
    }

    private func gatewayCommand(for request: ControlHarnessRequest) -> GatewayCommand? {
        switch request.command {
        case "gateway.pairing.begin":
            return .pairingBegin
        case "gateway.pairing.exchange":
            return .pairingExchange
        case "gateway.token.info":
            return .tokenInfo
        case "gateway.token.rotate":
            return .tokenRotate
        case "gateway.token.revoke":
            return .tokenRevoke
        case "gateway.devices.list":
            return .devicesList
        case "gateway.devices.revoke":
            return .devicesRevoke
        case "gateway.metrics":
            return .metrics
        case "gateway.metrics.reset":
            return .metricsReset
        case "gateway.instance.ping":
            return .instancePing
        case "gateway.desktop.register":
            return .desktopRegister
        case "gateway.desktop.unregister":
            return .desktopUnregister
        case "gateway.desktops.list":
            return .desktopsList
        default:
            return nil
        }
    }

    private func makeRegisteredDeviceListPayload(
        _ devices: [ControlHarnessRegisteredDeviceResult]
    ) -> ControlHarnessGatewayRegisteredDeviceListPayload {
        ControlHarnessGatewayRegisteredDeviceListPayload(
            devices: devices.map(makeRegisteredDevicePayload)
        )
    }

    private func makeRegisteredDevicePayload(
        _ device: ControlHarnessRegisteredDeviceResult
    ) -> ControlHarnessGatewayRegisteredDevicePayload {
        ControlHarnessGatewayRegisteredDevicePayload(
            deviceID: device.deviceID,
            displayLabel: device.displayLabel,
            trustState: device.trustState,
            lastSeenAt: device.lastSeenAt,
            currentConnectionState: connectionState(forDeviceID: device.deviceID),
            transportMode: device.transportMode,
            capabilityFlags: device.capabilityFlags
        )
    }

    private func connectionState(forDeviceID deviceID: String) -> String {
        sessionRegistry.isActive(identity: "paired:\(deviceID)") ? "connected" : "idle"
    }

    private func upsertDesktopRoute(
        from request: ControlHarnessRequest,
        source: String
    ) throws -> ControlHarnessGatewayRouteRegistrationPayload {
        guard let desktopID = request.desktopID?.trimmingCharacters(in: .whitespacesAndNewlines),
              desktopID.isEmpty == false else {
            throw ControlHarnessGatewayRouteRegistryError.invalidDesktopID
        }
        guard let upstreamHost = request.upstreamHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              upstreamHost.isEmpty == false else {
            throw ControlHarnessGatewayRouteRegistryError.invalidUpstreamHost
        }
        guard let upstreamPort = request.upstreamPort, upstreamPort > 0 else {
            throw ControlHarnessGatewayRouteRegistryError.invalidUpstreamPort
        }
        guard Self.isLoopbackHost(upstreamHost) else {
            throw ControlHarnessGatewayRouteRegistryError.nonLoopbackUpstreamHost
        }

        let upstreamPingPayload = try queryGatewayPingPayload(
            host: upstreamHost,
            port: upstreamPort
        )
        guard upstreamPingPayload.supportsDesktopRouting,
              let upstreamDesktopID = upstreamPingPayload.desktopID?.trimmingCharacters(in: .whitespacesAndNewlines),
              upstreamDesktopID.isEmpty == false else {
            throw ControlHarnessGatewayRouteRegistryError.upstreamProbeFailed
        }
        guard upstreamDesktopID == desktopID else {
            throw ControlHarnessGatewayRouteRegistryError.upstreamDesktopIDMismatch
        }

        let desktopLabel = request.desktopLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = DesktopRoute(
            desktopID: desktopID,
            desktopLabel: (desktopLabel?.isEmpty == false) ? desktopLabel! : desktopID,
            upstreamHost: upstreamHost,
            upstreamPort: upstreamPort,
            source: source,
            updatedAt: Date()
        )
        lifecycleQueue.sync {
            desktopRoutesByID[desktopID] = route
        }

        return ControlHarnessGatewayRouteRegistrationPayload(
            desktopID: route.desktopID,
            desktopLabel: route.desktopLabel,
            upstreamHost: route.upstreamHost,
            upstreamPort: route.upstreamPort,
            registered: true
        )
    }

    private func removeDesktopRoute(
        from request: ControlHarnessRequest
    ) throws -> ControlHarnessGatewayRouteRegistrationPayload {
        guard let desktopID = request.desktopID?.trimmingCharacters(in: .whitespacesAndNewlines),
              desktopID.isEmpty == false else {
            throw ControlHarnessGatewayRouteRegistryError.invalidDesktopID
        }

        let removed = lifecycleQueue.sync {
            desktopRoutesByID.removeValue(forKey: desktopID)
        }
        return ControlHarnessGatewayRouteRegistrationPayload(
            desktopID: desktopID,
            desktopLabel: removed?.desktopLabel ?? desktopID,
            upstreamHost: removed?.upstreamHost ?? "",
            upstreamPort: removed?.upstreamPort ?? 0,
            registered: false
        )
    }

    private func evictDesktopRoute(
        _ desktopID: String,
        reason: String
    ) {
        let trimmed = desktopID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let removed = lifecycleQueue.sync {
            desktopRoutesByID.removeValue(forKey: trimmed)
        }
        guard removed != nil else { return }
        logger.notice(
            "evicted desktop route \(trimmed, privacy: .public): \(reason, privacy: .public)"
        )
    }

    private func makeDesktopRouteListPayload() -> ControlHarnessGatewayDesktopRouteListPayload {
        let localRoute = localDesktopRoute()
        let remotes = lifecycleQueue.sync { Array(desktopRoutesByID.values) }
        let payload = ([localRoute] + remotes)
            .sorted(by: { lhs, rhs in lhs.desktopID < rhs.desktopID })
            .map { route in
                ControlHarnessGatewayDesktopRoutePayload(
                    desktopID: route.desktopID,
                    desktopLabel: route.desktopLabel,
                    upstreamHost: route.upstreamHost,
                    upstreamPort: route.upstreamPort,
                    source: route.source,
                    updatedAt: ISO8601DateFormatter().string(from: route.updatedAt)
                )
            }
        return ControlHarnessGatewayDesktopRouteListPayload(desktops: payload)
    }

    private func localDesktopRoute() -> DesktopRoute {
        let desktopIdentity = currentDesktopIdentity()
        let desktopID = desktopIdentity?.desktopID ?? "unknown"
        let desktopLabel = desktopIdentity?.desktopLabel ?? "local"
        return DesktopRoute(
            desktopID: desktopID,
            desktopLabel: desktopLabel,
            upstreamHost: Self.localProbeHost(from: configuration.listenHost),
            upstreamPort: listenerPort ?? configuration.listenPort,
            source: "local_owner",
            updatedAt: Date()
        )
    }

    private func currentDesktopIdentity() -> ControlHarnessDesktopIdentityResult? {
        guard let authManager else { return nil }
        switch withAuthManager(authManager, operation: {
            await authManager.desktopIdentityResult()
        }) {
        case .success(let identity):
            return identity
        case .failure:
            return nil
        }
    }

    private func resolveRouteDecision(for requestedDesktopID: String) -> RouteDecision {
        let normalized = requestedDesktopID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return .local }
        if normalized == currentDesktopIdentity()?.desktopID {
            return .local
        }
        guard let route = lifecycleQueue.sync(execute: { desktopRoutesByID[normalized] }) else {
            return .notFound
        }
        return .proxy(route)
    }

    private func proxyRawRequestIfNeeded(
        _ requestData: Data
    ) throws -> (command: String, responseData: Data)? {
        guard let request = try? JSONDecoder().decode(ControlHarnessRequest.self, from: requestData),
              let requestedDesktopID = request.desktopID?.trimmingCharacters(in: .whitespacesAndNewlines),
              requestedDesktopID.isEmpty == false else {
            return nil
        }
        switch resolveRouteDecision(for: requestedDesktopID) {
        case .local, .notFound:
            return nil
        case .proxy(let route):
            do {
                let responseData = try proxyUnaryRequest(requestData, route: route)
                return (request.normalizedCommand, responseData)
            } catch {
                evictDesktopRoute(
                    route.desktopID,
                    reason: "tcp proxy failed: \(error.localizedDescription)"
                )
                let response = ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: "desktop_route_unreachable",
                    errorMessage: "Desktop route is unreachable; reconnect and rebind this desktop"
                )
                return (request.normalizedCommand, try encodeResponse(response))
            }
        }
    }

    private func proxyWebSocketRequestIfNeeded(
        rawRequestData: Data,
        request: ControlHarnessRequest
    ) throws -> Data? {
        guard request.command != "gateway.encrypted",
              let requestedDesktopID = request.desktopID?.trimmingCharacters(in: .whitespacesAndNewlines),
              requestedDesktopID.isEmpty == false else {
            return nil
        }
        switch resolveRouteDecision(for: requestedDesktopID) {
        case .local, .notFound:
            return nil
        case .proxy(let route):
            do {
                let responseData = try proxyUnaryRequest(rawRequestData, route: route)
                return Self.encodeWebSocketTextFrame(Self.trimTrailingLineFeed(responseData))
            } catch {
                evictDesktopRoute(
                    route.desktopID,
                    reason: "websocket request proxy failed: \(error.localizedDescription)"
                )
                let response = ControlHarnessResponse(
                    requestID: request.requestID,
                    status: "error",
                    result: nil,
                    errorCode: "desktop_route_unreachable",
                    errorMessage: "Desktop route is unreachable; reconnect and rebind this desktop"
                )
                return try encodeWebSocketResponse(response)
            }
        }
    }

    private func proxyUnaryRequest(
        _ requestData: Data,
        route: DesktopRoute
    ) throws -> Data {
        let upstreamFD = try Self.connectTCP(
            host: route.upstreamHost,
            port: route.upstreamPort
        )
        defer { Darwin.close(upstreamFD) }

        try Self.setBlocking(upstreamFD)
        try Self.setNoDelay(upstreamFD)
        try Self.writeAll(requestData, to: upstreamFD)
        guard Darwin.shutdown(upstreamFD, SHUT_WR) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        return try Self.readAll(from: upstreamFD)
    }

    private func proxyWebSocketClient(
        _ clientFD: Int32,
        initialData: Data,
        route: DesktopRoute
    ) throws {
        let upstreamFD = try Self.connectTCP(
            host: route.upstreamHost,
            port: route.upstreamPort
        )
        defer { Darwin.close(upstreamFD) }

        try Self.setBlocking(upstreamFD)
        try Self.setNoDelay(upstreamFD)
        try Self.writeAll(initialData, to: upstreamFD)
        Self.proxySocketDuplex(clientFD: clientFD, upstreamFD: upstreamFD)
    }

    private static func proxySocketDuplex(clientFD: Int32, upstreamFD: Int32) {
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)

        func pump(from sourceFD: Int32, to destinationFD: Int32) {
            group.enter()
            queue.async {
                defer { group.leave() }
                var buffer = [UInt8](repeating: 0, count: 8192)
                while true {
                    let amount = Darwin.read(sourceFD, &buffer, buffer.count)
                    if amount > 0 {
                        do {
                            try writeAll(Data(buffer.prefix(amount)), to: destinationFD)
                        } catch {
                            _ = Darwin.shutdown(destinationFD, SHUT_WR)
                            return
                        }
                        continue
                    }
                    if amount == 0 {
                        _ = Darwin.shutdown(destinationFD, SHUT_WR)
                        return
                    }
                    if errno == EINTR {
                        continue
                    }
                    _ = Darwin.shutdown(destinationFD, SHUT_WR)
                    return
                }
            }
        }

        pump(from: clientFD, to: upstreamFD)
        pump(from: upstreamFD, to: clientFD)
        group.wait()
    }

    private func gatewayCommandErrorPayload(for error: Error) -> (code: String, message: String) {
        switch error {
        case ControlHarnessGatewayDeviceRegistryError.invalidDeviceID:
            return ("invalid_argument", error.localizedDescription)
        case ControlHarnessGatewayRouteRegistryError.invalidDesktopID,
             ControlHarnessGatewayRouteRegistryError.invalidUpstreamHost,
             ControlHarnessGatewayRouteRegistryError.invalidUpstreamPort,
             ControlHarnessGatewayRouteRegistryError.nonLoopbackUpstreamHost,
             ControlHarnessGatewayRouteRegistryError.upstreamProbeFailed,
             ControlHarnessGatewayRouteRegistryError.upstreamDesktopIDMismatch:
            return ("invalid_argument", error.localizedDescription)
        case ControlHarnessGatewayDeviceRegistryError.deviceNotFound,
             ControlHarnessAuthError.deviceNotFound:
            return ("device_not_found", error.localizedDescription)
        default:
            return ("gateway_auth_failure", error.localizedDescription)
        }
    }

    private func requiredScope(for request: ControlHarnessRequest) -> ControlHarnessAuthScope? {
        let command = request.normalizedCommand
        if ControlHarnessBrowserCommandAdapter.isBrowserCommand(command) {
            return ControlHarnessBrowserCommandAdapter.isMutation(command) ? .mutate : .observe
        }

        switch command {
        case "snapshot",
            "agent.runtime.snapshot",
            "read-terminal",
            "events.subscribe",
            "terminal.stream.open",
            "terminal.stream.ack",
            "terminal.snapshot.v2",
            "terminal.semantic.v2":
            return .observe
        case "new-tab",
            "close-tab",
            "rename-tab",
            "agent.runtime.session.register",
            "agent.runtime.session.heartbeat",
            "agent.runtime.session.release",
            "agent.runtime.task.enqueue",
            "agent.runtime.task.claim",
            "agent.runtime.task.claim_next",
            "agent.runtime.task.update",
            "agent.runtime.task.approve",
            "agent.runtime.task.cancel",
            "agent.runtime.schedule.enqueue",
            "agent.runtime.schedule.update",
            "agent.runtime.schedule.cancel",
            "send-text",
            "send-key",
            "run-command",
            "close-terminal":
            return .mutate
        default:
            return nil
        }
    }

    private func validateToken(
        _ token: String?,
        requiredScope: ControlHarnessAuthScope?,
        authManager: ControlHarnessAuth,
        transportMode: String?
    ) -> ControlHarnessAuth.Validation {
        switch withAuthManager(authManager, operation: {
            await authManager.validate(token: token, requiredScope: requiredScope)
        }) {
        case .success(let validation):
            if case .allow = validation, let token, token.isEmpty == false {
                _ = withAuthManager(authManager, operation: {
                    try await authManager.recordDeviceActivity(token: token, transportMode: transportMode)
                })
            }
            return validation
        case .failure:
            return .deny(
                errorCode: "unauthorized",
                errorMessage: "The gateway auth token is invalid, expired, or revoked"
            )
        }
    }

    private func withAuthManager<T>(
        _ authManager: ControlHarnessAuth,
        operation: @escaping @Sendable () async throws -> T
    ) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?

        Task {
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result ?? .failure(ControlHarnessAuthError.invalidToken)
    }

    private func withSessionReservation(
        request: ControlHarnessRequest,
        peerDescription: String,
        sessionIdentity: String?,
        responseWriter: (ControlHarnessResponse) throws -> Void,
        operation: () throws -> Void
    ) throws {
        if let rateLimited = rateLimit(request, peerDescription: peerDescription) {
            try responseWriter(rateLimited)
            return
        }

        guard let sessionIdentity else {
            try operation()
            return
        }
        guard shouldReserveSessionSlot(for: request) else {
            try operation()
            return
        }
        guard sessionRegistry.acquire(identity: sessionIdentity) else {
            if shouldReplaceSupersededSubscription(for: request),
               closeOldestActiveSubscription(identity: sessionIdentity, command: request.normalizedCommand) {
                let deadline = Date().addingTimeInterval(0.35)
                repeat {
                    if sessionRegistry.acquire(identity: sessionIdentity) {
                        defer {
                            sessionRegistry.release(identity: sessionIdentity)
                        }
                        try operation()
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.01)
                } while Date() < deadline
            }
            try responseWriter(ControlHarnessResponse(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: "session_limit_exceeded",
                errorMessage: "Gateway concurrent session limit exceeded"
            ))
            return
        }

        defer {
            sessionRegistry.release(identity: sessionIdentity)
        }

        try operation()
    }

    private func shouldReplaceSupersededSubscription(for request: ControlHarnessRequest) -> Bool {
        switch request.normalizedCommand {
        case "events.subscribe", "terminal.stream.open":
            return true
        default:
            return false
        }
    }

    private func shouldReserveSessionSlot(for request: ControlHarnessRequest) -> Bool {
        // Session caps are intended to guard long-lived streams only.
        // One-shot requests (snapshot/read/input/ack/etc.) should not consume
        // the same concurrency budget, otherwise refresh and typing can fail
        // while an observe stream is active.
        request.commandKind == .subscription
    }

    private func registerActiveStream(
        clientSession: ControlHarnessGatewayClientSession,
        clientFD: Int32,
        command: String,
        sessionIdentity: String?
    ) -> UUID {
        let streamID = UUID()
        lifecycleQueue.sync {
            activeStreams[streamID] = ActiveStream(
                sessionIdentity: sessionIdentity,
                command: command,
                startedAt: Date(),
                close: {
                    clientSession.close()
                    _ = Darwin.shutdown(clientFD, SHUT_RDWR)
                }
            )
            if let sessionIdentity {
                var streamIDs = activeStreamIDsByIdentity[sessionIdentity] ?? []
                streamIDs.insert(streamID)
                activeStreamIDsByIdentity[sessionIdentity] = streamIDs
            }
        }
        return streamID
    }

    private func unregisterActiveStream(_ streamID: UUID) {
        lifecycleQueue.sync {
            let sessionIdentity = activeStreams.removeValue(forKey: streamID)?.sessionIdentity
            if let sessionIdentity {
                var streamIDs = activeStreamIDsByIdentity[sessionIdentity] ?? []
                streamIDs.remove(streamID)
                if streamIDs.isEmpty {
                    activeStreamIDsByIdentity.removeValue(forKey: sessionIdentity)
                } else {
                    activeStreamIDsByIdentity[sessionIdentity] = streamIDs
                }
            }
        }
    }

    private func closeActiveStreams(identity: String) {
        let closures = lifecycleQueue.sync {
            (activeStreamIDsByIdentity[identity] ?? []).compactMap { activeStreams[$0]?.close }
        }
        closures.forEach { $0() }
    }

    private func closeOldestActiveSubscription(identity: String, command: String) -> Bool {
        let closure = lifecycleQueue.sync { () -> (@Sendable () -> Void)? in
            let matchingStreamIDs = (activeStreamIDsByIdentity[identity] ?? []).filter { streamID in
                activeStreams[streamID]?.command == command
            }
            guard let streamID = matchingStreamIDs.min(by: { lhs, rhs in
                guard let lhsStream = activeStreams[lhs], let rhsStream = activeStreams[rhs] else {
                    return false
                }
                return lhsStream.startedAt < rhsStream.startedAt
            }),
            let stream = activeStreams[streamID] else {
                return nil
            }
            return stream.close
        }

        guard let closure else {
            return false
        }
        closure()
        return true
    }

    private func waitForSessionDrain(identity: String, timeoutSeconds: TimeInterval = 1.0) {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if sessionRegistry.isActive(identity: identity) == false {
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func rateLimitIdentity(
        for request: ControlHarnessRequest,
        peerDescription: String
    ) -> String {
        let authIdentity = request.authToken
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "anonymous"
        let peerBucket = Self.rateLimitPeerBucket(peerDescription)
        return "\(authIdentity)@\(peerBucket)"
    }

    private static func rateLimitPeerBucket(_ peerDescription: String) -> String {
        if peerDescription == "unix-peer" || peerDescription.hasPrefix("fd-") || peerDescription.hasPrefix("peer-") {
            return peerDescription
        }

        if let separator = peerDescription.lastIndex(of: ":") {
            let host = String(peerDescription[..<separator])
            if host.isEmpty == false {
                return host
            }
        }
        return peerDescription
    }

    private func streamSubscription(
        _ envelope: ControlHarnessSubscriptionEnvelope,
        command: String,
        to clientFD: Int32,
        transport: String,
        closeReason: String,
        transportSharedSecret: String? = nil,
        sessionIdentity: String? = nil
    ) throws {
        let started = DispatchTime.now()
        let clientSession = makeClientSession()
        let attachment = attachSubscription(envelope, to: clientSession)
        let activeStreamID = registerActiveStream(
            clientSession: clientSession,
            clientFD: clientFD,
            command: command,
            sessionIdentity: sessionIdentity
        )
        performanceMonitor?.recordGatewayStreamOpened(transport: transport)
        defer {
            performanceMonitor?.recordGatewayStreamClosed(
                transport: transport,
                reason: closeReason,
                durationMs: Self.elapsedMilliseconds(since: started)
            )
            unregisterActiveStream(activeStreamID)
            attachment.close()
            clientSession.close()
        }

        try flushClientSession(clientSession, to: clientFD, transportSharedSecret: transportSharedSecret)
        guard envelope.session != nil else {
            return
        }

        while true {
            let hasBufferedData = clientSession.waitForBufferedData(timeout: .now() + .milliseconds(500))
            if !hasBufferedData, Self.isClientStreamDisconnected(clientFD) {
                return
            }
            try flushClientSession(clientSession, to: clientFD, transportSharedSecret: transportSharedSecret)
            if clientSession.isClosed {
                let drain = clientSession.drain()
                if drain.payloads.isEmpty {
                    return
                }
                for payload in drain.payloads {
                    try Self.writeAll(
                        try encodeOutboundPayload(payload, transportSharedSecret: transportSharedSecret),
                        to: clientFD
                    )
                }
                return
            }
        }
    }

    private func streamWebSocketSubscription(
        _ envelope: ControlHarnessSubscriptionEnvelope,
        command: String,
        to clientFD: Int32,
        transport: String,
        closeReason: String,
        transportSharedSecret: String? = nil,
        sessionIdentity: String? = nil
    ) throws {
        let started = DispatchTime.now()
        let clientSession = makeClientSession()
        let attachment = attachSubscription(envelope, to: clientSession)
        let activeStreamID = registerActiveStream(
            clientSession: clientSession,
            clientFD: clientFD,
            command: command,
            sessionIdentity: sessionIdentity
        )
        performanceMonitor?.recordGatewayStreamOpened(transport: transport)
        defer {
            performanceMonitor?.recordGatewayStreamClosed(
                transport: transport,
                reason: closeReason,
                durationMs: Self.elapsedMilliseconds(since: started)
            )
            unregisterActiveStream(activeStreamID)
            attachment.close()
            clientSession.close()
        }

        try flushWebSocketClientSession(clientSession, to: clientFD, transportSharedSecret: transportSharedSecret)
        guard envelope.session != nil else {
            return
        }

        while true {
            let hasBufferedData = clientSession.waitForBufferedData(timeout: .now() + .milliseconds(500))
            if !hasBufferedData, Self.isClientStreamDisconnected(clientFD) {
                return
            }
            try flushWebSocketClientSession(clientSession, to: clientFD, transportSharedSecret: transportSharedSecret)
            if clientSession.isClosed {
                let drain = clientSession.drain()
                if drain.payloads.isEmpty {
                    return
                }
                for payload in drain.payloads {
                    try Self.writeAll(
                        try encodeWebSocketPayload(payload, transportSharedSecret: transportSharedSecret),
                        to: clientFD
                    )
                }
                return
            }
        }
    }

    private func flushClientSession(
        _ clientSession: ControlHarnessGatewayClientSession,
        to clientFD: Int32,
        transportSharedSecret: String? = nil
    ) throws {
        let drain = clientSession.drain()
        for payload in drain.payloads {
            try Self.writeAll(
                try encodeOutboundPayload(payload, transportSharedSecret: transportSharedSecret),
                to: clientFD
            )
        }
    }

    private func flushWebSocketClientSession(
        _ clientSession: ControlHarnessGatewayClientSession,
        to clientFD: Int32,
        transportSharedSecret: String? = nil
    ) throws {
        let drain = clientSession.drain()
        for payload in drain.payloads {
            try Self.writeAll(
                try encodeWebSocketPayload(payload, transportSharedSecret: transportSharedSecret),
                to: clientFD
            )
        }
    }

    private static func isClientStreamDisconnected(_ clientFD: Int32) -> Bool {
        var byte: UInt8 = 0
        let count = Darwin.recv(clientFD, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        if count == 0 {
            return true
        }
        if count > 0 {
            // Readable bytes only mean the peer sent data (for example ping/control
            // frames). This is not a disconnect signal.
            return false
        }
        switch errno {
        case EAGAIN, EWOULDBLOCK:
            return false
        case EINTR:
            return isClientStreamDisconnected(clientFD)
        default:
            return true
        }
    }

    private func callRequestHandler(_ request: ControlHarnessRequest) -> ControlHarnessServiceReply {
        guard let requestHandler else {
            return .single(ControlHarnessResponse(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: "internal_failure",
                errorMessage: "The control harness gateway has no request handler"
            ))
        }
        let reply = syncMainActor { [self] in
            requestHandler(request, listenerPathDescription())
        }
        return reply ?? .single(ControlHarnessResponse(
            requestID: request.requestID,
            status: "error",
            result: nil,
            errorCode: "internal_failure",
            errorMessage: "The control harness gateway failed to produce a response"
        ))
    }

    private func syncMainActor<T>(
        _ body: @escaping @MainActor () -> T
    ) -> T? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                body()
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                body()
            }
        }
    }

    private func listenerPathDescription() -> String {
        "tcp://\(configuration.listenHost):\(listenerPort ?? configuration.listenPort)"
    }

    private static func elapsedMilliseconds(since started: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
    }

    private func encodeResponse(
        _ response: ControlHarnessResponse,
        transportSharedSecret: String? = nil
    ) throws -> Data {
        let rawPayload = try encoder.encode(response)
        guard let transportSharedSecret,
              transportSharedSecret.isEmpty == false else {
            var data = rawPayload
            data.append(0x0A)
            return data
        }
        let encrypted = try ControlHarnessGatewaySecureChannel.encryptEnvelopeData(
            rawPayload,
            transportSharedSecret: transportSharedSecret
        )
        var data = try encoder.encode(encrypted)
        data.append(0x0A)
        return data
    }

    private func encodeOutboundPayload(
        _ payload: Data,
        transportSharedSecret: String?
    ) throws -> Data {
        guard let transportSharedSecret,
              transportSharedSecret.isEmpty == false else {
            return payload
        }
        let encrypted = try ControlHarnessGatewaySecureChannel.encryptEnvelopeData(
            Self.trimTrailingLineFeed(payload),
            transportSharedSecret: transportSharedSecret
        )
        var data = try encoder.encode(encrypted)
        data.append(0x0A)
        return data
    }

    private func encodeWebSocketPayload(
        _ payload: Data,
        transportSharedSecret: String?
    ) throws -> Data {
        Self.encodeWebSocketTextFrame(
            Self.trimTrailingLineFeed(
                try encodeOutboundPayload(payload, transportSharedSecret: transportSharedSecret)
            )
        )
    }

    private func encodeWebSocketResponse(
        _ response: ControlHarnessResponse,
        transportSharedSecret: String? = nil
    ) throws -> Data {
        Self.encodeWebSocketTextFrame(
            Self.trimTrailingLineFeed(
                try encodeResponse(response, transportSharedSecret: transportSharedSecret)
            )
        )
    }

    private func makeListener(host: String, port: UInt16) throws -> (fd: Int32, port: UInt16) {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        do {
            var yes: Int32 = 1
            guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            try Self.setNonBlocking(fd)

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            let parseResult = withUnsafeMutablePointer(to: &address.sin_addr) {
                inet_pton(AF_INET, host, UnsafeMutableRawPointer($0).assumingMemoryBound(to: Int8.self))
            }
            guard parseResult == 1 else {
                throw ControlHarnessGatewayError.invalidListenHost(host)
            }

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            guard Darwin.listen(fd, SOMAXCONN) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            var boundAddress = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.getsockname(fd, $0, &length)
                }
            }
            guard nameResult == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            return (fd, UInt16(bigEndian: boundAddress.sin_port))
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private static func connectTCP(host: String, port: UInt16) throws -> Int32 {
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

            let connectResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard connectResult == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private static func localProbeHost(from host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "0.0.0.0" || trimmed == "*" || trimmed == "::" || trimmed == "[::]" {
            return "127.0.0.1"
        }
        if trimmed.contains(":") {
            return "127.0.0.1"
        }
        return trimmed
    }

    private static func shouldRetryLocalGatewayCommand(_ error: Error) -> Bool {
        if let posixError = error as? POSIXError {
            switch posixError.code {
            case .EAGAIN, .ECONNREFUSED, .ETIMEDOUT, .EHOSTDOWN, .EHOSTUNREACH, .ENETDOWN, .ENETUNREACH:
                return true
            default:
                return false
            }
        }

        if let routeError = error as? ControlHarnessGatewayRouteRegistryError,
           routeError == .upstreamProbeFailed {
            return true
        }

        return false
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "127.0.0.1"
            || normalized == "localhost"
            || normalized == "::1"
            || normalized == "[::1]"
    }

    private static func portConflictRecoveryCandidates(startingAt requestedPort: UInt16) -> [UInt16] {
        guard requestedPort < UInt16.max else { return [] }

        let maxSequentialAttempts = 16
        let upperBound = min(Int(UInt16.max), Int(requestedPort) + maxSequentialAttempts)
        guard upperBound > Int(requestedPort) else { return [] }

        return ((Int(requestedPort) + 1)...upperBound).compactMap(UInt16.init)
    }

    private static func setNonBlocking(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private static func setBlocking(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private static func setNoDelay(_ fd: Int32) throws {
        var enabled: Int32 = 1
        guard setsockopt(
            fd,
            IPPROTO_TCP,
            TCP_NODELAY,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private static func readAll(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                continue
            }
            if count == 0 {
                return data
            }
            if errno == EINTR {
                continue
            }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private static func readInitialClientData(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4)
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000

        while true {
            if !data.isEmpty {
                if data.count >= 4 || httpHeaderBoundary(in: data) != nil {
                    return data
                }
            }

            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == -1 {
                if errno == EINTR {
                    continue
                }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    if DispatchTime.now().uptimeNanoseconds >= deadline {
                        return data
                    }
                    usleep(1_000)
                    continue
                }
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            if count == 0 {
                return data
            }
            data.append(buffer, count: count)
        }
    }

    private static func looksLikeWebSocketHandshake(_ data: Data) -> Bool {
        let prefix = String(bytes: data.prefix(4), encoding: .utf8) ?? ""
        if prefix.hasPrefix("GET ") {
            return true
        }

        // Reverse tunnels can fragment the handshake verb and initially
        // deliver only "G", "GE", or "GET". These prefixes are still
        // unambiguously HTTP/WebSocket traffic for this socket.
        return prefix == "G" || prefix == "GE" || prefix == "GET"
    }

    private static func readHTTPHeaders(
        from fd: Int32,
        initialData: Data = Data()
    ) throws -> (headers: Data, remainder: Data) {
        var data = initialData
        var buffer = [UInt8](repeating: 0, count: 1024)
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000

        while true {
            if let headerEnd = httpHeaderBoundary(in: data) {
                return (
                    headers: Data(data[..<headerEnd]),
                    remainder: Data(data[headerEnd...])
                )
            }

            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.count > 16_384 {
                    throw ControlHarnessGatewayError.invalidWebSocketHandshake
                }
                if let headerEnd = httpHeaderBoundary(in: data) {
                    return (
                        headers: Data(data[..<headerEnd]),
                        remainder: Data(data[headerEnd...])
                    )
                }
                continue
            }
            if count == 0 {
                throw ControlHarnessGatewayError.invalidWebSocketHandshake
            }
            if errno == EINTR {
                continue
            }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                if DispatchTime.now().uptimeNanoseconds >= deadline {
                    throw ControlHarnessGatewayError.invalidWebSocketHandshake
                }
                usleep(1_000)
                continue
            }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

    }

    private static func httpHeaderBoundary(in data: Data) -> Data.Index? {
        if let range = data.range(of: Data("\r\n\r\n".utf8)) {
            return range.upperBound
        }
        if let range = data.range(of: Data("\n\n".utf8)) {
            return range.upperBound
        }
        let truncatedCRLF = Data("\r\n\r".utf8)
        if data.count >= truncatedCRLF.count && Data(data.suffix(truncatedCRLF.count)) == truncatedCRLF {
            return data.endIndex
        }
        return nil
    }

    private static func parseWebSocketKey(from handshake: Data) throws -> String {
        guard let request = String(data: handshake, encoding: .utf8) else {
            throw ControlHarnessGatewayError.invalidWebSocketHandshake
        }
        let lines = request.components(separatedBy: "\r\n")
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            if parts[0].caseInsensitiveCompare("Sec-WebSocket-Key") == .orderedSame {
                let key = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard key.isEmpty == false else {
                    break
                }
                return key
            }
        }
        throw ControlHarnessGatewayError.invalidWebSocketHandshake
    }

    private static func parseRequestedDesktopID(fromWebSocketHandshake handshake: Data) -> String? {
        guard let request = String(data: handshake, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return nil
        }

        let requestTarget = String(parts[1])
        guard let components = URLComponents(string: "http://localhost\(requestTarget)"),
              let desktopID = components.queryItems?
                .first(where: { $0.name == "desktop_id" })?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              desktopID.isEmpty == false else {
            return nil
        }
        return desktopID
    }

    private static func webSocketHandshakeResponse(for key: String) -> Data {
        let acceptSeed = Data("\(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11".utf8)
        let digest = Insecure.SHA1.hash(data: acceptSeed)
        let accept = Data(digest).base64EncodedString()
        let response =
            "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: \(accept)\r\n" +
            "\r\n"
        return Data(response.utf8)
    }

    private static func httpNotFoundResponse() -> Data {
        Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)
    }

    private static func httpBadGatewayResponse() -> Data {
        Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)
    }

    private static func readWebSocketFrame(
        from fd: Int32,
        bufferedBytes: inout Data
    ) throws -> Data {
        let header = try readExact(from: fd, count: 2, bufferedBytes: &bufferedBytes)
        let firstByte = header[0]
        let secondByte = header[1]
        let opcode = firstByte & 0x0F
        let isMasked = (secondByte & 0x80) != 0

        if opcode == 0x8 {
            return Data()
        }
        guard opcode == 0x1 else {
            throw ControlHarnessGatewayError.unsupportedWebSocketFrame
        }
        guard isMasked else {
            throw ControlHarnessGatewayError.invalidWebSocketHandshake
        }

        var payloadLength = Int(secondByte & 0x7F)
        if payloadLength == 126 {
            let extended = try readExact(from: fd, count: 2, bufferedBytes: &bufferedBytes)
            payloadLength = Int(UInt16(extended[0]) << 8 | UInt16(extended[1]))
        } else if payloadLength == 127 {
            let extended = try readExact(from: fd, count: 8, bufferedBytes: &bufferedBytes)
            payloadLength = extended.reduce(0) { (partial, byte) in
                (partial << 8) | Int(byte)
            }
        }

        let mask = try readExact(from: fd, count: 4, bufferedBytes: &bufferedBytes)
        var payload = try readExact(from: fd, count: payloadLength, bufferedBytes: &bufferedBytes)
        for index in payload.indices {
            payload[index] ^= mask[payload.distance(from: payload.startIndex, to: index) % 4]
        }
        return payload
    }

    private static func encodeWebSocketTextFrame(_ payload: Data) -> Data {
        var frame = Data()
        frame.append(0x81)

        let payloadLength = payload.count
        if payloadLength <= 125 {
            frame.append(UInt8(payloadLength))
        } else if payloadLength <= 65_535 {
            frame.append(126)
            frame.append(UInt8((payloadLength >> 8) & 0xFF))
            frame.append(UInt8(payloadLength & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((UInt64(payloadLength) >> UInt64(shift)) & 0xFF))
            }
        }

        frame.append(payload)
        return frame
    }

    private static func readExact(from fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < count {
                let readCount = Darwin.read(fd, baseAddress.advanced(by: offset), count - offset)
                if readCount > 0 {
                    offset += readCount
                    continue
                }
                if readCount == 0 {
                    throw ControlHarnessGatewayError.invalidWebSocketHandshake
                }
                if errno == EINTR {
                    continue
                }
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
        return data
    }

    private static func readExact(
        from fd: Int32,
        count: Int,
        bufferedBytes: inout Data
    ) throws -> Data {
        guard count > 0 else { return Data() }

        if bufferedBytes.count >= count {
            let prefix = bufferedBytes.prefix(count)
            bufferedBytes.removeFirst(count)
            return Data(prefix)
        }

        var data = Data()
        if !bufferedBytes.isEmpty {
            data.append(bufferedBytes)
            bufferedBytes.removeAll(keepingCapacity: false)
        }

        if data.count < count {
            data.append(try readExact(from: fd, count: count - data.count))
        }

        return data
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(fd, baseAddress.advanced(by: offset), rawBuffer.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                if written == -1 && errno == EINTR {
                    continue
                }
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
    }

    private static func peerDescription(for fd: Int32) -> String {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getpeername(fd, $0, &length)
            }
        }
        guard result == 0 else {
            return "fd-\(fd)"
        }

        switch Int32(storage.ss_family) {
        case AF_INET:
            return withUnsafePointer(to: &storage) { pointer in
                pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addressPointer in
                    var address = addressPointer.pointee.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    let host = inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count))
                        .map { String(cString: $0) }
                        ?? "ipv4"
                    let port = UInt16(bigEndian: addressPointer.pointee.sin_port)
                    return "\(host):\(port)"
                }
            }
        case AF_UNIX:
            return "unix-peer"
        default:
            return "peer-\(storage.ss_family)"
        }
    }

    private static func isLoopbackPeer(_ peerDescription: String) -> Bool {
        peerDescription.hasPrefix("127.0.0.1:")
            || peerDescription.hasPrefix("::1:")
            || peerDescription == "unix-peer"
    }

    private static func trimTrailingLineFeed(_ data: Data) -> Data {
        if data.last == 0x0A {
            return data.dropLast()
        }
        return data
    }
}

private final class ControlHarnessGatewayRateLimiter {
    private static let identityIdleTTLMinutes: Int64 = 30
    private static let maxTrackedIdentities = 2_048

    private struct WindowCounter {
        var minuteWindow: Int64?
        var count = 0

        mutating func allow(limit: Int, minuteWindow: Int64) -> Bool {
            if self.minuteWindow != minuteWindow {
                self.minuteWindow = minuteWindow
                count = 0
            }
            guard count < limit else {
                return false
            }
            count += 1
            return true
        }
    }

    private struct IdentityCounters {
        var command = WindowCounter()
        var input = WindowCounter()
        var snapshot = WindowCounter()
        var resync = WindowCounter()
        var lastSeenMinuteWindow: Int64 = 0
    }

    private enum Category {
        case command
        case input
        case snapshot
        case resync
    }

    private let configuration: ControlHarnessGateway.Configuration
    private let queue = DispatchQueue(
        label: "com.leongong.ghodex.control-harness.gateway.rate-limiter",
        qos: .utility
    )
    private let now: () -> Date

    private var globalCounter = WindowCounter()
    private var identities: [String: IdentityCounters] = [:]

    init(
        configuration: ControlHarnessGateway.Configuration,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.now = now
    }

    func evaluate(
        request: ControlHarnessRequest,
        identity: String
    ) -> ControlHarnessGateway.RequestAuthorization {
        queue.sync {
            let minuteWindow = Int64(now().timeIntervalSince1970 / 60.0)
            pruneIdentitiesLocked(currentMinuteWindow: minuteWindow)

            let resolvedCategory = category(for: request)
            if shouldApplyGlobalLimit(for: request, category: resolvedCategory) {
                guard globalCounter.allow(
                    limit: configuration.maxGlobalRequestsPerMinute,
                    minuteWindow: minuteWindow
                ) else {
                    return .deny(
                        errorCode: "rate_limited",
                        errorMessage: "Gateway global request rate limit exceeded"
                    )
                }
            }

            guard let category = resolvedCategory else {
                return .allow
            }

            var counters = identities[identity] ?? IdentityCounters()
            counters.lastSeenMinuteWindow = minuteWindow
            let allowed: Bool
            let errorMessage: String

            switch category {
            case .command:
                allowed = counters.command.allow(
                    limit: configuration.maxCommandsPerMinute,
                    minuteWindow: minuteWindow
                )
                errorMessage = "Gateway command rate limit exceeded"
            case .input:
                allowed = counters.input.allow(
                    limit: configuration.maxInputEventsPerMinute,
                    minuteWindow: minuteWindow
                )
                errorMessage = "Gateway input rate limit exceeded"
            case .snapshot:
                allowed = counters.snapshot.allow(
                    limit: configuration.maxSnapshotRequestsPerMinute,
                    minuteWindow: minuteWindow
                )
                errorMessage = "Gateway snapshot rate limit exceeded"
            case .resync:
                allowed = counters.resync.allow(
                    limit: configuration.maxResyncAttemptsPerMinute,
                    minuteWindow: minuteWindow
                )
                errorMessage = "Gateway resync rate limit exceeded"
            }

            identities[identity] = counters
            pruneIdentitiesLocked(currentMinuteWindow: minuteWindow)

            guard allowed else {
                return .deny(
                    errorCode: "rate_limited",
                    errorMessage: errorMessage
                )
            }

            return .allow
        }
    }

    private func shouldApplyGlobalLimit(
        for request: ControlHarnessRequest,
        category: Category?
    ) -> Bool {
        let command = request.normalizedCommand
        // terminal.stream.ack is a high-frequency flow-control signal. Applying
        // the global low-frequency guard to ACK traffic causes false positives
        // in realtime sessions under healthy throughput.
        if command == "terminal.stream.ack" {
            return false
        }

        // Input and resync paths already have category-specific budgets and can
        // legitimately be high-frequency in SSH-like interactive sessions.
        if category == .input || category == .resync {
            return false
        }

        return true
    }

    private func pruneIdentitiesLocked(currentMinuteWindow: Int64) {
        let idleCutoff = currentMinuteWindow - Self.identityIdleTTLMinutes
        var removedIdle = 0
        for (identity, counters) in identities where counters.lastSeenMinuteWindow < idleCutoff {
            identities.removeValue(forKey: identity)
            removedIdle += 1
        }

        let overflowCount = identities.count - Self.maxTrackedIdentities
        guard overflowCount > 0 else {
            if removedIdle > 0 {
                RuntimeDiagnosticsLogger.log(
                    component: "control_harness.gateway_rate_limiter",
                    event: "prune_identities",
                    details: [
                        "removed_idle": "\(removedIdle)",
                        "removed_capacity": "0",
                        "remaining": "\(identities.count)",
                    ]
                )
            }
            return
        }

        let evictionKeys = identities
            .sorted { lhs, rhs in
                if lhs.value.lastSeenMinuteWindow != rhs.value.lastSeenMinuteWindow {
                    return lhs.value.lastSeenMinuteWindow < rhs.value.lastSeenMinuteWindow
                }
                return lhs.key < rhs.key
            }
            .prefix(overflowCount)
            .map(\.key)
        for key in evictionKeys {
            identities.removeValue(forKey: key)
        }
        RuntimeDiagnosticsLogger.log(
            component: "control_harness.gateway_rate_limiter",
            event: "prune_identities",
            details: [
                "removed_idle": "\(removedIdle)",
                "removed_capacity": "\(evictionKeys.count)",
                "remaining": "\(identities.count)",
            ]
        )
    }

    private func category(for request: ControlHarnessRequest) -> Category? {
        let command = request.normalizedCommand
        let readMode = request.mode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if ControlHarnessBrowserCommandAdapter.isInput(command) {
            return .input
        }
        if ControlHarnessBrowserCommandAdapter.isResync(command) {
            return .resync
        }
        if ControlHarnessBrowserCommandAdapter.isBrowserCommand(command) {
            return ControlHarnessBrowserCommandAdapter.isMutation(command) ? .command : .snapshot
        }

        switch command {
        case "send-text", "send-key":
            return .input
        case "run-command", "close-terminal", "new-tab", "close-tab", "rename-tab":
            return .command
        case "snapshot", "terminal.snapshot.v2", "terminal.semantic.v2":
            return .snapshot
        case "read-terminal" where readMode == "delta":
            return .resync
        case "read-terminal":
            // read-terminal defaults to snapshot mode when mode is omitted, so
            // limiter categorization must mirror core read semantics.
            return .snapshot
        case "events.subscribe",
            "events.stream.subscribe",
            "events.stream.drain",
            "events.stream.unsubscribe",
            "terminal.stream.open":
            return .resync
        default:
            return nil
        }
    }
}

private final class ControlHarnessGatewaySessionRegistry {
    private let maxConcurrentSessionsPerIdentity: Int
    private let queue = DispatchQueue(
        label: "com.leongong.ghodex.control-harness.gateway.session-registry",
        qos: .utility
    )
    private var activeSessions: [String: Int] = [:]

    init(maxConcurrentSessionsPerIdentity: Int) {
        self.maxConcurrentSessionsPerIdentity = maxConcurrentSessionsPerIdentity
    }

    func acquire(identity: String) -> Bool {
        queue.sync {
            let current = activeSessions[identity] ?? 0
            guard current < maxConcurrentSessionsPerIdentity else {
                return false
            }
            activeSessions[identity] = current + 1
            return true
        }
    }

    func release(identity: String) {
        queue.sync {
            let current = activeSessions[identity] ?? 0
            if current <= 1 {
                activeSessions.removeValue(forKey: identity)
            } else {
                activeSessions[identity] = current - 1
            }
        }
    }

    func isActive(identity: String) -> Bool {
        queue.sync {
            (activeSessions[identity] ?? 0) > 0
        }
    }
}

enum ControlHarnessGatewayError: LocalizedError {
    case invalidListenHost(String)
    case invalidWebSocketHandshake
    case unsupportedWebSocketFrame

    var errorDescription: String? {
        switch self {
        case .invalidListenHost(let host):
            return "Control harness gateway listen host is invalid: \(host)"
        case .invalidWebSocketHandshake:
            return "The WebSocket handshake is invalid"
        case .unsupportedWebSocketFrame:
            return "The WebSocket frame is unsupported"
        }
    }
}

struct ControlHarnessDurationMetricsSnapshot: Codable, Equatable {
    let count: Int
    let averageMs: Double
    let p95Ms: Double
    let maxMs: Double
}

struct ControlHarnessSamplerMetricsSnapshot: Codable, Equatable {
    let tick: ControlHarnessDurationMetricsSnapshot
    let capture: ControlHarnessDurationMetricsSnapshot
    let lastTargetCount: Int
    let lastRefreshedCount: Int
    let lastTickAt: String?
    let lastCaptureScope: String?
    let lastCaptureActivityClass: String?
    let lastCaptureAt: String?

    enum CodingKeys: String, CodingKey {
        case tick
        case capture
        case lastTargetCount = "last_target_count"
        case lastRefreshedCount = "last_refreshed_count"
        case lastTickAt = "last_tick_at"
        case lastCaptureScope = "last_capture_scope"
        case lastCaptureActivityClass = "last_capture_activity_class"
        case lastCaptureAt = "last_capture_at"
    }
}

struct ControlHarnessGatewayMetricsSnapshot: Codable, Equatable {
    let request: ControlHarnessDurationMetricsSnapshot
    let streamLifetime: ControlHarnessDurationMetricsSnapshot
    let totalRequests: Int
    let openStreams: Int
    let totalStreamsStarted: Int
    let totalStreamsClosed: Int
    let requestCounts: [String: Int]
    let requestTransportCounts: [String: Int]
    let streamTransportCounts: [String: Int]
    let streamCloseReasons: [String: Int]

    enum CodingKeys: String, CodingKey {
        case request
        case streamLifetime = "stream_lifetime"
        case totalRequests = "total_requests"
        case openStreams = "open_streams"
        case totalStreamsStarted = "total_streams_started"
        case totalStreamsClosed = "total_streams_closed"
        case requestCounts = "request_counts"
        case requestTransportCounts = "request_transport_counts"
        case streamTransportCounts = "stream_transport_counts"
        case streamCloseReasons = "stream_close_reasons"
    }
}

struct ControlHarnessPerformanceSnapshot: Codable, Equatable {
    let generatedAt: String
    let windowStartedAt: String
    let windowAgeMs: Int
    let sampler: ControlHarnessSamplerMetricsSnapshot
    let gateway: ControlHarnessGatewayMetricsSnapshot

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case windowStartedAt = "window_started_at"
        case windowAgeMs = "window_age_ms"
        case sampler
        case gateway
    }

    static func empty(now: Date = Date()) -> Self {
        let emptyDuration = ControlHarnessDurationMetricsSnapshot(
            count: 0,
            averageMs: 0,
            p95Ms: 0,
            maxMs: 0
        )
        return Self(
            generatedAt: ControlHarnessPerformanceMonitor.timestamp(now),
            windowStartedAt: ControlHarnessPerformanceMonitor.timestamp(now),
            windowAgeMs: 0,
            sampler: .init(
                tick: emptyDuration,
                capture: emptyDuration,
                lastTargetCount: 0,
                lastRefreshedCount: 0,
                lastTickAt: nil,
                lastCaptureScope: nil,
                lastCaptureActivityClass: nil,
                lastCaptureAt: nil
            ),
            gateway: .init(
                request: emptyDuration,
                streamLifetime: emptyDuration,
                totalRequests: 0,
                openStreams: 0,
                totalStreamsStarted: 0,
                totalStreamsClosed: 0,
                requestCounts: [:],
                requestTransportCounts: [:],
                streamTransportCounts: [:],
                streamCloseReasons: [:]
            )
        )
    }
}

final class ControlHarnessPerformanceMonitor {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private struct RollingDurationWindow {
        let maxSamples: Int
        var samples: [Double] = []

        mutating func record(_ value: Double) {
            guard value.isFinite else { return }
            samples.append(value)
            if samples.count > maxSamples {
                samples.removeFirst(samples.count - maxSamples)
            }
        }

        func snapshot() -> ControlHarnessDurationMetricsSnapshot {
            guard !samples.isEmpty else {
                return .init(count: 0, averageMs: 0, p95Ms: 0, maxMs: 0)
            }

            let sorted = samples.sorted()
            let sum = samples.reduce(0, +)
            let p95Index = min(
                max(Int(ceil(Double(sorted.count) * 0.95)) - 1, 0),
                sorted.count - 1
            )

            return .init(
                count: sorted.count,
                averageMs: sum / Double(sorted.count),
                p95Ms: sorted[p95Index],
                maxMs: sorted.last ?? 0
            )
        }
    }

    private let queue = DispatchQueue(
        label: "com.leongong.ghodex.control-harness.performance-monitor",
        qos: .utility
    )
    private let now: () -> Date

    private var samplerTick = RollingDurationWindow(maxSamples: 64)
    private var samplerCapture = RollingDurationWindow(maxSamples: 128)
    private var gatewayRequest = RollingDurationWindow(maxSamples: 128)
    private var gatewayStreamLifetime = RollingDurationWindow(maxSamples: 64)

    private var lastSamplerTargetCount = 0
    private var lastSamplerRefreshedCount = 0
    private var lastSamplerTickAt: Date?
    private var lastCaptureScope: String?
    private var lastCaptureActivityClass: String?
    private var lastCaptureAt: Date?

    private var totalRequests = 0
    private var openStreams = 0
    private var totalStreamsStarted = 0
    private var totalStreamsClosed = 0
    private var requestCounts: [String: Int] = [:]
    private var requestTransportCounts: [String: Int] = [:]
    private var streamTransportCounts: [String: Int] = [:]
    private var streamCloseReasons: [String: Int] = [:]
    private var windowStartedAt: Date

    init(
        windowSize: Int = 128,
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        self.windowStartedAt = now()
        self.samplerTick = RollingDurationWindow(maxSamples: max(8, windowSize / 2))
        self.samplerCapture = RollingDurationWindow(maxSamples: max(8, windowSize))
        self.gatewayRequest = RollingDurationWindow(maxSamples: max(8, windowSize))
        self.gatewayStreamLifetime = RollingDurationWindow(maxSamples: max(8, windowSize / 2))
    }

    func recordSamplerTick(
        targetCount: Int,
        refreshedCount: Int,
        durationMs: Double,
        at: Date = Date()
    ) {
        queue.sync {
            samplerTick.record(durationMs)
            lastSamplerTargetCount = targetCount
            lastSamplerRefreshedCount = refreshedCount
            lastSamplerTickAt = at
        }
    }

    func recordSamplerCapture(
        scope: String,
        activityClass: ControlHarnessSamplingActivityClass,
        durationMs: Double,
        at: Date = Date()
    ) {
        queue.sync {
            samplerCapture.record(durationMs)
            lastCaptureScope = scope
            lastCaptureActivityClass = activityClass.rawValue
            lastCaptureAt = at
        }
    }

    func recordGatewayRequest(
        command: String,
        transport: String,
        durationMs: Double,
        at _: Date = Date()
    ) {
        queue.sync {
            gatewayRequest.record(durationMs)
            totalRequests += 1
            requestCounts[command, default: 0] += 1
            requestTransportCounts[transport, default: 0] += 1
        }
    }

    func recordGatewayStreamOpened(transport: String) {
        queue.sync {
            openStreams += 1
            totalStreamsStarted += 1
            streamTransportCounts[transport, default: 0] += 1
        }
    }

    func recordGatewayStreamClosed(
        transport _: String,
        reason: String,
        durationMs: Double,
        at _: Date = Date()
    ) {
        queue.sync {
            gatewayStreamLifetime.record(durationMs)
            openStreams = max(0, openStreams - 1)
            totalStreamsClosed += 1
            streamCloseReasons[reason, default: 0] += 1
        }
    }

    func snapshot(now: Date? = nil) -> ControlHarnessPerformanceSnapshot {
        queue.sync {
            let referenceNow = now ?? self.now()
            return ControlHarnessPerformanceSnapshot(
                generatedAt: Self.timestamp(referenceNow),
                windowStartedAt: Self.timestamp(windowStartedAt),
                windowAgeMs: max(0, Int(referenceNow.timeIntervalSince(windowStartedAt) * 1_000)),
                sampler: .init(
                    tick: samplerTick.snapshot(),
                    capture: samplerCapture.snapshot(),
                    lastTargetCount: lastSamplerTargetCount,
                    lastRefreshedCount: lastSamplerRefreshedCount,
                    lastTickAt: lastSamplerTickAt.map(Self.timestamp),
                    lastCaptureScope: lastCaptureScope,
                    lastCaptureActivityClass: lastCaptureActivityClass,
                    lastCaptureAt: lastCaptureAt.map(Self.timestamp)
                ),
                gateway: .init(
                    request: gatewayRequest.snapshot(),
                    streamLifetime: gatewayStreamLifetime.snapshot(),
                    totalRequests: totalRequests,
                    openStreams: openStreams,
                    totalStreamsStarted: totalStreamsStarted,
                    totalStreamsClosed: totalStreamsClosed,
                    requestCounts: requestCounts,
                    requestTransportCounts: requestTransportCounts,
                    streamTransportCounts: streamTransportCounts,
                    streamCloseReasons: streamCloseReasons
                )
            )
        }
    }

    func reset(now: Date? = nil) -> ControlHarnessPerformanceSnapshot {
        queue.sync {
            let referenceNow = now ?? self.now()
            samplerTick = RollingDurationWindow(maxSamples: samplerTick.maxSamples)
            samplerCapture = RollingDurationWindow(maxSamples: samplerCapture.maxSamples)
            gatewayRequest = RollingDurationWindow(maxSamples: gatewayRequest.maxSamples)
            gatewayStreamLifetime = RollingDurationWindow(maxSamples: gatewayStreamLifetime.maxSamples)
            lastSamplerTargetCount = 0
            lastSamplerRefreshedCount = 0
            lastSamplerTickAt = nil
            lastCaptureScope = nil
            lastCaptureActivityClass = nil
            lastCaptureAt = nil
            totalRequests = 0
            openStreams = 0
            totalStreamsStarted = 0
            totalStreamsClosed = 0
            requestCounts = [:]
            requestTransportCounts = [:]
            streamTransportCounts = [:]
            streamCloseReasons = [:]
            windowStartedAt = referenceNow
            return ControlHarnessPerformanceSnapshot.empty(now: referenceNow)
        }
    }

    static func timestamp(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
}
