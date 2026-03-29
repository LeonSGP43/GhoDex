import Foundation

enum BrowserRuntimeMediaAssessmentReason: Equatable {
    case managedChromiumDistribution
    case codecEnabledRuntime
    case chromiumBrandedRuntime
    case customRuntimeUnverified
}

struct BrowserRuntimeMediaCapabilities: Codable, Equatable {
    let h264: Bool?
    let aac: Bool?

    var providesChromeLikeMP4Parity: Bool {
        h264 == true && aac == true
    }
}

struct BrowserManagedRuntimeDescriptor: Codable, Equatable {
    let slug: String
    let downloadURL: URL
    let archiveSHA256: String
    let source: String?
    let ffmpegBranding: String?
    let proprietaryCodecs: Bool?
    let mediaCapabilities: BrowserRuntimeMediaCapabilities?

    var declaresChromeLikeMP4Parity: Bool {
        if mediaCapabilities?.providesChromeLikeMP4Parity == true {
            return true
        }

        return proprietaryCodecs == true && ffmpegBranding?.lowercased() == "chrome"
    }
}

struct BrowserRuntimeMediaAssessment {
    let reason: BrowserRuntimeMediaAssessmentReason
    let runtimePath: String?
    let runtimeSource: String?
    let ffmpegBranding: String?
    let proprietaryCodecs: Bool?
    let mediaCapabilities: BrowserRuntimeMediaCapabilities?
}

private struct BrowserRuntimeManifestMetadata: Codable {
    let source: String?
    let ffmpegBranding: String?
    let proprietaryCodecs: Bool?
    let mediaCapabilities: BrowserRuntimeMediaCapabilities?
}

enum BrowserPaths {
    static let envRoot = "GHODEX_CEF_ROOT"
    static let envProfilePath = "GHODEX_CEF_PROFILE_PATH"
    static let envAppSupportRoot = "GHODEX_BROWSER_APP_SUPPORT_ROOT"
    static let envManagedRuntimeDescriptorPath = "GHODEX_CEF_MANAGED_RUNTIME_DESCRIPTOR_PATH"
    static let runtimeDefaultsKey = "BrowserCEFRuntimePath"
    static let profileDefaultsKey = "BrowserCEFProfilePath"
    static let remoteDebugPortDefaultsKey = "BrowserCEFRemoteDebugPort"
    static let browserControlSocketName = "browser-control.sock"
    static let builtInHomePage = "https://www.google.com"
    static let defaultManagedRuntimeDescriptor = BrowserManagedRuntimeDescriptor(
        slug: "cef_binary_145.0.28+g51162e8+chromium-145.0.7632.160_macosarm64_minimal",
        downloadURL: URL(string: "https://cef-builds.spotifycdn.com/cef_binary_145.0.28%2Bg51162e8%2Bchromium-145.0.7632.160_macosarm64_minimal.tar.bz2")!,
        archiveSHA256: "004c79437220489f363b615a28f05c607fc13b7feb5045bdc8c7073e180506ad",
        source: "cef_binary_145.0.28+g51162e8+chromium-145.0.7632.160_macosarm64_minimal",
        ffmpegBranding: "Chromium",
        proprietaryCodecs: false,
        mediaCapabilities: BrowserRuntimeMediaCapabilities(h264: false, aac: false)
    )

    static var managedRuntimeDescriptor: BrowserManagedRuntimeDescriptor {
        configuredManagedRuntimeDescriptor()
    }

    static var managedRuntimeSlug: String {
        managedRuntimeDescriptor.slug
    }

    static var managedRuntimeDownloadURL: URL {
        managedRuntimeDescriptor.downloadURL
    }

    static var managedRuntimeSHA256: String {
        managedRuntimeDescriptor.archiveSHA256
    }

