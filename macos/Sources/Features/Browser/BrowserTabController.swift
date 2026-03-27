import AppKit
import SwiftUI
import Combine
import GhoDexKit

final class BrowserTabController: NSWindowController, NSWindowDelegate, TopLevelTabController {
    private static var liveControllersByID: [String: BrowserTabController] = [:]
    private static var liveControllerOrder: [String] = []

    static var all: [BrowserTabController] {
        liveControllerOrder.compactMap { liveControllersByID[$0] }
    }

    static var frontmostControllerID: String? {
        (NSApp.keyWindow?.windowController as? BrowserTabController)?.externalID
            ?? (NSApp.mainWindow?.windowController as? BrowserTabController)?.externalID
    }

    let externalID = "browser-tab-\(UUID().uuidString.lowercased())"
    let ghostty: Ghostty.App
    let contextPolicy: BrowserContextPolicy
    let model: BrowserTabModel

    var titleOverride: String? {
        didSet {
            applyWindowTitle()
            invalidateBrowserRestorableState()
        }
    }

    private var lastKnownPageTitle: String = AppLocalization.localizedText("Browser")
    private var titleCancellable: AnyCancellable?
    private var urlCancellable: AnyCancellable?

    override var windowNibName: NSNib.Name? {
        let defaultValue = "Browser"

        guard let appDelegate = NSApp.delegate as? AppDelegate else { return defaultValue }
        let config = appDelegate.ghostty.config

        if !config.windowDecorations {
            return defaultValue
        }

        let nib = switch config.macosTitlebarStyle {
        case "native": "Browser"
        case "hidden": "BrowserHiddenTitlebar"
        case "transparent": "BrowserTransparentTitlebar"
        case "tabs":
#if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                "BrowserTabsTitlebarTahoe"
            } else {
                "BrowserTabsTitlebarVentura"
            }
#else
            "BrowserTabsTitlebarVentura"
#endif
        default: defaultValue
        }

        return nib
    }

    init(
        _ ghostty: Ghostty.App,
        initialURL: URL? = nil,
        contextPolicy: BrowserContextPolicy = .default
    ) {
        self.ghostty = ghostty
        self.contextPolicy = contextPolicy
        self.model = BrowserTabModel(initialURL: initialURL ?? Self.defaultHomePageURL(for: ghostty))
        super.init(window: nil)
        model.openURLInNewWindowHandler = { [weak self] url in
            guard let self else { return nil }
            let controller = Self.newWindow(self.ghostty, initialURL: url, withParent: self.window)
            return BrowserPopupOpenWindowResult(
                browserTabID: controller.externalID,
                pageID: controller.model.selectedPageID,
                isPageActive: true,
                visibilityState: "newWindowRequested"
            )
        }
        Self.registerLiveController(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for BrowserTabController")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }

        window.delegate = self
        window.isRestorable = true
        window.restorationClass = BrowserWindowRestoration.self
        window.identifier = .init(String(describing: BrowserWindowRestoration.self))
        if let terminalWindow = window as? TerminalWindow {
            terminalWindow.tabbingMode = .preferred
        }

        window.contentView = NSHostingView(rootView: BrowserTabView(model: model))
        applyWindowTitle()

        titleCancellable = model.$pageTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                guard let self else { return }
                self.lastKnownPageTitle = title
                self.applyWindowTitle()
                self.invalidateBrowserRestorableState()
            }

        urlCancellable = model.$displayedURL
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.invalidateBrowserRestorableState()
            }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        applyWindowTitle()
    }

    func promptTabTitle() {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = AppLocalization.localizedText("Rename Tab")
        alert.informativeText = AppLocalization.localizedText("Enter a custom title for this browser tab.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.App.ok)
        alert.addButton(withTitle: L10n.App.cancel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = titleOverride ?? lastKnownPageTitle
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let newValue = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.titleOverride = newValue.isEmpty ? nil : newValue
        }
    }

    func closeTabImmediately(registerRedo: Bool = true) {
        window?.close()
    }

    func activateContext() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeContextImmediately() {
        closeTabImmediately(registerRedo: false)
    }

    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        BrowserRestorableState(from: self).encode(with: state)
    }

    func windowWillClose(_ notification: Notification) {
        Self.unregisterLiveController(self)
    }

    private func applyWindowTitle() {
        let title = titleOverride ?? lastKnownPageTitle
        window?.title = title
        (window as? TerminalWindow)?.title = title
    }

    private func invalidateBrowserRestorableState() {
        window?.invalidateRestorableState()
    }

    static func newWindow(
        _ ghostty: Ghostty.App,
        initialURL: URL? = nil,
        contextPolicy: BrowserContextPolicy = .default,
        withParent explicitParent: NSWindow? = nil
    ) -> BrowserTabController {
        let controller = BrowserTabController(
            ghostty,
            initialURL: initialURL,
            contextPolicy: contextPolicy
        )
        let parent = explicitParent ?? BrowserTabController.preferredParentWindow()

        DispatchQueue.main.async {
            if let parent,
               let window = controller.window,
               !parent.styleMask.contains(.fullScreen),
               window.tabGroup?.windows.count ?? 1 == 1 {
                _ = window.cascadeTopLeft(from: NSPoint(x: parent.frame.minX, y: parent.frame.maxY))
            }
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        return controller
    }

    static func newTab(
        _ ghostty: Ghostty.App,
        from parent: NSWindow? = nil,
        initialURL: URL? = nil,
        contextPolicy: BrowserContextPolicy = .default
    ) -> BrowserTabController {
        let controller = BrowserTabController(
            ghostty,
            initialURL: initialURL,
            contextPolicy: contextPolicy
        )
        guard let window = controller.window else { return controller }

        if let parent {
            if parent.isMiniaturized {
                parent.deminiaturize(nil)
            }
            if let tabGroup = parent.tabGroup,
               tabGroup.windows.contains(where: { $0 === window }) {
                tabGroup.removeWindow(window)
            }
            if window.tabbingMode != .disallowed {
                parent.addTabbedWindowSafely(window, ordered: .above)
            }
        }

        DispatchQueue.main.async {
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        return controller
    }

    static func preferredParentWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? TerminalController.preferredParent?.window
    }

    static func lookup(externalID: String) -> BrowserTabController? {
        liveControllersByID[externalID]
    }

    static func closeAllWindowsImmediately() {
        all.forEach { $0.window?.close() }
    }

    static func defaultHomePageURL(for ghostty: Ghostty.App) -> URL {
        let configured = ghostty.config.ghodexBrowserHomepage ?? BrowserPaths.builtInHomePage
        let normalized = BrowserPaths.normalizedURLString(configured)
        return URL(string: normalized) ?? URL(string: BrowserPaths.builtInHomePage)!
    }

    private static func registerLiveController(_ controller: BrowserTabController) {
        let id = controller.externalID
        liveControllersByID[id] = controller
        if !liveControllerOrder.contains(id) {
            liveControllerOrder.append(id)
        }
    }

    private static func unregisterLiveController(_ controller: BrowserTabController) {
        let id = controller.externalID
        liveControllersByID.removeValue(forKey: id)
        liveControllerOrder.removeAll { $0 == id }
    }
}
