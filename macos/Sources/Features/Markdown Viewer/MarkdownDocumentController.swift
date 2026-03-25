import AppKit
import SwiftUI

@MainActor
protocol MarkdownDocumentWindowActionHandling: AnyObject {
    func increaseFontSize()
    func decreaseFontSize()
    func resetFontSize()
}

final class MarkdownDocumentWindow: NSWindow {
    weak var actionHandler: MarkdownDocumentWindowActionHandling?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              modifiers.isSubset(of: [.command, .shift]),
              let characters = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "=", "+":
            actionHandler?.increaseFontSize()
            return true
        case "-", "_":
            actionHandler?.decreaseFontSize()
            return true
        case "0":
            actionHandler?.resetFontSize()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    @IBAction func increaseFontSize(_ sender: Any?) {
        actionHandler?.increaseFontSize()
    }

    @IBAction func decreaseFontSize(_ sender: Any?) {
        actionHandler?.decreaseFontSize()
    }

    @IBAction func resetFontSize(_ sender: Any?) {
        actionHandler?.resetFontSize()
    }

    @IBAction func close(_ sender: Any?) {
        super.performClose(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(close(_:)),
            #selector(performClose(_:)),
            #selector(increaseFontSize(_:)),
            #selector(decreaseFontSize(_:)),
            #selector(resetFontSize(_:)):
            return true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func keyDown(with event: NSEvent) {
        if performKeyEquivalent(with: event) {
            return
        }
        super.keyDown(with: event)
    }
}

struct MarkdownDocumentTarget: Equatable {
    static let supportedPathExtensions: Set<String> = [
        "md",
        "markdown",
        "mdown",
        "mkd",
    ]

    let fileURL: URL

    var displayName: String {
        let lastPathComponent = fileURL.lastPathComponent
        return lastPathComponent.isEmpty ? fileURL.path : lastPathComponent
    }

    init?(fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        guard standardizedURL.isFileURL else { return nil }
        guard Self.supportedPathExtensions.contains(standardizedURL.pathExtension.lowercased()) else { return nil }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }

        self.fileURL = standardizedURL
    }

    static func resolve(
        rawValue: String,
        kind: Ghostty.Action.OpenURL.Kind,
        workingDirectory: String? = nil
    ) -> MarkdownDocumentTarget? {
        guard kind != .html else { return nil }

        for candidateURL in candidateFileURLs(
            rawValue: rawValue,
            workingDirectory: workingDirectory
        ) {
            if let target = MarkdownDocumentTarget(fileURL: candidateURL) {
                return target
            }
        }

        return nil
    }

    static func resolveURL(
        rawValue: String,
        workingDirectory: String? = nil
    ) -> URL {
        if let candidate = URL(string: rawValue), candidate.scheme != nil {
            return candidate
        }

        let expandedPath = NSString(string: rawValue).standardizingPath
        if NSString(string: expandedPath).isAbsolutePath {
            return URL(fileURLWithPath: expandedPath)
        }

        if let workingDirectory,
           !workingDirectory.isEmpty {
            return URL(fileURLWithPath: workingDirectory)
                .appendingPathComponent(rawValue)
                .standardizedFileURL
        }

        return URL(fileURLWithPath: expandedPath)
    }

    private static func candidateFileURLs(
        rawValue: String,
        workingDirectory: String? = nil
    ) -> [URL] {
        var candidates: [URL] = []

        func appendCandidate(_ url: URL) {
            let standardized = url.standardizedFileURL
            if !candidates.contains(standardized) {
                candidates.append(standardized)
            }
        }

        let baseURL = resolveURL(rawValue: rawValue, workingDirectory: workingDirectory)
        if baseURL.isFileURL {
            appendCandidate(baseURL)

            var withoutFragment = baseURL
            withoutFragment.removeAllCachedResourceValues()
            if withoutFragment.fragment != nil {
                var components = URLComponents(url: withoutFragment, resolvingAgainstBaseURL: false)
                components?.fragment = nil
                if let stripped = components?.url, stripped.isFileURL {
                    appendCandidate(stripped)
                }
            }
        }

        let rawPathCandidate: String = {
            if let candidate = URL(string: rawValue), candidate.scheme != nil {
                return candidate.path(percentEncoded: false)
            }
            return rawValue
        }()

        for trimmedPath in trimmedPathCandidates(rawPathCandidate) {
            appendCandidate(resolveURL(rawValue: trimmedPath, workingDirectory: workingDirectory))
        }

        return candidates
    }

    private static func trimmedPathCandidates(_ rawValue: String) -> [String] {
        var candidates: [String] = []

        func appendCandidate(_ value: String) {
            if !candidates.contains(value) {
                candidates.append(value)
            }
        }

        appendCandidate(rawValue)

        let patterns: [String] = [
            ":([0-9]+):([0-9]+)$",
            ":([0-9]+)$",
        ]

        for pattern in patterns {
            if let range = rawValue.range(of: pattern, options: .regularExpression) {
                appendCandidate(String(rawValue[..<range.lowerBound]))
            }
        }

        return candidates
    }
}

@MainActor
final class MarkdownDocumentController: NSWindowController, NSWindowDelegate, MarkdownDocumentWindowActionHandling {
    private let appDelegate: AppDelegate
    private let theme = GhosttyChromeTheme()
    private let viewModel: MarkdownDocumentViewModel
    private let onClose: (MarkdownDocumentController) -> Void
    private var configObserver: NSObjectProtocol?
    private weak var referenceWindow: NSWindow?

    init(
        appDelegate: AppDelegate,
        target: MarkdownDocumentTarget,
        onClose: @escaping (MarkdownDocumentController) -> Void
    ) {
        self.appDelegate = appDelegate
        self.viewModel = MarkdownDocumentViewModel(target: target)
        self.onClose = onClose

        let hostingController = NSHostingController(
            rootView: MarkdownDocumentView(viewModel: viewModel)
                .environmentObject(theme)
        )
        let window = MarkdownDocumentWindow(contentViewController: hostingController)
        window.title = target.displayName
        window.representedURL = target.fileURL
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 720, height: 520)
        window.setContentSize(NSSize(width: 980, height: 720))
        window.tabbingMode = .preferred
        window.toolbarStyle = .unifiedCompact
        DispatchQueue.main.async {
            window.tabbingMode = .automatic
        }

        super.init(window: window)
        window.actionHandler = self
        self.window?.delegate = self

        configObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncChrome()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for MarkdownDocumentController")
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    func show(tabbedInto parentWindow: NSWindow?) {
        referenceWindow = parentWindow
        syncChrome()

        guard let window else { return }

        if let parentWindow,
           parentWindow !== window {
            if parentWindow.isMiniaturized {
                parentWindow.deminiaturize(nil)
            }

            let sameTabGroup = SSHConnectionsController.windowsAreInSameTabGroup(window, parentWindow)
            if !sameTabGroup &&
                parentWindow.tabbingMode != .disallowed &&
                window.tabbingMode != .disallowed {
                _ = parentWindow.addTabbedWindowSafely(window, ordered: .above)
            }
        } else {
            window.center()
        }

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose(self)
    }

    func increaseFontSize() {
        viewModel.increaseFontSize()
    }

    func decreaseFontSize() {
        viewModel.decreaseFontSize()
    }

    func resetFontSize() {
        viewModel.resetFontSize()
    }

    private func syncChrome() {
        let backgroundColor = GhosttyChrome.resolvedBackgroundColor(
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
        theme.apply(backgroundColor: backgroundColor)
        GhosttyChrome.syncWindowAppearance(
            window,
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
    }
}
