import Darwin
import CryptoKit
import Foundation
import OSLog

final class ControlHarnessGateway {
    private enum GatewayCommand {
        case pairingBegin
        case pairingExchange
        case tokenInfo
        case tokenRotate
        case tokenRevoke
    }

    struct Configuration: Sendable {
        var isEnabled = false
        var listenHost = "127.0.0.1"
        var listenPort: UInt16 = 0
        var maxBufferedEvents = 256
        var maxBufferedBytes = 1_048_576
        var authToken: String?
        var maxConcurrentSessionsPerIdentity = 2
        var maxGlobalRequestsPerMinute = 240
        var maxCommandsPerMinute = 60
        var maxSnapshotRequestsPerMinute = 30
        var maxResyncAttemptsPerMinute = 30

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
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_SNAPSHOT_REQUESTS_PER_MINUTE"]) {
                configuration.maxSnapshotRequestsPerMinute = max(1, value)
            }
            if let value = parseInt(environment["GHODEX_CONTROL_HARNESS_GATEWAY_MAX_RESYNC_ATTEMPTS_PER_MINUTE"]) {
                configuration.maxResyncAttemptsPerMinute = max(1, value)
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

    private let bundleID: String
    private let authManager: ControlHarnessAuth?
    private let requestHandler: (@MainActor (ControlHarnessRequest, String) -> ControlHarnessServiceReply)?
    private let requestAuthorizer: (@MainActor (ControlHarnessRequest) -> RequestAuthorization)?
    private let rateLimiter: ControlHarnessGatewayRateLimiter
    private let sessionRegistry: ControlHarnessGatewaySessionRegistry
    private let logger: Logger
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

    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init(
        bundleID: String,
        configuration: Configuration = .init(),
        authManager: ControlHarnessAuth? = nil,
        requestHandler: (@MainActor (ControlHarnessRequest, String) -> ControlHarnessServiceReply)? = nil,
        requestAuthorizer: (@MainActor (ControlHarnessRequest) -> RequestAuthorization)? = nil
    ) {
        self.bundleID = bundleID
        self.authManager = authManager
        self.requestHandler = requestHandler
        self.requestAuthorizer = requestAuthorizer
        self.rateLimiter = ControlHarnessGatewayRateLimiter(configuration: configuration)
        self.sessionRegistry = ControlHarnessGatewaySessionRegistry(
            maxConcurrentSessionsPerIdentity: configuration.maxConcurrentSessionsPerIdentity
        )
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
            logger.debug("control harness gateway transport is disabled")
            return
        }
        guard listenerFD == -1 else { return }

        do {
            let listener = try makeListener(host: configuration.listenHost, port: configuration.listenPort)
            listenerFD = listener.fd
            listenerPort = listener.port
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
            logger.notice(
                "control harness gateway listening at \(configuration.listenHost, privacy: .public):\(listener.port)"
            )
        } catch {
            logger.error("failed to start control harness gateway: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    func stop() {
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

        do {
            if try Self.looksLikeWebSocketHandshake(clientFD) {
                try handleWebSocketClient(clientFD, peerDescription: peerDescription)
                return
            }

            let requestData = try Self.readAll(from: clientFD)
            let request = try JSONDecoder().decode(ControlHarnessRequest.self, from: requestData)
            switch authorize(request, peerDescription: peerDescription) {
            case .deny(let response):
                try Self.writeAll(try encodeResponse(response), to: clientFD)
                return
            case .allow(let sessionIdentity):
                try withSessionReservation(
                    request: request,
                    peerDescription: peerDescription,
                    sessionIdentity: sessionIdentity,
                    responseWriter: { response in
                        try Self.writeAll(try encodeResponse(response), to: clientFD)
                    }
                ) {
                    let reply = callRequestHandler(request)
                    switch reply {
                    case .single(let response):
                        try Self.writeAll(try encodeResponse(response), to: clientFD)
                    case .subscription(let envelope):
                        try streamSubscription(envelope, to: clientFD)
                    }
                }
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
        }
    }

    private func handleWebSocketClient(
        _ clientFD: Int32,
        peerDescription: String
    ) throws {
        let handshake = try Self.readHTTPHeaders(from: clientFD)
        let key = try Self.parseWebSocketKey(from: handshake)
        try Self.writeAll(Self.webSocketHandshakeResponse(for: key), to: clientFD)

        let requestData = try Self.readWebSocketFrame(from: clientFD)
        let request = try JSONDecoder().decode(ControlHarnessRequest.self, from: requestData)

        switch authorize(request, peerDescription: peerDescription) {
        case .deny(let response):
            try Self.writeAll(try encodeWebSocketResponse(response), to: clientFD)
        case .allow(let sessionIdentity):
            try withSessionReservation(
                request: request,
                peerDescription: peerDescription,
                sessionIdentity: sessionIdentity,
                responseWriter: { response in
                    try Self.writeAll(try encodeWebSocketResponse(response), to: clientFD)
                }
            ) {
                let reply = callRequestHandler(request)
                switch reply {
                case .single(let response):
                    try Self.writeAll(try encodeWebSocketResponse(response), to: clientFD)
                case .subscription(let envelope):
                    try streamWebSocketSubscription(envelope, to: clientFD)
                }
            }
        }
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
        if let gatewayCommand = gatewayCommand(for: request) {
            return authorizeGatewayCommand(
                gatewayCommand,
                request: request,
                peerDescription: peerDescription
            )
        }

        if request.command == "handshake" {
            return .allow(sessionIdentity: nil)
        }

        if let authToken = configuration.authToken, request.authToken == authToken {
            return .allow(sessionIdentity: "static:\(authToken)")
        }

        if let requiredScope = requiredScope(for: request) {
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
                requiredScope: requiredScope,
                authManager: authManager
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

    private func continueAuthorization(
        request: ControlHarnessRequest,
        requestAuthorizer: (@MainActor (ControlHarnessRequest) -> RequestAuthorization)?,
        sessionIdentity: String?
    ) -> AuthorizationResult {
        guard let requestAuthorizer else { return .allow(sessionIdentity: sessionIdentity) }

        let semaphore = DispatchSemaphore(value: 0)
        var authorization: RequestAuthorization?

        Task { @MainActor in
            authorization = requestAuthorizer(request)
            semaphore.signal()
        }

        semaphore.wait()

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
            switch validateToken(request.authToken, requiredScope: nil, authManager: authManager) {
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

    private func handleGatewayCommand(_ request: ControlHarnessRequest) -> ControlHarnessResponse? {
        guard let gatewayCommand = gatewayCommand(for: request) else { return nil }
        guard let authManager else {
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: "gateway_auth_unavailable",
                errorMessage: "The gateway auth manager is unavailable"
            )
        }

        let result: Result<AnyEncodable, Error> = withAuthManager(authManager) {
            switch gatewayCommand {
            case .pairingBegin:
                let pairing = try await authManager.beginPairing(
                    client: request.client,
                    requestedScopes: request.requestedScopes
                )
                return AnyEncodable(pairing)
            case .pairingExchange:
                guard let pairingCode = request.pairingCode?.trimmingCharacters(in: .whitespacesAndNewlines),
                      pairingCode.isEmpty == false else {
                    throw ControlHarnessAuthError.invalidPairingCode
                }
                let issued = try await authManager.exchangePairingCode(pairingCode)
                return AnyEncodable(issued)
            case .tokenInfo:
                guard let token = request.authToken else {
                    throw ControlHarnessAuthError.invalidToken
                }
                return AnyEncodable(try await authManager.tokenStatus(for: token))
            case .tokenRotate:
                guard let token = request.authToken else {
                    throw ControlHarnessAuthError.invalidToken
                }
                return AnyEncodable(try await authManager.rotate(token: token))
            case .tokenRevoke:
                guard let token = request.authToken else {
                    throw ControlHarnessAuthError.invalidToken
                }
                return AnyEncodable(try await authManager.revoke(token: token))
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
            return ControlHarnessResponse(
                requestID: request.requestID,
                status: "error",
                result: nil,
                errorCode: "gateway_auth_failure",
                errorMessage: error.localizedDescription
            )
        }
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
        default:
            return nil
        }
    }

    private func requiredScope(for request: ControlHarnessRequest) -> ControlHarnessAuthScope? {
        switch request.command {
        case "snapshot", "read-terminal", "events.subscribe":
            return .observe
        case "new-tab", "close-tab", "send-text", "run-command", "close-terminal":
            return .mutate
        default:
            return nil
        }
    }

    private func validateToken(
        _ token: String?,
        requiredScope: ControlHarnessAuthScope?,
        authManager: ControlHarnessAuth
    ) -> ControlHarnessAuth.Validation {
        switch withAuthManager(authManager) {
        case .success(let validation):
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
        guard sessionRegistry.acquire(identity: sessionIdentity) else {
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

    private func rateLimitIdentity(
        for request: ControlHarnessRequest,
        peerDescription: String
    ) -> String {
        let authIdentity = request.authToken
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "anonymous"
        return "\(authIdentity)@\(peerDescription)"
    }

    private func streamSubscription(
        _ envelope: ControlHarnessSubscriptionEnvelope,
        to clientFD: Int32
    ) throws {
        let clientSession = makeClientSession()
        let attachment = attachSubscription(envelope, to: clientSession)
        defer {
            attachment.close()
            clientSession.close()
        }

        try flushClientSession(clientSession, to: clientFD)
        guard envelope.session != nil else {
            return
        }

        while true {
            _ = clientSession.waitForBufferedData()
            try flushClientSession(clientSession, to: clientFD)
            if clientSession.isClosed {
                let drain = clientSession.drain()
                if drain.payloads.isEmpty {
                    return
                }
                for payload in drain.payloads {
                    try Self.writeAll(payload, to: clientFD)
                }
                return
            }
        }
    }

    private func streamWebSocketSubscription(
        _ envelope: ControlHarnessSubscriptionEnvelope,
        to clientFD: Int32
    ) throws {
        let clientSession = makeClientSession()
        let attachment = attachSubscription(envelope, to: clientSession)
        defer {
            attachment.close()
            clientSession.close()
        }

        try flushWebSocketClientSession(clientSession, to: clientFD)
        guard envelope.session != nil else {
            return
        }

        while true {
            _ = clientSession.waitForBufferedData()
            try flushWebSocketClientSession(clientSession, to: clientFD)
            if clientSession.isClosed {
                let drain = clientSession.drain()
                if drain.payloads.isEmpty {
                    return
                }
                for payload in drain.payloads {
                    try Self.writeAll(Self.encodeWebSocketTextFrame(Self.trimTrailingLineFeed(payload)), to: clientFD)
                }
                return
            }
        }
    }

    private func flushClientSession(
        _ clientSession: ControlHarnessGatewayClientSession,
        to clientFD: Int32
    ) throws {
        let drain = clientSession.drain()
        for payload in drain.payloads {
            try Self.writeAll(payload, to: clientFD)
        }
    }

    private func flushWebSocketClientSession(
        _ clientSession: ControlHarnessGatewayClientSession,
        to clientFD: Int32
    ) throws {
        let drain = clientSession.drain()
        for payload in drain.payloads {
            try Self.writeAll(Self.encodeWebSocketTextFrame(Self.trimTrailingLineFeed(payload)), to: clientFD)
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

        let semaphore = DispatchSemaphore(value: 0)
        var reply: ControlHarnessServiceReply?

        Task { @MainActor in
            reply = requestHandler(request, listenerPathDescription())
            semaphore.signal()
        }

        semaphore.wait()
        return reply ?? .single(ControlHarnessResponse(
            requestID: request.requestID,
            status: "error",
            result: nil,
            errorCode: "internal_failure",
            errorMessage: "The control harness gateway failed to produce a response"
        ))
    }

    private func listenerPathDescription() -> String {
        "tcp://\(configuration.listenHost):\(listenerPort ?? configuration.listenPort)"
    }

    private func encodeResponse(_ response: ControlHarnessResponse) throws -> Data {
        var data = try encoder.encode(response)
        data.append(0x0A)
        return data
    }

    private func encodeWebSocketResponse(_ response: ControlHarnessResponse) throws -> Data {
        Self.encodeWebSocketTextFrame(Self.trimTrailingLineFeed(try encodeResponse(response)))
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

    private static func looksLikeWebSocketHandshake(_ fd: Int32) throws -> Bool {
        var buffer = [UInt8](repeating: 0, count: 4)
        let count = Darwin.recv(fd, &buffer, buffer.count, MSG_PEEK)
        if count == -1 {
            if errno == EINTR {
                return try looksLikeWebSocketHandshake(fd)
            }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard count >= 3 else {
            return false
        }
        let prefix = String(decoding: buffer.prefix(count), as: UTF8.self)
        return prefix.hasPrefix("GET ")
    }

    private static func readHTTPHeaders(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        let terminator = Data("\r\n\r\n".utf8)

        while data.range(of: terminator) == nil {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.count > 16_384 {
                    throw ControlHarnessGatewayError.invalidWebSocketHandshake
                }
                continue
            }
            if count == 0 {
                throw ControlHarnessGatewayError.invalidWebSocketHandshake
            }
            if errno == EINTR {
                continue
            }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        return data
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

    private static func webSocketHandshakeResponse(for key: String) -> Data {
        let acceptSeed = Data("\(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11".utf8)
        let digest = Insecure.SHA1.hash(data: acceptSeed)
        let accept = Data(digest).base64EncodedString()
        return Data(
            """
            HTTP/1.1 101 Switching Protocols\r
            Upgrade: websocket\r
            Connection: Upgrade\r
            Sec-WebSocket-Accept: \(accept)\r
            \r
            """.utf8
        )
    }

    private static func readWebSocketFrame(from fd: Int32) throws -> Data {
        let header = try readExact(from: fd, count: 2)
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
            let extended = try readExact(from: fd, count: 2)
            payloadLength = Int(UInt16(extended[0]) << 8 | UInt16(extended[1]))
        } else if payloadLength == 127 {
            let extended = try readExact(from: fd, count: 8)
            payloadLength = extended.reduce(0) { (partial, byte) in
                (partial << 8) | Int(byte)
            }
        }

        let mask = try readExact(from: fd, count: 4)
        var payload = try readExact(from: fd, count: payloadLength)
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
        var snapshot = WindowCounter()
        var resync = WindowCounter()
    }

    private enum Category {
        case command
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
            guard globalCounter.allow(limit: configuration.maxGlobalRequestsPerMinute, minuteWindow: minuteWindow) else {
                return .deny(
                    errorCode: "rate_limited",
                    errorMessage: "Gateway global request rate limit exceeded"
                )
            }

            guard let category = category(for: request) else {
                return .allow
            }

            var counters = identities[identity] ?? IdentityCounters()
            let allowed: Bool
            let errorMessage: String

            switch category {
            case .command:
                allowed = counters.command.allow(
                    limit: configuration.maxCommandsPerMinute,
                    minuteWindow: minuteWindow
                )
                errorMessage = "Gateway command rate limit exceeded"
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

            guard allowed else {
                return .deny(
                    errorCode: "rate_limited",
                    errorMessage: errorMessage
                )
            }

            return .allow
        }
    }

    private func category(for request: ControlHarnessRequest) -> Category? {
        switch request.command {
        case "send-text", "run-command", "close-terminal", "new-tab", "close-tab":
            return .command
        case "snapshot":
            return .snapshot
        case "read-terminal" where request.mode == "snapshot":
            return .snapshot
        case "events.subscribe":
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
