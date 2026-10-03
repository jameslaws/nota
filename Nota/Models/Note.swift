import CoreGraphics
import Foundation

/// One post-it. Nothing about it is app-specific — it is a markdown file with a
/// little frontmatter, so a note outlives Nota and can be read anywhere.
/// Which desktops a note appears on. The same choice the Dock offers an app.
enum NoteSpaces: String, Sendable, Equatable {
    /// Follows you everywhere.
    case all
    /// Stays on the desktop it is currently sitting on.
    case desktop
}

struct Note: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var colour: NotePaper
    var frame: CGRect
    var created: Date
    var spaces: NoteSpaces = .all

    /// First non-empty line, used for the menu and for the window's accessibility title.
    var summary: String {
        let line = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? "Empty note"

        return line
            .replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^[-*]\\s+(\\[[ xX]\\]\\s*)?", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func new(text: String = "", colour: NotePaper = .butter, at origin: CGPoint) -> Note {
        Note(
            id: UUID(),
            text: text,
            colour: colour,
            frame: CGRect(origin: origin, size: CGSize(width: 268, height: 232)),
            created: .now,
            spaces: .all
        )
    }
}

// MARK: - File format

extension Note {

    var filename: String { "\(id.uuidString).md" }

    /// Frontmatter then body. Deliberately boring and hand-editable.
    func serialised() -> String {
        """
        ---
        id: \(id.uuidString)
        colour: \(colour.rawValue)
        x: \(Int(frame.origin.x))
        y: \(Int(frame.origin.y))
        w: \(Int(frame.size.width))
        h: \(Int(frame.size.height))
        created: \(ISO8601DateFormatter().string(from: created))
        spaces: \(spaces.rawValue)
        ---
        \(text)
        """
    }

    init?(contents: String, fallbackID: UUID) {
        var fields: [String: String] = [:]
        var body = contents

        if contents.hasPrefix("---\n"),
           let end = contents.range(of: "\n---\n", range: contents.index(contents.startIndex, offsetBy: 3)..<contents.endIndex) {
            let header = contents[contents.index(contents.startIndex, offsetBy: 4)..<end.lowerBound]
            for line in header.split(separator: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                fields[key] = value
            }
            body = String(contents[end.upperBound...])
        }

        self.id = fields["id"].flatMap(UUID.init(uuidString:)) ?? fallbackID
        self.text = body
        self.colour = fields["colour"].flatMap(NotePaper.init(rawValue:)) ?? .butter
        self.created = fields["created"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
        self.spaces = fields["spaces"].flatMap(NoteSpaces.init(rawValue:)) ?? .all

        let x = Double(fields["x"] ?? "") ?? 200
        let y = Double(fields["y"] ?? "") ?? 200
        let w = Double(fields["w"] ?? "") ?? 268
        let h = Double(fields["h"] ?? "") ?? 232
        self.frame = CGRect(x: x, y: y, width: max(w, 160), height: max(h, 120))
    }
}
