import Foundation

@MainActor
final class BrowserExternalEventBroker {
    static let shared = BrowserExternalEventBroker()

    private let maxBufferedEvents = 256
    private var subscriptions: [UUID: Subscription] = [:]

    private init() {}

    func subscribe(
        to controller: BrowserTabController,
        kinds: Set<BrowserExternalEventKind>
    ) -> BrowserExternalEventSubscriptionResult {
        let subscriptionID = UUID()
        let browserTabID = ScriptBrowserTab.stableID(controller: controller)
        let observedKinds = internalKinds(for: kinds)
        let observerToken = controller.model.subscribeToControlEvents(kinds: observedKinds.isEmpty ? nil : observedKinds) { [weak self, weak controller] event in
            guard let self else { return }
            self.record(event, for: subscriptionID, browserTabID: browserTabID, controller: controller)
        }

        subscriptions[subscriptionID] = Subscription(
            browserTabID: browserTabID,
            observerToken: observerToken,
            controller: controller,
            eventKinds: kinds,
            deliveredCount: 0,
            droppedCount: 0,
            bufferedEvents: []
        )

        return BrowserExternalEventSubscriptionResult(subscriptionID: subscriptionID)
    }

    func drain(
        subscriptionID: UUID,
        limit: Int?
    ) -> BrowserExternalEventDrainResult? {
        guard var subscription = subscriptions[subscriptionID] else {
            return nil
        }

        let eventCount = limit.map { max(0, $0) } ?? subscription.bufferedEvents.count
        let drainedEvents = Array(subscription.bufferedEvents.prefix(eventCount))
        subscription.bufferedEvents.removeFirst(drainedEvents.count)
        subscription.deliveredCount += drainedEvents.count

        let result = BrowserExternalEventDrainResult(
            subscriptionID: subscriptionID,
            nextCursor: subscription.deliveredCount,
            droppedCount: subscription.droppedCount,
            events: drainedEvents
        )

        subscription.droppedCount = 0
        subscriptions[subscriptionID] = subscription
        return result
    }

    @discardableResult
    func unsubscribe(subscriptionID: UUID) -> Bool {
        guard let subscription = subscriptions.removeValue(forKey: subscriptionID) else {
            return false
        }

        subscription.controller?.model.unsubscribeFromControlEvents(subscription.observerToken)
        return true
    }

    private func internalKinds(for externalKinds: Set<BrowserExternalEventKind>) -> Set<BrowserControlEventKind> {
        Set(externalKinds.compactMap { eventKind in
            switch eventKind {
            case .consoleMessage:
                return .consoleMessage
            case .bridgeReady:
                return .bridgeReady
            case .navigationStateChanged:
                return .navigationStateChanged
            case .pageTitleChanged:
                return .pageTitleChanged
            }
        })
    }

    private func externalKind(for event: BrowserControlEvent) -> BrowserExternalEventKind? {
        switch event.kind {
        case .consoleMessage:
            return .consoleMessage
        case .bridgeReady:
            return .bridgeReady
        case .navigationStateChanged:
            return .navigationStateChanged
        case .pageTitleChanged:
            return .pageTitleChanged
        case .openURLInNewTabRequested:
            return nil
        }
    }

    private func record(
        _ event: BrowserControlEvent,
        for subscriptionID: UUID,
        browserTabID: String,
        controller: BrowserTabController?
    ) {
        guard var subscription = subscriptions[subscriptionID] else { return }

        if subscription.controller == nil {
            subscription.controller = controller
        }

        guard let externalKind = externalKind(for: event) else {
            subscriptions[subscriptionID] = subscription
            return
        }

        if !subscription.eventKinds.isEmpty, !subscription.eventKinds.contains(externalKind) {
            subscriptions[subscriptionID] = subscription
            return
        }

        var payload = event.payload
        payload["pageID"] = event.target.pageID.uuidString
        payload["documentRevision"] = String(event.target.documentRevision)
        if let frameName = event.target.frameName {
            payload["frameName"] = frameName
        }

        subscription.bufferedEvents.append(
            BrowserExternalEventEnvelope(
                subscriptionID: subscriptionID,
                browserTabID: browserTabID,
                kind: externalKind,
                payload: payload
            )
        )

        if subscription.bufferedEvents.count > maxBufferedEvents {
            let overflow = subscription.bufferedEvents.count - maxBufferedEvents
            subscription.bufferedEvents.removeFirst(overflow)
            subscription.droppedCount += overflow
        }

        subscriptions[subscriptionID] = subscription
    }

    private struct Subscription {
        let browserTabID: String
        let observerToken: UUID
        weak var controller: BrowserTabController?
        let eventKinds: Set<BrowserExternalEventKind>
        var deliveredCount: Int
        var droppedCount: Int
        var bufferedEvents: [BrowserExternalEventEnvelope]
    }
}
