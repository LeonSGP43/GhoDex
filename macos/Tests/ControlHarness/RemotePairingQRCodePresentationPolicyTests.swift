import Testing
@testable import GhoDex

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
