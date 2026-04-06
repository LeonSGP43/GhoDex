import AppKit
import Cocoa
import GhoDexKit

private let browserProfileConfigKey = "ghodex-browser-profile-path"
private let browserRuntimeConfigKey = "ghodex-browser-runtime-path"
private let browserRemoteDebugPortConfigKey = "ghodex-browser-remote-debug-port"

private enum XCTestRuntimeLogFilter {
    private static var buffer = Data()
    private static var passthroughHandle: FileHandle?
    private static var readHandle: FileHandle?
    private static var suppressingMenuNoiseBlock = false
    private static let newline = UInt8(ascii: "\n")

    static func installIfNeeded() {
        guard isRunningTests(), passthroughHandle == nil else {
            return
        }

        let pipe = Pipe()
        let duplicatedStderr = dup(STDERR_FILENO)
        guard duplicatedStderr >= 0 else {
            return
        }

        guard dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0 else {
            close(duplicatedStderr)
            return
        }

        passthroughHandle = FileHandle(fileDescriptor: duplicatedStderr, closeOnDealloc: true)
        readHandle = pipe.fileHandleForReading
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                flushBufferedLine()
                return
            }

            buffer.append(data)
            flushBufferedLines()
        }
    }

    private static func flushBufferedLines() {
        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            handleLine(Data(lineData))
        }
    }

    private static func flushBufferedLine() {
        guard !buffer.isEmpty else {
            return
        }

        let pending = buffer
        buffer.removeAll(keepingCapacity: false)
        handleLine(pending)
    }

    private static func handleLine(_ data: Data) {
        let line = String(bytes: data, encoding: .utf8) ?? ""

        if shouldSuppress(line) {
            return
        }

        guard let passthroughHandle else {
            return
        }

        passthroughHandle.write(data)
        passthroughHandle.write(Data([newline]))
    }

    private static func shouldSuppress(_ line: String) -> Bool {
        if suppressingMenuNoiseBlock {
            if line.hasPrefix("    ") || line.isEmpty {
                return true
            }
            suppressingMenuNoiseBlock = false
        }

        if line.contains("[Menu] Internal inconsistency in menus - menu") {
            suppressingMenuNoiseBlock = true
            return true
        }

        return false
    }
}

private func validatedBrowserDirectorySetting(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }

    let standardized = (value as NSString).standardizingPath
    guard !standardized.isEmpty, standardized.hasPrefix("/") else {
        return nil
    }

    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        return nil
    }

    return standardized
}

private func browserSettingJSONValue(for key: String, in text: String) -> Any? {
    for line in text.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\(key) ="), let separatorIndex = trimmed.firstIndex(of: "=") else {
            continue
        }

        let rawValue = trimmed[trimmed.index(after: separatorIndex)...].trimmingCharacters(in: .whitespaces)
        let data = Data("[\(rawValue)]".utf8)
        guard
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any],
            let value = decoded.first
        else {
            continue
        }

        return value
    }

    return nil
}

private func browserSettingValue(for key: String, in text: String) -> String? {
    browserSettingJSONValue(for: key, in: text) as? String
}

private func seedBrowserCEFDefaultsFromConfigFile() {
    guard BrowserPaths.shouldMirrorBrowserConfigIntoDefaults() else {
        return
    }

    guard let configPath = ProcessInfo.processInfo.environment["GHOSTTY_CONFIG_PATH"], !configPath.isEmpty else {
        return
    }
    guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else {
        return
    }

    let defaults = UserDefaults.standard
    if let profilePath = browserSettingValue(for: browserProfileConfigKey, in: text), !profilePath.isEmpty {
        if let validatedProfilePath = validatedBrowserDirectorySetting(profilePath) {
            defaults.set(validatedProfilePath, forKey: BrowserPaths.profileDefaultsKey)
        } else {
            NSLog("[CEF] Ignoring invalid Browser profile override from config file: %@", profilePath)
            defaults.removeObject(forKey: BrowserPaths.profileDefaultsKey)
        }
    } else {
        defaults.removeObject(forKey: BrowserPaths.profileDefaultsKey)
    }

    if let runtimePath = browserSettingValue(for: browserRuntimeConfigKey, in: text), !runtimePath.isEmpty {
        if let validatedRuntimePath = validatedBrowserDirectorySetting(runtimePath) {
            defaults.set(validatedRuntimePath, forKey: BrowserPaths.runtimeDefaultsKey)
        } else {
            NSLog("[CEF] Ignoring invalid Browser runtime override from config file: %@", runtimePath)
            defaults.removeObject(forKey: BrowserPaths.runtimeDefaultsKey)
        }
    } else {
        defaults.removeObject(forKey: BrowserPaths.runtimeDefaultsKey)
    }

    if let debugValue = browserSettingJSONValue(for: browserRemoteDebugPortConfigKey, in: text) {
        if let portNumber = debugValue as? NSNumber {
            let port = portNumber.intValue
            if (1...65535).contains(port) {
                defaults.set(port, forKey: BrowserPaths.remoteDebugPortDefaultsKey)
            } else if port == 0 {
                defaults.removeObject(forKey: BrowserPaths.remoteDebugPortDefaultsKey)
            } else {
                NSLog("[CEF] Ignoring invalid Browser remote debug port from config file: %@", "\(port)")
                defaults.removeObject(forKey: BrowserPaths.remoteDebugPortDefaultsKey)
            }
        } else {
            NSLog("[CEF] Ignoring invalid Browser remote debug port from config file: %@", "\(debugValue)")
            defaults.removeObject(forKey: BrowserPaths.remoteDebugPortDefaultsKey)
        }
    } else {
        defaults.removeObject(forKey: BrowserPaths.remoteDebugPortDefaultsKey)
    }

    defaults.synchronize()
}

seedBrowserCEFDefaultsFromConfigFile()
XCTestRuntimeLogFilter.installIfNeeded()

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
