import Foundation
import Testing
@testable import GhoDex

struct DockTilePluginTests {
    @Test func shouldWriteBundleIconRejectsDerivedDataBundle() {
        let appURL = URL(
            fileURLWithPath: "/Users/test/Library/Developer/Xcode/DerivedData/GhoDex/Build/Products/Debug/GhoDex.app"
        )
        #expect(AppBundleIconMutationPolicy.shouldWriteBundleIcon(at: appURL) == false)
    }

    @Test func shouldWriteBundleIconRejectsBuildProductsBundle() {
        let appURL = URL(fileURLWithPath: "/tmp/ghodex-send-key/Build/Products/Debug/GhoDex.app")
        #expect(AppBundleIconMutationPolicy.shouldWriteBundleIcon(at: appURL) == false)
    }

    @Test func shouldWriteBundleIconRejectsRepoBuildBundle() {
        let appURL = URL(fileURLWithPath: "/Users/test/Desktop/LeonProjects/GhoDex/macos/build/ReleaseLocal/GhoDex.app")
        #expect(AppBundleIconMutationPolicy.shouldWriteBundleIcon(at: appURL) == false)
    }

    @Test func shouldWriteBundleIconAllowsInstalledBundle() {
        let appURL = URL(fileURLWithPath: "/Applications/GhoDex.app")
        #expect(AppBundleIconMutationPolicy.shouldWriteBundleIcon(at: appURL))
    }
}
