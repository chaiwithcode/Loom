#!/usr/bin/env swift
//
//  generate-background.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import AppKit
import CoreGraphics
import Foundation

// Geometry definition matching approved specifications
struct DMGGeometry {
    static let width: CGFloat = 640
    static let height: CGFloat = 420

    static let appIconCenter = CGPoint(x: 180, y: 235)
    static let appDropCenter = CGPoint(x: 460, y: 235)
    static let iconSize: CGFloat = 96

    // Midpoint between icons
    static let midX: CGFloat = 320
}

func createBackgroundRepresentation(scale: CGFloat) -> NSBitmapImageRep {
    let pixelWidth = Int(DMGGeometry.width * scale)
    let pixelHeight = Int(DMGGeometry.height * scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        fatalError("Failed to create NSBitmapImageRep for scale \(scale)")
    }

    rep.size = NSSize(width: DMGGeometry.width, height: DMGGeometry.height)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create NSGraphicsContext for rep")
    }
    NSGraphicsContext.current = context

    let cgContext = context.cgContext

    // Fill background with warm light-neutral color (#F6F5F2)
    let backgroundColor = NSColor(srgbRed: 0.965, green: 0.961, blue: 0.949, alpha: 1.0)
    backgroundColor.setFill()
    NSRect(x: 0, y: 0, width: DMGGeometry.width, height: DMGGeometry.height).fill()

    // Helper for AppKit coordinates (AppKit origin is bottom-left; Finder origin is top-left)
    func appKitY(_ finderY: CGFloat) -> CGFloat {
        return DMGGeometry.height - finderY
    }

    // 1. Title: "Loom"
    let titleText = "Loom"
    let titleFont = NSFont.systemFont(ofSize: 26, weight: .bold)
    let titleColor = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1.0) // #1F1F21
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: titleColor
    ]
    let titleSize = (titleText as NSString).size(withAttributes: titleAttrs)
    let titleFinderY: CGFloat = 62
    let titleRect = NSRect(
        x: DMGGeometry.midX - (titleSize.width / 2.0),
        y: appKitY(titleFinderY) - (titleSize.height / 2.0),
        width: titleSize.width,
        height: titleSize.height
    )
    (titleText as NSString).draw(in: titleRect, withAttributes: titleAttrs)

    // 2. Tagline: "Monitor your local AI coding agents"
    let taglineText = "Monitor your local AI coding agents"
    let taglineFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    let taglineColor = NSColor(srgbRed: 0.42, green: 0.42, blue: 0.44, alpha: 1.0) // #6B6B70
    let taglineAttrs: [NSAttributedString.Key: Any] = [
        .font: taglineFont,
        .foregroundColor: taglineColor
    ]
    let taglineSize = (taglineText as NSString).size(withAttributes: taglineAttrs)
    let taglineFinderY: CGFloat = 92
    let taglineRect = NSRect(
        x: DMGGeometry.midX - (taglineSize.width / 2.0),
        y: appKitY(taglineFinderY) - (taglineSize.height / 2.0),
        width: taglineSize.width,
        height: taglineSize.height
    )
    (taglineText as NSString).draw(in: taglineRect, withAttributes: taglineAttrs)

    // 3. Subtle directional arrow between icons
    // Centered at DMGGeometry.midX (320), y = 235 (matching icon vertical center)
    let arrowColor = NSColor(srgbRed: 0.68, green: 0.68, blue: 0.70, alpha: 0.85) // Subtle neutral
    let arrowFinderY: CGFloat = 235
    let arrowY = appKitY(arrowFinderY)
    let arrowStartX: CGFloat = 292
    let arrowEndX: CGFloat = 348
    let arrowTipX = arrowEndX
    let arrowFinLength: CGFloat = 8
    let arrowFinAngle: CGFloat = 4.5

    cgContext.saveGState()
    cgContext.setStrokeColor(arrowColor.cgColor)
    cgContext.setFillColor(arrowColor.cgColor)
    cgContext.setLineWidth(2.0)
    cgContext.setLineCap(.round)
    cgContext.setLineJoin(.round)

    // Arrow shaft
    cgContext.beginPath()
    cgContext.move(to: CGPoint(x: arrowStartX, y: arrowY))
    cgContext.addLine(to: CGPoint(x: arrowEndX, y: arrowY))
    cgContext.strokePath()

    // Arrow head (clean chevron)
    cgContext.beginPath()
    cgContext.move(to: CGPoint(x: arrowTipX - arrowFinLength, y: arrowY + arrowFinAngle))
    cgContext.addLine(to: CGPoint(x: arrowTipX, y: arrowY))
    cgContext.addLine(to: CGPoint(x: arrowTipX - arrowFinLength, y: arrowY - arrowFinAngle))
    cgContext.strokePath()
    cgContext.restoreGState()

    // 4. Action guidance text: "Drag Loom to Applications"
    // Positioned below the arrow, well within negative space between icons
    let guideText = "Drag Loom to Applications"
    let guideFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    let guideColor = NSColor(srgbRed: 0.48, green: 0.48, blue: 0.50, alpha: 0.9)
    let guideAttrs: [NSAttributedString.Key: Any] = [
        .font: guideFont,
        .foregroundColor: guideColor
    ]
    let guideSize = (guideText as NSString).size(withAttributes: guideAttrs)
    let guideFinderY: CGFloat = 340
    let guideRect = NSRect(
        x: DMGGeometry.midX - (guideSize.width / 2.0),
        y: appKitY(guideFinderY) - (guideSize.height / 2.0),
        width: guideSize.width,
        height: guideSize.height
    )
    (guideText as NSString).draw(in: guideRect, withAttributes: guideAttrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func main() {
    let outputDir: String
    if CommandLine.arguments.count > 1 {
        outputDir = CommandLine.arguments[1]
    } else {
        let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
        outputDir = scriptDir.isEmpty ? "." : scriptDir
    }

    let rep1x = createBackgroundRepresentation(scale: 1.0)
    let rep2x = createBackgroundRepresentation(scale: 2.0)

    // 1. Export background.png (1x)
    guard let pngData1x = rep1x.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode 1x PNG")
    }
    let url1x = URL(fileURLWithPath: "\(outputDir)/background.png")
    try! pngData1x.write(to: url1x)
    print("Wrote \(url1x.path) (\(rep1x.pixelsWide)x\(rep1x.pixelsHigh))")

    // 2. Export background@2x.png (2x)
    guard let pngData2x = rep2x.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode 2x PNG")
    }
    let url2x = URL(fileURLWithPath: "\(outputDir)/background@2x.png")
    try! pngData2x.write(to: url2x)
    print("Wrote \(url2x.path) (\(rep2x.pixelsWide)x\(rep2x.pixelsHigh))")

    // 3. Export multi-representation TIFF (1x + 2x representations)
    let multiImage = NSImage(size: NSSize(width: DMGGeometry.width, height: DMGGeometry.height))
    multiImage.addRepresentation(rep1x)
    multiImage.addRepresentation(rep2x)

    guard let tiffData = multiImage.tiffRepresentation(using: .none, factor: 0) else {
        fatalError("Failed to create multi-representation TIFF")
    }
    let urlTiff = URL(fileURLWithPath: "\(outputDir)/background.tiff")
    try! tiffData.write(to: urlTiff)
    print("Wrote \(urlTiff.path) (Multi-representation TIFF)")
}

main()
