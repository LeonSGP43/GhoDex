import AppKit

// Application-level Cocoa scripting hooks for the Ghostty AppleScript dictionary.
//
// Cocoa scripting is mostly convention-based: we do not register handlers in
// code, we expose Objective-C selectors with names Cocoa derives from
// `GhoDex.sdef`.
//
// In practical terms:
// - An `<element>` in `sdef` maps to an ObjC collection accessor.
// - Unique-ID element lookup maps to `valueIn...WithUniqueID:`.
// - Some `<command>` declarations map to `handle...ScriptCommand:`.
//
// This file implements the selectors Cocoa expects on `NSApplication`, which is
// the runtime object behind the `application` class in `GhoDex.sdef`.

// MARK: - Windows

@MainActor
extension NSApplication {
    /// Backing collection for `application.windows`.
    ///
    /// We expose one scripting window per native tab group so scripts see the
    /// expected window/tab hierarchy instead of one AppKit window per tab.
    ///
    /// Required selector name from the `sdef` element key: `scriptWindows`.
    ///
    /// Cocoa scripting calls this whenever AppleScript evaluates a window list,
    /// such as `windows`, `window 1`, or `every window whose ...`.
    @objc(scriptWindows)
    var scriptWindows: [ScriptWindow] {
        guard isAppleScriptEnabled else { return [] }

        // AppKit exposes one NSWindow per tab. AppleScript users expect one
        // top-level window object containing multiple tabs, so we dedupe tab
        // siblings into a single ScriptWindow.
        var seen: Set<ObjectIdentifier> = []
        var result: [ScriptWindow] = []

        for controller in orderedTerminalControllers {
            // Collapse each controller to one canonical representative for the
            // whole tab group. Standalone windows map to themselves.
            guard let primary = primaryTerminalController(for: controller) else {
                continue
            }

            let primaryControllerID = ObjectIdentifier(primary)
            guard seen.insert(primaryControllerID).inserted else {
                // Another tab from this group already created the scripting
                // window object.
                continue
            }

            result.append(ScriptWindow(primaryController: primary))
        }

        return result
    }

    /// Exposed as the AppleScript `front window` property.
    ///
    /// `scriptWindows` is already ordered front-to-back, so the first item is
    /// the frontmost logical Ghostty window.
    @objc(frontWindow)
    var frontWindow: ScriptWindow? {
        guard isAppleScriptEnabled else { return nil }
        return scriptWindows.first
    }

    /// Enables AppleScript unique-ID lookup for window references.
    ///
    /// Required selector name pattern for element key `scriptWindows`:
    /// `valueInScriptWindowsWithUniqueID:`.
    ///
    /// Cocoa calls this when a script resolves `window id "..."`.
    /// Returning `nil` makes the object specifier fail naturally.
    @objc(valueInScriptWindowsWithUniqueID:)
    func valueInScriptWindows(uniqueID: String) -> ScriptWindow? {
        guard isAppleScriptEnabled else { return nil }
        return scriptWindows.first(where: { $0.stableID == uniqueID })
    }
}

// MARK: - Terminals

@MainActor
extension NSApplication {
    /// Backing collection for `application.terminals`.
    ///
    /// Required selector name: `terminals`.
    @objc(terminals)
    var terminals: [ScriptTerminal] {
        guard isAppleScriptEnabled else { return [] }
        return allSurfaceViews.map(ScriptTerminal.init)
    }

    /// Enables AppleScript unique-ID lookup for terminal references.
    ///
    /// Required selector name pattern for element `terminals`:
    /// `valueInTerminalsWithUniqueID:`.
    ///
    /// This is what lets scripts do stable references like
    /// `terminal id "..."` even as windows/tabs change.
    @objc(valueInTerminalsWithUniqueID:)
    func valueInTerminals(uniqueID: String) -> ScriptTerminal? {
        guard isAppleScriptEnabled else { return nil }
        return allSurfaceViews
            .first(where: { $0.id.uuidString == uniqueID })
            .map(ScriptTerminal.init)
    }
}

