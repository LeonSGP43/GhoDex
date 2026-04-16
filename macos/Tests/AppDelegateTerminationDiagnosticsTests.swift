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

    @Test func crashMarkerParsingExtractsFatalSignalContext() {
        let marker = RuntimeDiagnosticsLogger.parseCrashMarkerContents(
            """
            schema_version=1
            crash_kind=fatal_signal
            pid=81234
            bundle_id=com.leongong.ghodex
            executable_name=GhoDex
            session_id=session-123
            session_started_at=2026-04-15T08:30:00Z
            reason=signal_sigabrt
            signal_name=SIGABRT
            signal_number=6
            """
        )

        #expect(marker?.schemaVersion == 1)
        #expect(marker?.crashKind == "fatal_signal")
        #expect(marker?.pid == 81234)
        #expect(marker?.bundleID == "com.leongong.ghodex")
        #expect(marker?.sessionID == "session-123")
        #expect(marker?.reason == "signal_sigabrt")
        #expect(marker?.signalName == "SIGABRT")
        #expect(marker?.signalNumber == 6)
    }

    @Test func crashReportParsingExtractsExceptionAndTopFrameSummary() {
        let report = RuntimeDiagnosticsLogger.parseCrashReportSummary(
            contents:
                """
                {"app_name":"GhoDex","timestamp":"2026-04-09 08:43:40.00 +0800","app_version":"0.2.0","bundleID":"com.leongong.ghodex","bug_type":"309","incident_id":"INCIDENT-1"}
                {
                  "captureTime" : "2026-04-09 08:43:29.8694 +0800",
                  "pid" : 66978,
                  "procLaunch" : "2026-04-09 08:42:49.1031 +0800",
                  "procName" : "GhoDex",
                  "bundleInfo" : {"CFBundleIdentifier":"com.leongong.ghodex"},
                  "exception" : {"type":"EXC_CRASH","signal":"SIGABRT"},
                  "termination" : {"namespace":"SIGNAL","indicator":"Abort trap: 6"},
                  "faultingThread" : 0,
                  "threads" : [{
                    "triggered" : true,
                    "name" : "CrBrowserMain",
                    "queue" : "com.apple.main-thread",
                    "frames" : [{
                      "symbol" : "main",
                      "sourceFile" : "main.swift",
                      "sourceLine" : 238
                    }]
                  }]
                }
                """,
            fileName: "GhoDex-2026-04-09-084340.ips",
            filePath: "/tmp/GhoDex-2026-04-09-084340.ips"
        )

        #expect(report?.appName == "GhoDex")
        #expect(report?.bundleID == "com.leongong.ghodex")
        #expect(report?.bugType == "309")
        #expect(report?.pid == 66978)
        #expect(report?.procName == "GhoDex")
        #expect(report?.exceptionType == "EXC_CRASH")
        #expect(report?.exceptionSignal == "SIGABRT")
        #expect(report?.terminationNamespace == "SIGNAL")
        #expect(report?.terminationIndicator == "Abort trap: 6")
        #expect(report?.triggeredThreadName == "CrBrowserMain")
        #expect(report?.triggeredQueue == "com.apple.main-thread")
        #expect(report?.firstFrameSymbol == "main")
        #expect(report?.firstFrameSourceFile == "main.swift")
        #expect(report?.firstFrameSourceLine == 238)
    }
}
