import Foundation

struct MarkdownHTMLRenderer {
    private enum MediaKind {
        case image
        case video
        case audio
    }

    private static let rawHTMLMediaTags: Set<String> = [
        "img",
        "video",
        "audio",
        "picture",
        "figure",
        "iframe",
    ]

    static func renderDocument(markdown: String, title: String, baseFontSize: Double = 16) -> String {
        let body = renderBlocks(markdown)
        let formattedFontSize = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            baseFontSize
        )

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <style>
            :root {
              color-scheme: light dark;
              --base-font-size: \(formattedFontSize)px;
              --text: rgba(18, 18, 18, 0.96);
              --muted: rgba(18, 18, 18, 0.54);
              --border: rgba(18, 18, 18, 0.11);
              --border-strong: rgba(18, 18, 18, 0.18);
              --code-bg: rgba(18, 18, 18, 0.045);
              --quote-border: rgba(18, 18, 18, 0.22);
              --selection: rgba(18, 18, 18, 0.11);
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --text: rgba(255, 255, 255, 0.94);
                --muted: rgba(255, 255, 255, 0.56);
                --border: rgba(255, 255, 255, 0.10);
                --border-strong: rgba(255, 255, 255, 0.17);
                --code-bg: rgba(255, 255, 255, 0.055);
                --quote-border: rgba(255, 255, 255, 0.21);
                --selection: rgba(255, 255, 255, 0.10);
              }
            }
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; background: transparent; color: var(--text); }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
              font-size: var(--base-font-size);
              line-height: 1.72;
              -webkit-font-smoothing: antialiased;
              text-rendering: optimizeLegibility;
              padding: 24px 28px 42px;
            }
            ::selection { background: var(--selection); }
            main { max-width: 860px; margin: 0 auto; }
            h1, h2, h3, h4, h5, h6 {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", sans-serif;
              letter-spacing: -0.035em;
              line-height: 1.15;
              color: var(--text);
              margin: 1.65em 0 0.55em;
              font-weight: 700;
            }
            h1 { font-size: 2.25rem; margin-top: 0.1em; }
            h2 { font-size: 1.72rem; padding-bottom: 0.34em; border-bottom: 1px solid var(--border); }
            h3 { font-size: 1.34rem; }
            h4 { font-size: 1.08rem; }
            h5, h6 { font-size: 0.98rem; color: var(--muted); }
            p, ul, ol, blockquote, pre, figure, audio, video, iframe, table { margin: 0 0 1.2em; }
            p { color: var(--text); }
            ul, ol { padding-left: 1.35em; }
            ul ul, ul ol, ol ul, ol ol { margin-top: 0.45em; margin-bottom: 0.45em; }
            li { margin: 0.34em 0; }
            a {
              color: inherit;
              text-decoration-line: underline;
              text-decoration-thickness: 0.08em;
              text-decoration-color: var(--border-strong);
              text-underline-offset: 0.16em;
            }
            a:hover { text-decoration-color: currentColor; }
            strong { font-weight: 650; color: var(--text); }
            em { font-style: italic; }
            hr {
              border: 0;
              border-top: 1px solid var(--border);
              margin: 2.1em 0;
            }
            blockquote {
              padding: 0.05em 0 0.05em 1em;
              border-left: 3px solid var(--quote-border);
              color: var(--muted);
            }
            blockquote > :last-child { margin-bottom: 0; }
            code {
              font-family: ui-monospace, "SFMono-Regular", Menlo, Monaco, Consolas, monospace;
              font-size: 0.9em;
              background: var(--code-bg);
              border-radius: 0.45rem;
              padding: 0.12rem 0.38rem;
            }
            pre {
              background: var(--code-bg);
              border: 1px solid var(--border);
              border-radius: 14px;
              padding: 1rem 1.05rem;
              overflow-x: auto;
            }
            pre code {
              display: block;
              padding: 0;
              background: transparent;
              border-radius: 0;
              font-size: 0.92em;
              line-height: 1.62;
            }
            figure.media {
              margin: 1.5em 0;
            }
            figure.media img,
            figure.media video,
            figure.media audio,
            figure.media iframe,
            picture {
              display: block;
              width: 100%;
              max-width: 100%;
            }
            figure.media img,
            figure.media video,
            figure.media iframe,
            picture img {
              border-radius: 14px;
              border: 1px solid var(--border);
              background: var(--code-bg);
            }
            figure.media video {
              aspect-ratio: 16 / 9;
              height: auto;
            }
            figure.media audio {
              margin-top: 0.2em;
            }
            figcaption {
              margin-top: 0.55em;
              font-size: 0.86em;
              line-height: 1.45;
              color: var(--muted);
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 0.96rem;
              table-layout: fixed;
            }
            th, td {
              text-align: left;
              vertical-align: top;
              padding: 0.72rem 0.8rem;
              border-bottom: 1px solid var(--border);
              overflow-wrap: anywhere;
              word-break: break-word;
            }
            th {
              font-weight: 600;
              color: var(--text);
            }
            @media (max-width: 860px) {
              body { padding: 18px 16px 28px; }
              h1 { font-size: 2rem; }
              h2 { font-size: 1.5rem; }
            }
          </style>
        </head>
        <body>
          <main>
            \(body)
          </main>
        </body>
        </html>
        """
    }

    private static func renderBlocks(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var html: [String] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let tag = rawHTMLBlockStartTagName(trimmed) {
                let result = collectRawHTMLBlock(from: lines, startIndex: index, tagName: tag)
                html.append(result.html)
                index = result.nextIndex
                continue
            }

            if let heading = parseHeading(trimmed) {
                html.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                html.append("<hr>")
                index += 1
                continue
            }

            if isPipeTableHeader(at: index, in: lines) {
                let result = collectPipeTable(from: lines, startIndex: index)
                html.append(result.html)
                index = result.nextIndex
                continue
            }

            if isCodeFence(trimmed) {
                let result = collectCodeBlock(from: lines, startIndex: index)
                html.append(result.html)
                index = result.nextIndex
                continue
            }

            if isBlockquote(trimmed) {
                let result = collectBlockquote(from: lines, startIndex: index)
                html.append(result.html)
                index = result.nextIndex
                continue
            }

            if isUnorderedList(rawLine) {
                let result = collectList(from: lines, startIndex: index, ordered: false)
                html.append(result.html)
                index = result.nextIndex
                continue
            }

            if isOrderedList(rawLine) {
                let result = collectList(from: lines, startIndex: index, ordered: true)
                html.append(result.html)
                index = result.nextIndex
                continue
            }

            let result = collectParagraph(from: lines, startIndex: index)
            html.append(result.html)
            index = result.nextIndex
        }

        return html.joined(separator: "\n")
    }

    private static func collectParagraph(from lines: [String], startIndex: Int) -> (html: String, nextIndex: Int) {
        var index = startIndex
        var chunks: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty ||
                rawHTMLBlockStartTagName(trimmed) != nil ||
                parseHeading(trimmed) != nil ||
                isHorizontalRule(trimmed) ||
                isPipeTableHeader(at: index, in: lines) ||
                isCodeFence(trimmed) ||
                isBlockquote(trimmed) ||
                isUnorderedList(lines[index]) ||
                isOrderedList(lines[index]) {
                break
            }

            chunks.append(trimmed)
            index += 1
        }

        let joined = chunks.joined(separator: " ")
        if let mediaHTML = renderStandaloneMedia(from: joined) {
            return (mediaHTML, index)
        }

        return ("<p>\(renderInline(joined))</p>", index)
    }

    private static func collectList(from lines: [String], startIndex: Int, ordered: Bool) -> (html: String, nextIndex: Int) {
        var index = startIndex
        guard let firstMarker = listMarker(in: lines[startIndex], ordered: ordered) else {
            return ("", startIndex)
        }

        let baseIndent = firstMarker.indent
        var items: [(segments: [String], nested: [String])] = []
        var currentSegments: [String] = []
        var currentNested: [String] = []

        func flushCurrentItem() {
            if !currentSegments.isEmpty || !currentNested.isEmpty {
                items.append((currentSegments, currentNested))
            }
            currentSegments = []
            currentNested = []
        }

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if let nextNonEmptyIndex = nextNonEmptyLineIndex(from: index + 1, in: lines),
                   indentation(of: lines[nextNonEmptyIndex]) > baseIndent {
                    index = nextNonEmptyIndex
                    continue
                }
                break
            }

            if let marker = listMarker(in: rawLine, ordered: ordered), marker.indent == baseIndent {
                flushCurrentItem()
                if !marker.content.isEmpty {
                    currentSegments.append(marker.content)
                }
                index += 1
                continue
            }

            if let nestedUnordered = listMarker(in: rawLine, ordered: false), nestedUnordered.indent > baseIndent {
                let result = collectList(from: lines, startIndex: index, ordered: false)
                currentNested.append(result.html)
                index = result.nextIndex
                continue
            }

            if let nestedOrdered = listMarker(in: rawLine, ordered: true), nestedOrdered.indent > baseIndent {
                let result = collectList(from: lines, startIndex: index, ordered: true)
                currentNested.append(result.html)
                index = result.nextIndex
                continue
            }

            if indentation(of: rawLine) <= baseIndent &&
                (parseHeading(trimmed) != nil ||
                 isHorizontalRule(trimmed) ||
                 isCodeFence(trimmed) ||
                 isBlockquote(trimmed) ||
                 rawHTMLBlockStartTagName(trimmed) != nil ||
                 listMarker(in: rawLine, ordered: !ordered) != nil) {
                break
            }

            currentSegments.append(trimmed)
            index += 1
        }

        flushCurrentItem()

        let tag = ordered ? "ol" : "ul"
        let renderedItems = items.map { item in
            let text = item.segments.joined(separator: " ")
            let inlineHTML = text.isEmpty ? "" : renderInline(text)
            let nestedHTML = item.nested.joined(separator: "")
            if nestedHTML.isEmpty {
                return "<li>\(inlineHTML)</li>"
            }
            return "<li>\(inlineHTML)\(nestedHTML)</li>"
        }.joined()
        return ("<\(tag)>\(renderedItems)</\(tag)>", index)
    }

    private static func collectPipeTable(from lines: [String], startIndex: Int) -> (html: String, nextIndex: Int) {
        let headerCells = splitPipeRow(lines[startIndex])
        var index = startIndex + 2
        var bodyRows: [[String]] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || !looksLikePipeRow(lines[index]) {
                break
            }

            bodyRows.append(splitPipeRow(lines[index]))
            index += 1
        }

        let headHTML = headerCells
            .map { "<th>\(renderInline($0))</th>" }
            .joined()

        let bodyHTML = bodyRows.map { row in
            let normalized = normalizeTableRow(row, targetCount: headerCells.count)
            let cells = normalized.map { "<td>\(renderInline($0))</td>" }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()

        let html = """
        <table>
          <thead>
            <tr>\(headHTML)</tr>
          </thead>
          <tbody>\(bodyHTML)</tbody>
        </table>
        """

        return (html, index)
    }

    private static func collectCodeBlock(from lines: [String], startIndex: Int) -> (html: String, nextIndex: Int) {
        var index = startIndex + 1
        let opening = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let language = String(opening.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if isCodeFence(trimmed) {
                index += 1
                break
            }

            codeLines.append(lines[index])
            index += 1
        }

        let classAttribute = language.isEmpty ? "" : " class=\"language-\(escapeHTML(language))\""
        let codeHTML = escapeHTML(codeLines.joined(separator: "\n"))
        return ("<pre><code\(classAttribute)>\(codeHTML)</code></pre>", index)
    }

    private static func collectBlockquote(from lines: [String], startIndex: Int) -> (html: String, nextIndex: Int) {
        var index = startIndex
        var quoteLines: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || !isBlockquote(trimmed) { break }
            let withoutMarker = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            quoteLines.append(String(withoutMarker))
            index += 1
        }

        let body = quoteLines
            .filter { !$0.isEmpty }
            .map { "<p>\(renderInline($0))</p>" }
            .joined()
        return ("<blockquote>\(body)</blockquote>", index)
    }

    private static func collectRawHTMLBlock(
        from lines: [String],
        startIndex: Int,
        tagName: String
    ) -> (html: String, nextIndex: Int) {
        var index = startIndex
        var htmlLines: [String] = []
        let lowercasedClosingTag = "</\(tagName)>"
        let isSelfContained = tagName == "img"

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !htmlLines.isEmpty && trimmed.isEmpty {
                break
            }

            htmlLines.append(line)
            index += 1

            if isSelfContained || trimmed.lowercased().contains(lowercasedClosingTag) {
                break
            }
        }

        return (htmlLines.joined(separator: "\n"), index)
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        guard let range = line.range(of: #"^(#{1,6})\s+"#, options: .regularExpression) else { return nil }
        let marker = line[..<range.upperBound].trimmingCharacters(in: .whitespaces)
        let level = marker.filter { $0 == "#" }.count
        let text = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func isPipeTableHeader(at index: Int, in lines: [String]) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard looksLikePipeRow(header) else { return false }
        return isPipeTableSeparator(separator)
    }

    private static func looksLikePipeRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && !trimmed.hasPrefix(">") && !trimmed.hasPrefix("```")
    }

    private static func isPipeTableSeparator(_ line: String) -> Bool {
        let cells = splitPipeRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty && cell.contains("-")
        }
    }

    private static func splitPipeRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let row = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return row
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func normalizeTableRow(_ row: [String], targetCount: Int) -> [String] {
        if row.count == targetCount {
            return row
        }
        if row.count > targetCount {
            return Array(row.prefix(targetCount))
        }
        return row + Array(repeating: "", count: max(0, targetCount - row.count))
    }

    private static func rawHTMLBlockStartTagName(_ line: String) -> String? {
        guard line.hasPrefix("<") else { return nil }
        let lowercasedLine = line.lowercased()
        for tag in rawHTMLMediaTags where lowercasedLine.hasPrefix("<\(tag)") {
            return tag
        }
        return nil
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        line.range(of: #"^([-*_]){3,}$"#, options: .regularExpression) != nil
    }

    private static func isCodeFence(_ line: String) -> Bool {
        line.hasPrefix("```")
    }

    private static func isBlockquote(_ line: String) -> Bool {
        line.hasPrefix(">")
    }

    private static func isUnorderedList(_ line: String) -> Bool {
        listMarker(in: line, ordered: false) != nil
    }

    private static func isOrderedList(_ line: String) -> Bool {
        listMarker(in: line, ordered: true) != nil
    }

    private static func listMarker(in rawLine: String, ordered: Bool) -> (indent: Int, content: String)? {
        let pattern = ordered ? #"^(\s*)(\d+)\.\s+(.*)$"# : #"^(\s*)[-*+]\s+(.*)$"#
        guard let match = firstMatch(in: rawLine, pattern: pattern) else { return nil }
        let indent = (match[safe: 1] ?? "").count
        let contentIndex = ordered ? 3 : 2
        let content = (match[safe: contentIndex] ?? "").trimmingCharacters(in: .whitespaces)
        return (indent, content)
    }

    private static func indentation(of rawLine: String) -> Int {
        rawLine.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func nextNonEmptyLineIndex(from start: Int, in lines: [String]) -> Int? {
        guard start < lines.count else { return nil }
        for index in start..<lines.count where !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            return index
        }
        return nil
    }

    private static func renderStandaloneMedia(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = firstMatch(
            in: trimmed,
            pattern: #"^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)$"#
        ) {
            let alt = match[safe: 1] ?? ""
            let source = match[safe: 2] ?? ""
            let title = match[safe: 3]
            return renderMediaHTML(source: source, alt: alt, title: title)
        }

        if mediaKind(for: trimmed) != nil {
            return renderMediaHTML(source: trimmed, alt: "", title: nil)
        }

        return nil
    }

    private static func renderInline(_ text: String) -> String {
        var working = text
        var placeholders: [String: String] = [:]
        var placeholderIndex = 0

        func stash(_ html: String) -> String {
            let token = "__MD_HTML_TOKEN_\(placeholderIndex)__"
            placeholderIndex += 1
            placeholders[token] = html
            return token
        }

        working = replaceMatches(
            in: working,
            pattern: #"`([^`]+)`"#
        ) { groups in
            stash("<code>\(escapeHTML(groups[safe: 1] ?? ""))</code>")
        }

        working = replaceMatches(
            in: working,
            pattern: #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)"#
        ) { groups in
            stash(renderMediaHTML(
                source: groups[safe: 2] ?? "",
                alt: groups[safe: 1] ?? "",
                title: groups[safe: 3]
            ))
        }

        working = replaceMatches(
            in: working,
            pattern: #"\[([^\]]+)\]\(([^)]+)\)"#
        ) { groups in
            let label = escapeHTML(groups[safe: 1] ?? "")
            let destination = escapeHTML((groups[safe: 2] ?? "").trimmingCharacters(in: .whitespaces))
            return stash("<a href=\"\(destination)\">\(label)</a>")
        }

        working = escapeHTML(working)
        working = replaceMatches(
            in: working,
            pattern: #"\*\*([^*]+)\*\*"#
        ) { groups in
            "<strong>\(groups[safe: 1] ?? "")</strong>"
        }
        working = replaceMatches(
            in: working,
            pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#
        ) { groups in
            "<em>\(groups[safe: 1] ?? "")</em>"
        }

        for token in placeholders.keys.sorted(by: >) {
            if let html = placeholders[token] {
                working = working.replacingOccurrences(of: token, with: html)
            }
        }

        return working
    }

    private static func renderMediaHTML(source: String, alt: String, title: String?) -> String {
        let escapedSource = escapeHTML(source)
        let captionText = [alt, title].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " ")
        let captionHTML = captionText.isEmpty ? "" : "<figcaption>\(escapeHTML(captionText))</figcaption>"

        switch mediaKind(for: source) {
        case .image:
            let altText = escapeHTML(alt)
            return "<figure class=\"media media-image\"><img src=\"\(escapedSource)\" alt=\"\(altText)\" loading=\"lazy\">\(captionHTML)</figure>"
        case .video:
            return "<figure class=\"media media-video\"><video src=\"\(escapedSource)\" controls playsinline preload=\"metadata\"></video>\(captionHTML)</figure>"
        case .audio:
            return "<figure class=\"media media-audio\"><audio src=\"\(escapedSource)\" controls preload=\"metadata\"></audio>\(captionHTML)</figure>"
        case nil:
            let label = escapeHTML(alt.isEmpty ? source : alt)
            return "<a href=\"\(escapedSource)\">\(label)</a>"
        }
    }

    private static func mediaKind(for source: String) -> MediaKind? {
        let path: String = {
            if let url = URL(string: source), url.scheme != nil {
                return url.path
            }
            return source
        }()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "svg", "bmp", "tiff":
            return .image
        case "mp4", "m4v", "mov", "webm", "ogv":
            return .video
        case "mp3", "m4a", "aac", "wav", "ogg", "flac":
            return .audio
        default:
            return nil
        }
    }

    private static func replaceMatches(
        in text: String,
        pattern: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: output) else { continue }
            let groups = (0..<match.numberOfRanges).compactMap { index -> String? in
                let nsRange = match.range(at: index)
                guard nsRange.location != NSNotFound,
                      let range = Range(nsRange, in: output) else { return nil }
                return String(output[range])
            }
            output.replaceSubrange(matchRange, with: transform(groups))
        }
        return output
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index -> String? in
            let nsRange = match.range(at: index)
            guard nsRange.location != NSNotFound,
                  let range = Range(nsRange, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
