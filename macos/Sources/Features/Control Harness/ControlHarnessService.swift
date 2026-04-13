import Darwin
import Foundation
import OSLog

final class ControlHarnessService {
    private let bundleID: String
    private let requestHandler: @MainActor (ControlHarnessRequest, String) async -> ControlHarnessServiceReply
    private let logger: Logger
    private let acceptQueue = DispatchQueue(
        label: "com.leongong.ghodex.control-harness.service.accept",
        qos: .userInitiated
    )
    private let clientQueue = DispatchQueue(
        label: "com.leongong.ghodex.control-harness.service.client",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private(set) var socketURL: URL

    init(
        bundleID: String,
        requestHandler: @escaping @MainActor (ControlHarnessRequest, String) async -> ControlHarnessServiceReply
    ) {
        self.bundleID = bundleID
        self.requestHandler = requestHandler
        self.socketURL = Self.socketDirectory(bundleID: bundleID)
            .appendingPathComponent("harness.sock", isDirectory: false)
        self.logger = Logger(subsystem: bundleID, category: "ControlHarnessService")
    }

    deinit {
        stop()
    }

    func startIfNeeded() {
        guard listenerFD == -1 else { return }

        do {
            try FileManager.default.createDirectory(
                at: socketURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try removeStaleSocketIfNeeded()
            listenerFD = try makeListener(at: socketURL)
            let source = DispatchSource.makeReadSource(fileDescriptor: listenerFD, queue: acceptQueue)
            source.setEventHandler { [weak self] in
                self?.acceptAvailableConnections()
            }
            source.setCancelHandler { [socketURL, listenerFD] in
                if listenerFD >= 0 {
                    Darwin.close(listenerFD)
                }
                try? FileManager.default.removeItem(at: socketURL)
            }
            source.resume()
            acceptSource = source
            logger.notice("control harness listening at \(self.socketURL.path, privacy: .public)")
        } catch {
            logger.error("failed to start control harness service: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    func stop() {
        if let acceptSource {
            self.acceptSource = nil
            acceptSource.cancel()
            listenerFD = -1
            return
        }

        if listenerFD >= 0 {
            Darwin.close(listenerFD)
            listenerFD = -1
        }

        try? FileManager.default.removeItem(at: socketURL)
    }

    private func acceptAvailableConnections() {
        while true {
            let clientFD = Darwin.accept(listenerFD, nil, nil)
            if clientFD == -1 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }
                logger.error("failed to accept control harness connection: \(String(cString: strerror(errno)), privacy: .public)")
                return
            }

            do {
                try Self.setBlocking(clientFD)
            } catch {
                logger.error("failed to configure control harness client socket: \(error.localizedDescription, privacy: .public)")
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

        do {
            let requestData = try Self.readAll(from: clientFD)
            let decoder = JSONDecoder()
            let request = try decoder.decode(ControlHarnessRequest.self, from: requestData)
            let reply = callRequestHandler(request)
            switch reply {
            case .single(let response):
                try Self.writeResponse(response, to: clientFD, prettyPrinted: true)
            case .subscription(let envelope):
                try streamSubscription(envelope, to: clientFD)
            }
        } catch {
            logger.error("failed to process control harness client: \(error.localizedDescription, privacy: .public)")
            let fallback = ControlHarnessResponse(
                requestID: "unknown",
                status: "error",
                result: nil,
                errorCode: "decode_failure",
                errorMessage: error.localizedDescription
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(fallback) {
                try? Self.writeAll(data, to: clientFD)
            }
        }
    }

    private func streamSubscription(
        _ envelope: ControlHarnessSubscriptionEnvelope,
        to clientFD: Int32
    ) throws {
        let session = envelope.session
        let semaphore = DispatchSemaphore(value: 0)
        let subscriberID = session?.addSubscriber(
            sink: { [logger] data in
                do {
                    try Self.writeAll(data, to: clientFD)
                    return true
                } catch {
                    logger.error("failed to stream control harness event: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            },
            onFinish: {
                semaphore.signal()
            }
        )

        try Self.writeResponse(envelope.response, to: clientFD, prettyPrinted: false)

        guard let session else {
            return
        }

        for event in session.replayEvents {
            try Self.writeAll(event, to: clientFD)
        }

        session.completeReplay()

        if subscriberID != nil {
            semaphore.wait()
        }
    }

    private func callRequestHandler(_ request: ControlHarnessRequest) -> ControlHarnessServiceReply {
        let semaphore = DispatchSemaphore(value: 0)
        var reply: ControlHarnessServiceReply?

        Task { @MainActor in
            reply = await requestHandler(request, socketURL.path)
            semaphore.signal()
        }

        semaphore.wait()
        return reply ?? .single(ControlHarnessResponse(
            requestID: request.requestID,
            status: "error",
            result: nil,
            errorCode: "internal_failure",
            errorMessage: "The control harness failed to produce a response"
        ))
    }

    private static func writeResponse(
        _ response: ControlHarnessResponse,
        to clientFD: Int32,
        prettyPrinted: Bool
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        var responseData = try encoder.encode(response)
        responseData.append(0x0A)
        try writeAll(responseData, to: clientFD)
    }

    private func removeStaleSocketIfNeeded() throws {
        let path = socketURL.path
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(at: socketURL)
        }
    }

    private static func socketDirectory(bundleID: String) -> URL {
        let fileManager = FileManager.default
        let caches = (try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return caches
            .appendingPathComponent(socketNamespace(for: bundleID), isDirectory: true)
            .appendingPathComponent("ControlHarness", isDirectory: true)
    }

    private static func socketNamespace(for bundleID: String) -> String {
        "ghdx-\(fnv1a64Hex(bundleID))"
    }

    private static func fnv1a64Hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private func makeListener(at url: URL) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        do {
            try Self.setNonBlocking(fd)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(url.path.utf8)
            let capacity = MemoryLayout.size(ofValue: address.sun_path)
            guard pathBytes.count < capacity else {
                throw ControlHarnessServiceError.socketPathTooLong(url.path)
            }
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                buffer.initializeMemory(as: UInt8.self, repeating: 0)
                pathBytes.withUnsafeBytes { bytes in
                    buffer.copyBytes(from: bytes)
                }
            }

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            guard Darwin.listen(fd, SOMAXCONN) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return fd
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
}

enum ControlHarnessServiceError: LocalizedError {
    case socketPathTooLong(String)

    var errorDescription: String? {
        switch self {
        case .socketPathTooLong(let path):
            return "Control harness socket path is too long: \(path)"
        }
    }
}
