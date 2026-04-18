import CryptoKit
import Foundation

enum BrowserRuntimeInstallPhase: Equatable {
    case idle
    case downloading
    case extracting
    case installing
    case installed
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .downloading, .extracting, .installing:
            return true
        case .idle, .installed, .failed:
            return false
        }
    }

    var statusText: String? {
        switch self {
        case .idle:
            return nil
        case .downloading:
            return AppLocalization.localizedText("Downloading the browser runtime…")
        case .extracting:
            return AppLocalization.localizedText("Unpacking the browser runtime…")
        case .installing:
            return AppLocalization.localizedText("Installing the browser runtime…")
        case .installed:
            return AppLocalization.localizedText("Browser runtime installed. Activating Chromium in this tab…")
        case .failed(let message):
            return message
        }
    }
}

private struct BrowserRuntimeManifest: Encodable {
    let installedAt: String
    let source: String
    let downloadURL: String
    let archiveSHA256: String
    let ffmpegBranding: String?
    let proprietaryCodecs: Bool?
    let mediaCapabilities: BrowserRuntimeMediaCapabilities?
    let framework: String
}

private enum BrowserRuntimeInstallerError: LocalizedError {
    case downloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case unsupportedArchive(String)
    case runtimeRootNotFound
    case frameworkMissing
    case processFailed(String)
    case initializationFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return message
        case .checksumMismatch(let expected, let actual):
            return "Browser runtime download failed checksum verification. Expected \(expected), got \(actual)."
        case .unsupportedArchive(let path):
            return "Unsupported browser runtime archive: \(path)"
        case .runtimeRootNotFound:
            return "Downloaded browser runtime did not contain a Chromium Embedded Framework bundle."
        case .frameworkMissing:
            return "Downloaded browser runtime is missing Chromium Embedded Framework.framework."
        case .processFailed(let message):
            return message
        case .initializationFailed:
            return "Browser runtime installed, but Chromium could not be activated in this app session."
        }
    }
}

