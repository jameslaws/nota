import AppKit
import SwiftUI

/// A single sheet of paper.
///
/// Three rules came out of the first pass:
///
/// 1. Nothing moves on hover. The control strip is always the same height and the
///    buttons fade in, so the note never wiggles under the cursor.
/// 2. Translucent at rest, solid when you are working on it. A wall of opaque
///    rectangles buries the desktop; a wall of translucent ones is unreadable. So
///    it is quiet until you reach for it.
/// 3. Barely rounded. It is a piece of paper, not a card — and a big radius on a
///    transparent window is what made the corners look cut out.
struct NoteView: View {
    @State var note: Note
    var onChange: (Note) -> Void
    var onDelete: () -> Void
    var onNew: () -> Void
    var onResize: (CGSize) -> Void
    var onResizeEnd: () -> Void
    var onSpacesChange: (NoteSpaces) -> Void
    var onKeptChange: (Bool) -> Void
    var onPutAway: () -> Void

    @State private var isHovering = false
    @State private var confirmingDelete = false

    /// Controls show on hover only.
    private var raised: Bool { isHovering }
    /// The paper goes solid on hover, and stays solid on a kept note — that is the
    /// one you are working from, so it should never be hard to read.
    private var solid: Bool { isHovering || note.kept }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            body(for: note)
        }
        .background(paper)
        .overlay(alignment: .bottomTrailing) { grip }
        .clipShape(RoundedRectangle(cornerRadius: Sheet.radius, style: .continuous))
        // Drawn here rather than by the window. macOS builds a window shadow from
        // the alpha channel, and with 55% paper that shadow shows *through* the
        // sheet as a dark rim — which is the "black border" that would not go away.
        .shadow(color: .black.opacity(0.28), radius: 7, x: 0, y: 3)
        .padding(Sheet.shadowMargin)
        .onHover { hovering in
            isHovering = hovering
            if !hovering { confirmingDelete = false }
        }
        .animation(.easeOut(duration: 0.16), value: isHovering)
    }

    enum Sheet {
        /// Paper, not a card. Just enough to take the hard edge off.
        static let radius: CGFloat = 4
        static let controlHeight: CGFloat = 18
        /// One inset for every edge, so the gutters read as even.
        static let gutter: CGFloat = 16
        /// Transparent room inside the window for the shadow to fall into.
        static let shadowMargin: CGFloat = 14
    }

    // MARK: - Paper

    private var paper: some View {
        // Plain alpha over a transparent window, deliberately not a blur. A
        // visual-effect material tinted with colour comes out frosted and *pale* —
        // which is what the last version did, and pale is not the same as
        // see-through. Dropping the blur means the desktop is genuinely visible
        // through the sheet.
        LinearGradient(
            colors: [note.colour.top, note.colour.bottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(solid ? 0.94 : 0.55)
    }

    /// The window's own resize edge sits out in the transparent shadow margin where
    /// it is neither visible nor reachable, so the sheet carries its own corner.
    private var grip: some View {
        ResizeGrip(ink: note.colour.ink, visible: raised, onDrag: onResize, onEnd: onResizeEnd)
    }

    // MARK: - Controls
    //
    // Fixed height whether or not they are showing, so the text below never shifts.

    private var controls: some View {
        HStack(spacing: 5) {
            colours
                .opacity(raised ? 1 : 0)

            Spacer(minLength: 0)

            restingMarks

            if confirmingDelete {
                Text("Delete?")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(note.colour.ink.opacity(0.75))
            }

            // Open eye: hides with the rest. Filled eye: kept on screen. Pinning to a
            // desktop lives in the right-click menu; it is rarely what you reach for.
            button(
                note.kept ? "eye.fill" : "eye",
                help: note.kept ? "Kept on screen — click to let it hide with the others" : "Keep on screen when the other notes hide"
            ) {
                toggleKept()
            }

            button("plus", help: "New note", action: onNew)
            button(confirmingDelete ? "trash.fill" : "trash", help: "Delete note") {
                if confirmingDelete { onDelete() } else { confirmingDelete = true }
            }
        }
        .frame(height: Sheet.controlHeight)
        .padding(.horizontal, Sheet.gutter - 4)
        .padding(.top, 6)
        // The strip is the drag handle: the sheet below it belongs to the editor.
        .contentShape(Rectangle())
    }

    private var colours: some View {
        HStack(spacing: 4) {
            ForEach(NotePaper.allCases) { option in
                Circle()
                    .fill(option.swatch)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().strokeBorder(
                            note.colour == option ? note.colour.ink.opacity(0.75) : .black.opacity(0.10),
                            lineWidth: note.colour == option ? 1.3 : 0.5
                        )
                    )
                    .contentShape(Circle())
                    .onTapGesture {
                        note.colour = option
                        onChange(note)
                    }
            }
        }
    }

    /// Faint marks that stay with the controls hidden, so a kept note or one that
    /// lives on a single desktop says so without being hovered.
    private var restingMarks: some View {
        HStack(spacing: 4) {
            if note.spaces == .desktop {
                Image(systemName: "pin.fill")
            }
            if note.kept {
                Image(systemName: "eye.fill")
            }
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(note.colour.ink.opacity(0.3))
        .opacity(raised ? 0 : 1)
    }

    // MARK: - State

    private func toggleKept() {
        note.kept.toggle()
        onKeptChange(note.kept)
    }

    private func toggleSpaces() {
        let next: NoteSpaces = note.spaces == .all ? .desktop : .all
        note.spaces = next
        onSpacesChange(next)
    }

    private func putAway() {
        // Mirrors what the window does, so this sheet's copy stays truthful.
        note.kept = false
        onPutAway()
    }

    /// Nota's own items, placed above the usual text menu on a right-click.
    private func menuItems() -> [NSMenuItem] {
        let keep = ClosureMenuItem(title: "Keep on Screen") { toggleKept() }
        keep.state = note.kept ? .on : .off

        let pin = ClosureMenuItem(title: "Pin to This Desktop") { toggleSpaces() }
        pin.state = note.spaces == .desktop ? .on : .off

        // A pinned note holds its place on its desktop rather than joining the stack.
        let away = ClosureMenuItem(title: note.spaces == .desktop ? "Hide Note" : "Put in Stack") { putAway() }

        return [keep, pin, away]
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(note.colour.ink.opacity(0.55))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .opacity(raised ? 1 : 0)
    }

    // MARK: - Text

    private func body(for note: Note) -> some View {
        // No SwiftUI padding here: the text view owns its own inset, so the click
        // target still covers the full width of the sheet.
        NoteTextView(
            text: Binding(
                get: { self.note.text },
                set: { updated in
                    self.note.text = updated
                    // Live, as typed. There is no save button anywhere in Nota.
                    onChange(self.note)
                }
            ),
            paper: note.colour,
            menuItems: menuItems
        )
        .padding(.bottom, 6)
    }
}
