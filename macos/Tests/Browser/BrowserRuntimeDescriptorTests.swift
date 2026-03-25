import Foundation
import Testing
@testable import GhoDex

struct BrowserRuntimeDescriptorTests {
    @Test func managedRuntimeDescriptorOverrideDrivesCodecEnabledAssessment() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let descriptorURL = tempRoot.appendingPathComponent("managed-runtime.json", isDirectory: false)
        let descriptor = BrowserManagedRuntimeDescriptor(
            slug: "cef_binary_custom_codec_arm64",
            downloadURL: try #require(URL(string: "https://example.invalid/cef_binary_custom_codec_arm64.tar.bz2")),
            archiveSHA256: String(repeating: "a", count: 64),
            source: "codec-enabled-cef-arm64",
            ffmpegBranding: "Chrome",
            proprietaryCodecs: true,
            mediaCapabilities: BrowserRuntimeMediaCapabilities(h264: true, aac: true)
        )
        let descriptorData = try JSONEncoder().encode(descriptor)
        try descriptorData.write(to: descriptorURL, options: [.atomic])

        let resolved = BrowserPaths.configuredManagedRuntimeDescriptor(
            environment: [BrowserPaths.envManagedRuntimeDescriptorPath: descriptorURL.path],
            defaultDescriptorFileURL: tempRoot.appendingPathComponent("missing.json", isDirectory: false)
        )
        #expect(resolved == descriptor)

        let assessment = BrowserPaths.runtimeMediaAssessment(
            runtimePath: nil,
            usesManagedRuntime: true,
            managedRuntimeDescriptor: resolved
        )
        #expect(assessment.reason == .codecEnabledRuntime)
        #expect(assessment.runtimeSource == "codec-enabled-cef-arm64")
        #expect(assessment.mediaCapabilities?.providesChromeLikeMP4Parity == true)
    }

    @Test func customRuntimeManifestCanDeclareCodecEnabledParity() throws {
        let runtimeRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }

        let manifestURL = runtimeRoot.appendingPathComponent("manifest.json", isDirectory: false)
        let manifest = """
        {
          "source": "cef_binary_145_codec_enabled_macosarm64",
          "ffmpegBranding": "Chrome",
          "proprietaryCodecs": true,
          "mediaCapabilities": {
            "h264": true,
            "aac": true
          }
        }
        """
        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)

        let assessment = BrowserPaths.runtimeMediaAssessment(
            runtimePath: runtimeRoot.path,
            usesManagedRuntime: false
        )
        #expect(assessment.reason == .codecEnabledRuntime)
        #expect(assessment.runtimeSource == "cef_binary_145_codec_enabled_macosarm64")
        #expect(assessment.ffmpegBranding == "Chrome")
        #expect(assessment.proprietaryCodecs == true)
    }

    @Test func defaultManagedDescriptorStaysChromiumBrandedWithoutOverride() {
        let defaultDescriptor = BrowserPaths.configuredManagedRuntimeDescriptor(
            environment: [:],
            defaultDescriptorFileURL: URL(fileURLWithPath: "/tmp/ghodex-browser-no-managed-runtime-override.json", isDirectory: false)
        )
        let assessment = BrowserPaths.runtimeMediaAssessment(
            runtimePath: nil,
            usesManagedRuntime: true,
            managedRuntimeDescriptor: defaultDescriptor
        )
        #expect(assessment.reason == .managedChromiumDistribution)
        #expect(assessment.ffmpegBranding == "Chromium")
        #expect(assessment.mediaCapabilities?.providesChromeLikeMP4Parity == false)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghodex-browser-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
