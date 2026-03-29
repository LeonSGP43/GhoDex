import Testing
@testable import GhoDex

struct AppDelegateStartupPolicyTests {
    @Test func skipInitialTerminalWindowDefaultsToFalse() {
        #expect(AppDelegate.shouldSkipInitialTerminalWindow(environment: [:]) == false)
    }

    @Test func skipInitialTerminalWindowAcceptsTruthyValues() {
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "1"]
            )
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": " TRUE "]
            )
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "yes"]
            )
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "on"]
            )
        )
    }

    @Test func skipInitialTerminalWindowRejectsFalsyValues() {
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "0"]
            ) == false
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "false"]
            ) == false
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "nope"]
            ) == false
        )
    }
}
