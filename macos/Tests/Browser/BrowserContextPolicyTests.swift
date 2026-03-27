import Testing
@testable import GhoDex

struct BrowserContextPolicyTests {
    @Test func parseDefaultsWhenPolicyPayloadMissing() {
        let result = BrowserContextPolicy.parse(payload: [:])
        switch result {
        case let .success(policy):
            #expect(policy == .default)
        case let .failure(error):
            Issue.record("Expected default policy parse to succeed, got: \(error)")
        }
    }

    @Test func parseExplicitContextPolicyPayload() {
        let payload = [
            "profilePolicy": "isolated",
            "egressPolicy": "named-proxy",
            "egressTarget": "proxy-us-east-1",
            "fingerprintPolicy": "hardened-normal",
            "popupInheritancePolicy": "isolate-popup"
        ]
        let result = BrowserContextPolicy.parse(payload: payload)
        switch result {
        case let .success(policy):
            #expect(policy.profilePolicy == .isolated)
            #expect(policy.egressPolicy.mode == .namedProxy)
            #expect(policy.egressPolicy.target == "proxy-us-east-1")
            #expect(policy.fingerprintPolicy == .hardenedNormal)
            #expect(policy.popupInheritancePolicy == .isolatePopup)
        case let .failure(error):
            Issue.record("Expected explicit policy parse to succeed, got: \(error)")
        }
    }

    @Test func parseRejectsProxyModeWithoutTarget() {
        let result = BrowserContextPolicy.parse(
            payload: ["egressPolicy": "named-proxy"]
        )
        switch result {
        case .success:
            Issue.record("Expected named-proxy parse without egressTarget to fail")
        case let .failure(error):
            #expect(error.code == "invalid_request")
            #expect(error.message.contains("egressTarget"))
        }
    }
}
