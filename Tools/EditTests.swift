import AppKit
import SwiftUI

@main
struct EditTests {
    static var failures = 0

    static func make(_ text: String, caret: Int) -> (NoteEditor, NoteTextView.Coordinator) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let view = NoteEditor(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        view.isRichText = false
        view.allowsUndo = true
        let coordinator = NoteTextView.Coordinator(NoteTextView(text: .constant(""), paper: .butter))
        view.delegate = coordinator
        window.contentView = view
        view.string = text
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: caret, length: 0))
        return (view, coordinator)
    }

    static func check(_ name: String, _ got: String, _ want: String, caret: Int? = nil, view: NoteEditor? = nil) {
        var ok = got == want
        if let caret, let view, view.selectedRange().location != caret { ok = false }
        if !ok { failures += 1 }
        print(ok ? "PASS" : "FAIL", name, ok ? "" : "got \(got.debugDescription) caret \(view?.selectedRange().location ?? -1)")
    }

    static func end(_ s: String) -> Int { (s as NSString).length }

    static func main() {
        _ = NSApplication.shared

        var s = "- one"
        var (v, _) = make(s, caret: end(s)); v.insertNewline(nil)
        check("return continues bullet", v.string, "- one\n- ", caret: 8, view: v)

        s = "- one\n- "
        (v, _) = make(s, caret: end(s)); v.insertNewline(nil)
        check("return on empty bullet ends list", v.string, "- one\n", caret: 6, view: v)

        s = "- one\n\t- "
        (v, _) = make(s, caret: end(s)); v.insertNewline(nil)
        check("return on empty nested bullet outdents", v.string, "- one\n- ", view: v)

        s = "- [x] done"
        (v, _) = make(s, caret: end(s)); v.insertNewline(nil)
        check("return after task makes unticked task", v.string, "- [x] done\n- [ ] ")

        s = "9. nine"
        (v, _) = make(s, caret: end(s)); v.insertNewline(nil)
        check("return numbers the next item", v.string, "9. nine\n10. ")

        s = "\t* star"
        (v, _) = make(s, caret: end(s)); v.insertNewline(nil)
        check("return keeps nesting and symbol", v.string, "\t* star\n\t* ")

        s = "> said"
        (v, _) = make(s, caret: end(s)); v.insertNewline(nil)
        check("return continues quote", v.string, "> said\n> ")

        s = "plain"
        (v, _) = make(s, caret: end(s)); v.insertNewline(nil)
        check("return on plain line is plain", v.string, "plain\n")

        s = "- one\n- two"
        (v, _) = make(s, caret: end(s)); v.insertTab(nil)
        check("tab nests item, caret stays with text", v.string, "- one\n\t- two", caret: end(s) + 1, view: v)

        s = "- one\n\t- two"
        (v, _) = make(s, caret: end(s)); v.insertBacktab(nil)
        check("shift-tab outdents", v.string, "- one\n- two", caret: end(s) - 1, view: v)

        s = "- two"
        (v, _) = make(s, caret: 2); v.deleteBackward(nil)
        check("backspace at item start removes bullet", v.string, "two", caret: 0, view: v)

        s = "## Head"
        (v, _) = make(s, caret: 3); v.deleteBackward(nil)
        check("backspace at heading start removes heading", v.string, "Head")

        s = "- a\n\t- b"
        (v, _) = make(s, caret: 7); v.deleteBackward(nil)
        check("backspace at nested item start outdents", v.string, "- a\n- b")

        s = "- word"
        (v, _) = make(s, caret: 4); v.deleteBackward(nil)
        check("ordinary backspace still works", v.string, "- wrd")

        s = "- a\n- b"
        (v, _) = make(s, caret: 4)
        check("caret clicked into hidden marker snaps to text", v.string, s, caret: 6, view: v)

        s = "- [ ] task"
        (v, _) = make(s, caret: end(s)); _ = v.performKeyEquivalent(with: key("\r"))
        check("cmd-return ticks task", v.string, "- [x] task")

        s = "buy milk"
        (v, _) = make(s, caret: end(s)); _ = v.performKeyEquivalent(with: key("\r"))
        check("cmd-return makes a task", v.string, "- [ ] buy milk", caret: 14, view: v)

        s = "make bold"
        (v, _) = make(s, caret: 0); v.setSelectedRange(NSRange(location: 5, length: 4)); _ = v.performKeyEquivalent(with: key("b"))
        check("cmd-b wraps selection", v.string, "make **bold**")
        _ = v.performKeyEquivalent(with: key("b"))
        check("cmd-b again unwraps", v.string, "make bold")

        s = "- one"
        (v, _) = make(s, caret: end(s)); v.insertNewline(nil); v.undoManager?.undo()
        check("undo reverses list continuation", v.string, "- one")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func key(_ chars: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    }
}
