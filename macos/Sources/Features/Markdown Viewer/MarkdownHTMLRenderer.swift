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
              --page-bg: transparent;
              --text: rgba(18, 18, 18, 0.96);
              --muted: rgba(18, 18, 18, 0.54);
              --border: rgba(18, 18, 18, 0.11);
              --border-strong: rgba(18, 18, 18, 0.18);
              --code-bg: rgba(18, 18, 18, 0.045);
              --quote-border: rgba(18, 18, 18, 0.22);
              --selection: rgba(18, 18, 18, 0.11);
              --selection-text: inherit;
              --accent: rgba(18, 18, 18, 0.82);
              --token-comment: rgba(112, 117, 127, 0.82);
              --token-keyword: rgba(25, 84, 166, 0.96);
              --token-string: rgba(145, 92, 40, 0.96);
              --token-number: rgba(181, 112, 30, 0.96);
              --token-type: rgba(23, 129, 129, 0.96);
              --token-symbol: rgba(97, 101, 110, 0.9);
              --token-call: rgba(76, 74, 178, 0.96);
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
                --selection-text: inherit;
                --accent: rgba(255, 255, 255, 0.88);
                --token-comment: rgba(162, 168, 181, 0.86);
                --token-keyword: rgba(126, 184, 255, 0.98);
                --token-string: rgba(255, 198, 128, 0.96);
                --token-number: rgba(255, 167, 74, 0.96);
                --token-type: rgba(103, 221, 220, 0.96);
                --token-symbol: rgba(208, 213, 220, 0.84);
                --token-call: rgba(181, 175, 255, 0.98);
              }
            }
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; background: var(--page-bg); color: var(--text); }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
              font-size: var(--base-font-size);
              line-height: 1.72;
              -webkit-font-smoothing: antialiased;
              text-rendering: optimizeLegibility;
              padding: 24px 28px 42px;
            }
            ::selection { background: var(--selection); color: var(--selection-text); }
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
              border: 1px solid var(--border);
              color: var(--token-string);
              font-weight: 560;
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
              border: 0;
              color: inherit;
              border-radius: 0;
              font-size: 0.92em;
              line-height: 1.62;
              font-weight: 400;
            }
            .tok-comment { color: var(--token-comment); font-style: italic; }
            .tok-keyword { color: var(--token-keyword); font-weight: 700; }
            .tok-string {
              color: var(--token-string);
              font-weight: 620;
              text-decoration: underline;
              text-decoration-thickness: 0.05em;
              text-decoration-color: color-mix(in srgb, var(--token-string) 36%, transparent);
              text-underline-offset: 0.12em;
            }
            .tok-number { color: var(--token-number); }
            .tok-type { color: var(--token-type); font-weight: 550; }
            .tok-symbol { color: var(--token-symbol); }
            .tok-call { color: var(--token-call); font-weight: 700; }
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

            // A list marker for the same list type at a lower indentation level
            // belongs to an outer list, so stop the nested collector.
            if let marker = listMarker(in: rawLine, ordered: ordered), marker.indent < baseIndent {
                break
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
        let codeHTML = highlightCode(codeLines.joined(separator: "\n"), language: language)
        return ("<pre><code\(classAttribute)>\(codeHTML)</code></pre>", index)
    }

    private struct TokenPattern {
        let pattern: String
        let className: String
        let options: NSRegularExpression.Options

        init(_ pattern: String, className: String, options: NSRegularExpression.Options = []) {
            self.pattern = pattern
            self.className = className
            self.options = options
        }
    }

    private static func highlightCode(_ source: String, language: String) -> String {
        let category = syntaxCategory(for: language, source: source)
        let nsSource = source as NSString
        var consumed = IndexSet()
        var matches: [(range: NSRange, className: String)] = []

        for tokenPattern in tokenPatterns(for: category) {
            guard let regex = try? NSRegularExpression(pattern: tokenPattern.pattern, options: tokenPattern.options) else {
                continue
            }

            for match in regex.matches(
                in: source,
                options: [],
                range: NSRange(location: 0, length: nsSource.length)
            ) {
                let range = match.range
                guard range.location != NSNotFound,
                      range.length > 0 else { continue }

                let candidateIndexes = IndexSet(integersIn: range.location..<(range.location + range.length))
                guard consumed.isDisjoint(with: candidateIndexes) else { continue }

                consumed.formUnion(candidateIndexes)
                matches.append((range, tokenPattern.className))
            }
        }

        guard !matches.isEmpty else { return escapeHTML(source) }
        matches.sort { $0.range.location < $1.range.location }

        var html = ""
        var cursor = 0

        for match in matches {
            if cursor < match.range.location {
                html += escapeHTML(
                    nsSource.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                )
            }

            let tokenText = nsSource.substring(with: match.range)
            html += "<span class=\"\(match.className)\">\(escapeHTML(tokenText))</span>"
            cursor = match.range.location + match.range.length
        }

        if cursor < nsSource.length {
            html += escapeHTML(
                nsSource.substring(with: NSRange(location: cursor, length: nsSource.length - cursor))
            )
        }

        return html
    }

    private static func syntaxCategory(for language: String, source: String) -> String {
        let normalizedLanguage = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedLanguage.isEmpty {
            return inferSyntaxCategory(from: source)
        }

        switch normalizedLanguage {
        case "swift", "swiftui":
            return "swift"
        case "javascript", "js", "typescript", "ts", "jsx", "tsx", "node", "nodejs":
            return "javascript"
        case "json":
            return "json"
        case "python", "py":
            return "python"
        case "bash", "sh", "zsh", "shell", "shellsession", "shell-session", "console", "terminal", "fish", "nushell", "nu", "elvish":
            return "shell"
        case "zig":
            return "zig"
        case "yaml", "yml":
            return "yaml"
        case "html", "xml", "svg":
            return "markup"
        case "css", "scss", "sass", "less":
            return "css"
        case "sql", "postgresql", "mysql", "sqlite":
            return "sql"
        case "toml", "ini", "conf", "cfg", "dotenv", "properties":
            return "toml"
        case "diff", "patch":
            return "diff"
        case "text", "txt", "plaintext":
            return inferSyntaxCategory(from: source)
        default:
            return inferSyntaxCategory(from: source)
        }
    }

    private static func tokenPatterns(for category: String) -> [TokenPattern] {
        let stringPattern = #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'|`([^`\\]|\\.)*`"#
        let numberPattern = #"\b\d+(?:\.\d+)?\b"#
        let symbolPattern = #"[\[\]\(\)\{\}:=.,<>/+*!?-]"#
        let callPattern = #"\b[A-Za-z_][A-Za-z0-9_]*(?=\()"#

        switch category {
        case "swift":
            return [
                TokenPattern(#"/\*[\s\S]*?\*/"#, className: "tok-comment"),
                TokenPattern(#"//.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"\b(import|let|var|func|struct|class|enum|protocol|extension|if|else|guard|return|throw|throws|async|await|for|in|while|switch|case|default|break|continue|where|try|catch|public|private|fileprivate|internal|open|static|mutating|nonmutating|init|deinit|nil|true|false)\b"#, className: "tok-keyword"),
                TokenPattern(#"\b(String|Int|Double|Float|Bool|URL|Data|Date|UUID|Void|Any|Result|Error)\b"#, className: "tok-type"),
                TokenPattern(callPattern, className: "tok-call"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "javascript":
            return [
                TokenPattern(#"/\*[\s\S]*?\*/"#, className: "tok-comment"),
                TokenPattern(#"//.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"\b(import|from|export|default|const|let|var|function|return|class|extends|new|if|else|switch|case|break|continue|for|while|do|try|catch|finally|throw|async|await|true|false|null|undefined|typeof|instanceof)\b"#, className: "tok-keyword"),
                TokenPattern(#"\b(String|Number|Boolean|Object|Array|Promise|Date|Map|Set)\b"#, className: "tok-type"),
                TokenPattern(callPattern, className: "tok-call"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "json":
            return [
                TokenPattern(#""([^"\\]|\\.)*"(?=\s*:)"#, className: "tok-type"),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"\b(true|false|null)\b"#, className: "tok-keyword"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "python":
            return [
                TokenPattern(#"#.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"\b(import|from|as|def|class|return|if|elif|else|for|while|try|except|finally|raise|with|in|is|not|and|or|True|False|None|async|await|lambda|pass|break|continue)\b"#, className: "tok-keyword"),
                TokenPattern(#"\b(str|int|float|bool|dict|list|tuple|set|None)\b"#, className: "tok-type"),
                TokenPattern(callPattern, className: "tok-call"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "shell":
            return [
                TokenPattern(#"#.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"\b(if|then|else|fi|for|in|do|done|case|esac|function|export|local|return|while|until)\b"#, className: "tok-keyword"),
                TokenPattern(#"\$[A-Za-z_][A-Za-z0-9_]*"#, className: "tok-type"),
                TokenPattern(#"^\s*(?:[$#%]|❯)\s*[A-Za-z_./~:-][A-Za-z0-9_./~:-]*(?=\s|$)"#, className: "tok-call", options: [.anchorsMatchLines]),
                TokenPattern(#"^\s*[A-Za-z_./~:-][A-Za-z0-9_./~:-]*(?=\s|$)"#, className: "tok-call", options: [.anchorsMatchLines]),
                TokenPattern(callPattern, className: "tok-call"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "zig":
            return [
                TokenPattern(#"//.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"@[A-Za-z_][A-Za-z0-9_]*"#, className: "tok-call"),
                TokenPattern(#"\b(const|var|fn|pub|extern|export|struct|enum|union|opaque|error|defer|errdefer|if|else|switch|while|for|break|continue|return|try|catch|comptime|async|await|suspend|resume|nosuspend|packed|inline|noinline|usingnamespace|test|threadlocal|anytype|asm|volatile|allowzero|linksection|callconv|or|and|orelse|unreachable|null|undefined|true|false)\b"#, className: "tok-keyword"),
                TokenPattern(#"\b(u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize|f16|f32|f64|f80|f128|bool|void|noreturn|type|anyerror)\b"#, className: "tok-type"),
                TokenPattern(callPattern, className: "tok-call"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "yaml":
            return [
                TokenPattern(#"#.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"(?m)^\s*[\w.-]+\s*:(?=\s|$)"#, className: "tok-type"),
                TokenPattern(#"\b(true|false|yes|no|on|off|null|~)\b"#, className: "tok-keyword"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "markup":
            return [
                TokenPattern(#"<!--[\s\S]*?-->"#, className: "tok-comment"),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"</?[A-Za-z][A-Za-z0-9:-]*"#, className: "tok-keyword"),
                TokenPattern(#"\b[A-Za-z_:][A-Za-z0-9:._-]*(?==)"#, className: "tok-type"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "css":
            return [
                TokenPattern(#"/\*[\s\S]*?\*/"#, className: "tok-comment"),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"@[A-Za-z-]+"#, className: "tok-keyword"),
                TokenPattern(#"(?m)^\s*[.#]?[A-Za-z_-][A-Za-z0-9_:-]*(?=\s*\{)"#, className: "tok-type"),
                TokenPattern(#"\b[A-Za-z-]+(?=\s*:)"#, className: "tok-call"),
                TokenPattern(#"#[0-9A-Fa-f]{3,8}\b"#, className: "tok-number"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "sql":
            return [
                TokenPattern(#"/\*[\s\S]*?\*/"#, className: "tok-comment"),
                TokenPattern(#"--.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"\b(SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|LIMIT|OFFSET|AS|AND|OR|NOT|NULL|DISTINCT|HAVING)\b"#, className: "tok-keyword"),
                TokenPattern(callPattern, className: "tok-call"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "toml":
            return [
                TokenPattern(#"#.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"(?m)^\s*\[[^\]]+\]"#, className: "tok-keyword"),
                TokenPattern(#"(?m)^\s*[A-Za-z0-9_.-]+(?=\s*=)"#, className: "tok-type"),
                TokenPattern(#"\b(true|false)\b"#, className: "tok-keyword"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        case "diff":
            return [
                TokenPattern(#"^@@.*@@.*$"#, className: "tok-keyword", options: [.anchorsMatchLines]),
                TokenPattern(#"^\+.*$"#, className: "tok-string", options: [.anchorsMatchLines]),
                TokenPattern(#"^-.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
            ]
        default:
            return [
                TokenPattern(#"<!--[\s\S]*?-->"#, className: "tok-comment"),
                TokenPattern(#"/\*[\s\S]*?\*/"#, className: "tok-comment"),
                TokenPattern(#"--.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(#"#.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(#"//.*$"#, className: "tok-comment", options: [.anchorsMatchLines]),
                TokenPattern(stringPattern, className: "tok-string"),
                TokenPattern(#"</?[A-Za-z][A-Za-z0-9:-]*"#, className: "tok-keyword"),
                TokenPattern(#"\b(import|from|export|default|const|let|var|function|return|class|extends|new|if|else|switch|case|break|continue|for|while|do|try|catch|finally|throw|async|await|def|lambda|pass|raise|with|in|is|not|and|or|func|struct|enum|protocol|extension|guard|throws|public|private|static|mutating|init|deinit|select|from|where|insert|into|values|update|set|delete|create|table|join|group|order|limit|if|then|fi|done|export|local|true|false|null|nil|None)\b"#, className: "tok-keyword"),
                TokenPattern(numberPattern, className: "tok-number"),
                TokenPattern(#"\b[A-Za-z_:][A-Za-z0-9:._-]*(?==)"#, className: "tok-type"),
                TokenPattern(#"\b[A-Z][A-Za-z0-9_]+\b"#, className: "tok-type"),
                TokenPattern(callPattern, className: "tok-call"),
                TokenPattern(symbolPattern, className: "tok-symbol"),
            ]
        }
    }

    private static func inferSyntaxCategory(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "generic" }

        if let data = trimmed.data(using: .utf8),
           trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return "json"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?is)<!doctype\s+html|</?[A-Za-z][A-Za-z0-9:-]*(?:\s|>|/>)"#
        ) != nil {
            return "markup"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?m)^\s*[.#]?[A-Za-z_-][A-Za-z0-9_:#.\-\s>]*(?=\s*\{)"#
        ) != nil {
            return "css"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?m)^@@.*@@.*$|^(?:\+\+\+|---|\+|-).+$"#
        ) != nil {
            return "diff"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?im)\b(select|insert|update|delete|create|alter|drop)\b[\s\S]{0,80}\b(from|into|table|set)\b"#
        ) != nil {
            return "sql"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?m)^\s*\[[^\]]+\]\s*$"#
        ) != nil && trimmed.contains("=") {
            return "toml"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?m)^\s*[\w.-]+\s*:\s+\S+"#
        ) != nil && !trimmed.contains("{") && !trimmed.contains(";") {
            return "yaml"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?m)^\s*(const\s+\w+\s*[:=]|var\s+\w+\s*[:=]|pub\s+fn\b|fn\s+\w+\s*\(|@import\()"#
        ) != nil {
            return "zig"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?m)^\s*(def\s+\w+\(|class\s+\w+|from\s+\w+\s+import\b|import\s+\w+|print\(|@[\w.]+)"#
        ) != nil {
            return "python"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?m)^\s*(const|let|var|function|import|export|class)\b|console\.[A-Za-z_][A-Za-z0-9_]*\(|=>"#
        ) != nil {
            return "javascript"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?m)^\s*(import\s+\w+|let\s+\w+|var\s+\w+|func\s+\w+\(|struct\s+\w+|enum\s+\w+|guard\b)|print\("#
        ) != nil {
            return "swift"
        }

        if firstMatch(
            in: trimmed,
            pattern: #"(?m)^\s*(#!/|export\s+\w+=|if\s+\[|for\s+\w+\s+in\b|echo\s+|cd\s+|git\s+|sudo\s+|brew\s+|zig\s+|curl\s+|wget\s+|xcodebuild\s+|make\s+|cmake\s+|\$ |# )"#
        ) != nil {
            return "shell"
        }

        return "generic"
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
