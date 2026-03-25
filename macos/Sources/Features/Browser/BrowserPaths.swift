import Foundation

enum BrowserRuntimeMediaAssessmentReason {
    case managedChromiumDistribution
    case chromiumBrandedRuntime
    case customRuntimeUnverified
}

struct BrowserRuntimeMediaAssessment {
    let reason: BrowserRuntimeMediaAssessmentReason
    let runtimePath: String?
    let runtimeSource: String?
}

enum BrowserPaths {
    static let envRoot = "GHODEX_CEF_ROOT"
    static let envProfilePath = "GHODEX_CEF_PROFILE_PATH"
    static let envAppSupportRoot = "GHODEX_BROWSER_APP_SUPPORT_ROOT"
    static let runtimeDefaultsKey = "BrowserCEFRuntimePath"
    static let profileDefaultsKey = "BrowserCEFProfilePath"
    static let remoteDebugPortDefaultsKey = "BrowserCEFRemoteDebugPort"
    static let browserControlSocketName = "browser-control.sock"
    static let builtInHomePage = "https://www.google.com"
    static let managedRuntimeSlug = "cef_binary_145.0.28+g51162e8+chromium-145.0.7632.160_macosarm64_minimal"
    static let managedRuntimeDownloadURL = URL(string: "https://cef-builds.spotifycdn.com/cef_binary_145.0.28%2Bg51162e8%2Bchromium-145.0.7632.160_macosarm64_minimal.tar.bz2")!
    static let managedRuntimeSHA256 = "004c79437220489f363b615a28f05c607fc13b7feb5045bdc8c7073e180506ad"

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
        usesManagedRuntime: Bool
    ) -> BrowserRuntimeMediaAssessment {
        if usesManagedRuntime {
            return BrowserRuntimeMediaAssessment(
                reason: .managedChromiumDistribution,
                runtimePath: defaultManagedCEFRuntimeRoot().path,
                runtimeSource: managedRuntimeSlug
            )
        }

        let normalizedRuntimePath = normalizedDirectoryPath(rawRuntimePath)
        let runtimeSource = normalizedRuntimePath.flatMap(runtimeSourceDescriptor(runtimePath:))
        if runtimeLooksChromiumBranded(runtimePath: normalizedRuntimePath, runtimeSource: runtimeSource) {
            return BrowserRuntimeMediaAssessment(
                reason: .chromiumBrandedRuntime,
                runtimePath: normalizedRuntimePath,
                runtimeSource: runtimeSource
            )
        }

        return BrowserRuntimeMediaAssessment(
            reason: .customRuntimeUnverified,
            runtimePath: normalizedRuntimePath,
            runtimeSource: runtimeSource
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

    private static func runtimeSourceDescriptor(runtimePath: String) -> String? {
        let manifestURL = URL(fileURLWithPath: runtimePath, isDirectory: true)
            .appendingPathComponent("manifest.json", isDirectory: false)
        if
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let source = manifest["source"] as? String,
            !source.isEmpty {
            return source
        }

        return URL(fileURLWithPath: runtimePath, isDirectory: true).lastPathComponent
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
