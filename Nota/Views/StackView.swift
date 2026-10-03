import AppKit
import SwiftUI

/// The stack: a little deck of put-away notes, or — clicked — the list of them.
struct StackView: View {
    let store: NoteStore
    @Bindable var model: StackModel
    var onPullOut: (UUID) -> Void
    var onShowAll: () -> Void
    var onClose: () -> Void
    var onDeckDrag: () -> Void
    var onDeckDragEnd: () -> Void

    var body: some View {
        Group {
            if model.expanded {
                StackList(
                    notes: store.stacked,
                    query: $model.query,
                    onPullOut: onPullOut,
                    onShowAll: onShowAll,
                    onClose: onClose
                )
                .frame(width: NoteStack.fanSize.width, height: NoteStack.fanSize.height)
            } else {
                StackDeck(notes: store.stacked)
                    .frame(width: NoteStack.deckSize.width, height: NoteStack.deckSize.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in onDeckDrag() }
                            .onEnded { _ in onDeckDragEnd() }
                    )
            }
        }
        .padding(NoteStack.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Deck

/// Up to three sheets, slightly askew, showing the colours of the most recent
/// notes put away, with the count on top.
private struct StackDeck: View {
    let notes: [Note]
    @State private var isHovering = false

    private static let tilts: [Double] = [0, -7, 5]
    private static let offsets: [CGSize] = [.zero, CGSize(width: -4, height: 3), CGSize(width: 4, height: 5)]

    private var sheets: [NotePaper] { notes.prefix(3).map(\.colour) }

    var body: some View {
        ZStack {
            // Drawn back to front so the most recent note sits on top.
            ForEach(Array(sheets.enumerated()).reversed(), id: \.offset) { index, paper in
                Sheet(paper: paper)
                    .frame(width: 54, height: 48)
                    .rotationEffect(.degrees(Self.tilts[index] * (isHovering ? 1.4 : 1)))
                    .offset(Self.offsets[index])
            }

            if let top = sheets.first {
                Text("\(notes.count)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(top.ink.opacity(0.7))
                    .monospacedDigit()
            }
        }
        .opacity(isHovering ? 1 : 0.85)
        .scaleEffect(isHovering ? 1.05 : 1)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
        .help(notes.count == 1
              ? "1 note put away — click to find it, drag to move the stack"
              : "\(notes.count) notes put away — click to look through them, drag to move the stack")
    }

    private struct Sheet: View {
        let paper: NotePaper

        var body: some View {
            LinearGradient(colors: [paper.top, paper.bottom], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1.5)
        }
    }
}

// MARK: - List

/// The fanned-out stack: find a note, click it, and it comes back to where it was.
private struct StackList: View {
    let notes: [Note]
    @Binding var query: String
    var onPullOut: (UUID) -> Void
    var onShowAll: () -> Void
    var onClose: () -> Void

    @FocusState private var searching: Bool

    private var matches: [Note] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return notes }
        return notes.filter { $0.text.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            search
            list
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
        .onAppear { searching = true }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Stack")
                .font(.system(size: 13, weight: .semibold))
            Text("\(notes.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button("Show All", action: onShowAll)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .help("Bring every note back out")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Find a note", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searching)
                // Return brings back the top match. On the Mac a text field also
                // "submits" when it loses focus — which happens every time the stack
                // folds away — so only a real Return keypress counts.
                .onSubmit {
                    guard let event = NSApp.currentEvent,
                          event.type == .keyDown,
                          event.keyCode == 36 || event.keyCode == 76,
                          let first = matches.first
                    else { return }
                    onPullOut(first.id)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(0.06))
        )
    }

    @ViewBuilder
    private var list: some View {
        if matches.isEmpty {
            Text(notes.isEmpty ? "Nothing put away." : "No note mentions “\(query)”.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(matches) { note in
                        StackCard(note: note) { onPullOut(note.id) }
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.never)
        }
    }
}

/// One note in the list, on its own colour of paper.
private struct StackCard: View {
    let note: Note
    var onPick: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.summary)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.system(size: 11.5))
                    .foregroundStyle(note.colour.ink.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(note.colour.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            LinearGradient(colors: [note.colour.top, note.colour.bottom], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(isHovering ? 0.22 : 0.10), radius: isHovering ? 4 : 1.5, x: 0, y: 1)
        .offset(y: isHovering ? -1 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onPick)
        .help("Bring this note back")
    }
}
