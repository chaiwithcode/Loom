import SwiftUI
import AppKit

public enum LoomIcon {
    /// Creates a native monochrome template NSImage suitable for the macOS menu bar (18x18 pt).
    public static var menuBarImage: NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: rect, context: context, strokeColor: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws the Loom vector glyph in the provided rect using Core Graphics.
    public static func draw(in rect: CGRect, context: CGContext, strokeColor: CGColor) {
        context.saveGState()

        // Map 24x24 coordinate space into target rect preserving aspect ratio
        let scale = min(rect.width, rect.height) / 24.0
        let offsetX = rect.origin.x + (rect.width - 24.0 * scale) / 2.0
        let offsetY = rect.origin.y + (rect.height - 24.0 * scale) / 2.0

        context.translateBy(x: offsetX, y: offsetY)
        context.scaleBy(x: scale, y: scale)

        context.setStrokeColor(strokeColor)
        context.setLineWidth(1.8)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // 3 Agent Nodes (Codex, Claude, Antigravity)
        let r1 = CGRect(x: 2.5, y: 3.5, width: 4.0, height: 4.0)
        let r2 = CGRect(x: 2.5, y: 10.0, width: 4.0, height: 4.0)
        let r3 = CGRect(x: 2.5, y: 16.5, width: 4.0, height: 4.0)

        for r in [r1, r2, r3] {
            let path = CGPath(roundedRect: r, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil)
            context.addPath(path)
            context.strokePath()
        }

        // Connecting lines between left nodes
        context.move(to: CGPoint(x: 4.5, y: 7.5))
        context.addLine(to: CGPoint(x: 4.5, y: 10.0))
        context.move(to: CGPoint(x: 4.5, y: 14.0))
        context.addLine(to: CGPoint(x: 4.5, y: 16.5))
        context.strokePath()

        // Central Gathering Wheel
        let wheelCenter = CGPoint(x: 16.0, y: 12.0)
        context.addArc(center: wheelCenter, radius: 5.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        context.addArc(center: wheelCenter, radius: 2.0, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        // Converging Threads from agent nodes to gathering wheel
        context.move(to: CGPoint(x: 6.5, y: 5.5))
        context.addLine(to: CGPoint(x: 11.5, y: 8.5))

        context.move(to: CGPoint(x: 6.5, y: 12.0))
        context.addLine(to: CGPoint(x: 10.5, y: 12.0))

        context.move(to: CGPoint(x: 6.5, y: 18.5))
        context.addLine(to: CGPoint(x: 11.5, y: 15.5))
        context.strokePath()

        context.restoreGState()
    }
}

public struct LoomIconView: View {
    public var size: CGFloat = 18

    public init(size: CGFloat = 18) {
        self.size = size
    }

    public var body: some View {
        Image(nsImage: LoomIcon.menuBarImage)
            .renderingMode(.template)
            .frame(width: size, height: size)
    }
}
