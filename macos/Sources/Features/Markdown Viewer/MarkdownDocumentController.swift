import AppKit
import SwiftUI

@MainActor
protocol MarkdownDocumentWindowActionHandling: AnyObject {
    func increaseFontSize()
    func decreaseFontSize()
    func resetFontSize()
    func saveDocument()
}

final class MarkdownDocumentWindow: NSWindow {
    weak var actionHandler: MarkdownDocumentWindowActionHandling?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              modifiers.isSubset(of: [.command, .shift, .option]),
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
        case "s", "S":
            actionHandler?.saveDocument()
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

    @IBAction func saveDocument(_ sender: Any?) {
        actionHandler?.saveDocument()
    }

    @IBAction func close(_ sender: Any?) {
        super.performClose(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(close(_:)),
            #selector(performClose(_:)),
            #selector(saveDocument(_:)),
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

struct LocalPathTarget: Equatable {
    let fileURL: URL
    let isDirectory: Bool

    init?(fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        guard standardizedURL.isFileURL else { return nil }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        self.fileURL = standardizedURL
        self.isDirectory = isDirectory.boolValue
    }

    static func resolve(
        rawValue: String,
        workingDirectory: String? = nil
    ) -> LocalPathTarget? {
        for candidateURL in candidateFileURLs(
            rawValue: rawValue,
            workingDirectory: workingDirectory
        ) {
            if let target = LocalPathTarget(fileURL: candidateURL) {
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

    static func candidateFileURLs(
        rawValue: String,
        workingDirectory: String? = nil
    ) -> [URL] {
        let trimmedRawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRawValue.isEmpty else { return [] }

        var candidates: [URL] = []

        func appendCandidate(_ url: URL) {
            let standardized = url.standardizedFileURL
            if !candidates.contains(standardized) {
                candidates.append(standardized)
            }
        }

        let baseURL = resolveURL(rawValue: trimmedRawValue, workingDirectory: workingDirectory)
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
            if let candidate = URL(string: trimmedRawValue), candidate.scheme != nil {
                return candidate.path(percentEncoded: false)
            }
            return trimmedRawValue
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
        LocalPathTarget.resolveURL(
            rawValue: rawValue,
            workingDirectory: workingDirectory
        )
    }

    private static func candidateFileURLs(
        rawValue: String,
        workingDirectory: String? = nil
    ) -> [URL] {
        LocalPathTarget.candidateFileURLs(
            rawValue: rawValue,
            workingDirectory: workingDirectory
        )
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
    private var alert: NSAlert?

    init(
        appDelegate: AppDelegate,
        target: MarkdownDocumentTarget,
        onClose: @escaping (MarkdownDocumentController) -> Void
    ) {
        self.appDelegate = appDelegate
        self.viewModel = MarkdownDocumentViewModel(target: target)
        self.onClose = onClose

        let hostingController = NSHostingController(
            rootView: MarkdownDocumentView(
                viewModel: viewModel,
                onSaveRequested: {},
                onReloadRequested: {}
            )
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
        self.viewModel.onDirtyStateChange = { [weak self] isDirty in
            self?.window?.isDocumentEdited = isDirty
        }
        hostingController.rootView = MarkdownDocumentView(
            viewModel: viewModel,
            onSaveRequested: { [weak self] in self?.saveDocument() },
            onReloadRequested: { [weak self] in self?.reloadDocument() }
        )
        .environmentObject(theme)
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard viewModel.isDirty else { return true }
        guard alert == nil else { return false }

        let alert = NSAlert()
        alert.messageText = AppLocalization.localizedText("Save changes before closing?")
        alert.informativeText = AppLocalization.localizedText("This Markdown document has unsaved edits.")
        alert.addButton(withTitle: AppLocalization.localizedText("Save"))
        alert.addButton(withTitle: AppLocalization.localizedText("Cancel"))
        alert.addButton(withTitle: AppLocalization.localizedText("Discard"))
        alert.alertStyle = .warning
        self.alert = alert
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self else { return }
            defer { self.alert = nil }

            switch response {
            case .alertFirstButtonReturn:
                do {
                    try self.viewModel.saveSource()
                    sender.isDocumentEdited = false
                    sender.close()
                } catch {
                    self.presentSaveError(error)
                }
            case .alertThirdButtonReturn:
                sender.isDocumentEdited = false
                sender.close()
            default:
                break
            }
        }
        return false
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

    func saveDocument() {
        do {
            try viewModel.saveSource()
            window?.isDocumentEdited = false
        } catch {
            presentSaveError(error)
        }
    }

    private func reloadDocument() {
        guard viewModel.isDirty else {
            viewModel.reloadSource(force: true)
            return
        }

        guard let window else {
            viewModel.reloadSource(force: true)
            return
        }

        guard alert == nil else { return }

        let alert = NSAlert()
        alert.messageText = AppLocalization.localizedText("Discard unsaved changes?")
        alert.informativeText = AppLocalization.localizedText("Reloading will replace your current Markdown edits with the file on disk.")
        alert.addButton(withTitle: AppLocalization.localizedText("Reload"))
        alert.addButton(withTitle: AppLocalization.localizedText("Cancel"))
        alert.alertStyle = .warning
        self.alert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            defer { self.alert = nil }

            guard response == .alertFirstButtonReturn else { return }
            self.viewModel.reloadSource(force: true)
            self.window?.isDocumentEdited = false
        }
    }

    private func presentSaveError(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = AppLocalization.localizedText("Unable to save Markdown document")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
    }

    private func syncChrome() {
        let backgroundColor = GhosttyChrome.resolvedBackgroundColor(
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
        theme.apply(backgroundColor: backgroundColor)
        window?.isDocumentEdited = viewModel.isDirty
        GhosttyChrome.syncWindowAppearance(
            window,
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
    }
}
