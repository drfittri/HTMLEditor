import Cocoa

// MARK: - MarkdownRenderer
//
// Lightweight Markdown -> NSAttributedString renderer used to make agent chat answers
// readable instead of raw plain text. Deliberately dependency-free and forgiving: it
// handles the subset agents actually emit (headings, bold/italic/inline-code, fenced
// code blocks, ordered/unordered lists, blockquotes, horizontal rules, links) and falls
// back to plain runs for anything it doesn't recognize. Output is theme-aware via `Theme`.
enum MarkdownRenderer {

    struct Theme {
        let text: NSColor
        let secondary: NSColor
        let accent: NSColor
        let codeBackground: NSColor
        let base: CGFloat
    }

    // MARK: Public entry

    static func attributed(_ raw: String, theme: Theme) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var i = 0
        var inCode = false
        var codeBuffer: [String] = []
        var isFirstBlock = true

        func blockGap() {
            if !isFirstBlock { result.append(NSAttributedString(string: "\n")) }
            isFirstBlock = false
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block toggles
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inCode {
                    blockGap()
                    result.append(codeBlock(codeBuffer.joined(separator: "\n"), theme: theme))
                    codeBuffer = []
                    inCode = false
                } else {
                    inCode = true
                }
                i += 1
                continue
            }
            if inCode {
                codeBuffer.append(line)
                i += 1
                continue
            }

