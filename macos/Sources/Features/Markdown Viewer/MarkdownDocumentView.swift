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
    @Published private(set) var summary = MarkdownDocumentSummary(
        lineCount: 0,
        characterCount: 0,
        fileSizeDescription: "--",
        modifiedDescription: nil
    )

    let target: MarkdownDocumentTarget

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

    func reloadSource() {
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
                    self.sourceText = payload.0
                    self.previewHTML = payload.1
                    self.summary = payload.2
                    self.loadError = nil
                case .failure(let error):
                    self.sourceText = ""
                    self.previewHTML = ""
                    self.summary = MarkdownDocumentSummary(
                        lineCount: 0,
                        characterCount: 0,
                        fileSizeDescription: "--",
                        modifiedDescription: nil
                    )
                    self.loadError = error.localizedDescription
                }
            }
        }
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
            fileSizeDescription: formatter.string(fromByteCount: byteCount),
            modifiedDescription: modifiedDate.map(Self.modifiedDateString(from:))
        )
    }

    nonisolated private static func modifiedDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct MarkdownDocumentView: View {
    @EnvironmentObject private var theme: GhosttyChromeTheme
    @ObservedObject var viewModel: MarkdownDocumentViewModel

    var body: some View {
        ZStack {
            theme.backgroundColor
                .ignoresSafeArea()

            Rectangle()
                .fill(Color.primary.opacity(theme.isLight ? 0.018 : 0.045))
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
                .stroke(Color.primary.opacity(theme.isLight ? 0.08 : 0.12), lineWidth: 1)
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

            Button {
                viewModel.reloadSource()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(theme.isLight ? 0.05 : 0.12))
            )
        }
    }

    private var footerSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(theme.isLight ? 0.12 : 0.16))
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
                        fontSize: viewModel.previewFontSize
                    )
                case .source:
                    MarkdownSourceView(
                        sourceText: viewModel.sourceText,
                        fontSize: viewModel.sourceFontSize
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(contentSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(theme.isLight ? 0.08 : 0.12), lineWidth: 1)
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
        .subpanelSurface()
    }

    private var contentSurface: some ShapeStyle {
        Color.primary.opacity(theme.isLight ? 0.028 : 0.12)
    }

    private var footerSurface: some ShapeStyle {
        Color.primary.opacity(theme.isLight ? 0.022 : 0.10)
    }
}

private struct MarkdownRenderedPreview: View {
    let html: String
    let baseURL: URL
    let fontSize: Double

    var body: some View {
        MarkdownWebView(html: html, baseURL: baseURL, fontSize: fontSize)
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let fontSize: Double

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
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            context.coordinator.lastFontSize = fontSize
            nsView.loadHTMLString(html, baseURL: baseURL)
            return
        }

        guard context.coordinator.lastFontSize != fontSize else { return }
        context.coordinator.lastFontSize = fontSize
        context.coordinator.applyFontSize(fontSize, to: nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        var lastFontSize = 16.0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFontSize(lastFontSize, to: webView)
        }

        func applyFontSize(_ fontSize: Double, to webView: WKWebView) {
            let script = """
            document.documentElement.style.setProperty('--base-font-size', '\(fontSize)px');
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

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.importsGraphics = false
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

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != sourceText {
            textView.string = sourceText
        }
        let desiredFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font?.pointSize != desiredFont.pointSize {
            textView.font = desiredFont
        }
    }
}