// MARK: - Browser Tabs

@MainActor
extension NSApplication {
    /// Live Browser contexts for the external command protocol.
    ///
    /// The current implementation still uses `BrowserTabController` as the UI
    /// container, so the context ID is the same stable external identifier
    /// exposed through the legacy browser-tab compatibility layer.
    var browserContextsForExternalControl: [ScriptBrowserTab] {
        BrowserTabController.all.map { ScriptBrowserTab(controller: $0) }
    }

    /// Live Browser tabs for the external command protocol.
    ///
    /// This path is intentionally independent of `macos-applescript` so the
    /// local Browser IPC/CLI control plane keeps working even when AppleScript
    /// automation is disabled in user config.
    var browserTabsForExternalControl: [ScriptBrowserTab] {
        browserContextsForExternalControl
    }

    /// Backing collection for `application.browser tabs`.
    @objc(browserTabs)
    var browserTabs: [ScriptBrowserTab] {
        guard isAppleScriptEnabled else { return [] }
        return browserTabsForExternalControl
    }

    /// Enables AppleScript unique-ID lookup for browser tab references.
    @objc(valueInBrowserTabsWithUniqueID:)
    func valueInBrowserTabs(uniqueID: String) -> ScriptBrowserTab? {
        guard isAppleScriptEnabled else { return nil }
        return browserTabs.first(where: { $0.stableID == uniqueID })
    }
}

// MARK: - Commands

@MainActor
extension NSApplication {
    /// Handler for the `perform action` AppleScript command.
    ///
    /// Required selector name from the command in `sdef`:
    /// `handlePerformActionScriptCommand:`.
    ///
    /// Cocoa scripting parses script syntax and provides:
    /// - `directParameter`: the command string (`perform action "..."`).
    /// - `evaluatedArguments["on"]`: the target terminal (`... on terminal ...`).
    ///
    /// We return a Bool to match the command's declared result type.
    @objc(handlePerformActionScriptCommand:)
    func handlePerformActionScriptCommand(_ command: NSScriptCommand) -> NSNumber? {
        guard validateScript(command: command) else { return nil }

        guard let action = command.directParameter as? String else {
            command.scriptErrorNumber = errAEParamMissed
            command.scriptErrorString = "Missing action string."
            return nil
        }

        guard let terminal = command.evaluatedArguments?["on"] as? ScriptTerminal else {
            command.scriptErrorNumber = errAEParamMissed
            command.scriptErrorString = "Missing terminal target."
            return nil
        }

        return NSNumber(value: terminal.perform(action: action))
    }

    /// Handler for creating a reusable AppleScript surface configuration object.
    @objc(handleNewSurfaceConfigurationScriptCommand:)
    func handleNewSurfaceConfigurationScriptCommand(_ command: NSScriptCommand) -> NSDictionary? {
        guard validateScript(command: command) else { return nil }

        do {
            let configuration = try Ghostty.SurfaceConfiguration(
                scriptRecord: command.evaluatedArguments?["configuration"] as? NSDictionary
            )
            return configuration.dictionaryRepresentation
        } catch {
            command.scriptErrorNumber = errAECoercionFail
            command.scriptErrorString = error.localizedDescription
            return nil
        }
    }

