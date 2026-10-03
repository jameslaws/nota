import AppKit
import SwiftUI

@main
struct RenderPreview {
    static func main() {
        let args = CommandLine.arguments
        let text = try! String(contentsOfFile: args[1], encoding: .utf8)
        let out = args[2]
        let caret = args.count > 3 ? Int(args[3])! : -1
        let dark = args.count > 4 && args[4] == "dark"
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let paper = NotePaper.butter
        let size = NSSize(width: 320, height: 620)
        let view = NoteEditor(frame: NSRect(origin: .zero, size: size))
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: MarkdownStyler.gutter, height: 10)
        view.textContainer?.widthTracksTextView = true
        view.paper = paper
        view.string = text
        let ink = NSColor(paper.ink)
        view.linkTextAttributes = [.foregroundColor: ink, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: ink.withAlphaComponent(0.4)]
        view.layout = MarkdownStyler.apply(to: view.textStorage!, paper: paper, caret: caret)

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        container.addSubview(view)
        view.appearance = container.appearance
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            container.layer?.backgroundColor = NSColor(paper.top).cgColor
        }
        view.layoutManager?.ensureLayout(for: view.textContainer!)

        let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            container.cacheDisplay(in: container.bounds, to: rep)
        }
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    }
}
