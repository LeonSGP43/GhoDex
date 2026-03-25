import Foundation

final class ControlHarnessGatewaySubscription {
    private weak var subscriptionSession: ControlHarnessEventSubscriptionSession?
    private let queue = DispatchQueue(label: "com.leongong.ghodex.control-harness.gateway.subscription")

    private var subscriberID: UUID?
    private var closed = false

    init(
        subscriptionSession: ControlHarnessEventSubscriptionSession?,
        subscriberID: UUID?
    ) {
        self.subscriptionSession = subscriptionSession
        self.subscriberID = subscriberID
    }

    func close() {
        let payload = queue.sync { () -> (ControlHarnessEventSubscriptionSession?, UUID?) in
            guard !closed else { return (nil, nil) }
            closed = true
            let payload = (subscriptionSession, subscriberID)
            subscriberID = nil
            return payload
        }

        payload.0?.removeSubscriber(payload.1)
    }

    var isClosed: Bool {
        queue.sync { closed }
    }
}
