import AppKit
import Cocoa
import GhoDexKit

private let browserProfileConfigKey = "ghodex-browser-profile-path"
private let browserRuntimeConfigKey = "ghodex-browser-runtime-path"

private func browserSettingValue(for key: String, in text: String) -> String? {
    var result: String?

    for line in text.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\(key) ="), let separatorIndex = trimmed.firstIndex(of: "=") else {
            continue
        }

        let rawValue = trimmed[trimmed.index(after: separatorIndex)...].trimmingCharacters(in: .whitespaces)
        guard
            let data = "[\(rawValue)]".data(using: .utf8),
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String],
            let value = decoded.first
        else {
            continue
        }

        result = value
    }

    return result
}

private func seedBrowserCEFDefaultsFromConfigFile() {
    guard let configPath = ProcessInfo.processInfo.environment["GHOSTTY_CONFIG_PATH"], !configPath.isEmpty else {
        return
    }
    guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else {
        return
    }

    let defaults = UserDefaults.standard
    if let profilePath = browserSettingValue(for: browserProfileConfigKey, in: text), !profilePath.isEmpty {
        defaults.set(profilePath, forKey: BrowserPaths.profileDefaultsKey)
    } else {
        defaults.removeObject(forKey: BrowserPaths.profileDefaultsKey)
    }

    if let runtimePath = browserSettingValue(for: browserRuntimeConfigKey, in: text), !runtimePath.isEmpty {
        defaults.set(runtimePath, forKey: BrowserPaths.runtimeDefaultsKey)
    } else {
        defaults.removeObject(forKey: BrowserPaths.runtimeDefaultsKey)
    }

    defaults.synchronize()
}

seedBrowserCEFDefaultsFromConfigFile()

let cefExitCode = GhoDexCEFExecuteProcessIfNeeded()
if cefExitCode >= 0 {
    exit(cefExitCode)
}

// Initialize Ghostty global state. We do this once right away because the
// CLI APIs require it and it lets us ensure it is done immediately for the
// rest of the app.
if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
    Ghostty.logger.critical("ghostty_init failed")

    // We also write to stderr if this is executed from the CLI or zig run
    switch Ghostty.launchSource {
    case .cli, .zig_run:
        let stderrHandle = FileHandle.standardError
        stderrHandle.write(
            (
                AppLocalization.localizedText(
                    "GhoDex failed to initialize! If you're executing GhoDex from the command line\n" +
                    "then this is usually because an invalid action or multiple actions were specified.\n" +
                    "Actions start with the `+` character.\n\n" +
                    "View all available actions by running `ghodex +help`.\n"
                ) as NSString
            ).data(using: String.Encoding.utf8.rawValue) ?? Data()
        )
        exit(1)

    case .app:
        // For the app we exit immediately. We should handle this case more
        // gracefully in the future.
        exit(1)
    }
}

// This will run the CLI action and exit if one was specified. A CLI
// action is a command starting with a `+`, such as `ghodex +boo`.
ghostty_cli_try_action()

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
