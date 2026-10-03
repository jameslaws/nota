import AppKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.jameslaws.nota", category: "app")

@main
struct NotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Nota has no windows of its own — the notes are the windows, and the menu
        // bar item is built by hand below so a plain click can toggle them.
        Settings { EmptyView() }
    }
}

@MainActor
@Observable
final class NotaCore {
    static let shared = NotaCore()

    let store = NoteStore()
    let windows = NoteWindows()

    private init() {}

    func start() {
        windows.attach(to: store)
    }

    /// Makes a note from text handed in by Loqui, Shortcuts, or anything else that
    /// can open a URL.
    func capture(_ text: String) {
        // "Nota" on its own is a request for a blank note under the cursor's
        // attention, not a no-op.
        let note = store.create(text: text, centred: text.isEmpty)
        windows.sync()
        windows.reveal(note.id)
        log.info("captured a note of \(text.count) characters")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let core = NotaCore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        core.start()
        buildStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        core.store.flush()
    }

    // MARK: - Menu bar
    //
    // NSStatusItem rather than MenuBarExtra: a plain left click has to toggle the
    // notes, and MenuBarExtra always wants to open something instead.

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        refreshIcon()
    }

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if isRightClick {
            showMenu()
        } else {
            core.windows.toggle()
            refreshIcon()
        }
    }

    private func refreshIcon() {
        // Filled when the notes are on screen, outlined when they are hidden — the
        // icon says what a click will do without needing a badge.
        statusItem?.button?.image = StatusIcon.image(notesVisible: core.windows.isVisible)
        statusItem?.button?.toolTip = core.windows.isVisible ? "Hide notes" : "Show notes"
    }

    private func showMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "n").target = self
        menu.addItem(
            withTitle: core.windows.isVisible ? "Hide All Notes" : "Show All Notes",
            action: #selector(toggleNotes),
            keyEquivalent: ""
        ).target = self

        menu.addItem(.separator())

        let count = core.store.notes.count
        let counter = NSMenuItem(
            title: count == 1 ? "1 note" : "\(count) notes",
            action: nil,
            keyEquivalent: ""
        )
        counter.isEnabled = false
        menu.addItem(counter)

        menu.addItem(withTitle: "Reveal Notes Folder", action: #selector(revealFolder), keyEquivalent: "").target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nota", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Actions

    @objc private func newNote() {
        let note = core.store.create()
        core.windows.sync()
        core.windows.reveal(note.id)
        refreshIcon()
    }

    @objc private func toggleNotes() {
        core.windows.toggle()
        refreshIcon()
    }

    @objc private func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([core.store.folder])
    }

    @objc private func quit() {
        core.store.flush()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - URLs

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme?.lowercased() == "nota" else { continue }

            let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let text = query.first { $0.name == "text" }?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            switch action {
            case "toggle":
                // "Nota" on its own means show me what I've got, or put it away.
                core.windows.toggle()
            case "new":
                core.capture(text)
            default:
                continue
            }
            refreshIcon()
        }
    }
}
