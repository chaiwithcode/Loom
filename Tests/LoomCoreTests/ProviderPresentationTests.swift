//
//  ProviderPresentationTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
import AppKit
@testable import LoomCore

final class ProviderPresentationTests: XCTestCase {
    func testCodexPresentation() {
        let presentation = ProviderPresentation.presentation(for: .codex)
        XCTAssertEqual(presentation.id, .codex)
        XCTAssertEqual(presentation.displayName, "Codex")
        XCTAssertEqual(presentation.iconAssetName, "provider-codex")
        XCTAssertEqual(presentation.iconRenderingMode, .original)
    }

    func testClaudePresentation() {
        let presentation = ProviderPresentation.presentation(for: .claude)
        XCTAssertEqual(presentation.id, .claude)
        XCTAssertEqual(presentation.displayName, "Claude Code")
        XCTAssertEqual(presentation.iconAssetName, "provider-claude")
        XCTAssertEqual(presentation.iconRenderingMode, .original)
    }

    func testAntigravityPresentation() {
        let presentation = ProviderPresentation.presentation(for: .antigravity)
        XCTAssertEqual(presentation.id, .antigravity)
        XCTAssertEqual(presentation.displayName, "Antigravity")
        XCTAssertEqual(presentation.iconAssetName, "provider-antigravity")
        XCTAssertEqual(presentation.iconRenderingMode, .original)
    }

    func testUnknownProviderFallback() {
        let customID = ProviderID("custom_ai")
        let presentation = ProviderPresentation.presentation(for: customID)
        XCTAssertEqual(presentation.id, customID)
        XCTAssertEqual(presentation.displayName, "Custom_Ai")
        XCTAssertNil(presentation.iconAssetName)
        XCTAssertEqual(presentation.iconRenderingMode, .template)
    }

    func testProviderIDNormalizationAndAliases() {
        // Casing and whitespace
        XCTAssertEqual(ProviderPresentation.presentation(for: ProviderID(" Codex ")).id, .codex)
        XCTAssertEqual(ProviderPresentation.presentation(for: ProviderID("CLAUDE")).id, .claude)
        XCTAssertEqual(ProviderPresentation.presentation(for: ProviderID("AntiGravity")).id, .antigravity)

        // Aliases
        XCTAssertEqual(ProviderPresentation.presentation(for: ProviderID("claude-code")).id, .claude)
        XCTAssertEqual(ProviderPresentation.presentation(for: ProviderID("claudecode")).id, .claude)
        XCTAssertEqual(ProviderPresentation.presentation(for: ProviderID("gemini-antigravity")).id, .antigravity)
        XCTAssertEqual(ProviderPresentation.presentation(for: ProviderID("agy")).id, .antigravity)
    }

    func testKnownProviderAssetsCanBeResolvedAndDecoded() {
        let knownProviders: [ProviderID] = [.codex, .claude, .antigravity]

        for providerID in knownProviders {
            let presentation = ProviderPresentation.presentation(for: providerID)
            guard let assetName = presentation.iconAssetName else {
                XCTFail("Known provider \(providerID.rawValue) must specify an iconAssetName")
                continue
            }

            // 1. Actually resolve resource URL using application bundle search strategy
            let resolvedURL = ProviderIconImage.resolveResourceURL(named: assetName)
            XCTAssertNotNil(resolvedURL, "Resource URL for '\(assetName)' must be resolvable from app bundles, frameworks, or repository Resources/")

            if let url = resolvedURL {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Resource file must exist at path: \(url.path)")
            }

            // 2. Actually load and decode the NSImage
            let isTemplate = presentation.iconRenderingMode == .template
            let image = ProviderIconImage.image(named: assetName, template: isTemplate)
            XCTAssertNotNil(image, "Decoded image for '\(assetName)' must not be nil")

            guard let img = image else { continue }

            // 3. Verify image validity and non-zero dimensions
            XCTAssertTrue(img.isValid, "Image for '\(assetName)' must be valid")
            XCTAssertGreaterThan(img.size.width, 0, "Image width for '\(assetName)' must be positive")
            XCTAssertGreaterThan(img.size.height, 0, "Image height for '\(assetName)' must be positive")

            // 4. Verify template flag matches presentation mode
            if isTemplate {
                XCTAssertTrue(img.isTemplate, "Template image for '\(assetName)' must have isTemplate set to true")
            } else {
                XCTAssertFalse(img.isTemplate, "Brand artwork must preserve its original colours")
            }

            // 5. Provider-specific assertions
            switch providerID {
            case .codex:
                XCTAssertEqual(presentation.iconRenderingMode, .original)
                XCTAssertEqual(img.size.width, 104.0)
                XCTAssertEqual(img.size.height, 104.0)
            case .claude:
                XCTAssertEqual(presentation.iconRenderingMode, .original)
                XCTAssertEqual(resolvedURL?.pathExtension, "pdf")
                XCTAssertEqual(img.size.width, 128.0)
                XCTAssertEqual(img.size.height, 128.0)
            case .antigravity:
                XCTAssertEqual(presentation.iconRenderingMode, .original)
                XCTAssertEqual(resolvedURL?.pathExtension, "png")
                XCTAssertGreaterThanOrEqual(img.representations.first?.pixelsWide ?? 0, 256)
            default:
                break
            }
        }
    }

    func testMissingAssetLookupReturnsNilSafely() {
        let missing = ProviderIconImage.image(named: "non_existent_provider_icon_404")
        XCTAssertNil(missing, "Lookup for missing asset must return nil without crashing")
    }
    func testAntigravityIconActuallyDrawsVisiblePixels() throws {
        let image = try XCTUnwrap(ProviderIconImage.image(named: "provider-antigravity"))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let visiblePixels = (0..<32).reduce(0) { total, y in
            total + (0..<32).filter { x in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
            }.count
        }
        XCTAssertGreaterThan(visiblePixels, 100, "A decodable logo must also render visibly with AppKit")
    }

}
