import Foundation
import Darwin

final class BrowserControlIPCService {
    private let socketURL: URL
    private let listenerQueue = DispatchQueue(label: "com.leongong.ghodex.browser-control.ipc.listener")
    private let listenerQueueKey = DispatchSpecificKey<Void>()
    private var listenFileDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]

    init(socketURL: URL = BrowserPaths.browserControlSocketURL()) {
        self.socketURL = socketURL
        listenerQueue.setSpecific(key: listenerQueueKey, value: ())
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

        if !Self.configureSocket(fileDescriptor: fileDescriptor, nonblocking: true) {
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

        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: listenerQueue)
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

        let stopConnections = { [self] in
            let activeConnections = connections.values
            connections.removeAll()
            for connection in activeConnections {
                connection.close()
            }
        }

        if DispatchQueue.getSpecific(key: listenerQueueKey) != nil {
            stopConnections()
        } else {
            listenerQueue.sync(execute: stopConnections)
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

            guard Self.configureSocket(fileDescriptor: clientFileDescriptor, nonblocking: true) else {
                close(clientFileDescriptor)
                continue
            }

            let connectionQueue = DispatchQueue(
                label: "com.leongong.ghodex.browser-control.ipc.connection.\(clientFileDescriptor)"
            )
            let connection = Connection(
                fileDescriptor: clientFileDescriptor,
                queue: connectionQueue,
                processRequest: Self.processRequestJSON(_:completion:),
                onClose: { [weak self] fileDescriptor in
                    self?.listenerQueue.async {
                        self?.connections.removeValue(forKey: fileDescriptor)
                    }
                }
            )
            connections[clientFileDescriptor] = connection
            connection.start()
        }
    }

    private static func configureSocket(fileDescriptor: Int32, nonblocking: Bool) -> Bool {
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

        let nextFlags = nonblocking ? (currentFlags | O_NONBLOCK) : (currentFlags & ~O_NONBLOCK)
        guard fcntl(fileDescriptor, F_SETFL, nextFlags) == 0 else {
            AppDelegate.logger.error("Failed to set browser IPC socket flags: errno \(errno)")
            return false
        }

        return true
    }

    private static func processRequestJSON(
        _ requestJSON: String,
        completion: @escaping (String) -> Void
    ) {
        Task { @MainActor in
            let responseJSON: String
            do {
                responseJSON = try ScriptBrowserTab.runExternalCommandProtocol(requestJSON: requestJSON)
            } catch let error as BrowserExternalCommandError {
                responseJSON = encodeFailureResponse(error)
            } catch {
                responseJSON = encodeFailureResponse(
                    .internalFailure("The browser IPC service failed: \(error.localizedDescription)")
                )
            }

            completion(responseJSON)
        }
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
    private static let maxBufferedResponseBytes = 1024 * 1024

    private let fileDescriptor: Int32
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let processRequest: (String, @escaping (String) -> Void) -> Void
    private let onClose: (Int32) -> Void
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var inputBuffer = Data()
    private var pendingWrites: [Data] = []
    private var pendingWriteIndex = 0
    private var activeWrite = Data()
    private var activeWriteOffset = 0
    private var bufferedResponseBytes = 0
    private var didClose = false

    init(
        fileDescriptor: Int32,
        queue: DispatchQueue,
        processRequest: @escaping (String, @escaping (String) -> Void) -> Void,
        onClose: @escaping (Int32) -> Void
    ) {
        self.fileDescriptor = fileDescriptor
        self.queue = queue
        queue.setSpecific(key: queueKey, value: ())
        self.processRequest = processRequest
        self.onClose = onClose
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.readSource == nil, !self.didClose else { return }

            let source = DispatchSource.makeReadSource(fileDescriptor: self.fileDescriptor, queue: self.queue)
            source.setEventHandler { [weak self] in
                self?.handleReadable()
            }
            self.readSource = source
            source.resume()
        }
    }

    func close() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            closeLocked()
            return
        }

        queue.sync { [weak self] in
            self?.closeLocked()
        }
    }

    private func closeLocked() {
        guard !didClose else { return }
        didClose = true
        readSource?.cancel()
        readSource = nil
        writeSource?.cancel()
        writeSource = nil
        pendingWrites.removeAll(keepingCapacity: false)
        pendingWriteIndex = 0
        activeWrite.removeAll(keepingCapacity: false)
        bufferedResponseBytes = 0
        Darwin.close(fileDescriptor)
        onClose(fileDescriptor)
    }

    private func handleReadable() {
        guard !didClose else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let readCount = Darwin.read(fileDescriptor, &buffer, buffer.count)
            if readCount > 0 {
                inputBuffer.append(buffer, count: readCount)
                processBufferedLines()
                continue
            }

            if readCount == 0 {
                closeLocked()
                return
            }

            if errno == EWOULDBLOCK || errno == EAGAIN {
                return
            }

            closeLocked()
            return
        }
    }

    private func processBufferedLines() {
        while let newlineRange = inputBuffer.firstRange(of: Data([0x0A])) {
            let lineData = inputBuffer.subdata(in: inputBuffer.startIndex..<newlineRange.lowerBound)
            inputBuffer.removeSubrange(inputBuffer.startIndex...newlineRange.lowerBound)

            guard !lineData.isEmpty else { continue }
            guard let line = String(data: lineData, encoding: .utf8) else {
                enqueueResponse(BrowserControlIPCService.encodeInvalidRequestResponse())
                continue
            }

            processRequest(line.trimmingCharacters(in: .newlines)) { [weak self] response in
                self?.enqueueResponse(response)
            }
        }
    }

    private func enqueueResponse(_ response: String) {
        queue.async { [weak self] in
            guard let self, !self.didClose else { return }

            let responseData = Data((response + "\n").utf8)
            let nextBufferedByteCount = self.bufferedResponseBytes + responseData.count
            guard nextBufferedByteCount <= Self.maxBufferedResponseBytes else {
                AppDelegate.logger.error(
                    "Closing browser IPC connection due to response backpressure: fd=\(self.fileDescriptor) queued_bytes=\(nextBufferedByteCount)"
                )
                self.closeLocked()
                return
            }

            self.bufferedResponseBytes = nextBufferedByteCount
            self.pendingWrites.append(responseData)
            self.flushWritableBytes()
        }
    }

    private func flushWritableBytes() {
        guard !didClose else { return }

        while true {
            if activeWrite.isEmpty {
                guard pendingWriteIndex < pendingWrites.count else {
                    pendingWrites.removeAll(keepingCapacity: false)
                    pendingWriteIndex = 0
                    disarmWriteSource()
                    return
                }

                activeWrite = pendingWrites[pendingWriteIndex]
                pendingWrites[pendingWriteIndex] = Data()
                pendingWriteIndex += 1
                if pendingWriteIndex >= pendingWrites.count {
                    pendingWrites.removeAll(keepingCapacity: false)
                    pendingWriteIndex = 0
                } else if pendingWriteIndex > 32, pendingWriteIndex * 2 >= pendingWrites.count {
                    pendingWrites.removeFirst(pendingWriteIndex)
                    pendingWriteIndex = 0
                }
                activeWriteOffset = 0
            }

            let writeCount = activeWrite.withUnsafeBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                let nextPointer = baseAddress.advanced(by: activeWriteOffset)
                return Darwin.write(fileDescriptor, nextPointer, rawBuffer.count - activeWriteOffset)
            }

            if writeCount > 0 {
                activeWriteOffset += writeCount
                bufferedResponseBytes -= writeCount
                if activeWriteOffset == activeWrite.count {
                    activeWrite.removeAll(keepingCapacity: false)
                    activeWriteOffset = 0
                }
                continue
            }

            if writeCount < 0, errno == EWOULDBLOCK || errno == EAGAIN {
                armWriteSource()
                return
            }

            closeLocked()
            return
        }
    }

    private func armWriteSource() {
        guard writeSource == nil, !didClose else { return }

        let source = DispatchSource.makeWriteSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.flushWritableBytes()
        }
        source.resume()
        writeSource = source
    }

    private func disarmWriteSource() {
        guard let source = writeSource else { return }
        writeSource = nil
        source.cancel()
    }
}
