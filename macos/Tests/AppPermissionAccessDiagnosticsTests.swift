import Foundation
import Testing
@testable import GhoDex

struct AppPermissionAccessDiagnosticsTests {
    @Test func privacySettingsDestinationsIncludeExpectedCandidates() {
        let filesAndFolders = AppPermissionPrivacySettingsDestination.filesAndFolders.candidateURLs
            .map(\.absoluteString)
        #expect(
            filesAndFolders.contains(
                "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
            )
        )
        #expect(
            filesAndFolders.contains("file:///System/Library/PreferencePanes/Security.prefPane/")
        )

        let fullDiskAccess = AppPermissionPrivacySettingsDestination.fullDiskAccess.candidateURLs
            .map(\.absoluteString)
        #expect(
            fullDiskAccess.contains(
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            )
        )
        #expect(
            fullDiskAccess.contains("file:///System/Library/PreferencePanes/Security.prefPane/")
        )
    }

    @Test func unavailableSigningDiagnosticsUseLocalizedFallbackText() {
        let invalidBundleURL = URL(fileURLWithPath: "/tmp/ghodex-missing-bundle-\(UUID().uuidString)")
        let diagnostics = AppPermissionAccessDiagnostics.current(bundleURL: invalidBundleURL)

        guard case .unavailable(let message) = diagnostics.signingState else {
            Issue.record("Expected invalid bundle path to produce unavailable signing diagnostics")
            return
        }

        #expect(message.isEmpty == false)
        #expect(diagnostics.isAdHocSigned == false)
        #expect(diagnostics.statusText == L10n.Settings.permissionsSigningUnavailable)
        #expect(diagnostics.detailText == L10n.Settings.permissionsUnavailableDetail(message))
    }

    @Test func signingStateDerivedTextsMatchLocalization() {
        let adhoc = AppPermissionAccessDiagnostics(
            signingState: .adhoc,
            bundleIdentifier: "com.leongong.ghodex",
            teamIdentifier: nil,
            signerSummary: nil
        )
        #expect(adhoc.isAdHocSigned)
        #expect(adhoc.statusText == L10n.Settings.permissionsSigningAdhoc)
        #expect(adhoc.detailText == L10n.Settings.permissionsAdhocDetail)

        let signed = AppPermissionAccessDiagnostics(
            signingState: .signed,
            bundleIdentifier: "com.leongong.ghodex",
            teamIdentifier: "TEAM123",
            signerSummary: "Example Signer"
        )
        #expect(signed.isAdHocSigned == false)
        #expect(signed.statusText == L10n.Settings.permissionsSigningStable)
        #expect(signed.detailText == L10n.Settings.permissionsStableDetail)
    }
}
