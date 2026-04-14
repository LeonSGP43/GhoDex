import Testing
@testable import GhoDex

struct AppDelegateMouseNavigationTests {
    @Test func backButtonWrapsToPreviousTopLevelTab() {
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                forButtonNumber: 3,
                selectedIndex: 0,
                tabCount: 3
            ) == 2
        )
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                forButtonNumber: 3,
                selectedIndex: 2,
                tabCount: 3
            ) == 1
        )
    }

    @Test func forwardButtonWrapsToNextTopLevelTab() {
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                forButtonNumber: 4,
                selectedIndex: 2,
                tabCount: 3
            ) == 0
        )
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                forButtonNumber: 4,
                selectedIndex: 0,
                tabCount: 3
            ) == 1
        )
    }

    @Test func nonNavigationButtonsAndInvalidStateDoNotSwitchTabs() {
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                forButtonNumber: 2,
                selectedIndex: 0,
                tabCount: 3
            ) == nil
        )
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                forButtonNumber: 3,
                selectedIndex: 0,
                tabCount: 1
            ) == nil
        )
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                forButtonNumber: 4,
                selectedIndex: 4,
                tabCount: 3
            ) == nil
        )
    }
}
