//
//  capture-docs-assets.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import AppKit
import SwiftUI
import CoreGraphics
import LoomCore
import Loom

@main
struct AssetCapturer {
    @MainActor
    static func settle(_ host: NSView, cycles: Int = 30) async {
        for _ in 0..<cycles {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }

    @MainActor
    static func saveView(_ host: NSView, to url: URL, isDark: Bool = true) {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            fatalError("Failed to create bitmapImageRepForCachingDisplay for \(url.lastPathComponent)")
        }
        host.cacheDisplay(in: host.bounds, to: rep)

        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(rep)

        let composited = NSImage(size: host.bounds.size)
        composited.lockFocus()
        let bgColor = isDark
            ? NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
            : NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
        bgColor.setFill()
        NSRect(origin: .zero, size: host.bounds.size).fill()
        image.draw(in: NSRect(origin: .zero, size: host.bounds.size))
        composited.unlockFocus()

        guard let tiff = composited.tiffRepresentation,
              let finalRep = NSBitmapImageRep(data: tiff),
              let png = finalRep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to generate PNG data for \(url.lastPathComponent)")
        }
        try! png.write(to: url)
        print(" Saved: \(url.path) (\(finalRep.pixelsWide)x\(finalRep.pixelsHigh))")
    }

    @MainActor
    static func findSegmentedControl(in view: NSView) -> NSSegmentedControl? {
        if let seg = view as? NSSegmentedControl {
            return seg
        }
        for sub in view.subviews {
            if let found = findSegmentedControl(in: sub) {
                return found
            }
        }
        return nil
    }

    @MainActor
    static func clickTab(_ window: NSWindow, segment: Int) {
        guard let contentView = window.contentView else { return }
        if let seg = findSegmentedControl(in: contentView) {
            seg.selectedSegment = segment
            if let action = seg.action {
                NSApp.sendAction(action, to: seg.target, from: seg)
            }
        }
    }

    @MainActor
    static func renderMenuBar(
        store: SessionStore,
        settings: LoomSettings,
        isDark: Bool,
        isUsageExpanded: Bool = false,
        selectedProviderID: ProviderID? = .codex,
        expandedSessionIds: Set<String> = ["loom-main"]
    ) -> (host: NSHostingView<AnyView>, window: NSWindow) {
        let appearanceName: NSAppearance.Name = isDark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        let colorScheme: ColorScheme = isDark ? .dark : .light
        let menuWidth: CGFloat = 420

        let root = MenuBarRootView(
            store: store,
            settings: settings,
            isUsageExpanded: isUsageExpanded,
            expandedSessionIds: expandedSessionIds,
            selectedProviderID: selectedProviderID
        )
        .frame(width: menuWidth)
        .preferredColorScheme(colorScheme)

        let host = NSHostingView(rootView: AnyView(root))
        host.appearance = appearance

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: menuWidth, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        window.orderFront(nil)

        return (host, window)
    }

    @MainActor
    static func renderSettings(
        store: SessionStore,
        settings: LoomSettings,
        isDark: Bool
    ) async -> (host: NSView, window: NSWindow) {
        let appearanceName: NSAppearance.Name = isDark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        let colorScheme: ColorScheme = isDark ? .dark : .light
        let width: CGFloat = 540
        let height: CGFloat = 480

        let root = SettingsView(
            settings: settings,
            store: store,
            initialTab: .general
        )
        .frame(width: width, height: height)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(colorScheme)

        let host = NSHostingView(rootView: AnyView(root))
        host.appearance = appearance
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.title = "Loom Settings"
        window.contentView = host
        window.orderFront(nil)

        await settle(host, cycles: 40)
        return (host, window)
    }

    @MainActor
    static func main() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.applicationIconImage = NSImage(contentsOfFile: "Resources/LoomIconMaster.png")

        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let docsDir = repoRoot.appendingPathComponent("docs")
        let visualDir = URL(fileURLWithPath: "/private/tmp/loom-visual")
        try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: visualDir, withIntermediateDirectories: true)

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 10
        components.minute = 0
        components.second = 0
        let now = calendar.date(from: components) ?? Date()

        let demoLoomPath = URL(fileURLWithPath: "/Users/Shared/Projects/Loom")
        try? FileManager.default.createDirectory(at: demoLoomPath, withIntermediateDirectories: true)

        // 1. Create realistic, sanitized fixtures for Codex, Claude Code, and Antigravity
        let codexSessions = [
            AgentSession(
                id: "loom-main",
                provider: .codex,
                projectName: "Loom",
                projectPath: demoLoomPath,
                state: .working,
                startedAt: now.addingTimeInterval(-1800),
                lastActivityAt: now.addingTimeInterval(-60),
                branch: "main",
                summary: "Polishing documentation and release assets",
                pid: 4812,
                hostApp: .vsCode,
                discoveryEvidence: ["pid:4812", "cwd:/Users/Shared/Projects/Loom"]
            ),
            AgentSession(
                id: "core-engine",
                provider: .codex,
                projectName: "CoreEngine",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/CoreEngine"),
                state: .starting,
                startedAt: now.addingTimeInterval(-180),
                lastActivityAt: now.addingTimeInterval(-30),
                branch: "main",
                summary: "Initializing session",
                pid: 4890,
                hostApp: .terminal
            ),
            AgentSession(
                id: "web-pipeline",
                provider: .codex,
                projectName: "WebPipeline",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/WebPipeline"),
                state: .idle,
                startedAt: now.addingTimeInterval(-7200),
                lastActivityAt: now.addingTimeInterval(-3600),
                branch: "feature/sync",
                summary: "Completed sync pass",
                pid: 3201
            )
        ]

        let codexUsage = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: now,
            planType: "Plus",
            primaryBucket: UsageBucket(
                identifier: "codex-5h",
                label: "5-hour window",
                usedFraction: 0.28,
                resetsAt: now.addingTimeInterval(8220),
                windowDurationMins: 300
            ),
            secondaryBucket: UsageBucket(
                identifier: "codex-weekly",
                label: "Weekly window",
                usedFraction: 0.36,
                resetsAt: now.addingTimeInterval(367200),
                windowDurationMins: 10080
            ),
            additionalGroups: [
                UsageGroup(
                    identifier: "codex-models",
                    label: "Other models",
                    buckets: [
                        UsageBucket(
                            identifier: "gpt-4o",
                            label: "GPT-4o",
                            usedFraction: 0.35,
                            resetsAt: now.addingTimeInterval(14400),
                            windowDurationMins: 300
                        )
                    ]
                )
            ]
        )

        let codexProvider = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: codexSessions,
            usage: codexUsage
        )

        let claudeSessions = [
            AgentSession(
                id: "smart-remote",
                provider: .claude,
                projectName: "SmartRemote",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/SmartRemote"),
                state: .waiting,
                startedAt: now.addingTimeInterval(-2100),
                lastActivityAt: now.addingTimeInterval(-120),
                branch: "fix/pairing",
                summary: "Waiting for confirmation: npm test",
                pid: 5120,
                hostApp: .terminal
            ),
            AgentSession(
                id: "parser-kit",
                provider: .claude,
                projectName: "ParserKit",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/ParserKit"),
                state: .failed,
                startedAt: now.addingTimeInterval(-3600),
                lastActivityAt: now.addingTimeInterval(-720),
                branch: "v0-kickoff",
                summary: "Build failed: undefined symbol in parser",
                pid: 5180
            )
        ]

        let claudeProvider = MockAgentProvider(
            id: .claude,
            displayName: "Claude Code",
            availability: .available,
            sessions: claudeSessions,
            usage: nil
        )

        let antigravitySessions = [
            AgentSession(
                id: "experiment",
                provider: .antigravity,
                projectName: "Experiment",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Experiment"),
                state: .finished,
                startedAt: now.addingTimeInterval(-3000),
                lastActivityAt: now.addingTimeInterval(-300),
                branch: "prototype-v2",
                summary: "Completed test suite optimization",
                pid: 6100,
                hostApp: .vsCode
            )
        ]

        let antigravityUsage = ProviderUsageSnapshot(
            providerID: .antigravity,
            updatedAt: now,
            planType: nil,
            primaryBucket: UsageBucket(
                identifier: "gemini-5h",
                label: "Gemini 5h",
                usedFraction: 0.15,
                resetsAt: now.addingTimeInterval(8820),
                windowDurationMins: 300
            ),
            secondaryBucket: UsageBucket(
                identifier: "gemini-weekly",
                label: "Gemini Weekly",
                usedFraction: 0.13,
                resetsAt: now.addingTimeInterval(518400),
                windowDurationMins: 10080
            ),
            additionalGroups: [
                UsageGroup(
                    identifier: "claude-and-gpt",
                    label: "Claude & GPT",
                    buckets: [
                        UsageBucket(
                            identifier: "3p-5h",
                            label: "3P 5h",
                            usedFraction: 0.0,
                            resetsAt: now.addingTimeInterval(14400),
                            windowDurationMins: 300
                        )
                    ]
                )
            ]
        )

        let antigravityProvider = MockAgentProvider(
            id: .antigravity,
            displayName: "Antigravity",
            availability: .available,
            sessions: antigravitySessions,
            usage: antigravityUsage
        )

        let store = SessionStore(providers: [codexProvider, claudeProvider, antigravityProvider])
        await store.refresh()
        await store.refreshStorage(force: true)

        let settings = LoomSettings()

        // 2. Render Menu Bar and Settings Views across Dark and Light modes
        print("==> Capturing Visual QA previews for Dark and Light modes...")
        for isDark in [true, false] {
            let mode = isDark ? "dark" : "light"
            let appearanceName: NSAppearance.Name = isDark ? .darkAqua : .aqua
            NSApp.appearance = NSAppearance(named: appearanceName)

            // A. Sessions Tab (Default: Codex selected)
            do {
                let (host, window) = renderMenuBar(
                    store: store,
                    settings: settings,
                    isDark: isDark,
                    isUsageExpanded: false,
                    selectedProviderID: .codex,
                    expandedSessionIds: ["loom-main"]
                )
                await settle(host, cycles: 30)
                saveView(host, to: visualDir.appendingPathComponent("sessions-\(mode).png"), isDark: isDark)
                saveView(host, to: visualDir.appendingPathComponent("sessions-codex-\(mode).png"), isDark: isDark)
                if isDark {
                    saveView(host, to: docsDir.appendingPathComponent("menu-navigation-sessions.png"), isDark: isDark)
                }
                window.close()
            }

            // B. Sessions Tab (Claude Code selected)
            do {
                let (host, window) = renderMenuBar(
                    store: store,
                    settings: settings,
                    isDark: isDark,
                    isUsageExpanded: false,
                    selectedProviderID: .claude,
                    expandedSessionIds: ["smart-remote"]
                )
                await settle(host, cycles: 30)
                saveView(host, to: visualDir.appendingPathComponent("sessions-claude-\(mode).png"), isDark: isDark)
                window.close()
            }

            // C. Sessions Tab (Antigravity selected)
            do {
                let (host, window) = renderMenuBar(
                    store: store,
                    settings: settings,
                    isDark: isDark,
                    isUsageExpanded: false,
                    selectedProviderID: .antigravity,
                    expandedSessionIds: ["experiment"]
                )
                await settle(host, cycles: 30)
                saveView(host, to: visualDir.appendingPathComponent("sessions-antigravity-\(mode).png"), isDark: isDark)
                window.close()
            }

            // D. Usage Tab
            do {
                let (host, window) = renderMenuBar(
                    store: store,
                    settings: settings,
                    isDark: isDark,
                    isUsageExpanded: true,
                    selectedProviderID: .codex
                )
                await settle(host, cycles: 30)
                saveView(host, to: visualDir.appendingPathComponent("usage-\(mode).png"), isDark: isDark)
                if isDark {
                    saveView(host, to: docsDir.appendingPathComponent("menu-navigation-usage.png"), isDark: isDark)
                }
                window.close()
            }

            // E. Storage Tab
            do {
                let (host, window) = renderMenuBar(
                    store: store,
                    settings: settings,
                    isDark: isDark,
                    isUsageExpanded: false,
                    selectedProviderID: .codex
                )
                await settle(host, cycles: 20)
                clickTab(window, segment: 2)
                await settle(host, cycles: 30)
                saveView(host, to: visualDir.appendingPathComponent("storage-\(mode).png"), isDark: isDark)
                if isDark {
                    saveView(host, to: docsDir.appendingPathComponent("menu-navigation-storage.png"), isDark: isDark)
                }
                window.close()
            }

            // F. Settings Window
            do {
                let (host, window) = await renderSettings(
                    store: store,
                    settings: settings,
                    isDark: isDark
                )
                await settle(host, cycles: 30)
                saveView(host, to: visualDir.appendingPathComponent("settings-\(mode).png"), isDark: isDark)
                window.close()
            }
        }

        // 3. Render Widgets
        let baseSnapshot = LoomWidgetSnapshot.make(from: store)
        let widgetSnapshot = LoomWidgetSnapshot(
            schemaVersion: baseSnapshot.schemaVersion,
            timestamp: now,
            activeSessionCount: baseSnapshot.activeSessionCount,
            attentionSessionCount: baseSnapshot.attentionSessionCount,
            totalSessionCount: baseSnapshot.totalSessionCount,
            providerSummaries: baseSnapshot.providerSummaries,
            statusMessage: baseSnapshot.statusMessage
        )
        let widgetEntry = LoomWidgetEntry(
            date: now,
            snapshot: widgetSnapshot,
            readResult: .success(widgetSnapshot),
            providerID: "all"
        )

        let smallSize = NSSize(width: 170, height: 170)
        let mediumSize = NSSize(width: 364, height: 170)
        let largeSize = NSSize(width: 364, height: 382)

        // Render Small Quotas Widget (All enabled providers)
        let smallQuotaHost = NSHostingView(
            rootView: LoomQuotaWidgetView(entry: widgetEntry, familyOverride: .systemSmall).padding(14)
        )
        smallQuotaHost.frame = NSRect(origin: .zero, size: smallSize)
        smallQuotaHost.appearance = NSAppearance(named: .darkAqua)
        await settle(smallQuotaHost, cycles: 20)
        let smallQuotaImg = renderImage(view: smallQuotaHost)

        // Render Small Sessions Widget (Multi-provider active sessions)
        let smallSessionsHost = NSHostingView(rootView: LoomSmallWidgetView(entry: widgetEntry).padding(14))
        smallSessionsHost.frame = NSRect(origin: .zero, size: smallSize)
        smallSessionsHost.appearance = NSAppearance(named: .darkAqua)
        await settle(smallSessionsHost, cycles: 20)
        let smallSessionsImg = renderImage(view: smallSessionsHost)

        // Render Medium Quotas Widget (All enabled providers)
        let mediumQuotaHost = NSHostingView(
            rootView: LoomQuotaWidgetView(entry: widgetEntry, familyOverride: .systemMedium).padding(14)
        )
        mediumQuotaHost.frame = NSRect(origin: .zero, size: mediumSize)
        mediumQuotaHost.appearance = NSAppearance(named: .darkAqua)
        await settle(mediumQuotaHost, cycles: 20)
        let mediumQuotaImg = renderImage(view: mediumQuotaHost)

        // Render Large Usage Overview Widget (All enabled providers)
        let largeOverviewHost = NSHostingView(rootView: LoomUsageOverviewLargeView(entry: widgetEntry).padding(14))
        largeOverviewHost.frame = NSRect(origin: .zero, size: largeSize)
        largeOverviewHost.appearance = NSAppearance(named: .darkAqua)
        await settle(largeOverviewHost, cycles: 20)
        let largeOverviewImg = renderImage(view: largeOverviewHost)

        // 4. Compose Widget Showcase
        composeWidgetShowcase(
            medium: mediumQuotaImg,
            smallSessions: smallSessionsImg,
            smallQuotas: smallQuotaImg,
            large: largeOverviewImg,
            outputURL: docsDir.appendingPathComponent("widget-showcase.png")
        )

        // 5. Compose Social Preview (1280x640)
        composeSocialPreview(
            masterIconURL: repoRoot.appendingPathComponent("Resources/LoomIconMaster.png"),
            outputURL: docsDir.appendingPathComponent("social-preview.png")
        )

        print("\nAll Loom documentation & Visual QA assets generated successfully!")
    }

    @MainActor
    static func renderImage(view: NSView) -> NSImage {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fatalError("Failed to get bitmap image rep")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: view.bounds.size)
        img.addRepresentation(rep)
        return img
    }

    static func composeWidgetShowcase(
        medium: NSImage,
        smallSessions: NSImage,
        smallQuotas: NSImage,
        large: NSImage,
        outputURL: URL
    ) {
        let scale: CGFloat = 2.0
        let ptWidth: CGFloat = 860
        let ptHeight: CGFloat = 478
        let pxWidth = Int(ptWidth * scale)
        let pxHeight = Int(ptHeight * scale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pxWidth,
                height: pxHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            fatalError("Failed to create CGContext")
        }

        context.scaleBy(x: scale, y: scale)

        // Draw background gradient (dark desktop theme)
        let gradientColors = [
            NSColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1.0).cgColor,
            NSColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1.0).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: ptHeight),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }

        let cornerRadius: CGFloat = 22.0
        func drawWidget(_ img: NSImage, at rect: CGRect) {
            context.saveGState()

            // Shadow
            context.setShadow(
                offset: CGSize(width: 0, height: -6),
                blur: 16,
                color: NSColor.black.withAlphaComponent(0.40).cgColor
            )

            // Rounded rect path
            let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            context.addPath(path)
            context.setFillColor(NSColor(white: 0.12, alpha: 1.0).cgColor)
            context.fillPath()

            context.restoreGState()

            // Clip and draw image
            context.saveGState()
            context.addPath(path)
            context.clip()

            if let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.draw(cgImg, in: rect)
            }
            context.restoreGState()

            // Subtle border
            context.saveGState()
            context.addPath(path)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
            context.setLineWidth(1.0)
            context.strokePath()
            context.restoreGState()
        }

        let leftX: CGFloat = 48
        let rightX: CGFloat = leftX + 364 + 36
        let topY: CGFloat = ptHeight - 48

        // Left Top: Medium (364 x 170)
        let mediumRect = CGRect(x: leftX, y: topY - 170, width: 364, height: 170)
        drawWidget(medium, at: mediumRect)

        // Left Bottom: Small Quotas & Small Sessions (each 170 x 170, gap 24)
        let bottomY = mediumRect.minY - 24 - 170
        let smallQuotasRect = CGRect(x: leftX, y: bottomY, width: 170, height: 170)
        drawWidget(smallQuotas, at: smallQuotasRect)

        let smallSessionsRect = CGRect(x: leftX + 170 + 24, y: bottomY, width: 170, height: 170)
        drawWidget(smallSessions, at: smallSessionsRect)

        // Right Column: Large (364 x 382, matching top alignment)
        let largeRect = CGRect(x: rightX, y: topY - 382, width: 364, height: 382)
        drawWidget(large, at: largeRect)

        guard let cgFinal = context.makeImage() else { fatalError("makeImage failed") }
        let rep = NSBitmapImageRep(cgImage: cgFinal)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { fatalError("png failed") }
        try! pngData.write(to: outputURL)
        print(" Saved: \(outputURL.path) (\(pxWidth)x\(pxHeight))")
    }

    static func composeSocialPreview(masterIconURL: URL, outputURL: URL) {
        let width = 1280
        let height = 640
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            fatalError("Failed to create context for social preview")
        }

        // Dark gradient background
        let gradientColors = [
            NSColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0).cgColor,
            NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: height),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }

        // Subtle decorative background circles / ambient glow
        context.saveGState()
        let glowCenter = CGPoint(x: 640, y: 350)
        let glowRadius: CGFloat = 340
        let glowColors = [
            NSColor(red: 0.35, green: 0.45, blue: 0.85, alpha: 0.12).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let radial = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
            context.drawRadialGradient(
                radial,
                startCenter: glowCenter,
                startRadius: 0,
                endCenter: glowCenter,
                endRadius: glowRadius,
                options: []
            )
        }
        context.restoreGState()

        // Draw App Icon
        if let iconImg = NSImage(contentsOf: masterIconURL),
           let cgIcon = iconImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let iconSize: CGFloat = 164
            let iconRect = CGRect(x: (CGFloat(width) - iconSize) / 2.0, y: 370, width: iconSize, height: iconSize)

            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -10),
                blur: 32,
                color: NSColor.black.withAlphaComponent(0.65).cgColor
            )
            context.draw(cgIcon, in: iconRect)
            context.restoreGState()
        }

        // Draw Typography using CoreText / AppKit
        let fontTitle = NSFont.systemFont(ofSize: 52, weight: .bold)
        let fontTagline = NSFont.systemFont(ofSize: 26, weight: .semibold)
        let fontSub = NSFont.systemFont(ofSize: 18, weight: .regular)

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        let subStyle = NSMutableParagraphStyle()
        subStyle.alignment = .center

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: fontTitle,
            .foregroundColor: NSColor.white,
            .paragraphStyle: titleStyle
        ]
        let taglineAttrs: [NSAttributedString.Key: Any] = [
            .font: fontTagline,
            .foregroundColor: NSColor(white: 0.94, alpha: 1.0),
            .paragraphStyle: subStyle
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: fontSub,
            .foregroundColor: NSColor(white: 0.65, alpha: 1.0),
            .paragraphStyle: subStyle
        ]

        let titleStr = NSAttributedString(string: "Loom", attributes: titleAttrs)
        let taglineStr = NSAttributedString(string: "Three agents. One Loom.", attributes: taglineAttrs)
        let subStr = NSAttributedString(string: "Local AI agents, one native macOS menu bar.", attributes: subAttrs)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        titleStr.draw(in: CGRect(x: 0, y: 280, width: CGFloat(width), height: 60))
        taglineStr.draw(in: CGRect(x: 0, y: 235, width: CGFloat(width), height: 36))
        subStr.draw(in: CGRect(x: 0, y: 198, width: CGFloat(width), height: 28))

        // Draw Provider Marks along bottom
        let badgeFont = NSFont.systemFont(ofSize: 14, weight: .medium)
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: NSColor(white: 0.60, alpha: 1.0)
        ]

        let providers = [
            ("provider-codex", "Codex"),
            ("provider-claude", "Claude Code"),
            ("provider-antigravity", "Antigravity")
        ]

        var totalBadgeWidth: CGFloat = 0
        let itemWidths: [CGFloat] = providers.map { (iconName, label) in
            let labelWidth = (label as NSString).size(withAttributes: badgeAttrs).width
            return 20 + 8 + labelWidth
        }
        let itemGap: CGFloat = 36
        totalBadgeWidth = itemWidths.reduce(0, +) + CGFloat(providers.count - 1) * itemGap

        var currentX = (CGFloat(width) - totalBadgeWidth) / 2.0
        let badgeY: CGFloat = 100

        for (idx, (iconName, label)) in providers.enumerated() {
            let iconURL = URL(fileURLWithPath: "Resources/\(iconName).png")
            if let iconImg = NSImage(contentsOf: iconURL) {
                let iconRect = CGRect(x: currentX, y: badgeY - 2, width: 20, height: 20)
                if iconName == "provider-codex" {
                    if let cgIcon = iconImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        context.draw(cgIcon, in: iconRect)
                    }
                } else {
                    let tinted = NSImage(size: iconImg.size)
                    tinted.lockFocus()
                    NSColor(white: 0.88, alpha: 1.0).set()
                    NSRect(origin: .zero, size: iconImg.size).fill()
                    iconImg.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1.0)
                    tinted.unlockFocus()
                    if let cgTinted = tinted.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        context.draw(cgTinted, in: iconRect)
                    }
                }
            }
            let labelRect = CGRect(x: currentX + 28, y: badgeY, width: itemWidths[idx] - 28, height: 22)
            NSAttributedString(string: label, attributes: badgeAttrs).draw(in: labelRect)
            currentX += itemWidths[idx] + itemGap
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let finalCG = context.makeImage() else { fatalError("makeImage failed for social preview") }
        let rep = NSBitmapImageRep(cgImage: finalCG)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { fatalError("png failed") }
        try! pngData.write(to: outputURL)
        print(" Saved: \(outputURL.path) (\(width)x\(height))")
    }
}
