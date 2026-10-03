import AppKit
import SwiftUI

/// The note's text, as one continuous editor.
///
/// An earlier version gave every line its own text field, which is why Return lost
/// focus and typing felt haunted: each Return destroyed the view holding the cursor
/// and hoped the next one would pick it up. One NSTextView instead means Return,
/// arrows, selection across lines, undo and paste are all AppKit's problem, and they
/// simply work.
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    let paper: NotePaper
    var menuItems: () -> [NSMenuItem] = { [] }

    func makeNSView(context: Context) -> NSScrollView {
        let view = NoteEditor()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        // The gutter lives here rather than in SwiftUI padding, so the click target
        // still covers the whole sheet.
        view.textContainerInset = NSSize(width: MarkdownStyler.gutter, height: 10)
        view.paper = paper
        view.menuItems = menuItems
        view.string = text
        view.onFocusChange = { [weak view] in
            guard let view else { return }
            context.coordinator.restyle(view)
        }

        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true

        context.coordinator.restyle(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NoteEditor else { return }
        context.coordinator.parent = self
        view.paper = paper
        view.menuItems = menuItems

        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            ))
        }
        context.coordinator.restyle(view)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView

        init(_ parent: NoteTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NoteEditor else { return }
            parent.text = view.string
            restyle(view)
        }

        /// Moving the caret changes which line shows its syntax, so styling is
        /// recomputed on selection as well as on edit.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NoteEditor else { return }
            restyle(view)
        }

        func restyle(_ view: NoteEditor) {
            guard let storage = view.textStorage else { return }
            // No caret means no revealed line: clicking away from a note settles
            // every line back into its rendered form.
            let focused = view.window?.firstResponder === view
            view.layout = MarkdownStyler.apply(
                to: storage,
                paper: view.paper,
                caret: focused ? view.selectedRange().location : -1
            )
            view.insertionPointColor = NSColor(view.paper.ink)
            view.typingAttributes[.foregroundColor] = NSColor(view.paper.ink)
            view.needsDisplay = true
        }
    }
}

/// Draws the list markers that the styler hid.
///
/// TextKit will not swap one character's glyph for another, so a `-` cannot simply
/// become a bullet. Instead the raw marker is hidden, the line is indented to leave
/// a gap, and the bullet or checkbox is painted into that gap here.
final class NoteEditor: NSTextView {
    var paper: NotePaper = .butter
    var layout = MarkdownStyler.Layout()
    var onFocusChange: (() -> Void)?
    var menuItems: () -> [NSMenuItem] = { [] }

    /// The note's own items go first, above AppKit's usual text menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let items = menuItems()
        guard !items.isEmpty else { return menu }

        menu.insertItem(.separator(), at: 0)
        for item in items.reversed() {
            menu.insertItem(item, at: 0)
        }
        return menu
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        onFocusChange?()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        onFocusChange?()
        return resigned
    }

    /// Without this, the first click on an unfocused note only wakes the window and
    /// the caret needs a second click — which felt broken, because it was.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let manager = layoutManager else { return }

        let origin = textContainerOrigin
        let ink = NSColor(paper.ink)

        for line in layout.drawn {
            let glyphRange = manager.glyphRange(forCharacterRange: line.range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }

            // The *fragment* rect, not the glyph bounding rect. A bounding rect
            // starts where the text starts — which, on an indented list line, is
            // exactly where the marker must not go. The fragment spans the full
            // container, so its left edge is the gutter the indent opened up.
            var fragment = manager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            fragment.origin.x += origin.x
            fragment.origin.y += origin.y

            switch line.kind {
            case .bullet:
                drawBullet(in: fragment, ink: ink)
            case .task(let done):
                drawCheckbox(in: fragment, done: done, ink: ink)
            default:
                break
            }
        }
    }

    private func drawBullet(in fragment: NSRect, ink: NSColor) {
        let size: CGFloat = 4.5
        let dot = NSRect(
            x: fragment.minX + 6,
            y: fragment.minY + (fragment.height - size) / 2,
            width: size,
            height: size
        )
        ink.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    private func drawCheckbox(in fragment: NSRect, done: Bool, ink: NSColor) {
        let side: CGFloat = 11
        let box = NSRect(
            x: fragment.minX + 1.5,
            y: fragment.minY + (fragment.height - side) / 2,
            width: side,
            height: side
        )
        let path = NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5)
        path.lineWidth = 1.2

        if done {
            ink.withAlphaComponent(0.5).setFill()
            path.fill()

            // NSTextView is flipped, so minY is the *top* of the box. The tick has
            // to fall to the bottom before rising to the top right; doing it the
            // other way round drew it upside down.
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 2.4, y: box.midY + 0.1))
            tick.line(to: NSPoint(x: box.midX - 0.5, y: box.maxY - 2.7))
            tick.line(to: NSPoint(x: box.maxX - 2.1, y: box.minY + 2.7))
            tick.lineWidth = 1.5
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.withAlphaComponent(0.95).setStroke()
            tick.stroke()
        } else {
            ink.withAlphaComponent(0.45).setStroke()
            path.stroke()
        }
    }
}

/// A menu item that runs a closure, so SwiftUI views can build AppKit menus
/// without a target object of their own. AppKit declares menu items outside the
/// main actor, so this one is too, and hops back onto it to run the closure.
nonisolated final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func fire() {
        let handler = self.handler
        MainActor.assumeIsolated { handler() }
    }
}
