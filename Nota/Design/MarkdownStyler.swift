import AppKit
import SwiftUI

/// Applies markdown styling to live text.
///
/// Syntax characters are never deleted — the file always holds exactly what was
/// typed. They are shrunk to nothing and made transparent instead.
///
/// Two kinds of syntax, treated differently:
///
/// - **Block syntax** (`- `, `- [ ] `, `> `, `## `) is never shown. Bullets,
///   checkboxes and quote bars are painted into the gap by the text view, and the
///   editor keeps the caret out of the hidden characters, so the text never jumps
///   sideways when the caret arrives on a line.
/// - **Inline syntax** (`**`, `*`, `~~`, `` ` ``, links) is shown faintly on the
///   line holding the caret, because that is the only way to edit it, and hidden
///   everywhere else.
enum MarkdownStyler {

    static let gutter: CGFloat = 16
    static let bodySize: CGFloat = 12.5

    /// What the text view needs to paint, worked out during styling so it does not
    /// have to parse the document twice.
    struct Layout {
        /// Lines with something drawn in their gutter: bullets, checkboxes, quote
        /// bars, rules.
        var drawn: [MarkdownLine] = []
        /// Each fenced code block, fences included, for the shaded panel behind it.
        var codeBlocks: [NSRange] = []
        /// Every line, for the editor's list handling.
        var lines: [MarkdownLine] = []
    }

