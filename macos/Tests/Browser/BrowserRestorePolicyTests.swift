import Foundation
import Testing
@testable import GhoDex

struct BrowserRestorePolicyTests {
    @Test func browserWindowsRestoreForNormalManagedRuns() {
        #expect(BrowserPaths.shouldRestoreBrowserWindows(
            windowSaveState: "default",
            configuredExternalProfile: nil,
            isolatedAppSupportRootOverride: nil
        ) == true)
    }

    @Test func browserWindowsDoNotRestoreWhenWindowSaveStateIsNever() {
        #expect(BrowserPaths.shouldRestoreBrowserWindows(
            windowSaveState: "never",
            configuredExternalProfile: nil,
            isolatedAppSupportRootOverride: nil
        ) == false)
    }

    @Test func browserWindowsDoNotRestoreForExternalProfiles() {
        #expect(BrowserPaths.shouldRestoreBrowserWindows(
            windowSaveState: "default",
            configuredExternalProfile: "/Users/test/Library/Application Support/Google/Chrome/Profile 1",
            isolatedAppSupportRootOverride: nil
        ) == false)
    }

    @Test func browserWindowsDoNotRestoreForIsolatedBrowserRoots() {
        #expect(BrowserPaths.shouldRestoreBrowserWindows(
            windowSaveState: "default",
            configuredExternalProfile: nil,
            isolatedAppSupportRootOverride: URL(fileURLWithPath: "/tmp/ghx-browser-isolated", isDirectory: true)
        ) == false)
    }
}
