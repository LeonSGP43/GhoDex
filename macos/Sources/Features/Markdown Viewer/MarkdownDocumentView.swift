import AppKit
import SwiftUI
import WebKit

enum MarkdownDocumentPanel: String, CaseIterable, Identifiable {
    case preview
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview:
            return AppLocalization.localizedText("Preview")
        case .source:
            return AppLocalization.localizedText("Source")
        }
    }
}

struct MarkdownDocumentSummary {
    let lineCount: Int
    let characterCount: Int
    let fileSizeDescription: String
    let modifiedDescription: String?
}

@MainActor
final class MarkdownDocumentViewModel: ObservableObject {
    private enum FontSizing {
        static let minimumStep = -6
        static let maximumStep = 18
        static let previewBaseSize = 16.0
        static let sourceBaseSize = 13.0
    }

    @Published var selectedPanel: MarkdownDocumentPanel = .preview
    @Published private(set) var sourceText: String = ""
    @Published private(set) var previewHTML = ""
    @Published private(set) var loadError: String?
    @Published private(set) var isLoadingSource = false
    @Published private(set) var fontSizeStep = 0
    @Published private(set) var isDirty = false
    @Published private(set) var summary = MarkdownDocumentSummary(
        lineCount: 0,
        characterCount: 0,
        fileSizeDescription: "--",
        modifiedDescription: nil
    )

    let target: MarkdownDocumentTarget
    private var persistedSourceText = ""
    var onDirtyStateChange: ((Bool) -> Void)?

    init(target: MarkdownDocumentTarget) {
        self.target = target
        reloadSource()
    }

    var sourceFontSize: CGFloat {
        CGFloat(FontSizing.sourceBaseSize + Double(fontSizeStep))
    }

    var previewFontSize: Double {
        FontSizing.previewBaseSize + Double(fontSizeStep)
    }

    func reloadSource(force: Bool = false) {
        guard force || !isDirty else { return }
        isLoadingSource = true
        loadError = nil

        let fileURL = target.fileURL
        Task.detached(priority: .userInitiated) {
            let result = Result<(String, String, MarkdownDocumentSummary), Error> {
                var usedEncoding = String.Encoding.utf8
                let sourceText = try String(contentsOf: fileURL, usedEncoding: &usedEncoding)
                let previewHTML = MarkdownHTMLRenderer.renderDocument(
                    markdown: sourceText,
                    title: fileURL.lastPathComponent,
                    baseFontSize: FontSizing.previewBaseSize
                )
                let summary = try Self.makeSummary(for: fileURL, sourceText: sourceText)
                return (sourceText, previewHTML, summary)
            }

            await MainActor.run {
                self.isLoadingSource = false
                switch result {
                case .success(let payload):
                    self.persistedSourceText = payload.0
                    self.sourceText = payload.0
                    self.previewHTML = payload.1
                    self.summary = payload.2
                    self.setDirty(false)
                    self.loadError = nil
                case .failure(let error):
                    self.sourceText = ""
                    self.previewHTML = ""
                    self.persistedSourceText = ""
                    self.summary = MarkdownDocumentSummary(
                        lineCount: 0,
                        characterCount: 0,
                        fileSizeDescription: "--",
                        modifiedDescription: nil
                    )
                    self.setDirty(false)
                    self.loadError = error.localizedDescription
                }
            }
        }
    }

    func updateSourceText(_ text: String) {
        guard sourceText != text else { return }
        sourceText = text
        setDirty(text != persistedSourceText)
        previewHTML = MarkdownHTMLRenderer.renderDocument(
            markdown: text,
            title: target.fileURL.lastPathComponent,
            baseFontSize: FontSizing.previewBaseSize
        )
        summary = Self.makeEditingSummary(
            for: target.fileURL,
            sourceText: text,
            isDirty: isDirty
        )
    }

    func saveSource() throws {
        try sourceText.write(to: target.fileURL, atomically: true, encoding: .utf8)
        persistedSourceText = sourceText
        setDirty(false)
        summary = try Self.makeSummary(for: target.fileURL, sourceText: sourceText)
        loadError = nil
    }

    func increaseFontSize() {
        guard fontSizeStep < FontSizing.maximumStep else { return }
        fontSizeStep += 1
    }

    func decreaseFontSize() {
        guard fontSizeStep > FontSizing.minimumStep else { return }
        fontSizeStep -= 1
    }

    func resetFontSize() {
        guard fontSizeStep != 0 else { return }
        fontSizeStep = 0
    }