    static func baseAttributes(ink: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: bodySize), .foregroundColor: ink, .paragraphStyle: paragraph()]
    }

    @discardableResult
    static func apply(to storage: NSTextStorage, paper: NotePaper, caret: Int) -> Layout {
        let string = storage.string as NSString
        let full = NSRange(location: 0, length: string.length)
        var layout = Layout()
        layout.lines = MarkdownScanner.lines(in: string)
        guard full.length > 0 else { return layout }

        let ink = NSColor(paper.ink)
        let palette = Palette(ink: ink)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(ink: ink), range: full)

        var blockStart: Int?
        for line in layout.lines {
            // The caret sits between characters, so the end of a line still counts.
            let revealed = caret >= line.range.location && caret <= line.range.upperBound
            style(line, in: storage, string: string, revealed: revealed, palette: palette, layout: &layout)

            switch line.kind {
            case .fence:
                if let start = blockStart {
                    layout.codeBlocks.append(NSRange(location: start, length: line.range.upperBound - start))
                    blockStart = nil
                } else {
                    blockStart = line.range.location
                }
            default:
                break
            }
        }
        // An unclosed block runs to the end, the way it reads while still typing it.
        if let start = blockStart {
            layout.codeBlocks.append(NSRange(location: start, length: full.upperBound - start))
        }

        storage.endEditing()
        return layout
    }

    /// The handful of ink strengths everything is drawn in.
    struct Palette {
        let ink: NSColor
        var soft: NSColor { ink.withAlphaComponent(0.45) }
        var muted: NSColor { ink.withAlphaComponent(0.72) }
        var wash: NSColor { ink.withAlphaComponent(0.08) }
    }

    // MARK: - One line

    private static func style(
        _ line: MarkdownLine,
        in storage: NSTextStorage,
        string: NSString,
        revealed: Bool,
        palette: Palette,
        layout: inout Layout
    ) {
        guard line.range.length > 0 else { return }

        switch line.kind {
        case .heading(let level):
            let sizes: [CGFloat] = [19, 16, 14, 13, 12.5, 12.5]
            let weights: [NSFont.Weight] = [.bold, .semibold, .semibold, .semibold, .semibold, .medium]
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: sizes[level - 1], weight: weights[level - 1]),
                .paragraphStyle: paragraph(spacingBefore: line.range.location == 0 ? 0 : 5),
            ], range: line.range)
            hide(line.markerRange, in: storage)

        case .bullet:
            hide(line.markerRange, in: storage)
            hang(line, in: storage)
            layout.drawn.append(line)

        case .task(let done):
            hide(line.markerRange, in: storage)
            hang(line, in: storage)
            layout.drawn.append(line)
            if done {
                storage.addAttributes(
                    [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: palette.soft],
                    range: line.content
                )
            }

        case .ordered:
            // The number stays — it is content. Only the nesting whitespace goes,
            // and the number hangs in the gutter so wrapped lines align with the text.
            hide(line.indentRange, in: storage)
            let number = NSRange(location: line.indentRange.upperBound, length: line.contentStart - line.indentRange.upperBound)
            let font = NSFont.monospacedDigitSystemFont(ofSize: bodySize, weight: .regular)
            storage.addAttributes([.foregroundColor: palette.muted, .font: font], range: number)
            let width = (string.substring(with: number) as NSString).size(withAttributes: [.font: font]).width
            hang(line, in: storage, firstLineOffset: width)

        case .quote:
            hide(line.markerRange, in: storage)
            storage.addAttributes([
                .foregroundColor: palette.muted,
                .paragraphStyle: paragraph(indent: 14),
            ], range: line.range)
            layout.drawn.append(line)

        case .rule:
            if revealed {
                storage.addAttribute(.foregroundColor, value: palette.soft, range: line.range)
            } else {
                hide(line.range, in: storage)
                // The characters are gone, so the line needs height of its own for
                // the rule to sit in.
                let style = paragraph()
                style.minimumLineHeight = 16
                storage.addAttribute(.paragraphStyle, value: style, range: line.range)
                layout.drawn.append(line)
            }
            return

        case .fence:
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: bodySize - 2, weight: .regular),
                .foregroundColor: palette.soft,
            ], range: line.range)
            return

        case .code:
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular), range: line.range)
            return

        case .plain:
            break
        }

        inline(line, in: storage, string: string, revealed: revealed, palette: palette)
    }

    // MARK: - Inline

    private struct Rule {
        let pattern: String
        let marker: Int
        let apply: (NSFont) -> [NSAttributedString.Key: Any]
        /// Nothing else may style inside it (code), or start inside it (links).
        let exclusive: Bool
    }

    /// Code and links first, because nothing inside them is markdown; then the
    /// emphasis rules, longest marker first so `***` is not read as `**` + `*`.
    private static func rules(palette: Palette) -> [Rule] {
        let bold: (NSFont) -> NSFont = { NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask) }
        let italic: (NSFont) -> NSFont = { NSFontManager.shared.convert($0, toHaveTrait: .italicFontMask) }
        return [
            Rule(pattern: "`([^`\n]+?)`", marker: 1, apply: { base in
                [.font: NSFont.monospacedSystemFont(ofSize: base.pointSize - 1, weight: .regular),
                 .backgroundColor: palette.wash]
            }, exclusive: true),
            Rule(pattern: "\\*\\*\\*(?!\\s)(.+?)(?<!\\s)\\*\\*\\*", marker: 3, apply: { [.font: italic(bold($0))] }, exclusive: true),
            Rule(pattern: "\\*\\*(?!\\s)(.+?)(?<!\\s)\\*\\*", marker: 2, apply: { [.font: bold($0)] }, exclusive: false),
            Rule(pattern: "(?<![_\\w])__(?!\\s)(.+?)(?<!\\s)__(?![_\\w])", marker: 2, apply: { [.font: bold($0)] }, exclusive: false),
            Rule(pattern: "(?<![*\\w])\\*(?![\\s*])([^*\n]+?)(?<!\\s)\\*(?![*\\w])", marker: 1, apply: { [.font: italic($0)] }, exclusive: false),
            Rule(pattern: "(?<![_\\w])_(?![\\s_])([^_\n]+?)(?<!\\s)_(?![_\\w])", marker: 1, apply: { [.font: italic($0)] }, exclusive: false),
            Rule(pattern: "~~(?!\\s)(.+?)(?<!\\s)~~", marker: 2, apply: { _ in
                [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: palette.soft]
            }, exclusive: false),
            Rule(pattern: "==(?!\\s)(.+?)(?<!\\s)==", marker: 2, apply: { _ in
                [.backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)]
            }, exclusive: false),
        ]
    }

    private static func inline(
        _ line: MarkdownLine,
        in storage: NSTextStorage,
        string: NSString,
        revealed: Bool,
        palette: Palette
    ) {
        let scope = line.content
        guard scope.length > 0 else { return }
        let text = string.substring(with: scope)
        let local = NSRange(location: 0, length: (text as NSString).length)
        var claimed: [NSRange] = []

        func free(_ range: NSRange) -> Bool {
            !claimed.contains { NSIntersectionRange($0, range).length > 0 }
        }

        func marker(_ range: NSRange) {
            if revealed {
                storage.addAttribute(.foregroundColor, value: palette.soft, range: range)
            } else {
                hide(range, in: storage)
            }
        }

        // Code spans claim their ground before anything else.
        let all = rules(palette: palette)
        if let code = all.first, let regex = MarkdownScanner.regex(code.pattern) {
            for m in regex.matches(in: text, range: local) {
                apply(code, m, start: scope.location, storage: storage, marker: marker)
                claimed.append(m.range)
            }
        }

        // [text](url): the text becomes a live link, the rest is syntax.
        if let regex = MarkdownScanner.regex("\\[([^\\]\n]+)\\]\\(([^)\\s]+)\\)") {
            for m in regex.matches(in: text, range: local) where free(m.range) {
                let label = shift(m.range(at: 1), by: scope.location)
                let target = (text as NSString).substring(with: m.range(at: 2))
                if let url = URL(string: target) {
                    storage.addAttribute(.link, value: url, range: label)
                }
                let whole = shift(m.range, by: scope.location)
                marker(NSRange(location: whole.location, length: 1))
                marker(NSRange(location: label.upperBound, length: whole.upperBound - label.upperBound))
                claimed.append(m.range)
            }
        }

        // Bare web addresses.
        if let regex = MarkdownScanner.regex("https?://[^\\s<>()\\[\\]]+[^\\s<>()\\[\\].,;:!?'\"]") {
            for m in regex.matches(in: text, range: local) where free(m.range) {
                let range = shift(m.range, by: scope.location)
                if let url = URL(string: (text as NSString).substring(with: m.range)) {
                    storage.addAttribute(.link, value: url, range: range)
                }
                claimed.append(m.range)
            }
        }

        for rule in all.dropFirst() {
            guard let regex = MarkdownScanner.regex(rule.pattern) else { continue }
            for m in regex.matches(in: text, range: local) where free(m.range) {
                apply(rule, m, start: scope.location, storage: storage, marker: marker)
                if rule.exclusive { claimed.append(m.range) }
            }
        }
    }

    private static func apply(
        _ rule: Rule,
        _ match: NSTextCheckingResult,
        start: Int,
        storage: NSTextStorage,
        marker: (NSRange) -> Void
    ) {
        let inner = shift(match.range(at: 1), by: start)
        guard inner.length > 0, inner.upperBound <= storage.length else { return }

        // Applied run by run, so bold inside a heading stays heading-sized.
        storage.enumerateAttribute(.font, in: inner) { value, run, _ in
            let base = value as? NSFont ?? .systemFont(ofSize: bodySize)
            storage.addAttributes(rule.apply(base), range: run)
        }

        let whole = shift(match.range, by: start)
        marker(NSRange(location: whole.location, length: rule.marker))
        marker(NSRange(location: whole.upperBound - rule.marker, length: rule.marker))
    }

    // MARK: - Helpers

    /// Hidden by making the characters weightless rather than by deleting them, so
    /// the file is never rewritten behind the user's back.
    private static func hide(_ range: NSRange, in storage: NSTextStorage) {
        guard range.length > 0, range.upperBound <= storage.length else { return }
        storage.addAttributes(
            [.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear],
            range: range
        )
    }

    /// A hanging indent one step deeper per level of nesting. Wrapped lines line up
    /// under the text, not under the marker; `firstLineOffset` pulls the first line
    /// back for a visible marker such as "12."
    private static func hang(_ line: MarkdownLine, in storage: NSTextStorage, firstLineOffset: CGFloat = 0) {
        let indent = CGFloat(line.depth + 1) * MarkdownScanner.markerIndent
        let floor = CGFloat(line.depth) * MarkdownScanner.markerIndent
        storage.addAttribute(
            .paragraphStyle,
            value: paragraph(indent: indent, firstLine: max(floor, indent - firstLineOffset)),
            range: line.range
        )
    }

    private static func paragraph(indent: CGFloat = 0, firstLine: CGFloat? = nil, spacingBefore: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1.5
        style.paragraphSpacing = 2
        style.paragraphSpacingBefore = spacingBefore
        style.firstLineHeadIndent = firstLine ?? indent
        style.headIndent = indent
        return style
    }

    private static func shift(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }
}
