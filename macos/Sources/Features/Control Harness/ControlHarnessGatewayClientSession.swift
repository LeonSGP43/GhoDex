import Foundation

final class ControlHarnessGatewayClientSession {
    struct Limits: Sendable {
        let maxBufferedEvents: Int
        let maxBufferedBytes: Int
    }

    let id: UUID

    private let limits: Limits
    private let queue: DispatchQueue
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let dataAvailable = DispatchSemaphore(value: 0)

    private var bufferedPayloads: [Data] = []
    private var bufferedBytes = 0
    private var droppedEvents = 0
    private var requiresSnapshotResync = false
    private var closed = false

    init(
        id: UUID = UUID(),
        limits: Limits
    ) {
        self.id = id
        self.limits = limits
        self.queue = DispatchQueue(label: "com.leongong.ghodex.control-harness.gateway.session.\(id.uuidString)")
    }

    @discardableResult
    func enqueueEvent(_ data: Data) -> ControlHarnessGatewaySessionEnqueueResult {
        queue.sync {
            guard !closed else {
                return .overflowed
            }

            let wasEmpty = bufferedPayloads.isEmpty
            guard data.count <= limits.maxBufferedBytes else {
                enterOverflowLocked(droppedAdditionalEvents: 1)
                if wasEmpty {
                    dataAvailable.signal()
                }
                return .droppedOversize
            }

            if !requiresSnapshotResync,
               bufferedPayloads.count >= limits.maxBufferedEvents || bufferedBytes + data.count > limits.maxBufferedBytes {
                enterOverflowLocked(droppedAdditionalEvents: bufferedPayloads.count + 1)
                if wasEmpty {
                    dataAvailable.signal()
                }
                return .overflowed
            }

            if requiresSnapshotResync,
               bufferedPayloads.count + 1 > limits.maxBufferedEvents || bufferedBytes + data.count > limits.maxBufferedBytes {
                enterOverflowLocked(droppedAdditionalEvents: max(bufferedPayloads.count - 1, 0) + 1)
                if wasEmpty {
                    dataAvailable.signal()
                }
                return .overflowed
            }

            bufferedPayloads.append(data)
            bufferedBytes += data.count
            if wasEmpty {
                dataAvailable.signal()
            }
            return requiresSnapshotResync ? .overflowed : .buffered
        }
    }

    func waitForBufferedData(timeout: DispatchTime = .distantFuture) -> Bool {
        dataAvailable.wait(timeout: timeout) == .success
    }

    func drain() -> ControlHarnessGatewaySessionDrainResult {
        queue.sync {
            let result = ControlHarnessGatewaySessionDrainResult(
                payloads: bufferedPayloads,
                requiresSnapshotResync: requiresSnapshotResync,
                droppedEvents: droppedEvents
            )
            bufferedPayloads.removeAll(keepingCapacity: false)
            bufferedBytes = 0
            droppedEvents = 0
            requiresSnapshotResync = false
            return result
        }
    }

    func close() {
        let shouldSignal = queue.sync {
            guard !closed else { return false }
            closed = true
            return true
        }

        if shouldSignal {
            dataAvailable.signal()
        }
    }

    var isClosed: Bool {
        queue.sync { closed }
    }

    private func enterOverflowLocked(droppedAdditionalEvents: Int) {
        droppedEvents += max(droppedAdditionalEvents, 0)
        requiresSnapshotResync = true
        bufferedPayloads.removeAll(keepingCapacity: false)
        bufferedBytes = 0

        guard let marker = try? encoder.encode(
            ControlHarnessGatewayOverflowMarker(droppedEvents: droppedEvents)
        ) else {
            return
        }

        let markerLine = marker + Data([0x0A])
        bufferedPayloads = [markerLine]
        bufferedBytes = markerLine.count
    }
}
