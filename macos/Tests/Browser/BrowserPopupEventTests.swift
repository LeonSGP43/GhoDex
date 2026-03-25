import Foundation
import Testing
@testable import GhoDex

@MainActor
struct BrowserPopupEventTests {
    @Test func popupRequestEventIncludesResolvedPageTabOutcome() throws {
        let model = BrowserTabModel(initialURL: try #require(URL(string: "https://example.com")))
        let sourcePageID = model.selectedPageID
        let sourceTarget = try #require(model.controlTarget(for: sourcePageID))
        var receivedEvent: BrowserControlEvent?

        let token = model.subscribeToControlEvents(kinds: [.openURLInNewTabRequested]) { event in
            receivedEvent = event
        }
        defer { model.unsubscribeFromControlEvents(token) }

        model.handle(
            .openURLInNewTabRequested(
                target: sourceTarget,
                url: "https://popup.example/child",
                disposition: .newForegroundTab,
                userGesture: true
            ),
            from: sourcePageID
        )

        let event = try #require(receivedEvent)
        #expect(event.payload["sourcePageID"] == sourcePageID.uuidString)
        #expect(event.payload["requestedURL"] == "https://popup.example/child")
        #expect(event.payload["dispositionName"] == "newForegroundTab")
        #expect(event.payload["routingTarget"] == "pageTab")
        #expect(event.payload["resultIsActive"] == "true")
        #expect(event.payload["resultVisibilityState"] == "foreground")

        let resultPageID = try #require(event.payload["resultPageID"]).lowercased()
        #expect(model.selectedPageID.uuidString.lowercased() == resultPageID)
        #expect(model.pages.contains { $0.id.uuidString.lowercased() == resultPageID })
    }

    @Test func popupRequestEventIncludesResolvedBrowserWindowOutcome() throws {
        let model = BrowserTabModel(initialURL: try #require(URL(string: "https://example.com")))
        let sourcePageID = model.selectedPageID
        let sourceTarget = try #require(model.controlTarget(for: sourcePageID))
        let destinationPageID = UUID()
        var receivedEvent: BrowserControlEvent?

        model.openURLInNewWindowHandler = { _ in
            BrowserPopupOpenWindowResult(
                browserTabID: "browser-tab-popup-target",
                pageID: destinationPageID,
                isPageActive: true,
                visibilityState: "newWindowRequested"
            )
        }

        let token = model.subscribeToControlEvents(kinds: [.openURLInNewTabRequested]) { event in
            receivedEvent = event
        }
        defer { model.unsubscribeFromControlEvents(token) }

        model.handle(
            .openURLInNewTabRequested(
                target: sourceTarget,
                url: "https://popup.example/window",
                disposition: .newWindow,
                userGesture: true
            ),
            from: sourcePageID
        )

        let event = try #require(receivedEvent)
        #expect(event.payload["routingTarget"] == "browserWindow")
        #expect(event.payload["resultBrowserTabID"] == "browser-tab-popup-target")
        #expect(event.payload["resultPageID"] == destinationPageID.uuidString)
        #expect(event.payload["resultIsActive"] == "true")
        #expect(event.payload["resultVisibilityState"] == "newWindowRequested")
    }

    @Test func popupRequestEventIncludesDedicatedPopupHostOutcome() throws {
        let model = BrowserTabModel(initialURL: try #require(URL(string: "https://example.com")))
        let sourcePageID = model.selectedPageID
        let sourceTarget = try #require(model.controlTarget(for: sourcePageID))
        var receivedEvent: BrowserControlEvent?

        let token = model.subscribeToControlEvents(kinds: [.popupWindowHosted]) { event in
            receivedEvent = event
        }
        defer { model.unsubscribeFromControlEvents(token) }

        model.handle(
            .popupWindowHosted(
                target: sourceTarget,
                url: "https://popup.example/dedicated",
                disposition: .newPopup,
                userGesture: true
            ),
            from: sourcePageID
        )

        let event = try #require(receivedEvent)
        #expect(event.payload["sourcePageID"] == sourcePageID.uuidString)
        #expect(event.payload["requestedURL"] == "https://popup.example/dedicated")
        #expect(event.payload["dispositionName"] == "newPopup")
        #expect(event.payload["routingTarget"] == "popupWindowHost")
        #expect(event.payload["resultIsActive"] == "true")
        #expect(event.payload["resultVisibilityState"] == "popupWindowForeground")
        #expect(event.payload["resultPageID"] == nil)
        #expect(event.payload["resultBrowserTabID"] == nil)
    }
}