    static func defaultAppSupportRootDirectory() -> URL {
        if let override = isolatedAppSupportRootOverride() {
            return override
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GhoDex", isDirectory: true)
    }

    static func isolatedAppSupportRootOverride() -> URL? {
        guard let override = ProcessInfo.processInfo.environment[envAppSupportRoot], !override.isEmpty else {
            return nil
        }

        let standardized = (override as NSString).standardizingPath
        guard !standardized.isEmpty, standardized.hasPrefix("/") else {
            return nil
        }

        return URL(fileURLWithPath: standardized, isDirectory: true)
    }

    static func shouldRestoreBrowserWindows(
        windowSaveState: String,
        configuredExternalProfile: String?,
        isolatedAppSupportRootOverride: URL?
    ) -> Bool {
        guard windowSaveState != "never" else {
            return false
        }

        if let configuredExternalProfile, !configuredExternalProfile.isEmpty {
            return false
        }

        // Isolated Browser roots are used for automation and acceptance runs.
        // Reopening stale browser windows from macOS restoration breaks the
        // intended blank-slate context boundary before the first explicit open.
        if isolatedAppSupportRootOverride != nil {
            return false
        }

        return true
    }

    static func shouldMirrorBrowserConfigIntoDefaults() -> Bool {
        isolatedAppSupportRootOverride() == nil
    }

    static func defaultCEFRootDirectory() -> URL {
        defaultAppSupportRootDirectory()
            .appendingPathComponent("CEF", isDirectory: true)
    }

    static func browserControlSocketURL() -> URL {
        defaultAppSupportRootDirectory()
            .appendingPathComponent(browserControlSocketName, isDirectory: false)
    }

    static func defaultManagedCEFRuntimeRoot() -> URL {
        defaultCEFRootDirectory().appendingPathComponent("current", isDirectory: true)
    }

    static func defaultManagedRuntimeDescriptorFileURL() -> URL {
        defaultCEFRootDirectory().appendingPathComponent("managed-runtime.json", isDirectory: false)
    }

    static func defaultCEFRuntimeRoot() -> URL {
        defaultManagedCEFRuntimeRoot()
    }

    static func configuredCEFRuntimeOverride() -> URL? {
        if let override = ProcessInfo.processInfo.environment[envRoot], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        if let override = UserDefaults.standard.string(forKey: runtimeDefaultsKey), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return nil
    }

    static func configuredCEFRuntimeRoot() -> URL {
        configuredCEFRuntimeOverride() ?? defaultManagedCEFRuntimeRoot()
    }

    static func configuredCEFFrameworkDirectory() -> URL {
        configuredCEFRuntimeRoot()
            .appendingPathComponent("Frameworks", isDirectory: true)
            .appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)
    }

    static func configuredCEFFrameworkBinary() -> URL {
        configuredCEFFrameworkDirectory()
            .appendingPathComponent("Chromium Embedded Framework", isDirectory: false)
    }

    static func runtimeMediaAssessment(
        runtimePath rawRuntimePath: String?,
        usesManagedRuntime: Bool,
        managedRuntimeDescriptor: BrowserManagedRuntimeDescriptor = BrowserPaths.managedRuntimeDescriptor
    ) -> BrowserRuntimeMediaAssessment {
        if usesManagedRuntime {
            if managedRuntimeDescriptor.declaresChromeLikeMP4Parity {
                return BrowserRuntimeMediaAssessment(
                    reason: .codecEnabledRuntime,
                    runtimePath: defaultManagedCEFRuntimeRoot().path,
                    runtimeSource: managedRuntimeDescriptor.source ?? managedRuntimeDescriptor.slug,
                    ffmpegBranding: managedRuntimeDescriptor.ffmpegBranding,
                    proprietaryCodecs: managedRuntimeDescriptor.proprietaryCodecs,
                    mediaCapabilities: managedRuntimeDescriptor.mediaCapabilities
                )
            }

            return BrowserRuntimeMediaAssessment(
                reason: .managedChromiumDistribution,
                runtimePath: defaultManagedCEFRuntimeRoot().path,
                runtimeSource: managedRuntimeDescriptor.source ?? managedRuntimeDescriptor.slug,
                ffmpegBranding: managedRuntimeDescriptor.ffmpegBranding,
                proprietaryCodecs: managedRuntimeDescriptor.proprietaryCodecs,
                mediaCapabilities: managedRuntimeDescriptor.mediaCapabilities
            )
        }

        let normalizedRuntimePath = normalizedDirectoryPath(rawRuntimePath)
        let runtimeMetadata = normalizedRuntimePath.flatMap(runtimeMetadata(runtimePath:))
        let runtimeSource = runtimeMetadata?.source ?? normalizedRuntimePath.flatMap(runtimeSourceDescriptor(runtimePath:))
        if runtimeDeclaresChromeLikeMP4Parity(runtimeMetadata) {
            return BrowserRuntimeMediaAssessment(
                reason: .codecEnabledRuntime,
                runtimePath: normalizedRuntimePath,
                runtimeSource: runtimeSource,
                ffmpegBranding: runtimeMetadata?.ffmpegBranding,
                proprietaryCodecs: runtimeMetadata?.proprietaryCodecs,
                mediaCapabilities: runtimeMetadata?.mediaCapabilities
            )
        }

        if runtimeLooksChromiumBranded(runtimePath: normalizedRuntimePath, runtimeSource: runtimeSource) {
            return BrowserRuntimeMediaAssessment(
                reason: .chromiumBrandedRuntime,
                runtimePath: normalizedRuntimePath,
                runtimeSource: runtimeSource,
                ffmpegBranding: runtimeMetadata?.ffmpegBranding,
                proprietaryCodecs: runtimeMetadata?.proprietaryCodecs,
                mediaCapabilities: runtimeMetadata?.mediaCapabilities
            )
        }

        return BrowserRuntimeMediaAssessment(
            reason: .customRuntimeUnverified,
            runtimePath: normalizedRuntimePath,
            runtimeSource: runtimeSource,
            ffmpegBranding: runtimeMetadata?.ffmpegBranding,
            proprietaryCodecs: runtimeMetadata?.proprietaryCodecs,
            mediaCapabilities: runtimeMetadata?.mediaCapabilities
        )
    }