            // Blank line -> paragraph break
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Heading (#..######)
            if let (level, content) = parseHeading(trimmed) {
                blockGap()
                let extra: [CGFloat] = [7, 5, 3, 2, 1, 0]
                let size = theme.base + extra[min(level - 1, 5)]
                let heading = inline(content, theme: theme,
                                     font: NSFont.systemFont(ofSize: size, weight: .bold),
                                     color: theme.text)
                let m = NSMutableAttributedString(attributedString: heading)
                let para = NSMutableParagraphStyle()
                para.paragraphSpacing = 2
                para.lineSpacing = 1
                m.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: m.length))
                result.append(m)
                result.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blockGap()
                result.append(NSAttributedString(string: "──────────\n", attributes: [
                    .foregroundColor: theme.secondary.withAlphaComponent(0.4),
                    .font: NSFont.systemFont(ofSize: theme.base),
                ]))
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                blockGap()
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let q = inline(content, theme: theme,
                               font: NSFont.systemFont(ofSize: theme.base),
                               color: theme.secondary)
                let m = NSMutableAttributedString(attributedString: q)
                let para = NSMutableParagraphStyle()
                para.firstLineHeadIndent = 12
                para.headIndent = 12
                para.paragraphSpacing = 2
                m.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: m.length))
                result.append(m)
                result.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }

            // List item (ordered or unordered)
            if let item = parseList(line) {
                blockGap()
                let bullet = item.ordered ? "\(item.number). " : "•  "
                let indent = CGFloat(item.indent) * 16 + 2
                let m = NSMutableAttributedString()
                m.append(NSAttributedString(string: bullet, attributes: [
                    .foregroundColor: theme.accent,
                    .font: NSFont.systemFont(ofSize: theme.base, weight: .semibold),
                ]))
                m.append(inline(item.content, theme: theme,
                                font: NSFont.systemFont(ofSize: theme.base),
                                color: theme.text))
                let para = NSMutableParagraphStyle()
                para.firstLineHeadIndent = indent
                para.headIndent = indent + 18
                para.paragraphSpacing = 2
                para.lineSpacing = 1.5
                m.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: m.length))
                result.append(m)
                result.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }

            // Paragraph: gather consecutive non-structural lines
            blockGap()
            var paragraphLines = [line]
            var j = i + 1
            while j < lines.count {
                let l = lines[j]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("```") || t.hasPrefix("~~~") || t.hasPrefix(">")
                    || parseHeading(t) != nil || parseList(l) != nil
                    || t == "---" || t == "***" || t == "___" {
                    break
                }
                paragraphLines.append(l)
                j += 1
            }
            let paragraph = paragraphLines.joined(separator: " ")
            let m = NSMutableAttributedString(attributedString: inline(paragraph, theme: theme,
                                                                       font: NSFont.systemFont(ofSize: theme.base),
                                                                       color: theme.text))
            let para = NSMutableParagraphStyle()
            para.paragraphSpacing = 2
            para.lineSpacing = 1.5
            m.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: m.length))
            result.append(m)
            result.append(NSAttributedString(string: "\n"))
            i = j
        }

        if inCode && !codeBuffer.isEmpty {
            blockGap()
            result.append(codeBlock(codeBuffer.joined(separator: "\n"), theme: theme))
        }

        // Trim a single trailing newline for tight bubbles
        if result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }
        return result
    }

    // MARK: Block helpers

    private static func codeBlock(_ code: String, theme: Theme) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: theme.base - 0.5, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 8
        para.headIndent = 8
        para.paragraphSpacing = 2
        para.lineSpacing = 1
        return NSAttributedString(string: code + "\n", attributes: [
            .font: mono,
            .foregroundColor: theme.text,
            .backgroundColor: theme.codeBackground,
            .paragraphStyle: para,
        ])
    }

    private static func parseHeading(_ trimmed: String) -> (Int, String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex, trimmed[idx] == "#", level < 6 {
            level += 1
            idx = trimmed.index(after: idx)
        }
        guard level >= 1, idx < trimmed.endIndex, trimmed[idx] == " " else { return nil }
        let content = String(trimmed[idx...]).trimmingCharacters(in: .whitespaces)
        return (level, content)
    }

    private struct ListItem {
        let ordered: Bool
        let number: Int
        let content: String
        let indent: Int
    }

    private static func parseList(_ line: String) -> ListItem? {
        // Count leading spaces (tabs count as 4) to derive nesting depth.
        var leading = 0
        for ch in line {
            if ch == " " { leading += 1 }
            else if ch == "\t" { leading += 4 }
            else { break }
        }
        let indent = leading / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Unordered
        if let first = trimmed.first, first == "-" || first == "*" || first == "+" {
            let after = trimmed.index(after: trimmed.startIndex)
            if after < trimmed.endIndex, trimmed[after] == " " {
                let content = String(trimmed[after...]).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { return ListItem(ordered: false, number: 0, content: content, indent: indent) }
            }
        }

        // Ordered: "<digits>. text"
        var digits = ""
        var cursor = trimmed.startIndex
        while cursor < trimmed.endIndex, trimmed[cursor].isNumber {
            digits.append(trimmed[cursor])
            cursor = trimmed.index(after: cursor)
        }
        if !digits.isEmpty, cursor < trimmed.endIndex, trimmed[cursor] == "." {
            let afterDot = trimmed.index(after: cursor)
            if afterDot < trimmed.endIndex, trimmed[afterDot] == " " {
                let content = String(trimmed[afterDot...]).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    return ListItem(ordered: true, number: Int(digits) ?? 1, content: content, indent: indent)
                }
            }
        }
        return nil
    }

    // MARK: Inline parsing (recursive for nested emphasis)

    private static func inline(_ text: String, theme: Theme, font: NSFont, color: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let chars = Array(text)
        var i = 0
        var plain = ""

        func flush() {
            if !plain.isEmpty {
                out.append(NSAttributedString(string: plain, attributes: [.font: font, .foregroundColor: color]))
                plain = ""
            }
        }

        while i < chars.count {
            let c = chars[i]

            // Inline code `...`
            if c == "`", let close = findSingle(chars, i + 1, "`"), close > i + 1 {
                flush()
                let codeText = String(chars[(i + 1)..<close])
                let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize - 0.5, weight: .regular)
                out.append(NSAttributedString(string: codeText, attributes: [
                    .font: mono,
                    .foregroundColor: theme.accent,
                    .backgroundColor: theme.codeBackground,
                ]))
                i = close + 1
                continue
            }

            // Bold ** or __
            if (c == "*" || c == "_"), i + 1 < chars.count, chars[i + 1] == c,
               let close = findDouble(chars, i + 2, c) {
                flush()
                let inner = String(chars[(i + 2)..<close])
                out.append(inline(inner, theme: theme, font: withTrait(font, .bold), color: color))
                i = close + 2
                continue
            }

            // Strikethrough ~~
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~",
               let close = findDouble(chars, i + 2, "~") {
                flush()
                let inner = String(chars[(i + 2)..<close])
                let m = NSMutableAttributedString(attributedString: inline(inner, theme: theme, font: font, color: color))
                m.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: m.length))
                out.append(m)
                i = close + 2
                continue
            }

            // Italic * or _
            if (c == "*" || c == "_"), let close = findSingle(chars, i + 1, c), close > i + 1 {
                flush()
                let inner = String(chars[(i + 1)..<close])
                out.append(inline(inner, theme: theme, font: withTrait(font, .italic), color: color))
                i = close + 1
                continue
            }

            // Link [text](url)
            if c == "[", let link = parseLink(chars, i) {
                flush()
                let m = NSMutableAttributedString(attributedString: inline(link.text, theme: theme, font: font, color: theme.accent))
                m.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: m.length))
                if let url = URL(string: link.url) {
                    m.addAttribute(.link, value: url, range: NSRange(location: 0, length: m.length))
                }
                out.append(m)
                i = link.next
                continue
            }

            plain.append(c)
            i += 1
        }
        flush()
        return out
    }

    private static func findSingle(_ chars: [Character], _ start: Int, _ target: Character) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == target {
                // Not part of a doubled marker
                let doubledNext = (i + 1 < chars.count && chars[i + 1] == target)
                let doubledPrev = (i - 1 >= start && chars[i - 1] == target)
                if !doubledNext && !doubledPrev { return i }
            }
            i += 1
        }
        return nil
    }

    private static func findDouble(_ chars: [Character], _ start: Int, _ target: Character) -> Int? {
        var i = start
        while i + 1 < chars.count {
            if chars[i] == target && chars[i + 1] == target { return i }
            i += 1
        }
        return nil
    }

    private static func parseLink(_ chars: [Character], _ start: Int) -> (text: String, url: String, next: Int)? {
        // start points at '['
        guard start < chars.count, chars[start] == "[" else { return nil }
        var i = start + 1
        var text = ""
        while i < chars.count, chars[i] != "]" {
            text.append(chars[i]); i += 1
        }
        guard i < chars.count, chars[i] == "]", i + 1 < chars.count, chars[i + 1] == "(" else { return nil }
        i += 2
        var url = ""
        while i < chars.count, chars[i] != ")" {
            url.append(chars[i]); i += 1
        }
        guard i < chars.count, chars[i] == ")" else { return nil }
        return (text, url.trimmingCharacters(in: .whitespaces), i + 1)
    }

    private static func withTrait(_ font: NSFont, _ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(trait)
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
