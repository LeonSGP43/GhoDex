import Foundation
import Testing
@testable import GhoDex

struct ControlHarnessHostEnvironmentTests {
    @Test func injectsCurrentHostInstanceIdentityIntoEnvironment() {
        var environment = ["PATH": "/usr/bin"]

        GhoDexHostInstanceEnvironment.inject(
            into: &environment,
            controlSocketPath: "/tmp/ghodex.sock",
            processID: 4242,
            bundleID: "com.leongong.ghodex",
            executablePath: "/Applications/GhoDex.app/Contents/MacOS/GhoDex"
        )

        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment[GhoDexHostInstanceEnvironment.controlSocketKey] == "/tmp/ghodex.sock")
        #expect(environment[GhoDexHostInstanceEnvironment.instancePIDKey] == "4242")
        #expect(environment[GhoDexHostInstanceEnvironment.instanceBundleIDKey] == "com.leongong.ghodex")
        #expect(environment[GhoDexHostInstanceEnvironment.instanceExecutableKey] == "/Applications/GhoDex.app/Contents/MacOS/GhoDex")
    }

    @Test func hostInstanceInjectionOverridesReservedKeysOnly() {
        var environment = [
            GhoDexHostInstanceEnvironment.controlSocketKey: "/tmp/other.sock",
            GhoDexHostInstanceEnvironment.instancePIDKey: "1",
            "FOO": "bar",
        ]

        GhoDexHostInstanceEnvironment.inject(
            into: &environment,
            controlSocketPath: "/tmp/current.sock",
            processID: 9001,
            bundleID: "com.leongong.ghodex.debug",
            executablePath: nil
        )

        #expect(environment["FOO"] == "bar")
        #expect(environment[GhoDexHostInstanceEnvironment.controlSocketKey] == "/tmp/current.sock")
        #expect(environment[GhoDexHostInstanceEnvironment.instancePIDKey] == "9001")
        #expect(environment[GhoDexHostInstanceEnvironment.instanceBundleIDKey] == "com.leongong.ghodex.debug")
        #expect(environment[GhoDexHostInstanceEnvironment.instanceExecutableKey] == nil)
    }

    @Test func injectsManagedAgentRuntimeBootstrapIntoAIManagerEnvironment() throws {
        var environment = [
            "PATH": "/usr/bin",
            "GHOSTTY_AI_MANAGER": "1",
            "GHOSTTY_AI_SESSION_KIND": "local_workspace",
            "GHOSTTY_AI_WORKSPACE_ID": "workspace-123",
        ]

        GhoDexHostInstanceEnvironment.inject(
            into: &environment,
            controlSocketPath: "/tmp/ghodex.sock",
            processID: 4242,
            bundleID: "com.leongong.ghodex",
            executablePath: "/Applications/GhoDex.app/Contents/MacOS/GhoDex",
            runtimeDefaultHeartbeatSeconds: 42
        )

        #expect(environment[GhoDexHostInstanceEnvironment.runtimeSocketKey] == "/tmp/ghodex.sock")
        #expect(environment[GhoDexHostInstanceEnvironment.runtimeSessionKindKey] == AgentRuntimeClientKind.codexTab.rawValue)
        #expect(environment[GhoDexHostInstanceEnvironment.runtimeWorkspaceIDKey] == "workspace-123")
        #expect(environment[GhoDexHostInstanceEnvironment.runtimeCapabilitiesKey] == "runtime.executor.terminal,runtime.executor.browser,runtime.executor.vision,runtime.observe,runtime.task.claim,runtime.task.manage")
        #expect(environment[GhoDexHostInstanceEnvironment.runtimeDefaultHeartbeatSecondsKey] == "42")

        let clientID = try #require(environment[GhoDexHostInstanceEnvironment.runtimeClientIDKey])
        #expect(UUID(uuidString: clientID) != nil)
    }

    @Test func removesRuntimeBootstrapFromNonManagedEnvironment() {
        var environment = [
            GhoDexHostInstanceEnvironment.runtimeSocketKey: "/tmp/stale.sock",
            GhoDexHostInstanceEnvironment.runtimeSessionKindKey: "old-kind",
            GhoDexHostInstanceEnvironment.runtimeClientIDKey: "old-client",
            GhoDexHostInstanceEnvironment.runtimeWorkspaceIDKey: "old-workspace",
            GhoDexHostInstanceEnvironment.runtimeCapabilitiesKey: "runtime.admin",
            GhoDexHostInstanceEnvironment.runtimeDefaultHeartbeatSecondsKey: "99",
        ]

        GhoDexHostInstanceEnvironment.inject(
            into: &environment,
            controlSocketPath: "/tmp/ghodex.sock",
            processID: 4242,
            bundleID: "com.leongong.ghodex",
            executablePath: "/Applications/GhoDex.app/Contents/MacOS/GhoDex",
            runtimeDefaultHeartbeatSeconds: 42
        )

        #expect(environment[GhoDexHostInstanceEnvironment.runtimeSocketKey] == nil)
        #expect(environment[GhoDexHostInstanceEnvironment.runtimeSessionKindKey] == nil)
        #expect(environment[GhoDexHostInstanceEnvironment.runtimeClientIDKey] == nil)
        #expect(environment[GhoDexHostInstanceEnvironment.runtimeWorkspaceIDKey] == nil)
        #expect(environment[GhoDexHostInstanceEnvironment.runtimeCapabilitiesKey] == nil)
        #expect(environment[GhoDexHostInstanceEnvironment.runtimeDefaultHeartbeatSecondsKey] == nil)
    }
}