    /// Handler for the `new window` AppleScript command.
    ///
    /// Required selector name from the command in `sdef`:
    /// `handleNewWindowScriptCommand:`.
    ///
    /// Accepts an optional reusable surface configuration object.
    ///
    /// Returns the newly created scripting window object.
    @objc(handleNewWindowScriptCommand:)
    func handleNewWindowScriptCommand(_ command: NSScriptCommand) -> ScriptWindow? {
        guard validateScript(command: command) else { return nil }

        guard let appDelegate = delegate as? AppDelegate else {
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = "GhoDex app delegate is unavailable."
            return nil
        }

        let baseConfig: Ghostty.SurfaceConfiguration?
        if let scriptRecord = command.evaluatedArguments?["configuration"] as? NSDictionary {
            do {
                baseConfig = try Ghostty.SurfaceConfiguration(scriptRecord: scriptRecord)
            } catch {
                command.scriptErrorNumber = errAECoercionFail
                command.scriptErrorString = error.localizedDescription
                return nil
            }
        } else {
            baseConfig = nil
        }

        let controller = TerminalController.newWindow(
            appDelegate.ghostty,
            withBaseConfig: baseConfig
        )
        let createdWindowID = ScriptWindow.stableID(primaryController: controller)

        if let scriptWindow = scriptWindows.first(where: { $0.stableID == createdWindowID }) {
            return scriptWindow
        }

        // Fall back to wrapping the created controller if AppKit window ordering
        // has not refreshed yet in the current run loop.
        return ScriptWindow(primaryController: controller)
    }

    /// Handler for the `quit` AppleScript command.
    ///
    /// Required selector name from the command in `sdef`:
    /// `handleQuitScriptCommand:`.
    @objc(handleQuitScriptCommand:)
    func handleQuitScriptCommand(_ command: NSScriptCommand) {
        guard validateScript(command: command) else { return }
        terminate(nil)
    }

    /// Handler for the `new tab` AppleScript command.
    ///
    /// Required selector name from the command in `sdef`:
    /// `handleNewTabScriptCommand:`.
    ///
    /// Accepts an optional target window and optional surface configuration.
    /// If no window is provided, this mirrors App Intents and uses the
    /// preferred parent window.
    ///
    /// Returns the newly created scripting tab object.
    @objc(handleNewTabScriptCommand:)
    func handleNewTabScriptCommand(_ command: NSScriptCommand) -> ScriptTab? {
        guard validateScript(command: command) else { return nil }

        guard let appDelegate = delegate as? AppDelegate else {
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = "GhoDex app delegate is unavailable."
            return nil
        }

        let baseConfig: Ghostty.SurfaceConfiguration?
        if let scriptRecord = command.evaluatedArguments?["configuration"] as? NSDictionary {
            do {
                baseConfig = try Ghostty.SurfaceConfiguration(scriptRecord: scriptRecord)
            } catch {
                command.scriptErrorNumber = errAECoercionFail
                command.scriptErrorString = error.localizedDescription
                return nil
            }
        } else {
            baseConfig = nil
        }

        let targetWindow = command.evaluatedArguments?["window"] as? ScriptWindow
        let parentWindow: NSWindow?
        if let targetWindow {
            guard let resolvedWindow = targetWindow.preferredParentWindow else {
                command.scriptErrorNumber = errAEEventFailed
                command.scriptErrorString = "Target window is no longer available."
                return nil
            }

            parentWindow = resolvedWindow
        } else {
            parentWindow = TerminalController.preferredParent?.window
        }

        guard let createdController = TerminalController.newTab(
            appDelegate.ghostty,
            from: parentWindow,
            withBaseConfig: baseConfig
        ) else {
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = "Failed to create tab."
            return nil
        }

        let createdTabID = ScriptTab.stableID(controller: createdController)

        if let targetWindow,
           let scriptTab = targetWindow.valueInTabs(uniqueID: createdTabID) {
            return scriptTab
        }

        for scriptWindow in scriptWindows {
            if let scriptTab = scriptWindow.valueInTabs(uniqueID: createdTabID) {
                return scriptTab
            }
        }

        // Fall back to wrapping the created controller if AppKit tab-group
        // bookkeeping has not fully refreshed in the current run loop.
        let fallbackWindow = ScriptWindow(primaryController: createdController)
        return ScriptTab(window: fallbackWindow, controller: createdController)
    }

