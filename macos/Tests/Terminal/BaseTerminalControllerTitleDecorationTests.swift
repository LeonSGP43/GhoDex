import Testing
@testable import Ghostty

struct TerminalTitleDecorationTests {
    @Test func leavesPlainTitleUntouched() {
        #expect(
            BaseTerminalController.decorateTitle(
                title: "Build",
                bell: false,
                showsBellInTitle: false,
                suppressBellDecoration: false
            ) == "Build"
        )
    }

    @Test func ignoresBellWhenEnabled() {
        #expect(
            BaseTerminalController.decorateTitle(
                title: "Build",
                bell: true,
                showsBellInTitle: true,
                suppressBellDecoration: false
            ) == "Build"
        )
    }

    @Test func ignoresBellWhenTitleFeatureDisabled() {
        #expect(
            BaseTerminalController.decorateTitle(
                title: "Build",
                bell: true,
                showsBellInTitle: false,
                suppressBellDecoration: false
            ) == "Build"
        )
    }

    @Test func ignoresBellWhenSuppressed() {
        #expect(
            BaseTerminalController.decorateTitle(
                title: "Build",
                bell: true,
                showsBellInTitle: true,
                suppressBellDecoration: true
            ) == "Build"
        )
    }
}
