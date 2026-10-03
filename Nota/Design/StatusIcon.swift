import SwiftUI

/// The menu bar glyph: a sheet with a turned-up corner.
///
/// SF Symbols has nothing that reads as "sticky note" — `note.text` is a page of
/// ruled lines, which is a document, not a post-it. This is drawn instead, and
/// rendered as a template image so macOS tints it for the menu bar like any other
/// system icon.
enum StatusIcon {

    static func image(notesVisible: Bool) -> NSImage {
        let side: CGFloat = 16

        let content = ZStack {
            if notesVisible {
                StickyShape().fill(.black)
                FoldShape().fill(.black.opacity(0.35))
            } else {
                StickyShape().stroke(.black, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                FoldShape().stroke(.black, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            }
        }
        .frame(width: side, height: side)
        .padding(0.8)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return NSImage(systemSymbolName: "note.text", accessibilityDescription: "Nota") ?? NSImage()
        }
        image.isTemplate = true
        return image
    }
}

/// A square sheet with the bottom-right corner cut away.
private struct StickyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let fold = rect.width * 0.36
        let radius = rect.width * 0.14

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// The turned-up corner that fills the cut.
private struct FoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let fold = rect.width * 0.36

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY - fold))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