    static func defaultManagedProfileRoot() -> URL {
        defaultCEFRootDirectory()
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent(defaultManagedProfileSlug(), isDirectory: true)
    }

    static func defaultManagedProfileSlug() -> String {
        let bundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !bundleID.isEmpty {
            return sanitizedPathComponent(bundleID)
        }

        let bundleName = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
        if !bundleName.isEmpty {
            return sanitizedPathComponent(bundleName)
        }

        return "managed-default"
    }

    static func sanitizedPathComponent(_ value: String) -> String {
        guard !value.isEmpty else { return "default" }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scalars)
    }

    static func normalizedDirectoryPath(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let standardized = (trimmed as NSString).standardizingPath
        guard standardized.hasPrefix("/") else { return nil }
        return standardized
    }

    static func configuredManagedRuntimeDescriptor(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultDescriptorFileURL: URL? = nil
    ) -> BrowserManagedRuntimeDescriptor {
        if
            let overridePath = environment[envManagedRuntimeDescriptorPath],
            let overrideURL = normalizedFileURL(overridePath),
            let descriptor = loadManagedRuntimeDescriptor(at: overrideURL) {
            return descriptor
        }

        let defaultDescriptorURL = defaultDescriptorFileURL ?? defaultManagedRuntimeDescriptorFileURL()
        if let descriptor = loadManagedRuntimeDescriptor(at: defaultDescriptorURL) {
            return descriptor
        }

        return defaultManagedRuntimeDescriptor
    }

    private static func runtimeLooksChromiumBranded(
        runtimePath: String?,
        runtimeSource: String?
    ) -> Bool {
        let candidates = [runtimeSource, runtimePath].compactMap { $0?.lowercased() }
        return candidates.contains(where: { candidate in
            candidate.contains("chromium-") ||
                candidate.contains("_minimal") ||
                candidate.contains("cef_binary_")
        })
    }

    private static func runtimeDeclaresChromeLikeMP4Parity(_ metadata: BrowserRuntimeManifestMetadata?) -> Bool {
        guard let metadata else { return false }
        if metadata.mediaCapabilities?.providesChromeLikeMP4Parity == true {
            return true
        }

        return metadata.proprietaryCodecs == true && metadata.ffmpegBranding?.lowercased() == "chrome"
    }

    private static func runtimeMetadata(runtimePath: String) -> BrowserRuntimeManifestMetadata? {
        let manifestURL = URL(fileURLWithPath: runtimePath, isDirectory: true)
            .appendingPathComponent("manifest.json", isDirectory: false)
        return loadRuntimeMetadata(at: manifestURL)
    }

    private static func runtimeSourceDescriptor(runtimePath: String) -> String? {
        let manifestURL = URL(fileURLWithPath: runtimePath, isDirectory: true)
            .appendingPathComponent("manifest.json", isDirectory: false)
        if let source = loadRuntimeMetadata(at: manifestURL)?.source, !source.isEmpty {
            return source
        }

        return URL(fileURLWithPath: runtimePath, isDirectory: true).lastPathComponent
    }

    private static func loadRuntimeMetadata(at url: URL) -> BrowserRuntimeManifestMetadata? {
        guard
            let data = try? Data(contentsOf: url),
            let metadata = try? JSONDecoder().decode(BrowserRuntimeManifestMetadata.self, from: data) else {
            return nil
        }

        return metadata
    }

    private static func loadManagedRuntimeDescriptor(at url: URL) -> BrowserManagedRuntimeDescriptor? {
        guard
            let data = try? Data(contentsOf: url),
            let descriptor = try? JSONDecoder().decode(BrowserManagedRuntimeDescriptor.self, from: data) else {
            return nil
        }

        guard !descriptor.slug.isEmpty, !descriptor.archiveSHA256.isEmpty else {
            return nil
        }

        return descriptor
    }

    private static func normalizedFileURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let fileURL = URL(string: trimmed), fileURL.isFileURL, !fileURL.path.isEmpty {
            return fileURL.standardizedFileURL
        }

        let standardized = (trimmed as NSString).standardizingPath
        guard standardized.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: standardized, isDirectory: false)
    }

    static func installHintLines() -> [String] {
        let root = configuredCEFRuntimeRoot().path
        if configuredCEFRuntimeOverride() != nil {
            return [
                "GhoDex is currently using a custom Chromium runtime directory:",
                root,
                "Place a compatible CEF runtime there and then reopen this browser tab."
            ]
        }

        return [
            "GhoDex installs its managed browser runtime into:",
            root,
            "If you prefer to install it manually, place a compatible CEF runtime there and then reopen this browser tab."
        ]
    }

    static func normalizedURLString(_ rawValue: String, fallback: String = builtInHomePage) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed.contains("://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }
}
