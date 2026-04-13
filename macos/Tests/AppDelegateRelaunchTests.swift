import Foundation
import Testing
@testable import GhoDex

struct AppDelegateRelaunchTests {
    @Test func relaunchPlanPreservesCurrentExecutableEnvironmentAndWorkingDirectory() {
        let executablePath = "/Applications/GhoDex.app/Contents/MacOS/GhoDex"
        let bundlePath = "/Applications/GhoDex.app"
        let environment = [
            "HOME": "/tmp/ghx-home",
            "TMPDIR": "/tmp/ghx-home/tmp",
            "GHODEX_BROWSER_APP_SUPPORT_ROOT": "/tmp/ghx-support",
            "GHOSTTY_CONFIG_PATH": "/tmp/ghx-home/.config/ghostty/config",
            "GHODEX_CEF_ROOT": "/tmp/cef-runtime",
        ]

        let plan = AppDelegate.makeRelaunchProcessPlan(
            executableURL: URL(fileURLWithPath: executablePath),
            bundlePath: bundlePath,
            arguments: [executablePath, "-psn_0_0", "--restored", "yes"],
            environment: environment,
            currentDirectoryPath: "/tmp/ghx-session"
        )

        #expect(plan.executableURL.path == executablePath)
        #expect(plan.arguments == ["--restored", "yes"])
        #expect(plan.environment == environment)
        #expect(plan.currentDirectoryURL?.path == "/tmp/ghx-session")
    }

    @Test func relaunchPlanFallsBackToOpenWhenExecutableURLIsUnavailable() {
        let plan = AppDelegate.makeRelaunchProcessPlan(
            executableURL: nil,
            bundlePath: "/Applications/GhoDex.app",
            arguments: ["/Applications/GhoDex.app/Contents/MacOS/GhoDex"],
            environment: ["HOME": "/tmp/ghx-home"],
            currentDirectoryPath: "/tmp/ghx-session"
        )

        #expect(plan.executableURL.path == "/usr/bin/open")
        #expect(plan.arguments == ["-n", "/Applications/GhoDex.app"])
        #expect(plan.environment == nil)
        #expect(plan.currentDirectoryURL == nil)
    }
}
