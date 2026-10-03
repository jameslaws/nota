import AppKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.jameslaws.nota", category: "windows")

/// One borderless panel per note, kept in step with the store.
///
/// Every note joins all Spaces. macOS gives no way to pin a window to a *named*
/// desktop, so rather than half-implement that, notes are everywhere and the menu
/// bar toggle is what controls whether you are looking at them.
///
/// The window is deliberately larger than the paper: `Sheet.shadowMargin` of
/// transparent space on every side gives the sheet's own shadow somewhere to fall.
/// The system shadow is off, because it is built from the alpha channel and a
/// translucent note turns it into a dark rim around the edge.
@MainActor
@Observable
final class NoteWindows {

    private(set) var isVisible = true
    private var panels: [UUID: NotePanel] = [:]
    private weak var store: NoteStore?
    private var clickMonitor: Any?

    /// Deliberately without `.stationary`. That flag pins a window to the desktop
    /// the way wallpaper is pinned, which fights `.canJoinAllSpaces` — the two
    /// together are why notes once started living on one desktop only.
    private static func behaviour(for spaces: NoteSpaces) -> NSWindow.CollectionBehavior {
        switch spaces {
        case .all: [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        case .desktop: [.fullScreenAuxiliary, .ignoresCycle]
        }
    }

    func attach(to store: NoteStore) {
        self.store = store
        watchForClicksAway()
        sync()
    }

    /// Clicking the desktop does not reliably deactivate a floating panel, so the
    /// note kept its caret while plainly not being used. Watching for any click
    /// outside the notes catches the desktop, the Dock and everything else in one go.
    private func watchForClicksAway() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.releaseFocus() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.releaseFocus() }
        }
    }

    /// Settles every note: no caret, so every line renders.
    func releaseFocus() {
        for panel in panels.values where panel.firstResponder is NSTextView {
            panel.makeFirstResponder(nil)
        }
    }

    /// Creates panels for new notes, closes them for deleted ones.
    func sync() {
        guard let store else { return }
        let live = Set(store.notes.map(\.id))

        for (id, panel) in panels where !live.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }

        for note in store.notes where panels[note.id] == nil {
            panels[note.id] = makePanel(for: note)
        }

        if isVisible { showAll() }
    }

    // MARK: - Visibility

    @discardableResult
    func toggle() -> Bool {
        isVisible.toggle()
        if isVisible { showAll() } else { hideAll() }
        return isVisible
    }

    // Hiding fades rather than orders out. `orderOut` throws away a window's Space
    // assignment, so a note pinned to one desktop would come back on whichever
    // desktop you happened to be looking at. Left ordered-in at zero alpha, a pinned
    // note stays exactly where it was put.

    func showAll() {
        isVisible = true
        for panel in panels.values {
            panel.ignoresMouseEvents = false
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    func hideAll() {
        isVisible = false
        for panel in panels.values {
            panel.alphaValue = 0
            // Invisible windows must not keep swallowing clicks.
            panel.ignoresMouseEvents = true
        }
    }

    /// Moves a note between "all desktops" and "this desktop".
    func setSpaces(_ spaces: NoteSpaces, for id: UUID) {
        guard var note = store?.notes.first(where: { $0.id == id }) else { return }
        note.spaces = spaces
        store?.update(note)

        guard let panel = panels[id] else { return }
        panel.collectionBehavior = Self.behaviour(for: spaces)
        // Re-order so the change takes hold on the desktop showing right now, which
        // is the one the user is looking at while they click it.
        panel.orderFrontRegardless()
    }

    /// Brings a single note forward and puts the cursor in it — used right after a
    /// note arrives by voice, so you can see what landed.
    func reveal(_ id: UUID) {
        showAll()
        guard let panel = panels[id] else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Put the caret in the note so a spoken "Nota" is immediately typeable.
        if let editor = panel.contentView?.firstTextView {
            panel.makeFirstResponder(editor)
        }
    }

    /// Drag-to-resize from the sheet's own corner. The top-left stays put, which is
    /// what people expect from a bottom-right handle.
    private func resize(_ id: UUID, by translation: CGSize) {
        guard let panel = panels[id] else { return }
        if panel.resizeAnchor == nil { panel.resizeAnchor = panel.frame }
        guard let start = panel.resizeAnchor else { return }

        let width = max(panel.minSize.width, start.width + translation.width)
        let height = max(panel.minSize.height, start.height + translation.height)
        let top = start.maxY

        panel.setFrame(
            NSRect(x: start.minX, y: top - height, width: width, height: height),
            display: true
        )
    }

    // MARK: - Panels

    private func makePanel(for note: Note) -> NotePanel {
        let margin = NoteView.Sheet.shadowMargin
        let windowFrame = note.frame.insetBy(dx: -margin, dy: -margin)

        let panel = NotePanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.margin = margin
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = Self.behaviour(for: note.spaces)
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.minSize = NSSize(width: 180 + margin * 2, height: 120 + margin * 2)

        let view = NoteView(
            note: note,
            onChange: { [weak self] updated in self?.store?.update(updated) },
            onDelete: { [weak self] in
                guard let self, let current = self.store?.notes.first(where: { $0.id == note.id }) else { return }
                self.store?.delete(current)
                self.sync()
            },
            onNew: { [weak self] in
                guard let self, let store = self.store else { return }
                let fresh = store.create()
                self.sync()
                self.reveal(fresh.id)
            },
            onResize: { [weak self] translation in
                self?.resize(note.id, by: translation)
            },
            onResizeEnd: { [weak self] in
                self?.panels[note.id]?.resizeAnchor = nil
            },
            onSpacesChange: { [weak self] spaces in
                self?.setSpaces(spaces, for: note.id)
            }
        )

        let hosting = NSHostingView(rootView: view)
        // Without this the hosting view can push its own fitting size onto the
        // window, which would silently undo a restored size.
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(windowFrame, display: false)

        log.info("placed \(note.id.uuidString.prefix(4), privacy: .public) at \(Int(note.frame.width))x\(Int(note.frame.height))")

        // Assigned after the initial placement so restoring a saved position does
        // not immediately report itself back as a change.
        panel.onSheetFrameChange = { [weak self] frame in
            guard let self, var current = self.store?.notes.first(where: { $0.id == note.id }) else { return }
            guard current.frame != frame else { return }
            current.frame = frame
            self.store?.update(current)
        }

        return panel
    }
}

extension NSView {
    /// First text view anywhere in the hierarchy — used to hand a new note the caret.
    var firstTextView: NSTextView? {
        if let view = self as? NSTextView { return view }
        for child in subviews {
            if let found = child.firstTextView { return found }
        }
        return nil
    }
}

/// Borderless windows refuse key status by default, which would make the notes
/// impossible to type into.
final class NotePanel: NSPanel, NSWindowDelegate {
    var onSheetFrameChange: ((CGRect) -> Void)?
    var margin: CGFloat = 0
    /// Frame at the moment a resize drag began, so translation can be absolute.
    var resizeAnchor: CGRect?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The paper itself, without the transparent shadow margin around it.
    var sheetFrame: CGRect { frame.insetBy(dx: margin, dy: margin) }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        delegate = self
    }

    // Dragging a window by its background moves it with setFrameOrigin, which never
    // routes through setFrame — so an override there missed every drag the user made
    // and positions were lost on restart. The delegate callbacks catch both.

    func windowDidMove(_ notification: Notification) {
        repaint()
        onSheetFrameChange?(sheetFrame)
    }

    /// A transparent window's shadow is cached, and dragging can leave the old one
    /// painted behind. Marking the view dirty is not enough on its own — the redraw
    /// has to be flushed while the drag is still in progress.
    private func repaint() {
        invalidateShadow()
        contentView?.needsDisplay = true
        contentView?.displayIfNeeded()
        displayIfNeeded()
    }

    func windowDidResize(_ notification: Notification) {
        repaint()
        log.info("resized to \(Int(self.sheetFrame.width))x\(Int(self.sheetFrame.height))")
        onSheetFrameChange?(sheetFrame)
    }

    /// Clicking away from a note should settle it: no caret, every line rendered.
    func windowDidResignKey(_ notification: Notification) {
        makeFirstResponder(nil)
    }
}
