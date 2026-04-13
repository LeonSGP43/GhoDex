import Foundation
import Testing
@testable import GhoDex

@MainActor
struct BrowserBridgeReadinessTests {
    @Test func pageCanBeMarkedPendingAndRearmedForTheNextBridgeReadySignal() throws {
        let page = BrowserPageState(initialURL: try #require(URL(string: "https://example.com")))
        let bridge = BrowserPageControlBridge { _, _ in }

        page.bindControlBridge(bridge)
        page.markControlBridgeReady()
        #expect(page.isControlBridgeReady)

        page.markControlBridgePending()
        #expect(!page.isControlBridgeReady)

        page.markControlBridgeReady()
        #expect(page.isControlBridgeReady)
    }

    @Test func modelCanForceTheActivePageBridgeBackToPendingBeforeNavigationStarts() throws {
        let model = BrowserTabModel(initialURL: try #require(URL(string: "https://example.com")))
        let pageID = model.selectedPageID
        let bridge = BrowserPageControlBridge { _, _ in }
        let page = try #require(model.activePage)

        model.bindBridge(for: pageID, bridge: bridge)
        page.markControlBridgeReady()
        #expect(page.isControlBridgeReady)

        model.markBridgePending(for: pageID)

        #expect(!page.isControlBridgeReady)
    }
}
