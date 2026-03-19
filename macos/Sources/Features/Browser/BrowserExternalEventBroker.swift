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
        var kinds = Set<BrowserControlEventKind>(externalKinds.compactMap { eventKind in
            switch eventKind {
            case .consoleMessage:
                return BrowserControlEventKind.consoleMessage
            case .bridgeReady:
                return BrowserControlEventKind.bridgeReady
            case .navigationStateChanged:
                return BrowserControlEventKind.navigationStateChanged
            case .pageTitleChanged:
                return BrowserControlEventKind.pageTitleChanged
            case .networkRequestFinished:
                return BrowserControlEventKind.networkRequestFinished
            case .pageInspectionSnapshot:
                return nil
            }
        })

        if externalKinds.contains(.pageInspectionSnapshot) {
            kinds.insert(BrowserControlEventKind.bridgeReady)
            kinds.insert(BrowserControlEventKind.navigationStateChanged)
        }

        return kinds
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
        case .networkRequestFinished:
            return .networkRequestFinished
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

        if shouldCaptureInspectionSnapshot(for: subscription, event: event) {
            captureInspectionSnapshot(for: subscriptionID, event: event, controller: controller)
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

        appendEvent(
            BrowserExternalEventEnvelope(
                subscriptionID: subscriptionID,
                browserTabID: browserTabID,
                kind: externalKind,
                payload: payload
            ),
            to: &subscription
        )
        subscriptions[subscriptionID] = subscription
    }

    private func shouldCaptureInspectionSnapshot(
        for subscription: Subscription,
        event: BrowserControlEvent
    ) -> Bool {
        guard subscription.eventKinds.contains(.pageInspectionSnapshot) else {
            return false
        }

        switch event.kind {
        case .bridgeReady:
            return true
        case .navigationStateChanged:
            return event.payload["isLoading"] == "false"
        default:
            return false
        }
    }

    private func captureInspectionSnapshot(
        for subscriptionID: UUID,
        event: BrowserControlEvent,
        controller: BrowserTabController?
    ) {
        guard let controller else { return }

        let browserTabID = ScriptBrowserTab.stableID(controller: controller)
        controller.model.requestInspectionSnapshot(for: event.target.pageID, maxDepth: 2, includeText: true) { [weak self] result in
            guard let self else { return }
            guard var subscription = self.subscriptions[subscriptionID] else { return }
            guard subscription.eventKinds.contains(.pageInspectionSnapshot) else { return }

            var payload: [String: String] = [
                "pageID": event.target.pageID.uuidString,
                "documentRevision": String(event.target.documentRevision),
                "triggerKind": event.kind.rawValue,
            ]
            if let frameName = event.target.frameName {
                payload["frameName"] = frameName
            }

            switch result {
            case let .success(snapshot):
                payload["ok"] = "true"
                payload["snapshotJSON"] = (try? encodeJSON(snapshot)) ?? ""
            case let .failure(error):
                payload["ok"] = "false"
                payload["errorCode"] = error.code.rawValue
                payload["errorMessage"] = error.message
            }

            self.appendEvent(
                BrowserExternalEventEnvelope(
                    subscriptionID: subscriptionID,
                    browserTabID: browserTabID,
                    kind: .pageInspectionSnapshot,
                    payload: payload
                ),
                to: &subscription
            )
            self.subscriptions[subscriptionID] = subscription
        }
    }

    private func appendEvent(
        _ event: BrowserExternalEventEnvelope,
        to subscription: inout Subscription
    ) {
        subscription.bufferedEvents.append(event)
        if subscription.bufferedEvents.count > maxBufferedEvents {
            let overflow = subscription.bufferedEvents.count - maxBufferedEvents
            subscription.bufferedEvents.removeFirst(overflow)
            subscription.droppedCount += overflow
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw BrowserExternalCommandError.internalFailure("The browser inspection event payload could not be serialized as UTF-8.")
        }
        return encoded
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
