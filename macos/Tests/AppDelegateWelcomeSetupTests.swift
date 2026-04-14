import Foundation
import Testing
@testable import GhoDex

struct AppDelegateWelcomeSetupTests {
    @Test func welcomeSetupAutoShowsOnlyOnce() {
        let suiteName = "AppDelegateWelcomeSetupTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        #expect(
            AppDelegate.shouldShowWelcomeSetupOnFirstLaunch(
                userDefaults: defaults,
                isRunningUnderTests: false
            )
        )

        AppDelegate.markWelcomeSetupShown(userDefaults: defaults)

        #expect(
            AppDelegate.shouldShowWelcomeSetupOnFirstLaunch(
                userDefaults: defaults,
                isRunningUnderTests: false
            ) == false
        )
    }

    @Test func welcomeSetupDoesNotAutoShowInsideTests() {
        let suiteName = "AppDelegateWelcomeSetupTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        #expect(
            AppDelegate.shouldShowWelcomeSetupOnFirstLaunch(
                userDefaults: defaults,
                isRunningUnderTests: true
            ) == false
        )
    }
}
