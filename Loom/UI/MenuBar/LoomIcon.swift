//
//  LoomIcon.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit

public enum LoomIcon {
    /// Three incoming strands and a woven base, optically simplified for the menu bar.
    public static var menuBarImage: NSImage { templateImage(size: 18) }

    public static func templateImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: rect, context: context, strokeColor: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Matches docs/loom-icon.svg. The underpass is transparent, so the glyph
    /// follows the system's template tint on either menu-bar appearance.
    public static func draw(in rect: CGRect, context: CGContext, strokeColor: CGColor) {
        context.saveGState()
        defer { context.restoreGState() }
        let scale = min(rect.width, rect.height) / 24
        context.translateBy(x: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
        context.scaleBy(x: scale, y: scale)
        context.setStrokeColor(strokeColor)
        context.setLineWidth(3.4)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let middle = CGMutablePath()
        middle.move(to: CGPoint(x: 12, y: 2.8))
        middle.addLine(to: CGPoint(x: 12, y: 10.5))

        let right = CGMutablePath()
        right.move(to: CGPoint(x: 17, y: 4.2))
        right.addLine(to: CGPoint(x: 17, y: 8))
        right.addCurve(to: CGPoint(x: 13.4, y: 11.9), control1: CGPoint(x: 17, y: 9.8), control2: CGPoint(x: 15.3, y: 10.6))
        right.addCurve(to: CGPoint(x: 6.9, y: 19.8), control1: CGPoint(x: 10.2, y: 14), control2: CGPoint(x: 7.1, y: 16.2))

        let left = CGMutablePath()
        left.move(to: CGPoint(x: 7, y: 4.2))
        left.addLine(to: CGPoint(x: 7, y: 8))
        left.addCurve(to: CGPoint(x: 10.6, y: 11.9), control1: CGPoint(x: 7, y: 9.8), control2: CGPoint(x: 8.7, y: 10.6))
        left.addCurve(to: CGPoint(x: 17.1, y: 19.8), control1: CGPoint(x: 13.8, y: 14), control2: CGPoint(x: 16.9, y: 16.2))

        // Cut a real transparent underpass instead of painting a background colour.
        let crossing = CGMutablePath()
        crossing.move(to: CGPoint(x: 9, y: 10.7))
        crossing.addCurve(to: CGPoint(x: 14.7, y: 15.1), control1: CGPoint(x: 10.7, y: 12), control2: CGPoint(x: 13, y: 13.5))
        let underpass = CGMutablePath()
        underpass.addRect(CGRect(x: 0, y: 0, width: 24, height: 24))
        underpass.addPath(crossing.copy(strokingWithWidth: 5.3, lineCap: .round, lineJoin: .round, miterLimit: 10))
        context.saveGState()
        context.addPath(underpass)
        context.clip(using: .evenOdd)
        context.addPath(middle)
        context.addPath(right)
        context.strokePath()
        context.restoreGState()
        context.addPath(left)
        context.strokePath()

        // A material front band gives the circular base the Dock mark's weight.
        // Its raised inner oval leaves more mass below than above, preserving
        // perspective without shading or a background-colour cutout.
        let base = CGMutablePath()
        base.addEllipse(in: CGRect(x: 2, y: 12.9, width: 20, height: 9.1))
        base.addEllipse(in: CGRect(x: 4, y: 14.1, width: 16, height: 5))
        context.setFillColor(strokeColor)
        context.addPath(base)
        context.drawPath(using: .eoFill)

    }
}

public struct LoomIconView: View {
    public var size: CGFloat = 18

    public init(size: CGFloat = 18) { self.size = size }

    public var body: some View {
        Image(nsImage: LoomIcon.templateImage(size: size))
            .renderingMode(.template)
            .frame(width: size, height: size)
    }
}

extension View {
    @ViewBuilder
    func loomToolbarButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderless)
        }
        #else
        self.buttonStyle(.borderless)
        #endif
    }
}

struct LoomPanelMaterial: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else if #available(macOS 26.0, *) {
            // The MenuBarExtra window owns the panel backdrop on Tahoe.
            Color.clear
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}
