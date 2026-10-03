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

        /// Moving the caret changes which line shows its inline syntax, so styling
        /// is recomputed on selection as well as on edit.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NoteEditor else { return }
            restyle(view)
        }

        /// Keeps the caret out of hidden block syntax. Landing inside a hidden "- "
        /// would mean typing into characters nobody can see, so the caret is moved
        /// to where the text starts — or, when arrowing left out of that spot, on
        /// to the end of the line above.
        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange old: NSRange,
            toCharacterRange new: NSRange
        ) -> NSRange {
            guard new.length == 0, let view = textView as? NoteEditor else { return new }
            let lines = MarkdownScanner.lines(in: view.string as NSString)
            guard let line = MarkdownScanner.line(at: new.location, in: lines),
                  line.hiddenEnd > line.range.location,
                  new.location < line.hiddenEnd
            else { return new }

            // ⌘← heads for the start of the line on purpose; only a step left leaves it.
            let jumping = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            let leaving = old.length == 0 && old.location == line.hiddenEnd && new.location < old.location && !jumping
            if leaving && line.range.location > 0 {
                return NSRange(location: line.range.location - 1, length: 0)
            }
            return NSRange(location: line.hiddenEnd, length: 0)
        }

        func restyle(_ view: NoteEditor) {
            guard let storage = view.textStorage else { return }
            // No caret means no revealed line: clicking away from a note settles
            // every line back into its rendered form.
            let focused = view.window?.firstResponder === view
            let ink = NSColor(view.paper.ink)
            view.layout = MarkdownStyler.apply(
                to: storage,
                paper: view.paper,
                caret: focused ? view.selectedRange().location : -1
            )
            view.insertionPointColor = ink
            // Typing after a hidden marker must not inherit its invisible font.
            view.typingAttributes = MarkdownStyler.baseAttributes(ink: ink)
            view.linkTextAttributes = [
                .foregroundColor: ink,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: ink.withAlphaComponent(0.4),
                .cursor: NSCursor.pointingHand,
            ]
            view.needsDisplay = true
        }
    }
}

/// Draws what the styler hid, and does the list editing a plain text view does not.
///
/// TextKit will not swap one character's glyph for another, so a `-` cannot simply
/// become a bullet. Instead the raw marker is hidden, the line is indented to leave
/// a gap, and the bullet, checkbox, quote bar or rule is painted into that gap here.
final class NoteEditor: NSTextView {
    var paper: NotePaper = .butter
    var layout = MarkdownStyler.Layout()
    var onFocusChange: (() -> Void)?
    var menuItems: () -> [NSMenuItem] = { [] }

    /// Where each checkbox was last drawn, so a click on one can tick it.
    private var checkboxes: [(rect: NSRect, flag: NSRange)] = []

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

    // MARK: - Checkboxes

