import AppKit
import Testing
@testable import GhoDex

struct AppDelegateTerminationDiagnosticsTests {
    @Test func signalReasonMappingUsesStableReasonCodes() {
        #expect(AppDelegate.terminationReason(forSignal: SIGTERM) == "signal_sigterm")
        #expect(AppDelegate.terminationReason(forSignal: SIGINT) == "signal_sigint")
        #expect(AppDelegate.terminationReason(forSignal: SIGHUP) == "signal_sighup")
        #expect(AppDelegate.terminationReason(forSignal: 123) == "signal_123")
    }

    @Test func signalNameMappingUsesReadableNames() {
        #expect(AppDelegate.signalName(for: SIGTERM) == "SIGTERM")
        #expect(AppDelegate.signalName(for: SIGINT) == "SIGINT")
        #expect(AppDelegate.signalName(for: SIGHUP) == "SIGHUP")
        #expect(AppDelegate.signalName(for: SIGUSR2) == "SIGUSR2")
        #expect(AppDelegate.signalName(for: 12) == "SIG12")
    }

    @Test func appleEventReasonMappingUsesSystemReasonCodes() {
        #expect(AppDelegate.terminationReason(forAppleEventTypeCode: kAEShutDown) == "system_shutdown")
        #expect(AppDelegate.terminationReason(forAppleEventTypeCode: kAERestart) == "system_restart")
        #expect(AppDelegate.terminationReason(forAppleEventTypeCode: kAEReallyLogOut) == "system_logout")
    }
}