    nonisolated private static func makeSummary(
        for fileURL: URL,
        sourceText: String
    ) throws -> MarkdownDocumentSummary {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return makeSummary(
            for: fileURL,
            sourceText: sourceText,
            attributes: attributes,
            isDirty: false
        )
    }

    nonisolated private static func makeEditingSummary(
        for fileURL: URL,
        sourceText: String,
        isDirty: Bool
    ) -> MarkdownDocumentSummary {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
        return makeSummary(
            for: fileURL,
            sourceText: sourceText,
            attributes: attributes,
            isDirty: isDirty
        )
    }

    nonisolated private static func makeSummary(
        for fileURL: URL,
        sourceText: String,
        attributes: [FileAttributeKey: Any],
        isDirty: Bool
    ) -> MarkdownDocumentSummary {
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? Int64(sourceText.utf8.count)
        let modifiedDate = attributes[.modificationDate] as? Date
        let lineCount = sourceText.isEmpty
            ? 0
            : sourceText.split(whereSeparator: \.isNewline).count + (sourceText.hasSuffix("\n") ? 1 : 0)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useBytes]
        formatter.countStyle = .file

        return MarkdownDocumentSummary(
            lineCount: lineCount,
            characterCount: sourceText.count,
            fileSizeDescription: formatter.string(fromByteCount: isDirty ? Int64(sourceText.utf8.count) : byteCount),
            modifiedDescription: isDirty ? AppLocalization.localizedText("Unsaved") : modifiedDate.map(Self.modifiedDateString(from:))
        )
    }

    nonisolated private static func modifiedDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func setDirty(_ dirty: Bool) {
        guard isDirty != dirty else { return }
        isDirty = dirty
        onDirtyStateChange?(dirty)
    }
}

struct MarkdownDocumentView: View {
    @EnvironmentObject private var theme: GhosttyChromeTheme
    @ObservedObject var viewModel: MarkdownDocumentViewModel
    let onSaveRequested: () -> Void
    let onReloadRequested: () -> Void

    private var previewTheme: MarkdownPreviewTheme {
        MarkdownPreviewTheme(
            backgroundColor: theme.backgroundNSColor,
            isLight: theme.isLight
        )
    }

