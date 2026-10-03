import AppKit
import SwiftUI

/// Applies markdown styling to live text.
///
/// Syntax characters are never deleted — the file always holds exactly what was
/// typed. They are shrunk to nothing and made transparent on every line except the
/// one holding the caret, which produces "the line I'm editing shows the markdown,
/// the rest show the formatting" without ever lying to the document.
///
/// A hidden `- ` leaves a hole where a bullet ought to be, so list lines are also
/// indented and the bullet or checkbox is painted into that gap by the text view.
enum MarkdownStyler {

    static let gutter: CGFloat = 16
    static let bodySize: CGFloat = 12.5

    /// Which lines want a marker drawn, worked out during styling and handed to the
    /// text view so it does not have to parse the document twice.
    struct Layout {
        var drawn: [MarkdownLine] = []
    }

    @discardableResult
    static func apply(to storage: NSTextStorage, paper: NotePaper, caret: Int) -> Layout {
        let string = storage.string as NSString
        let full = NSRange(location: 0, length: string.length)
        var layout = Layout()
        guard full.length > 0 else { return layout }

        let ink = NSColor(paper.ink)
        let soft = NSColor(paper.ink.opacity(0.45))

        storage.beginEditing()
        storage.setAttributes(
            [.font: NSFont.systemFont(ofSize: bodySize), .foregroundColor: ink, .paragraphStyle: paragraph(indent: 0)],
            range: full
        )

        for line in MarkdownScanner.lines(in: string) where line.range.length > 0 {
            // The caret sits between characters, so the end of a line still counts.
            let revealed = caret >= line.range.location && caret <= line.range.upperBound
            style(line, in: storage, string: string, revealed: revealed, ink: ink, soft: soft)

            if !revealed, line.hasMarker {
                switch line.kind {
                case .bullet, .task:
                    layout.drawn.append(line)
                default:
                    break
                }
            }
        }

        storage.endEditing()
        return layout
    }

    // MARK: - One line

    private static func style(
        _ line: MarkdownLine,
        in storage: NSTextStorage,
        string: NSString,
        revealed: Bool,
        ink: NSColor,
        soft: NSColor
    ) {
        switch line.kind {
        case .heading(let level):
            let sizes: [CGFloat] = [19, 16, 14]
            storage.addAttribute(
                .font,
                value: NSFont.systemFont(ofSize: sizes[level - 1], weight: .semibold),
                range: line.range
            )
            hide(line.markerRange, in: storage, revealed: revealed, soft: soft)

        case .bullet:
            hide(line.markerRange, in: storage, revealed: revealed, soft: soft)
            indent(line, in: storage, revealed: revealed)

        case .task(let done):
            hide(line.markerRange, in: storage, revealed: revealed, soft: soft)
            indent(line, in: storage, revealed: revealed)
            if done {
                let rest = NSRange(
                    location: line.markerRange.upperBound,
                    length: max(0, line.range.upperBound - line.markerRange.upperBound)
                )
                storage.addAttributes(
                    [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: soft],
                    range: rest
                )
            }

        case .quote:
            hide(line.markerRange, in: storage, revealed: revealed, soft: soft)
            indent(line, in: storage, revealed: revealed)
            storage.addAttribute(
                .font,
                value: NSFontManager.shared.convert(.systemFont(ofSize: bodySize), toHaveTrait: .italicFontMask),
                range: line.range
            )

        case .plain:
            break
        }

        inline(line, in: storage, string: string, revealed: revealed, soft: soft)
    }

    /// Bold, italic and code, each with its markers hidden unless the caret is here.
    private static func inline(
        _ line: MarkdownLine,
        in storage: NSTextStorage,
        string: NSString,
        revealed: Bool,
        soft: NSColor
    ) {
        let start = line.markerRange.upperBound
        let scope = NSRange(location: start, length: max(0, line.range.upperBound - start))
        guard scope.length > 0 else { return }

        let text = string.substring(with: scope)
        let base = storage.attribute(.font, at: start, effectiveRange: nil) as? NSFont
            ?? .systemFont(ofSize: bodySize)

        let rules: [(String, Int, [NSAttributedString.Key: Any])] = [
            ("\\*\\*(.+?)\\*\\*", 2, [.font: NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)]),
            ("(?<![*\\w])\\*([^*\n]+?)\\*(?![*\\w])", 1, [
                .font: NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            ]),
            ("`([^`\n]+?)`", 1, [.font: NSFont.monospacedSystemFont(ofSize: bodySize - 0.5, weight: .regular)]),
        ]

        for (pattern, markerLength, attributes) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                let inner = shift(match.range(at: 1), by: start)
                guard inner.upperBound <= storage.length else { continue }
                storage.addAttributes(attributes, range: inner)

                let whole = shift(match.range, by: start)
                hide(NSRange(location: whole.location, length: markerLength), in: storage, revealed: revealed, soft: soft)
                hide(NSRange(location: whole.upperBound - markerLength, length: markerLength), in: storage, revealed: revealed, soft: soft)
            }
        }
    }

    // MARK: - Markers

    /// Hidden by making the characters weightless rather than by deleting them, so
    /// the file is never rewritten behind the user's back.
    private static func hide(_ range: NSRange, in storage: NSTextStorage, revealed: Bool, soft: NSColor) {
        guard range.length > 0, range.upperBound <= storage.length else { return }

        if revealed {
            storage.addAttribute(.foregroundColor, value: soft, range: range)
        } else {
            storage.addAttributes(
                [.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear],
                range: range
            )
        }
    }

    /// Leaves room for the drawn bullet, and keeps wrapped lines lined up under the
    /// text rather than under the marker.
    private static func indent(_ line: MarkdownLine, in storage: NSTextStorage, revealed: Bool) {
        guard line.range.length > 0, line.range.upperBound <= storage.length else { return }
        storage.addAttribute(
            .paragraphStyle,
            value: paragraph(indent: revealed ? 0 : MarkdownScanner.markerIndent),
            range: line.range
        )
    }

    private static func paragraph(indent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1.5
        style.paragraphSpacing = 2
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    private static func shift(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }
}
