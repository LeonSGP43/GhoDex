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
}