    /// A click on a checkbox ticks it without moving the caret there.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let box = checkboxes.first(where: { $0.rect.insetBy(dx: -4, dy: -3).contains(point) }) {
            let current = (string as NSString).substring(with: box.flag).lowercased()
            replace(box.flag, with: current == "x" ? " " : "x")
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for box in checkboxes {
            addCursorRect(box.rect.insetBy(dx: -4, dy: -3), cursor: .pointingHand)
        }
    }

    // MARK: - List editing

    private var lines: [MarkdownLine] { MarkdownScanner.lines(in: string as NSString) }

    private var currentLine: MarkdownLine? {
        MarkdownScanner.line(at: selectedRange().location, in: lines)
    }

    /// Return continues a list with the next bullet, checkbox or number. Return on
    /// an empty item ends the list instead — or steps out one level if nested.
    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard let line = currentLine,
              line.isListItem || line.kind == .quote,
              selection.location >= line.contentStart
        else {
            super.insertNewline(sender)
            return
        }

        let content = (string as NSString).substring(with: line.content)
        if content.trimmingCharacters(in: .whitespaces).isEmpty && selection.length == 0 {
            if line.depth > 0 {
                outdent(line)
            } else {
                replace(line.markerRange, with: "", caret: line.range.location)
            }
            return
        }

        insertText("\n" + line.continuation(in: string as NSString), replacementRange: selection)
    }

    /// Tab nests a list item one level deeper.
    override func insertTab(_ sender: Any?) {
        guard let line = currentLine, line.isListItem else {
            super.insertTab(sender)
            return
        }
        let caret = selectedRange()
        replace(NSRange(location: line.range.location, length: 0), with: "\t",
                caret: caret.location + 1, length: caret.length)
    }

    /// Shift-Tab brings it back out.
    override func insertBacktab(_ sender: Any?) {
        guard let line = currentLine, line.isListItem, line.depth > 0 else {
            super.insertBacktab(sender)
            return
        }
        outdent(line)
    }

    /// Backspace at the very start of a list item, quote or heading removes the
    /// formatting first — stepping out a level if nested — rather than reaching
    /// back across hidden syntax into the line above.
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0,
              let line = currentLine,
              line.hasMarker,
              selection.location == line.contentStart,
              line.kind != .fence, line.kind != .code
        else {
            super.deleteBackward(sender)
            return
        }

        if line.isListItem && line.depth > 0 {
            outdent(line)
        } else {
            let marker = NSRange(location: line.indentRange.upperBound, length: line.contentStart - line.indentRange.upperBound)
            replace(marker, with: "", caret: marker.location)
        }
    }

    private func outdent(_ line: MarkdownLine) {
        let indent = (string as NSString).substring(with: line.indentRange)
        // One tab, or two spaces, is one level.
        let remove = indent.hasPrefix("\t") ? 1 : min(2, indent.count)
        let caret = selectedRange()
        replace(NSRange(location: line.range.location, length: remove), with: "",
                caret: max(line.range.location, caret.location - remove), length: caret.length)
    }

    // MARK: - Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()

        switch (flags, key) {
        case ([.command], "b"):
            wrap(with: "**")
        case ([.command], "i"):
            wrap(with: "*")
        case ([.command, .shift], "x"):
            wrap(with: "~~")
        case ([.command], "k"):
            link()
        case ([.command], "\r"):
            toggleTask()
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Wraps the selection in a marker, or unwraps it if it is already wrapped.
    /// With nothing selected, leaves the caret between a fresh pair.
    private func wrap(with marker: String) {
        let ns = string as NSString
        let selection = selectedRange()
        let length = (marker as NSString).length

        let before = NSRange(location: selection.location - length, length: length)
        let after = NSRange(location: selection.upperBound, length: length)
        if before.location >= 0, after.upperBound <= ns.length,
           ns.substring(with: before) == marker, ns.substring(with: after) == marker {
            let whole = NSRange(location: before.location, length: after.upperBound - before.location)
            replace(whole, with: ns.substring(with: selection), caret: before.location, length: selection.length)
            return
        }

        let inner = ns.substring(with: selection)
        replace(selection, with: marker + inner + marker,
                caret: selection.location + length, length: selection.length)
    }

    /// Makes the selection the text of a link, with the caret ready for the address.
    private func link() {
        let selection = selectedRange()
        let inner = (string as NSString).substring(with: selection)
        let text = "[\(inner)]()"
        replace(selection, with: text, caret: selection.location + (text as NSString).length - 1)
    }

    /// ⌘↩: a line becomes a checkbox; a checkbox is ticked or unticked.
    private func toggleTask() {
        guard let line = currentLine else { return }
        switch line.kind {
        case .task:
            if let flag = line.flagRange {
                let current = (string as NSString).substring(with: flag).lowercased()
                replace(flag, with: current == "x" ? " " : "x")
            }
        case .bullet:
            let insert = NSRange(location: line.contentStart, length: 0)
            replace(insert, with: "[ ] ", caret: selectedRange().location + 4)
        case .plain, .ordered:
            let start = NSRange(location: line.indentRange.upperBound, length: line.contentStart - line.indentRange.upperBound)
            let delta = 6 - start.length
            replace(start, with: "- [ ] ", caret: selectedRange().location + delta)
        default:
            break
        }
    }

    /// An undoable edit that goes through the normal change notifications, so the
    /// note saves and restyles exactly as if it had been typed.
    private func replace(_ range: NSRange, with text: String, caret: Int? = nil, length: Int = 0) {
        guard range.upperBound <= (string as NSString).length,
              shouldChangeText(in: range, replacementString: text)
        else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        if let caret {
            setSelectedRange(NSRange(location: max(0, caret), length: length))
        }
    }

    // MARK: - Drawing

    /// Shaded panels behind code blocks go under the text.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let manager = layoutManager, let container = textContainer else { return }

        for block in layout.codeBlocks {
            let glyphs = manager.glyphRange(forCharacterRange: block, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            var bounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
            bounds.origin.x = textContainerOrigin.x + container.lineFragmentPadding - 6
            bounds.size.width = container.size.width - container.lineFragmentPadding * 2 + 12
            bounds.origin.y += textContainerOrigin.y - 3
            bounds.size.height += 6

            NSColor(paper.ink).withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let manager = layoutManager, let container = textContainer else { return }

        let origin = textContainerOrigin
        let ink = NSColor(paper.ink)
        var boxes: [(rect: NSRect, flag: NSRange)] = []

        for line in layout.drawn {
            let glyphRange = manager.glyphRange(forCharacterRange: line.range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }

            // The *fragment* rect, not the glyph bounding rect. A bounding rect
            // starts where the text starts — which, on an indented list line, is
            // exactly where the marker must not go. The fragment spans the full
            // container, so its left edge is the gutter the indent opened up.
            var fragment = manager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            fragment.origin.x += origin.x + container.lineFragmentPadding
            fragment.origin.y += origin.y
            // Line spacing sits below the text; leave it out when centring a marker.
            let text = NSRect(x: fragment.minX, y: fragment.minY, width: fragment.width, height: fragment.height - 1.5)
            let nest = CGFloat(line.depth) * MarkdownScanner.markerIndent

            switch line.kind {
            case .bullet:
                drawBullet(in: text, x: text.minX + nest, depth: line.depth, ink: ink)
            case .task(let done):
                let box = drawCheckbox(in: text, x: text.minX + nest, done: done, ink: ink)
                if let flag = line.flagRange { boxes.append((box, flag)) }
            case .quote:
                var whole = manager.boundingRect(forGlyphRange: glyphRange, in: container)
                whole.origin.y += origin.y
                let bar = NSRect(x: fragment.minX + 2, y: whole.minY + 1, width: 2.5, height: whole.height - 2)
                ink.withAlphaComponent(0.28).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.25, yRadius: 1.25).fill()
            case .rule:
                let y = (fragment.midY).rounded() + 0.5
                let path = NSBezierPath()
                path.move(to: NSPoint(x: fragment.minX, y: y))
                path.line(to: NSPoint(x: fragment.minX + container.size.width - container.lineFragmentPadding * 2, y: y))
                path.lineWidth = 1
                ink.withAlphaComponent(0.22).setStroke()
                path.stroke()
            default:
                break
            }
        }

        if boxes.map(\.rect) != checkboxes.map(\.rect) {
            checkboxes = boxes
            window?.invalidateCursorRects(for: self)
        } else {
            checkboxes = boxes
        }
    }

    /// Filled dot, then hollow ring, then small square, as lists nest.
    private func drawBullet(in line: NSRect, x: CGFloat, depth: Int, ink: NSColor) {
        let size: CGFloat = depth % 3 == 2 ? 4 : 4.5
        let mark = NSRect(x: x + 5, y: line.minY + (line.height - size) / 2, width: size, height: size)

        switch depth % 3 {
        case 0:
            ink.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: mark).fill()
        case 1:
            let ring = NSBezierPath(ovalIn: mark.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1
            ink.withAlphaComponent(0.55).setStroke()
            ring.stroke()
        default:
            ink.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: mark).fill()
        }
    }

    @discardableResult
    private func drawCheckbox(in line: NSRect, x: CGFloat, done: Bool, ink: NSColor) -> NSRect {
        let side: CGFloat = 11
        let box = NSRect(x: x + 0.5, y: line.minY + (line.height - side) / 2, width: side, height: side)
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
        return box
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