    /// Handler for the `new browser tab` AppleScript command.
    @objc(handleNewBrowserTabScriptCommand:)
    func handleNewBrowserTabScriptCommand(_ command: NSScriptCommand) -> ScriptBrowserTab? {
        guard validateScript(command: command) else { return nil }

        guard let appDelegate = delegate as? AppDelegate else {
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = "GhoDex app delegate is unavailable."
            return nil
        }

        let initialURL: URL?
        if let rawURL = command.evaluatedArguments?["url"] as? String, !rawURL.isEmpty {
            let normalizedURL = BrowserPaths.normalizedURLString(
                rawURL,
                fallback: BrowserTabController.defaultHomePageURL(for: appDelegate.ghostty).absoluteString
            )
            guard let url = URL(string: normalizedURL) else {
                command.scriptErrorNumber = errAECoercionFail
                command.scriptErrorString = "The Browser tab URL is invalid."
                return nil
            }
            initialURL = url
        } else {
            initialURL = nil
        }

        let controller = BrowserTabController.newWindow(appDelegate.ghostty, initialURL: initialURL)
        return ScriptBrowserTab(controller: controller)
    }

    /// Handler for the versioned `run browser command protocol` AppleScript command.
    @objc(handleRunBrowserCommandProtocolScriptCommand:)
    func handleRunBrowserCommandProtocolScriptCommand(_ command: NSScriptCommand) -> NSString? {
        guard validateScript(command: command) else { return nil }

        guard let requestJSON = command.directParameter as? String, !requestJSON.isEmpty else {
            command.scriptErrorNumber = errAEParamMissed
            command.scriptErrorString = "Missing browser command protocol JSON request."
            return nil
        }

        let responseJSON: String
        do {
            responseJSON = try ScriptBrowserTab.runExternalCommandProtocolSynchronously(requestJSON: requestJSON)
        } catch let error as BrowserExternalCommandError {
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = error.message
            return nil
        } catch {
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = error.localizedDescription
            return nil
        }

        return responseJSON as NSString
    }
}

// MARK: - Private Helpers

@MainActor
extension NSApplication {
    /// Whether Ghostty should currently accept AppleScript interactions.
    var isAppleScriptEnabled: Bool {
        guard let appDelegate = delegate as? AppDelegate else { return true }
        return appDelegate.ghostty.config.macosAppleScript
    }

    /// Applies a consistent error when scripting is disabled by configuration.
    @discardableResult
    func validateScript(command: NSScriptCommand) -> Bool {
        guard isAppleScriptEnabled else {
            command.scriptErrorNumber = errAEEventNotPermitted
            command.scriptErrorString = "AppleScript is disabled by the macos-applescript configuration."
            return false
        }

        return true
    }

    /// Discovers all currently alive terminal surfaces across normal and quick
    /// terminal windows. This powers both terminal enumeration and ID lookup.
    fileprivate var allSurfaceViews: [Ghostty.SurfaceView] {
        allTerminalControllers
            .flatMap { $0.allSurfaces }
    }

    /// All terminal controllers in undefined order.
    fileprivate var allTerminalControllers: [BaseTerminalController] {
        NSApp.windows.compactMap { $0.windowController as? BaseTerminalController }
    }

    /// All terminal controllers in front-to-back order.
    fileprivate var orderedTerminalControllers: [BaseTerminalController] {
        NSApp.orderedWindows.compactMap { $0.windowController as? BaseTerminalController }
    }

    /// Identifies the primary tab controller for a window's tab group.
    ///
    /// This gives us one stable representative for all tabs in the same native
    /// AppKit tab group.
    ///
    /// For standalone windows this returns the window's controller directly.
    /// For tabbed windows, "primary" is currently the first controller in the
    /// tab group's ordered windows list.
    fileprivate func primaryTerminalController(for controller: BaseTerminalController) -> BaseTerminalController? {
        guard let window = controller.window else { return nil }
        guard let tabGroup = window.tabGroup else { return controller }

        return tabGroup.windows
            .compactMap { $0.windowController as? BaseTerminalController }
            .first
    }
}
