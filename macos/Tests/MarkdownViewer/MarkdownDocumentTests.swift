import Testing
import Foundation
@testable import GhoDex

struct MarkdownDocumentTests {
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
    }

    @Test func markdownHTMLRendererAcceptsCustomBaseFontSize() {
        let html = MarkdownHTMLRenderer.renderDocument(
            markdown: "Body",
            title: "Doc",
            baseFontSize: 19
        )

        #expect(html.contains("--base-font-size: 19.0px;"))
        #expect(html.contains("font-size: var(--base-font-size);"))
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
}