enum BrowserRuntimeInstaller {
    static func install(
        destinationRuntimeRoot: URL? = nil,
        progress: @escaping @MainActor (BrowserRuntimeInstallPhase) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let workRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ghodex-cef-install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workRoot) }

        await progress(.downloading)
        let archiveURL = try await downloadArchive(into: workRoot)

        await progress(.extracting)
        let unpackRoot = workRoot.appendingPathComponent("unpack", isDirectory: true)
        try fileManager.createDirectory(at: unpackRoot, withIntermediateDirectories: true)
        try extractArchive(at: archiveURL, into: unpackRoot)
        let runtimeRoot = try resolveRuntimeRoot(in: unpackRoot)

        await progress(.installing)
        try installRuntime(from: runtimeRoot, destinationRuntimeRoot: destinationRuntimeRoot)

        await progress(.installed)
    }

    private static func downloadArchive(into workRoot: URL) async throws -> URL {
        let descriptor = BrowserPaths.managedRuntimeDescriptor
        var request = URLRequest(url: descriptor.downloadURL)
        request.timeoutInterval = 600

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw BrowserRuntimeInstallerError.downloadFailed(
                "Browser runtime download failed with HTTP \(httpResponse.statusCode).")
        }

        let archiveURL = workRoot.appendingPathComponent(
            descriptor.downloadURL.lastPathComponent,
            isDirectory: false)
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)
        try validateArchiveChecksum(at: archiveURL, expectedSHA256: descriptor.archiveSHA256)
        return archiveURL
    }

    private static func extractArchive(at archiveURL: URL, into destinationURL: URL) throws {
        switch archiveURL.pathExtension.lowercased() {
        case "bz2":
            try runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-xjf", archiveURL.path, "-C", destinationURL.path])
        case "gz", "tgz":
            try runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-xzf", archiveURL.path, "-C", destinationURL.path])
        case "zip":
            try runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archiveURL.path, destinationURL.path])
        default:
            throw BrowserRuntimeInstallerError.unsupportedArchive(archiveURL.lastPathComponent)
        }
    }

    private static func resolveRuntimeRoot(in directory: URL) throws -> URL {
        if containsRuntime(at: directory) {
            return directory
        }

        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])

        while let candidate = enumerator?.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            if containsRuntime(at: candidate) {
                return candidate
            }
        }

        throw BrowserRuntimeInstallerError.runtimeRootNotFound
    }

    private static func containsRuntime(at directory: URL) -> Bool {
        runtimeFrameworkSource(for: directory) != nil
    }

    private static func runtimeFrameworkSource(for directory: URL) -> URL? {
        let bundled = directory
            .appendingPathComponent("Frameworks", isDirectory: true)
            .appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        let release = directory
            .appendingPathComponent("Release", isDirectory: true)
            .appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)
        if FileManager.default.fileExists(atPath: release.path) {
            return release
        }

        return nil
    }

    private static func installRuntime(
        from runtimeRoot: URL,
        destinationRuntimeRoot: URL?
    ) throws {
        if let destinationRuntimeRoot {
            try installRuntimeAtCustomRoot(from: runtimeRoot, destinationRuntimeRoot: destinationRuntimeRoot)
            return
        }

        try installManagedRuntimeAtDefaultRoot(from: runtimeRoot)
    }

    private static func installManagedRuntimeAtDefaultRoot(from runtimeRoot: URL) throws {
        let fileManager = FileManager.default
        let descriptor = BrowserPaths.managedRuntimeDescriptor
        let destinationRoot = BrowserPaths.defaultCEFRootDirectory()
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        guard let frameworkSource = runtimeFrameworkSource(for: runtimeRoot) else {
            throw BrowserRuntimeInstallerError.frameworkMissing
        }

        let slug = descriptor.slug.replacingOccurrences(of: " ", with: "-")
        let installRoot = destinationRoot.appendingPathComponent(slug, isDirectory: true)
        let stagingRoot = destinationRoot.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        let frameworkDestination = stagingRoot
            .appendingPathComponent("Frameworks", isDirectory: true)
            .appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)

        try fileManager.createDirectory(
            at: stagingRoot.appendingPathComponent("Frameworks", isDirectory: true),
            withIntermediateDirectories: true)
        try fileManager.copyItem(at: frameworkSource, to: frameworkDestination)
        try ensureFrameworkInfoPlist(at: frameworkDestination)
        try adHocCodeSign(frameworkDestination)

        let manifest = BrowserRuntimeManifest(
            installedAt: ISO8601DateFormatter().string(from: Date()),
            source: descriptor.source ?? descriptor.slug,
            downloadURL: descriptor.downloadURL.absoluteString,
            archiveSHA256: descriptor.archiveSHA256,
            ffmpegBranding: descriptor.ffmpegBranding,
            proprietaryCodecs: descriptor.proprietaryCodecs,
            mediaCapabilities: descriptor.mediaCapabilities,
            framework: "Frameworks/Chromium Embedded Framework.framework")
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(
            to: stagingRoot.appendingPathComponent("manifest.json", isDirectory: false),
            options: [.atomic])

        if fileManager.fileExists(atPath: installRoot.path) {
            try fileManager.removeItem(at: installRoot)
        }
        try fileManager.moveItem(at: stagingRoot, to: installRoot)

        let currentRoot = BrowserPaths.defaultManagedCEFRuntimeRoot()
        try? fileManager.removeItem(at: currentRoot)
        try fileManager.createSymbolicLink(at: currentRoot, withDestinationURL: installRoot)
    }

    private static func installRuntimeAtCustomRoot(
        from runtimeRoot: URL,
        destinationRuntimeRoot: URL
    ) throws {
        let fileManager = FileManager.default
        guard let frameworkSource = runtimeFrameworkSource(for: runtimeRoot) else {
            throw BrowserRuntimeInstallerError.frameworkMissing
        }

        let normalizedDestination = destinationRuntimeRoot.standardizedFileURL
        let parentDirectory = normalizedDestination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let stagingRoot = parentDirectory.appendingPathComponent(
            ".install-\(UUID().uuidString)",
            isDirectory: true
        )
        let frameworkDestination = stagingRoot
            .appendingPathComponent("Frameworks", isDirectory: true)
            .appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)

        try fileManager.createDirectory(
            at: stagingRoot.appendingPathComponent("Frameworks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: frameworkSource, to: frameworkDestination)
        try ensureFrameworkInfoPlist(at: frameworkDestination)
        try adHocCodeSign(frameworkDestination)

        let descriptor = BrowserPaths.managedRuntimeDescriptor
        let manifest = BrowserRuntimeManifest(
            installedAt: ISO8601DateFormatter().string(from: Date()),
            source: descriptor.source ?? descriptor.slug,
            downloadURL: descriptor.downloadURL.absoluteString,
            archiveSHA256: descriptor.archiveSHA256,
            ffmpegBranding: descriptor.ffmpegBranding,
            proprietaryCodecs: descriptor.proprietaryCodecs,
            mediaCapabilities: descriptor.mediaCapabilities,
            framework: "Frameworks/Chromium Embedded Framework.framework"
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(
            to: stagingRoot.appendingPathComponent("manifest.json", isDirectory: false),
            options: [.atomic]
        )

        if fileManager.fileExists(atPath: normalizedDestination.path) {
            try fileManager.removeItem(at: normalizedDestination)
        }
        try fileManager.moveItem(at: stagingRoot, to: normalizedDestination)
    }

    private static func ensureFrameworkInfoPlist(at frameworkURL: URL) throws {
        let frameworkRootInfo = frameworkURL.appendingPathComponent("Info.plist", isDirectory: false)
        guard !FileManager.default.fileExists(atPath: frameworkRootInfo.path) else { return }

        let resourcesInfo = frameworkURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)
        guard FileManager.default.fileExists(atPath: resourcesInfo.path) else { return }

        try FileManager.default.createSymbolicLink(
            at: frameworkRootInfo,
            withDestinationURL: URL(fileURLWithPath: "Resources/Info.plist"))
    }

    private static func validateArchiveChecksum(at archiveURL: URL, expectedSHA256: String) throws {
        let actual = try sha256Hex(for: archiveURL)
        let expected = expectedSHA256.lowercased()
        guard actual == expected else {
            throw BrowserRuntimeInstallerError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    private static func sha256Hex(for fileURL: URL) throws -> String {
        guard let stream = InputStream(url: fileURL) else {
            throw BrowserRuntimeInstallerError.downloadFailed(
                "Could not open downloaded browser runtime for checksum verification.")
        }

        stream.open()
        defer { stream.close() }

        var digest = SHA256()
        let bufferSize = 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount < 0 {
                throw BrowserRuntimeInstallerError.downloadFailed(
                    stream.streamError?.localizedDescription
                    ?? "Could not read the downloaded browser runtime for checksum verification.")
            }

            if readCount == 0 {
                break
            }

            digest.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: readCount))
        }

        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func adHocCodeSign(_ url: URL) throws {
        try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--force", "--deep", "--sign", "-", url.path])
    }

    private static func runProcess(executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw BrowserRuntimeInstallerError.processFailed(
                "Failed to start \(executable.lastPathComponent): \(error.localizedDescription)")
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let message = [stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                           stdout.trimmingCharacters(in: .whitespacesAndNewlines)]
                .first(where: { !$0.isEmpty }) ?? "exit code \(process.terminationStatus)"
            throw BrowserRuntimeInstallerError.processFailed(message)
        }
    }
}
