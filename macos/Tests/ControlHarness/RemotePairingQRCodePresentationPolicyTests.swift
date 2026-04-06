import Testing
@testable import GhoDex

// swiftlint:disable:next type_name
struct RemotePairingQRCodePresentationPolicyTests {
    @Test func manualRequestsKeepBlockingErrorFeedback() {
        #expect(
            RemotePairingQRCodePresentationPolicy.errorPresentation(for: .manual)
            == .blockingModal
        )
    }

    @Test func launchTriggeredRequestsDoNotBlockMainThreadOnFailure() {
        #expect(
            RemotePairingQRCodePresentationPolicy.errorPresentation(for: .launchPreference)
            == .logOnly
        )
    }
}
