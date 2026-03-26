import Testing
@testable import GhoDex

struct LastWindowCloseTerminationPolicyTests {
    @Test func browserLastCloseDoesNotTerminateApp() async throws {
        let shouldTerminate = LastWindowCloseTerminationPolicy.shouldTerminateAfterLastWindowClosed(
            shouldQuitAfterLastWindowClosed: true,
            lastClosedWindowKind: .browser
        )

        #expect(shouldTerminate == false)
    }

    @Test func terminalLastCloseStillHonorsQuitAfterLastWindowClosed() async throws {
        let shouldTerminate = LastWindowCloseTerminationPolicy.shouldTerminateAfterLastWindowClosed(
            shouldQuitAfterLastWindowClosed: true,
            lastClosedWindowKind: .terminal
        )

        #expect(shouldTerminate == true)
    }

    @Test func disabledQuitAfterLastWindowClosedAlwaysStaysRunning() async throws {
        let shouldTerminate = LastWindowCloseTerminationPolicy.shouldTerminateAfterLastWindowClosed(
            shouldQuitAfterLastWindowClosed: false,
            lastClosedWindowKind: .terminal
        )

        #expect(shouldTerminate == false)
    }

    @Test func cefPopupWindowsAreClassifiedAsBrowserCloses() async throws {
        let kind = LastClosedTopLevelWindowKind.fromWindowControllerClassName(
            "GhoDexCEFPopupWindowController"
        )

        #expect(kind == .browser)
    }

    @Test func unknownWindowControllersFallBackToOther() async throws {
        let kind = LastClosedTopLevelWindowKind.fromWindowControllerClassName("AboutController")

        #expect(kind == .other)
    }
}
