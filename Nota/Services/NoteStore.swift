import AppKit
import Foundation
import OSLog

private let log = Logger(subsystem: "com.jameslaws.nota", category: "store")

/// Notes on disk, one markdown file each, in iCloud Drive so the phone can read
/// them in Files without Nota ever having to sync anything itself.
@MainActor
@Observable
final class NoteStore {

    private(set) var notes: [Note] = []
    let folder: URL

    /// Writes are debounced per note — typing should not hit the disk on every key.
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]

    init() {
        let icloud = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)

        let cloudDrive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

        let base: URL
        if FileManager.default.fileExists(atPath: cloudDrive.path) {
            base = cloudDrive
        } else if let icloud {
            base = icloud
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents", isDirectory: true)
        }

        folder = base.appendingPathComponent("Nota", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Reading

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []

        notes = files
            .filter { $0.pathExtension == "md" }
            .compactMap { url in
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let fallback = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
                return Note(contents: contents, fallbackID: fallback)
            }
            .sorted { $0.created < $1.created }

        log.info("loaded \(self.notes.count) notes from \(self.folder.path, privacy: .public)")
    }

    // MARK: - Writing

    @discardableResult
    func create(text: String = "", colour: NotePaper? = nil, centred: Bool = false) -> Note {
        let note = Note.new(
            text: text,
            colour: colour ?? nextColour(),
            at: centred ? centreOrigin() : nextOrigin()
        )
        notes.append(note)
        write(note)
        return note
    }

    func update(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
        scheduleWrite(note)
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        pendingSaves[note.id]?.cancel()
        pendingSaves[note.id] = nil
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(note.filename))
    }

    private func scheduleWrite(_ note: Note) {
        pendingSaves[note.id]?.cancel()
        pendingSaves[note.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.write(note)
        }
    }

    private func write(_ note: Note) {
        let url = folder.appendingPathComponent(note.filename)
        do {
            try note.serialised().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            log.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Flushes anything still waiting, so quitting never loses the last sentence.
    func flush() {
        for (_, task) in pendingSaves { task.cancel() }
        pendingSaves.removeAll()
        notes.forEach(write)
    }

    // MARK: - Placement

    /// Cycles the palette so consecutive notes are never the same colour.
    private func nextColour() -> NotePaper {
        let used = notes.suffix(1).first?.colour
        let all = NotePaper.allCases
        guard let used, let index = all.firstIndex(of: used) else { return .butter }
        return all[(index + 1) % all.count]
    }

    /// Dead centre, for a blank note summoned by voice — it should land where the
    /// eye already is, not on the pile in the corner.
    private func centreOrigin() -> CGPoint {
        guard let screen = NSScreen.main?.visibleFrame else { return CGPoint(x: 300, y: 300) }
        return CGPoint(x: screen.midX - 134, y: screen.midY - 116)
    }

    /// Cascades down and right from the top-left of the screen, wrapping before it
    /// runs off the bottom, so a burst of dictated notes doesn't land in one stack.
    private func nextOrigin() -> CGPoint {
        guard let screen = NSScreen.main?.visibleFrame else { return CGPoint(x: 200, y: 200) }
        let step: CGFloat = 28
        let offset = CGFloat(notes.count % 8) * step

        return CGPoint(
            x: screen.minX + 40 + offset,
            y: screen.maxY - 272 - offset
        )
    }
}
