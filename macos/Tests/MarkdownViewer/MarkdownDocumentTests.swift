import Testing
import Foundation
@testable import GhoDex

struct MarkdownDocumentTests {
    @Test func resolvesLocalDirectoryPathAgainstWorkingDirectory() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let childDirectoryURL = tempDirectoryURL.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: childDirectoryURL, withIntermediateDirectories: true)

        let target = LocalPathTarget.resolve(
            rawValue: "Docs",
            workingDirectory: tempDirectoryURL.path
        )

        #expect(target?.fileURL == childDirectoryURL)
        #expect(target?.isDirectory == true)
    }

    @Test func resolvesMarkdownFileURL() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let fileURL = tempDirectoryURL.appendingPathComponent("README.md")
        try Data("hello".utf8).write(to: fileURL)

        let target = MarkdownDocumentTarget.resolve(
            rawValue: fileURL.absoluteString,
            kind: .text
        )

        #expect(target?.fileURL == fileURL)
    }

    @Test func resolvesRelativeMarkdownPathAgainstWorkingDirectory() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let fileURL = tempDirectoryURL.appendingPathComponent("README.md")
        try Data("hello".utf8).write(to: fileURL)

        let target = MarkdownDocumentTarget.resolve(
            rawValue: "README.md",
            kind: .text,
            workingDirectory: tempDirectoryURL.path
        )

        #expect(target?.fileURL == fileURL)
    }

    @Test func ignoresNonMarkdownFiles() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let fileURL = tempDirectoryURL.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: fileURL)

        let target = MarkdownDocumentTarget.resolve(
            rawValue: fileURL.absoluteString,
            kind: .text
        )

        #expect(target == nil)
    }

    @Test func ignoresMissingMarkdownFiles() {
        let target = MarkdownDocumentTarget.resolve(
            rawValue: "/tmp/ghodex-missing-\(UUID().uuidString).md",
            kind: .text
        )

        #expect(target == nil)
    }

    @Test func ignoresNonTextOpenActions() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let fileURL = tempDirectoryURL.appendingPathComponent("README.md")
        try Data("hello".utf8).write(to: fileURL)

        let target = MarkdownDocumentTarget.resolve(
            rawValue: fileURL.absoluteString,
            kind: .html
        )

        #expect(target == nil)
    }

    @Test func resolvesMarkdownPathWithLineNumberSuffix() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let fileURL = tempDirectoryURL.appendingPathComponent("README.md")
        try Data("hello".utf8).write(to: fileURL)

        let target = MarkdownDocumentTarget.resolve(
            rawValue: "\(fileURL.path):12:4",
            kind: .unknown
        )

        #expect(target?.fileURL == fileURL)
    }

    @Test func resolvesFileURLMarkdownWithFragment() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let fileURL = tempDirectoryURL.appendingPathComponent("README.md")
        try Data("hello".utf8).write(to: fileURL)

        let rawValue = fileURL.absoluteString + "#L12"
        let target = MarkdownDocumentTarget.resolve(
            rawValue: rawValue,
            kind: .unknown
        )

        #expect(target?.fileURL == fileURL)
    }

    @Test func markdownHTMLRendererBuildsDocumentSections() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: """
            # Title

            A **bold** paragraph with [link](https://example.com).

            - one
            - two

            > quote

            ```swift
            print("hi")
            ```
            """,
            title: "Doc"
        )

        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("font-size: 16.0px;"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<a href=\"https://example.com\">link</a>"))
        #expect(html.contains("<ul><li>one</li><li>two</li></ul>"))
        #expect(html.contains("<blockquote><p>quote</p></blockquote>"))
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("<span class=\"tok-call\">print</span>"))
        #expect(html.contains("<span class=\"tok-string\">&quot;hi&quot;</span>"))
    }

    @Test func markdownHTMLRendererAcceptsCustomBaseFontSize() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: "Body",
            title: "Doc",
            baseFontSize: 19
        )

        #expect(html.contains("--base-font-size: 19.0px;"))
        #expect(html.contains("font-size: var(--base-font-size);"))
        #expect(html.contains("--page-bg: transparent;"))
        #expect(html.contains("::selection { background: var(--selection); color: var(--selection-text); }"))
    }

    @Test func markdownHTMLRendererStylesInlineCodeWithVisibleAccent() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: "Path: `/tmp/demo/file.md`",
            title: "Doc"
        )

        #expect(html.contains("color: var(--token-string);"))
        #expect(html.contains("border: 1px solid var(--border);"))
        #expect(html.contains("<code>/tmp/demo/file.md</code>"))
    }

    @Test func markdownHTMLRendererInfersLanguageForUnlabeledCodeBlocks() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: """
            ```
            const value = 42
            console.log("hi")
            ```
            """,
            title: "Doc"
        )

        #expect(html.contains("--token-keyword: rgba(25, 84, 166, 0.96);"))
        #expect(html.contains("<span class=\"tok-keyword\">const</span>"))
        #expect(html.contains("<span class=\"tok-call\">log</span>"))
        #expect(html.contains("<span class=\"tok-string\">&quot;hi&quot;</span>"))
    }

    @Test func markdownHTMLRendererHighlightsShellSessionBlocks() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: """
            ```shell-session
            sudo xcode-select --switch /Applications/Xcode.app
            ```
            """,
            title: "Doc"
        )

        #expect(html.contains("<pre><code class=\"language-shell-session\">"))
        #expect(html.contains("<span class=\"tok-call\">sudo</span>"))
        #expect(html.contains("xcode<span class=\"tok-symbol\">-</span>select"))
    }

    @Test func markdownHTMLRendererHighlightsZigBlocks() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: """
            ```zig
            const std = @import("std");
            pub fn main() void {
                std.debug.print("hi", .{});
            }
            ```
            """,
            title: "Doc"
        )

        #expect(html.contains("<pre><code class=\"language-zig\">"))
        #expect(html.contains("<span class=\"tok-keyword\">const</span>"))
        #expect(html.contains("<span class=\"tok-call\">@import</span>"))
        #expect(html.contains("<span class=\"tok-call\">print</span>"))
    }

    @Test func markdownHTMLRendererInfersShellForPlainCommandBlocks() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: """
            ```
            zig build
            xcodebuild -project macos/GhoDex.xcodeproj
            ```
            """,
            title: "Doc"
        )

        #expect(html.contains("<span class=\"tok-call\">zig</span>"))
        #expect(html.contains("<span class=\"tok-call\">xcodebuild</span>"))
    }

    @Test func markdownHTMLRendererRendersImageAndVideoMedia() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: """
            ![Poster](poster.png)

            movie.mp4
            """,
            title: "Media"
        )

        #expect(html.contains("<img src=\"poster.png\""))
        #expect(html.contains("<video src=\"movie.mp4\" controls"))
    }

    @Test func markdownHTMLRendererHandlesMultilineAndNestedLists() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: """
            - parent item
              continuation line
              - child item
            - sibling
            """,
            title: "Lists"
        )

        #expect(html.contains("<li>parent item continuation line<ul><li>child item</li></ul></li>"))
        #expect(html.contains("<li>sibling</li>"))
    }

    @Test func markdownHTMLRendererHandlesPipeTables() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: """
            | Name | Score | URL |
            | --- | ---: | --- |
            | collart.ai | 10.03 | https://collart.ai |
            | biosafeield.ai | 9.18 | https://example.com |
            """,
            title: "Table"
        )

        #expect(html.contains("<table>"))
        #expect(html.contains("<th>Name</th>"))
        #expect(html.contains("<td>collart.ai</td>"))
        #expect(html.contains("<td>10.03</td>"))
    }

    @MainActor
    @Test func markdownViewModelTracksDirtyStateAndLivePreview() async throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let fileURL = tempDirectoryURL.appendingPathComponent("README.md")
        try Data("hello".utf8).write(to: fileURL)

        guard let target = MarkdownDocumentTarget(fileURL: fileURL) else {
            Issue.record("Expected markdown target")
            return
        }

        let viewModel = MarkdownDocumentViewModel(target: target)
        try await waitUntilLoaded(viewModel)

        viewModel.updateSourceText("# Changed")

        #expect(viewModel.isDirty)
        #expect(viewModel.previewHTML.contains("<h1>Changed</h1>"))
        #expect(viewModel.summary.modifiedDescription == AppLocalization.localizedText("Unsaved"))
    }

    @MainActor
    @Test func markdownViewModelSavesEditedSource() async throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let fileURL = tempDirectoryURL.appendingPathComponent("README.md")
        try Data("hello".utf8).write(to: fileURL)

        guard let target = MarkdownDocumentTarget(fileURL: fileURL) else {
            Issue.record("Expected markdown target")
            return
        }

        let viewModel = MarkdownDocumentViewModel(target: target)
        try await waitUntilLoaded(viewModel)

        viewModel.updateSourceText("updated")
        try viewModel.saveSource()

        let savedText = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(savedText == "updated")
        #expect(!viewModel.isDirty)
        #expect(viewModel.summary.modifiedDescription != AppLocalization.localizedText("Unsaved"))
    }

    @MainActor
    private func waitUntilLoaded(_ viewModel: MarkdownDocumentViewModel) async throws {
        for _ in 0..<50 {
            if !viewModel.isLoadingSource && viewModel.loadError == nil && !viewModel.previewHTML.isEmpty {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        Issue.record("MarkdownDocumentViewModel did not finish loading in time")
    }
}