    var body: some View {
        ZStack {
            theme.backgroundColor
                .ignoresSafeArea()

            contentCard
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerBar
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            metadataLabel(viewModel.target.displayName, monospaced: false)

            footerSeparator

            metadataLabel(viewModel.target.fileURL.path, monospaced: true, allowCompression: true)

            footerSeparator

            metadataLabel("\(viewModel.summary.lineCount)L", monospaced: false)
            metadataLabel("\(viewModel.summary.characterCount)C", monospaced: false)
            metadataLabel(viewModel.summary.fileSizeDescription, monospaced: false)

            if viewModel.isDirty {
                metadataLabel(AppLocalization.localizedText("Edited"), monospaced: false)
            }

            if let modified = viewModel.summary.modifiedDescription {
                metadataLabel(modified, monospaced: false)
            }

            Spacer(minLength: 12)

            footerControlGroup
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(footerSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: previewTheme.chromeBorder), lineWidth: 1)
        )
    }

    private var footerControlGroup: some View {
        HStack(spacing: 8) {
            Picker("", selection: $viewModel.selectedPanel) {
                ForEach(MarkdownDocumentPanel.allCases) { panel in
                    Text(panel.title).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            if viewModel.isDirty {
                Button(action: onSaveRequested) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: previewTheme.controlFill))
                )
            }

            Button {
                onReloadRequested()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(viewModel.isLoadingSource)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: previewTheme.controlFill))
            )
        }
    }

    private var footerSeparator: some View {
        Rectangle()
            .fill(Color(nsColor: previewTheme.chromeBorder))
            .frame(width: 1, height: 12)
    }

    private func metadataLabel(
        _ text: String,
        monospaced: Bool,
        allowCompression: Bool = false
    ) -> some View {
        Text(text)
            .font(
                monospaced
                    ? .system(size: 11, weight: .medium, design: .monospaced)
                    : .system(size: 11, weight: .medium, design: .rounded)
            )
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(allowCompression ? 0 : 1)
    }

    private var contentCard: some View {
        Group {
            if let loadError = viewModel.loadError {
                failureView(message: loadError)
            } else if viewModel.isLoadingSource {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(48)
            } else {
                switch viewModel.selectedPanel {
                case .preview:
                    MarkdownRenderedPreview(
                        html: viewModel.previewHTML,
                        baseURL: viewModel.target.fileURL.deletingLastPathComponent(),
                        fontSize: viewModel.previewFontSize,
                        theme: previewTheme
                    )
                case .source:
                    MarkdownSourceView(
                        sourceText: viewModel.sourceText,
                        fontSize: viewModel.sourceFontSize,
                        theme: previewTheme,
                        onChange: viewModel.updateSourceText
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(contentSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: previewTheme.chromeBorder), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text(AppLocalization.localizedText("Unable to open Markdown source"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(contentSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: previewTheme.chromeBorder), lineWidth: 1)
        )
    }

    private var contentSurface: some ShapeStyle {
        theme.backgroundColor
    }

    private var footerSurface: some ShapeStyle {
        Color(nsColor: previewTheme.chromeFill)
    }
}

private struct MarkdownRenderedPreview: View {
    let html: String
    let baseURL: URL
    let fontSize: Double
    let theme: MarkdownPreviewTheme

    var body: some View {
        MarkdownWebView(html: html, baseURL: baseURL, fontSize: fontSize, theme: theme)
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let fontSize: Double
    let theme: MarkdownPreviewTheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastTheme = theme
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastTheme = theme
            nsView.loadHTMLString(html, baseURL: baseURL)
            return
        }

        if context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            context.coordinator.applyFontSize(fontSize, to: nsView)
        }

        guard context.coordinator.lastTheme != theme else { return }
        context.coordinator.lastTheme = theme
        context.coordinator.applyTheme(theme, to: nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        var lastFontSize = 16.0
        var lastTheme = MarkdownPreviewTheme()

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFontSize(lastFontSize, to: webView)
            applyTheme(lastTheme, to: webView)
        }

        func applyFontSize(_ fontSize: Double, to webView: WKWebView) {
            let script = """
            document.documentElement.style.setProperty('--base-font-size', '\(fontSize)px');
            """
            webView.evaluateJavaScript(script)
        }

        func applyTheme(_ theme: MarkdownPreviewTheme, to webView: WKWebView) {
            let script = """
            document.documentElement.style.setProperty('--page-bg', '\(theme.pageBackground.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--text', '\(theme.textColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--muted', '\(theme.mutedTextColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--border', '\(theme.borderColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--border-strong', '\(theme.borderStrongColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--code-bg', '\(theme.codeBackground.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--quote-border', '\(theme.quoteBorderColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--selection', '\(theme.selectionColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--selection-text', '\(theme.selectionTextColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--accent', '\(theme.accentColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--token-comment', '\(theme.tokenCommentColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--token-keyword', '\(theme.tokenKeywordColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--token-string', '\(theme.tokenStringColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--token-number', '\(theme.tokenNumberColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--token-type', '\(theme.tokenTypeColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--token-symbol', '\(theme.tokenSymbolColor.javaScriptSingleQuotedLiteral)');
            document.documentElement.style.setProperty('--token-call', '\(theme.tokenCallColor.javaScriptSingleQuotedLiteral)');
            """
            webView.evaluateJavaScript(script)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if let delegate = NSApp.delegate as? AppDelegate,
               let markdownTarget = MarkdownDocumentTarget(fileURL: url) {
                delegate.openMarkdownDocument(
                    at: markdownTarget.fileURL,
                    tabbedInto: webView.window
                )
                decisionHandler(.cancel)
                return
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}

private struct MarkdownSourceView: NSViewRepresentable {
    let sourceText: String
    let fontSize: CGFloat
    let theme: MarkdownPreviewTheme
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .clear
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = sourceText
        textView.selectedTextAttributes = [
            .backgroundColor: theme.selectionNSColor,
            .foregroundColor: theme.selectionTextNSColor,
        ]
        context.coordinator.isApplyingProgrammaticUpdate = true
        context.coordinator.lastText = sourceText
        context.coordinator.isApplyingProgrammaticUpdate = false

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != sourceText {
            context.coordinator.isApplyingProgrammaticUpdate = true
            textView.string = sourceText
            context.coordinator.lastText = sourceText
            context.coordinator.isApplyingProgrammaticUpdate = false
        }
        let desiredFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font?.pointSize != desiredFont.pointSize {
            textView.font = desiredFont
        }
        textView.textColor = theme.textNSColor
        textView.selectedTextAttributes = [
            .backgroundColor: theme.selectionNSColor,
            .foregroundColor: theme.selectionTextNSColor,
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let onChange: (String) -> Void
        var isApplyingProgrammaticUpdate = false
        var lastText = ""

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate,
                  let textView = notification.object as? NSTextView else { return }
            let updatedText = textView.string
            guard updatedText != lastText else { return }
            lastText = updatedText
            onChange(updatedText)
        }
    }
}

private struct MarkdownPreviewTheme: Equatable {
    let pageBackground: String
    let textColor: String
    let mutedTextColor: String
    let borderColor: String
    let borderStrongColor: String
    let codeBackground: String
    let quoteBorderColor: String
    let selectionColor: String
    let selectionTextColor: String
    let accentColor: String
    let tokenCommentColor: String
    let tokenKeywordColor: String
    let tokenStringColor: String
    let tokenNumberColor: String
    let tokenTypeColor: String
    let tokenSymbolColor: String
    let tokenCallColor: String
    let chromeFill: NSColor
    let chromeBorder: NSColor
    let controlFill: NSColor
    let textNSColor: NSColor
    let selectionNSColor: NSColor
    let selectionTextNSColor: NSColor

    init() {
        self.init(backgroundColor: .windowBackgroundColor, isLight: true)
    }

    init(backgroundColor: NSColor, isLight: Bool) {
        let background = backgroundColor.usingColorSpace(.sRGB) ?? backgroundColor
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        let text = isLight
            ? NSColor(calibratedWhite: 0.08, alpha: 0.96)
            : NSColor(calibratedWhite: 0.96, alpha: 0.94)
        let muted = text.withAlphaComponent(isLight ? 0.58 : 0.64)
        let border = text.withAlphaComponent(isLight ? 0.09 : 0.14)
        let borderStrong = text.withAlphaComponent(isLight ? 0.16 : 0.22)
        let code = text.withAlphaComponent(isLight ? 0.05 : 0.09)
        let quote = accent.withAlphaComponent(isLight ? 0.34 : 0.42)
        let selection = accent.withAlphaComponent(isLight ? 0.34 : 0.42)
        let selectionText = accent.isLightColor
            ? NSColor(calibratedWhite: 0.08, alpha: 1)
            : NSColor(calibratedWhite: 1, alpha: 1)
        let keyword = (NSColor.systemBlue.usingColorSpace(.sRGB) ?? accent)
        let string = (NSColor.systemBrown.usingColorSpace(.sRGB)
            ?? NSColor.systemOrange.usingColorSpace(.sRGB)
            ?? accent)
        let number = (NSColor.systemOrange.usingColorSpace(.sRGB) ?? accent)
        let type = (NSColor.systemTeal.usingColorSpace(.sRGB) ?? accent)
        let symbol = text.withAlphaComponent(isLight ? 0.70 : 0.78)
        let call = (NSColor.systemIndigo.usingColorSpace(.sRGB) ?? keyword)

        self.pageBackground = background.cssRGBAString
        self.textColor = text.cssRGBAString
        self.mutedTextColor = muted.cssRGBAString
        self.borderColor = border.cssRGBAString
        self.borderStrongColor = borderStrong.cssRGBAString
        self.codeBackground = code.cssRGBAString
        self.quoteBorderColor = quote.cssRGBAString
        self.selectionColor = selection.cssRGBAString
        self.selectionTextColor = selectionText.cssRGBAString
        self.accentColor = accent.cssRGBAString
        self.tokenCommentColor = muted.cssRGBAString
        self.tokenKeywordColor = keyword.cssRGBAString
        self.tokenStringColor = string.cssRGBAString
        self.tokenNumberColor = number.cssRGBAString
        self.tokenTypeColor = type.cssRGBAString
        self.tokenSymbolColor = symbol.cssRGBAString
        self.tokenCallColor = call.cssRGBAString
        self.chromeFill = text.withAlphaComponent(isLight ? 0.04 : 0.08)
        self.chromeBorder = text.withAlphaComponent(isLight ? 0.10 : 0.15)
        self.controlFill = text.withAlphaComponent(isLight ? 0.055 : 0.11)
        self.textNSColor = text
        self.selectionNSColor = selection
        self.selectionTextNSColor = selectionText
    }
}

private extension NSColor {
    var cssRGBAString: String {
        let rgb = usingColorSpace(.sRGB) ?? self
        return String(
            format: "rgba(%d, %d, %d, %.3f)",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255)),
            rgb.alphaComponent
        )
    }
}

private extension String {
    var javaScriptSingleQuotedLiteral: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
