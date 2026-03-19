import Foundation
import Darwin

final class BrowserControlIPCService {
    private let socketURL: URL
    private let queue = DispatchQueue(label: "com.leongong.ghodex.browser-control.ipc")
    private var listenFileDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]

    init(socketURL: URL = BrowserPaths.browserControlSocketURL()) {
        self.socketURL = socketURL
    }

    deinit {
        stop()
    }

    func start() {
        guard listenFileDescriptor == -1 else { return }

        do {
            try FileManager.default.createDirectory(
                at: socketURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            AppDelegate.logger.error("Failed to create browser IPC directory: \(error.localizedDescription)")
            return
        }

        let socketPath = socketURL.path
        let pathBytes = Array(socketPath.utf8CString)
        let pathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard pathBytes.count <= pathCapacity else {
            AppDelegate.logger.error("Browser IPC socket path is too long: \(socketPath, privacy: .public)")
            return
        }

        unlink(socketPath)

        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            AppDelegate.logger.error("Failed to create browser IPC socket: errno \(errno)")
            return
        }

        if !Self.configureListener(fileDescriptor: fileDescriptor) {
            close(fileDescriptor)
            unlink(socketPath)
            return
        }

        var address = sockaddr_un()
        address.sun_len = __uint8_t(MemoryLayout<sockaddr_un>.stride)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            let pathBuffer = buffer.bindMemory(to: CChar.self)
            pathBuffer.initialize(repeating: 0)
            for (index, byte) in pathBytes.enumerated() where index < pathBuffer.count {
                pathBuffer[index] = byte
            }
        }

        let bindResult = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }

        guard bindResult == 0 else {
            AppDelegate.logger.error("Failed to bind browser IPC socket: errno \(errno)")
            close(fileDescriptor)
            unlink(socketPath)
            return
        }

        guard listen(fileDescriptor, SOMAXCONN) == 0 else {
            AppDelegate.logger.error("Failed to listen on browser IPC socket: errno \(errno)")
            close(fileDescriptor)
            unlink(socketPath)
            return
        }

        chmod(socketPath, 0o600)

        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.resume()

        listenFileDescriptor = fileDescriptor
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil

        let activeConnections = connections.values
        connections.removeAll()
        for connection in activeConnections {
            connection.close()
        }

        if listenFileDescriptor >= 0 {
            close(listenFileDescriptor)
            listenFileDescriptor = -1
        }

        unlink(socketURL.path)
    }

    private func acceptPendingConnections() {
        guard listenFileDescriptor >= 0 else { return }

        while true {
            let clientFileDescriptor = accept(listenFileDescriptor, nil, nil)
            if clientFileDescriptor < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }

                AppDelegate.logger.error("Failed to accept browser IPC connection: errno \(errno)")
                return
            }

            let connection = Connection(
                fileDescriptor: clientFileDescriptor,
                queue: queue,
                processRequest: Self.processRequestJSON(_:),
                onClose: { [weak self] fileDescriptor in
                    self?.connections.removeValue(forKey: fileDescriptor)
                }
            )
            connections[clientFileDescriptor] = connection
            connection.start()
        }
    }

    private static func configureListener(fileDescriptor: Int32) -> Bool {
        var noSigPipe: Int32 = 1
        if setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) != 0 {
            AppDelegate.logger.error("Failed to configure browser IPC SO_NOSIGPIPE: errno \(errno)")
            return false
        }

        let currentFlags = fcntl(fileDescriptor, F_GETFL)
        guard currentFlags >= 0 else {
            AppDelegate.logger.error("Failed to read browser IPC socket flags: errno \(errno)")
            return false
        }

        guard fcntl(fileDescriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
            AppDelegate.logger.error("Failed to set browser IPC socket nonblocking: errno \(errno)")
            return false
        }

        return true
    }

    private static func processRequestJSON(_ requestJSON: String) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var responseJSON = encodeFailureResponse(
            .internalFailure("The browser IPC service did not produce a response.")
        )

        Task { @MainActor in
            defer { semaphore.signal() }

            do {
                responseJSON = try ScriptBrowserTab.runExternalCommandProtocol(requestJSON: requestJSON)
            } catch let error as BrowserExternalCommandError {
                responseJSON = encodeFailureResponse(error)
            } catch {
                responseJSON = encodeFailureResponse(
                    .internalFailure("The browser IPC service failed: \(error.localizedDescription)")
                )
            }
        }

        semaphore.wait()
        return responseJSON
    }

    private static func encodeFailureResponse(_ error: BrowserExternalCommandError) -> String {
        let response = BrowserExternalCommandResponse(
            id: UUID(),
            version: BrowserCommandProtocolVersion.v1,
            ok: false,
            resultJSON: nil,
            error: error
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(response),
              let encoded = String(data: data, encoding: .utf8) else {
            return """
            {"id":"\(UUID().uuidString)","version":"\(BrowserCommandProtocolVersion.v1)","ok":false,"resultJSON":null,"error":{"code":"internal_failure","message":"The browser IPC service could not encode its error response.","isRetryable":false}}
            """
        }

        return encoded
    }

    fileprivate static func encodeInvalidRequestResponse() -> String {
        encodeFailureResponse(.invalidRequest("The browser IPC request must be a UTF-8 JSON line."))
    }
}

private final class Connection {
    private let fileDescriptor: Int32
    private let queue: DispatchQueue
    private let processRequest: (String) -> String
    private let onClose: (Int32) -> Void
    private var readSource: DispatchSourceRead?
    private var inputBuffer = Data()
    private var didClose = false

    init(
        fileDescriptor: Int32,
        queue: DispatchQueue,
        processRequest: @escaping (String) -> String,
        onClose: @escaping (Int32) -> Void
    ) {
        self.fileDescriptor = fileDescriptor
        self.queue = queue
        self.processRequest = processRequest
        self.onClose = onClose
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleReadable()
        }
        source.resume()
        readSource = source
    }

    func close() {
        guard !didClose else { return }
        didClose = true
        readSource?.cancel()
        readSource = nil
        Darwin.close(fileDescriptor)
        onClose(fileDescriptor)
    }

    private func handleReadable() {
        guard !didClose else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let readCount = read(fileDescriptor, &buffer, buffer.count)
        if readCount > 0 {
            inputBuffer.append(buffer, count: readCount)
            processBufferedLines()
            return
        }

        close()
    }

    private func processBufferedLines() {
        while let newlineRange = inputBuffer.firstRange(of: Data([0x0A])) {
            let lineData = inputBuffer.subdata(in: inputBuffer.startIndex..<newlineRange.lowerBound)
            inputBuffer.removeSubrange(inputBuffer.startIndex...newlineRange.lowerBound)

            guard !lineData.isEmpty else { continue }
            guard let line = String(data: lineData, encoding: .utf8) else {
                writeResponse(BrowserControlIPCService.encodeInvalidRequestResponse())
                continue
            }

            let response = processRequest(line.trimmingCharacters(in: .newlines))
            writeResponse(response)
        }
    }

    private func writeResponse(_ response: String) {
        let responseBytes = Array((response + "\n").utf8)
        let wroteAllBytes = responseBytes.withUnsafeBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return true }

            var totalWritten = 0
            while totalWritten < rawBuffer.count {
                let bytePointer = baseAddress.advanced(by: totalWritten)
                let wrote = write(fileDescriptor, bytePointer, rawBuffer.count - totalWritten)
                if wrote <= 0 {
                    return false
                }
                totalWritten += wrote
            }

            return true
        }

        if !wroteAllBytes {
            close()
        }
    }
}
