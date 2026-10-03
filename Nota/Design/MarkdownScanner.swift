import Foundation

/// What a single line of markdown is, and where its syntax characters sit.
/// Shared by the styler (which hides the syntax) and the text view (which draws the
/// bullet or checkbox in the space the hidden syntax left behind).
enum MarkdownLineKind: Equatable {
    case plain
    case heading(level: Int)
    case bullet
    case task(done: Bool)
    case quote
}

struct MarkdownLine: Equatable {
    /// Range of the whole line in the document.
    var range: NSRange
    /// Range of the leading syntax, e.g. "## " or "- [x] ".
    var markerRange: NSRange
    var kind: MarkdownLineKind

    var hasMarker: Bool { markerRange.length > 0 }
}

enum MarkdownScanner {

    /// The gap left for a drawn bullet or checkbox once the raw marker is hidden.
    static let markerIndent: CGFloat = 20

    static func lines(in string: NSString) -> [MarkdownLine] {
        var result: [MarkdownLine] = []
        let full = NSRange(location: 0, length: string.length)

        string.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = string.substring(with: lineRange)
            result.append(MarkdownLine(
                range: lineRange,
                markerRange: markerRange(in: line, lineStart: lineRange.location),
                kind: kind(of: line)
            ))
        }

        // enumerateSubstrings skips a trailing empty line, which the caret can still
        // be sitting on.
        if string.length == 0 || string.hasSuffix("\n") {
            result.append(MarkdownLine(
                range: NSRange(location: string.length, length: 0),
                markerRange: NSRange(location: string.length, length: 0),
                kind: .plain
            ))
        }
        return result
    }

    static func kind(of line: String) -> MarkdownLineKind {
        if let match = match("^(#{1,6})[ \t]+", line), match.numberOfRanges > 1 {
            return .heading(level: min(match.range(at: 1).length, 3))
        }
        if let match = match("^[-*][ \t]+\\[([ xX])\\][ \t]+", line), match.numberOfRanges > 1 {
            let flag = (line as NSString).substring(with: match.range(at: 1)).lowercased()
            return .task(done: flag == "x")
        }
        if match("^[-*][ \t]+", line) != nil { return .bullet }
        if match("^>[ \t]+", line) != nil { return .quote }
        return .plain
    }

    private static func markerRange(in line: String, lineStart: Int) -> NSRange {
        let patterns = ["^(#{1,6})[ \t]+", "^[-*][ \t]+\\[[ xX]\\][ \t]+", "^[-*][ \t]+", "^>[ \t]+"]
        for pattern in patterns {
            if let match = match(pattern, line) {
                return NSRange(location: lineStart, length: match.range.length)
            }
        }
        return NSRange(location: lineStart, length: 0)
    }

    private static func match(_ pattern: String, _ line: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
    }
}
