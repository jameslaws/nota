import Foundation

/// What a single line of markdown is, and where its syntax characters sit.
/// Shared by the styler (which hides the syntax), the text view (which draws
/// bullets, checkboxes, quote bars and rules into the space the syntax left), and
/// the editor (which continues lists on Return and indents them on Tab).
enum MarkdownLineKind: Equatable {
    case plain
    case heading(level: Int)
    case bullet
    case task(done: Bool)
    /// "1." or "1)". The number stays visible — it is content, not decoration.
    case ordered(number: Int, delimiter: Character)
    case quote
    /// A line of three or more `-`, `*` or `_`.
    case rule
    /// A ``` or ~~~ line opening or closing a code block.
    case fence
    /// A line inside a code block. Nothing in it is markdown.
    case code
}

struct MarkdownLine: Equatable {
    /// Range of the whole line in the document, without its line break.
    var range: NSRange
    /// Leading tabs and spaces.
    var indentRange: NSRange
    /// Leading whitespace plus the syntax, e.g. "\t- [x] ". Text starts after it.
    var markerRange: NSRange
    var kind: MarkdownLineKind
    /// How deeply a list item is nested: a tab, or two spaces, per level.
    var depth: Int
    /// The character between a task's brackets, which a click flips.
    var flagRange: NSRange?

    var hasMarker: Bool { markerRange.length > indentRange.length }
    var contentStart: Int { markerRange.upperBound }
    var content: NSRange { NSRange(location: contentStart, length: range.upperBound - contentStart) }

    var isListItem: Bool {
        switch kind {
        case .bullet, .task, .ordered: true
        default: false
        }
    }

    /// Lines whose syntax is never shown: it is drawn instead, or is just a shortcut
    /// for the formatting. The caret is kept out of it.
    var hidesMarker: Bool {
        switch kind {
        case .bullet, .task, .quote, .heading: true
        default: false
        }
    }

    /// Where the hidden part of the line ends — the first place the caret may sit.
    var hiddenEnd: Int { hidesMarker ? contentStart : indentRange.upperBound }

    /// The syntax that starts the next line when Return is pressed here.
    func continuation(in string: NSString) -> String {
        let indent = string.substring(with: indentRange)
        let symbol = hasMarker ? string.substring(with: NSRange(location: indentRange.upperBound, length: 1)) : "-"
        switch kind {
        case .bullet: return indent + symbol + " "
        case .task: return indent + symbol + " [ ] "
        case .ordered(let number, let delimiter): return indent + "\(number + 1)\(delimiter) "
        case .quote: return "> "
        default: return ""
        }
    }
}

enum MarkdownScanner {

    /// The gap left for a drawn bullet or checkbox, per level of nesting.
    static let markerIndent: CGFloat = 18

    static func lines(in string: NSString) -> [MarkdownLine] {
        var result: [MarkdownLine] = []
        var inCode = false
        let full = NSRange(location: 0, length: string.length)

        string.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let text = string.substring(with: lineRange)
            let line = parse(text, at: lineRange, inCode: inCode)
            if line.kind == .fence { inCode.toggle() }
            result.append(line)
        }

        // enumerateSubstrings skips a trailing empty line, which the caret can still
        // be sitting on.
        if string.length == 0 || string.hasSuffix("\n") {
            let end = NSRange(location: string.length, length: 0)
            result.append(MarkdownLine(
                range: end, indentRange: end, markerRange: end,
                kind: inCode ? .code : .plain, depth: 0
            ))
        }
        return result
    }

    /// The line holding a character position.
    static func line(at location: Int, in lines: [MarkdownLine]) -> MarkdownLine? {
        lines.last { $0.range.location <= location && location <= $0.range.upperBound }
    }

    // MARK: - One line

    private static func parse(_ text: String, at range: NSRange, inCode: Bool) -> MarkdownLine {
        let ns = text as NSString
        let start = range.location

        // Leading whitespace: a tab is one level of nesting, so are two spaces.
        var indentLength = 0
        var tabs = 0
        var spaces = 0
        while indentLength < ns.length {
            let c = ns.character(at: indentLength)
            if c == 9 { tabs += 1 } else if c == 32 { spaces += 1 } else { break }
            indentLength += 1
        }
        let indent = NSRange(location: start, length: indentLength)
        let depth = tabs + spaces / 2

        func line(_ kind: MarkdownLineKind, marker: Int = 0, flag: NSRange? = nil) -> MarkdownLine {
            MarkdownLine(
                range: range,
                indentRange: indent,
                markerRange: NSRange(location: start, length: indentLength + marker),
                kind: kind,
                depth: depth,
                flagRange: flag
            )
        }

        let rest = ns.substring(from: indentLength)

        if match("^(```|~~~)", rest) != nil {
            return line(.fence)
        }
        if inCode {
            return line(.code)
        }

        // Block syntax that only counts at the left margin.
        if indentLength == 0 {
            if let m = match("^(#{1,6})[ \t]+", rest) {
                return line(.heading(level: m.range(at: 1).length), marker: m.range.length)
            }
            if match("^(-[ \t]*){3,}$|^(\\*[ \t]*){3,}$|^(_[ \t]*){3,}$", rest) != nil {
                return line(.rule)
            }
            if let m = match("^>[ \t]?", rest) {
                return line(.quote, marker: m.range.length)
            }
        }

        if let m = match("^[-*+][ \t]+\\[([ xX])\\](?:[ \t]+|$)", rest) {
            let flag = NSRange(location: start + indentLength + m.range(at: 1).location, length: 1)
            let done = (rest as NSString).substring(with: m.range(at: 1)).lowercased() == "x"
            return line(.task(done: done), marker: m.range.length, flag: flag)
        }
        if let m = match("^[-*+][ \t]+", rest) {
            return line(.bullet, marker: m.range.length)
        }
        if let m = match("^(\\d{1,9})([.)])[ \t]+", rest) {
            let number = Int((rest as NSString).substring(with: m.range(at: 1))) ?? 1
            let delimiter = Character((rest as NSString).substring(with: m.range(at: 2)))
            return line(.ordered(number: number, delimiter: delimiter), marker: m.range.length)
        }

        return line(.plain)
    }

    private static var cache: [String: NSRegularExpression] = [:]

    static func match(_ pattern: String, _ text: String) -> NSTextCheckingResult? {
        regex(pattern)?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    static func regex(_ pattern: String) -> NSRegularExpression? {
        if let cached = cache[pattern] { return cached }
        let compiled = try? NSRegularExpression(pattern: pattern)
        cache[pattern] = compiled
        return compiled
    }
}
