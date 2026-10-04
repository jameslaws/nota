import AppKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.jameslaws.nota", category: "stack")

/// What the stack view shows and edits. Separate from the panel so SwiftUI can
/// watch it.
@MainActor
@Observable
final class StackModel {
    var expanded = false
    var query = ""
}

/// The pile of put-away notes: a small deck at the edge of the screen that fans
/// out into a searchable list.
///
/// One panel plays both parts. Collapsed it is just the deck; expanded it grows
/// out from the deck's corner into the list, and shrinks back when you are done.
@MainActor
final class NoteStack {

    private weak var store: NoteStore?
    private var panel: StackPanel?
    private let model = StackModel()
    private var onPullOut: (UUID) -> Void = { _ in }
    private var onShowAll: () -> Void = {}

    /// Where a drag on the deck started, in screen coordinates.
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?
    private var dragging = false

    private static let originKey = "stackOrigin"
    static let margin: CGFloat = 14
    static let deckSize = CGSize(width: 76, height: 70)
    static let fanSize = CGSize(width: 300, height: 430)

    func attach(
        to store: NoteStore,
        onPullOut: @escaping (UUID) -> Void,
        onShowAll: @escaping () -> Void
    ) {
        self.store = store
        self.onPullOut = onPullOut
        self.onShowAll = onShowAll
    }

    /// Shows the deck while your notes are showing and anything is in the stack;
    /// it goes away with the notes.
    func refresh(visible: Bool) {
        guard let store else { return }

        if !visible || store.stacked.isEmpty {
            collapse()
            panel?.orderOut(nil)
            return
        }

        let panel = self.panel ?? makePanel(store: store)
        self.panel = panel
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    // MARK: - Expanding

    func toggleExpanded() {
        model.expanded ? collapse() : expand()
    }

    func expand() {
        guard let panel, !model.expanded else { return }
        model.query = ""
        model.expanded = true
        panel.setFrame(fanFrame(from: panel.frame), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func collapse() {
        guard let panel, model.expanded else { return }
        model.expanded = false
        panel.setFrame(deckFrame(), display: true)
    }

    private func pullOut(_ id: UUID) {
        collapse()
        onPullOut(id)
    }

    private func showAll() {
        collapse()
        onShowAll()
    }

    // MARK: - Placement

    /// The deck lives bottom-right until you drag it somewhere else, and then it
    /// stays wherever you left it.
    private func deckFrame() -> CGRect {
        let size = CGSize(
            width: Self.deckSize.width + Self.margin * 2,
            height: Self.deckSize.height + Self.margin * 2
        )

        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let point = NSPointFromString(saved)
            let frame = CGRect(origin: point, size: size)
            // Only honour it if it is still on a screen — monitors come and go.
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return frame
            }
        }

        let screen = NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(
            origin: CGPoint(x: screen.maxX - size.width - 16, y: screen.minY + 16),
            size: size
        )
    }

    /// The list grows out of the deck's own corner — up and to the left when the
    /// deck is bottom-right — and is nudged back inside the screen when it would
    /// run off an edge.
    private func fanFrame(from deck: CGRect) -> CGRect {
        let size = CGSize(
            width: Self.fanSize.width + Self.margin * 2,
            height: Self.fanSize.height + Self.margin * 2
        )
        let screen = NSScreen.screens.first { $0.frame.intersects(deck) }?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? deck

        let growsLeft = deck.midX > screen.midX
        let growsDown = deck.midY > screen.midY

        var origin = CGPoint(
            x: growsLeft ? deck.maxX - size.width : deck.minX,
            y: growsDown ? deck.maxY - size.height : deck.minY
        )
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Dragging the deck
    //
    // Measured in screen coordinates from the mouse itself. A SwiftUI drag reports
    // its translation in the window's own space, and the window is the thing being
    // moved, so it would chase its own tail.

    private func deckDragChanged() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }

        let dx = mouse.x - start.mouse.x
        let dy = mouse.y - start.mouse.y
        if !dragging && hypot(dx, dy) < 3 { return }

        dragging = true
        panel.setFrameOrigin(CGPoint(x: start.origin.x + dx, y: start.origin.y + dy))
    }

    private func deckDragEnded() {
        if dragging, let panel {
            UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        } else {
            // A press that never moved is a click.
            expand()
        }
        dragStart = nil
        dragging = false
    }

    // MARK: - Panel

    private func makePanel(store: NoteStore) -> StackPanel {
        let panel = StackPanel(
            contentRect: deckFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.onDismiss = { [weak self] in self?.collapse() }

        let view = StackView(
            store: store,
            model: model,
            onPullOut: { [weak self] id in self?.pullOut(id) },
            onShowAll: { [weak self] in self?.showAll() },
            onClose: { [weak self] in self?.collapse() },
            onDeckDrag: { [weak self] in self?.deckDragChanged() },
            onDeckDragEnd: { [weak self] in self?.deckDragEnded() }
        )
        let hosting = FirstMouseHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(deckFrame(), display: false)

        log.info("stack deck placed at \(Int(panel.frame.minX)),\(Int(panel.frame.minY))")
        return panel
    }
}

/// The stack's window. It can take the keyboard so the search field works, and
/// it folds itself back into the deck the moment you look elsewhere.
final class StackPanel: NSPanel, NSWindowDelegate {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        delegate = self
    }

    /// Clicking a note, another app or the desktop all take key status away.
    func windowDidResignKey(_ notification: Notification) {
        onDismiss?()
    }

    /// Escape.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

/// A hosting view that answers the first click, so the deck responds even while
/// another app is in front.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
