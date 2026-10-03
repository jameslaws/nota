import SwiftUI

/// Bottom-right corner grab. Three short strokes, shown only on hover, in the same
/// language as the rest of the controls.
struct ResizeGrip: View {
    var ink: Color
    var visible: Bool
    var onDrag: (CGSize) -> Void
    var onEnd: () -> Void

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for offset in stride(from: 3.0, through: 11.0, by: 4.0) {
                path.move(to: CGPoint(x: size.width - offset, y: size.height - 2))
                path.addLine(to: CGPoint(x: size.width - 2, y: size.height - offset))
            }
            context.stroke(path, with: .color(ink.opacity(0.35)), lineWidth: 1.2)
        }
        .frame(width: 16, height: 16)
        .opacity(visible ? 1 : 0)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { onDrag($0.translation) }
                .onEnded { _ in onEnd() }
        )
        .onHover { hovering in
            if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
        }
    }
}
