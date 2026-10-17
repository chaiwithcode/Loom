//
//  WidgetVisualProbe.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import AppKit
import SwiftUI
import Vision
import Foundation
import LoomCore
import Loom

struct OCRToken {
    let text: String
    let boundingBox: CGRect
}

@MainActor
final class WidgetVisualProbe {
    static let shared = WidgetVisualProbe()

    let outputDir = URL(fileURLWithPath: "/tmp/loom-widget-qa/screenshots")
    var capturedPaths: [String] = []

    init() {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    private var window: NSWindow?

    func closeWindow() {
        window?.close()
        window = nil
    }

    func renderAndCapture<V: View>(
        view: V,
        size: NSSize,
        isDark: Bool,
        filename: String
    ) async -> [OCRToken] {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        let container = ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(isDark ? NSColor.windowBackgroundColor : NSColor.controlBackgroundColor))
            view
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(isDark ? 0.08 : 0.06), lineWidth: 1)
        )

        let hostingView = NSHostingView(rootView: container)
        hostingView.appearance = appearance
        hostingView.frame = NSRect(origin: .zero, size: size)

        let win: NSWindow
        if let existing = self.window {
            win = existing
            win.appearance = appearance
            win.setContentSize(size)
            win.contentView = hostingView
        } else {
            win = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.animationBehavior = .none
            win.appearance = appearance
            win.backgroundColor = .clear
            win.isOpaque = false
            win.contentView = hostingView
            win.center()
            win.orderFront(nil)
            self.window = win
        }

        // Settle layout
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            win.displayIfNeeded()
        }

        // Render bitmap representation
        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return []
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return []
        }

        let fileURL = outputDir.appendingPathComponent(filename)
        try? pngData.write(to: fileURL)
        capturedPaths.append(fileURL.path)

        // Run OCR text analysis
        let tokens = performOCR(on: pngData)
        return tokens
    }

    private func performOCR(on imageData: Data) -> [OCRToken] {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        var results: [OCRToken] = []
        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                results.append(OCRToken(text: candidate.string, boundingBox: obs.boundingBox))
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return results
    }

    // MARK: - Test Snapshot Fixtures

    func makeActiveSnapshot() -> LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 3,
            attentionSessionCount: 0,
            totalSessionCount: 3,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 2,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: "2 active",
                    usage: ProviderUsageWidgetSummary(
                        status: .available,
                        fractionUsed: 0.27,
                        percentRemaining: 73,
                        percentUsed: 27,
                        summary: "73% left",
                        windows: [WidgetQuotaWindow(id: "5h", label: "5 hours", percentRemaining: 73,
                            resetsAt: Date().addingTimeInterval(7200), observedAt: Date())]
                    )
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 1,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: "1 active",
                    usage: ProviderUsageWidgetSummary(
                        status: .unavailable,
                        summary: "Usage unavailable"
                    )
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "unknown",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: nil,
                    usage: ProviderUsageWidgetSummary(
                        status: .unsupported,
                        summary: "Usage unsupported"
                    )
                )
            ],
            statusMessage: "3 active sessions"
        )
    }

    func makeZeroSessionsSnapshot() -> LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 0,
            attentionSessionCount: 0,
            totalSessionCount: 0,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 0,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .available, percentRemaining: 85, summary: "85% left")
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 0,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "Usage unavailable")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unsupported, summary: "Usage unsupported")
                )
            ],
            statusMessage: "No active sessions"
        )
    }

    func makeAttentionSnapshot() -> LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 3,
            attentionSessionCount: 2,
            totalSessionCount: 3,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 2,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .available, percentRemaining: 40, summary: "40% left")
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 1,
                    healthStatus: "degraded",
                    isDegradedOrUnavailable: true,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "Usage unavailable")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "degraded",
                    isDegradedOrUnavailable: true,
                    usage: ProviderUsageWidgetSummary(status: .unsupported, summary: "Usage unsupported")
                )
            ],
            statusMessage: "2 sessions require attention"
        )
    }

    func makeDegradedUnavailableSnapshot() -> LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 1,
            attentionSessionCount: 0,
            totalSessionCount: 1,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 1,
                    healthStatus: "degraded",
                    isDegradedOrUnavailable: true,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "Usage unavailable")
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 0,
                    healthStatus: "unavailable",
                    isDegradedOrUnavailable: true,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "Usage unavailable")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "error",
                    isDegradedOrUnavailable: true,
                    usage: ProviderUsageWidgetSummary(status: .unsupported, summary: "Usage unsupported")
                )
            ],
            statusMessage: "Provider errors detected"
        )
    }

    func makeAllDisabledSnapshot() -> LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 0,
            attentionSessionCount: 0,
            totalSessionCount: 0,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 0,
                    healthStatus: "disabled",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unknown, summary: "Monitoring disabled")
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 0,
                    healthStatus: "disabled",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unknown, summary: "Monitoring disabled")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "disabled",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unknown, summary: "Monitoring disabled")
                )
            ],
            statusMessage: "All monitoring disabled"
        )
    }

    func makeHealthyAndLowQuotaSnapshot() -> LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 2,
            attentionSessionCount: 0,
            totalSessionCount: 2,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 1,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .available, percentRemaining: 5, summary: "5% left")
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 1,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .available, percentRemaining: 100, summary: "100% left")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .available, percentRemaining: 50, summary: "50% left")
                )
            ],
            statusMessage: "2 active sessions"
        )
    }

    func makeStaleSnapshot() -> LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date().addingTimeInterval(-1800), // 30 minutes ago
            activeSessionCount: 2,
            attentionSessionCount: 0,
            totalSessionCount: 2,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 2,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .available, percentRemaining: 73, summary: "73% left",
                        windows: [WidgetQuotaWindow(id: "5h", label: "5 hours", percentRemaining: 73,
                            resetsAt: Date().addingTimeInterval(7200), observedAt: Date())])
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 0,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "Usage unavailable")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "unknown",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unsupported, summary: "Usage unsupported")
                )
            ],
            statusMessage: "Last seen 30m ago"
        )
    }

    func makeLongTextSnapshot() -> LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 12,
            attentionSessionCount: 4,
            totalSessionCount: 12,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "OpenAI Codex CLI Engine Enterprise",
                    sessionCount: 8,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .available, percentRemaining: 92, summary: "92% left (resets in 2h 45m)")
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Anthropic Claude Code Workspace Runner",
                    sessionCount: 4,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "Usage metric unavailable")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Google DeepMind Antigravity Studio",
                    sessionCount: 0,
                    healthStatus: "unknown",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unsupported, summary: "Quota tracking unsupported")
                )
            ],
            statusMessage: "12 active sessions across all providers"
        )
    }

    func makeSingleEnabledProviderSnapshot() -> LoomWidgetSnapshot {
        let obsDate = Date()
        let reset5h = obsDate.addingTimeInterval(7200)
        let resetWeekly = obsDate.addingTimeInterval(432000)

        return LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: obsDate,
            activeSessionCount: 2,
            attentionSessionCount: 0,
            totalSessionCount: 2,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 2,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: "2 active",
                    usage: ProviderUsageWidgetSummary(
                        status: .available,
                        fractionUsed: 0.27,
                        percentRemaining: 73,
                        percentUsed: 27,
                        summary: "73% left",
                        windows: [
                            WidgetQuotaWindow(id: "5h", label: "5 hours", percentRemaining: 73,
                                resetsAt: reset5h, observedAt: obsDate, windowDurationMins: 300),
                            WidgetQuotaWindow(id: "weekly", label: "Weekly", percentRemaining: 40,
                                resetsAt: resetWeekly, observedAt: obsDate, windowDurationMins: 10080)
                        ],
                        groups: [
                            WidgetQuotaGroup(id: "models", label: "Model Limits", windows: [
                                WidgetQuotaWindow(id: "gpt-4o", label: "GPT-4o", percentRemaining: 65,
                                    resetsAt: reset5h, observedAt: obsDate)
                            ])
                        ]
                    )
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 0,
                    healthStatus: "disabled",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "Monitoring disabled")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "disabled",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "Monitoring disabled")
                )
            ],
            statusMessage: "1 provider enabled"
        )
    }

    func makeTwoEnabledProvidersSnapshot() -> LoomWidgetSnapshot {
        let obsDate = Date()
        let reset5h = obsDate.addingTimeInterval(7200)
        let resetWeekly = obsDate.addingTimeInterval(432000)

        return LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: obsDate,
            activeSessionCount: 2,
            attentionSessionCount: 0,
            totalSessionCount: 2,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 2,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: "2 active",
                    usage: ProviderUsageWidgetSummary(
                        status: .available,
                        fractionUsed: 0.27,
                        percentRemaining: 73,
                        percentUsed: 27,
                        summary: "73% left",
                        windows: [
                            WidgetQuotaWindow(id: "5h", label: "5 hours", percentRemaining: 73,
                                resetsAt: reset5h, observedAt: obsDate, windowDurationMins: 300),
                            WidgetQuotaWindow(id: "weekly", label: "Weekly", percentRemaining: 40,
                                resetsAt: resetWeekly, observedAt: obsDate, windowDurationMins: 10080)
                        ]
                    )
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 0,
                    healthStatus: "disabled",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "Monitoring disabled")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: nil,
                    usage: ProviderUsageWidgetSummary(
                        status: .available,
                        fractionUsed: 0.40,
                        percentRemaining: 60,
                        percentUsed: 40,
                        summary: "60% left",
                        windows: [
                            WidgetQuotaWindow(id: "ag-5h", label: "5 hours", percentRemaining: 60,
                                resetsAt: reset5h, observedAt: obsDate, windowDurationMins: 300)
                        ],
                        groups: [
                            WidgetQuotaGroup(id: "gemini", label: "Gemini Models", windows: [
                                WidgetQuotaWindow(id: "gemini-pro", label: "Gemini 1.5 Pro", percentRemaining: 82,
                                    resetsAt: reset5h, observedAt: obsDate)
                            ])
                        ]
                    )
                )
            ],
            statusMessage: "2 providers enabled"
        )
    }

    func makeThreeEnabledProvidersSnapshot() -> LoomWidgetSnapshot {
        .preview
    }

    func makeNoQuotaProvidersEnabledSnapshot() -> LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 0,
            attentionSessionCount: 0,
            totalSessionCount: 0,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 0,
                    healthStatus: "disabled",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "No quota providers enabled")
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 0,
                    healthStatus: "disabled",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "No quota providers enabled")
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "disabled",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(status: .unavailable, summary: "No quota providers enabled")
                )
            ],
            statusMessage: "No quota providers enabled"
        )
    }
}

@main
struct WidgetVisualProbeMain {
    static func main() async {
        let probe = WidgetVisualProbe.shared
        print("==================================================")
        print("Loom macOS Widgets — Visual & Runtime QA Pass")
        print("==================================================")
        fflush(stdout)

        let smallSize = NSSize(width: 170, height: 170)
        let mediumSize = NSSize(width: 364, height: 170)
        let largeSize = NSSize(width: 364, height: 364)

        // ==================================================
        // Multi-Provider Loom Quotas Widget Scenarios
        // ==================================================

        // 1. Small widget with 1 enabled provider (Codex) — Dark & Light modes
        print("\n[QA Quotas 1] Small Quota Widget — 1 Enabled Provider (Codex) — Dark & Light")
        let snap1Prov = probe.makeSingleEnabledProviderSnapshot()
        let entry1Prov = LoomWidgetEntry(date: Date(), snapshot: snap1Prov, readResult: .success(snap1Prov), providerID: "codex")
        for dark in [true, false] {
            let mode = dark ? "dark" : "light"
            let tokens = await probe.renderAndCapture(
                view: LoomQuotaWidgetView(entry: entry1Prov).padding(14),
                size: smallSize,
                isDark: dark,
                filename: "quota-01-small-1provider-\(mode).png"
            )
            print("  Captured: quota-01-small-1provider-\(mode).png (Tokens: \(tokens.count))")
            print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")
        }

        // 2. Small widget with 2 enabled providers (Codex + Antigravity) — Dark & Light modes
        print("\n[QA Quotas 2] Small Quota Widget — 2 Enabled Providers (Codex + Antigravity) — Dark & Light")
        let snap2Prov = probe.makeTwoEnabledProvidersSnapshot()
        let entry2Prov = LoomWidgetEntry(date: Date(), snapshot: snap2Prov, readResult: .success(snap2Prov), providerID: "codex")
        for dark in [true, false] {
            let mode = dark ? "dark" : "light"
            let tokens = await probe.renderAndCapture(
                view: LoomQuotaWidgetView(entry: entry2Prov).padding(14),
                size: smallSize,
                isDark: dark,
                filename: "quota-02-small-2providers-\(mode).png"
            )
            print("  Captured: quota-02-small-2providers-\(mode).png (Tokens: \(tokens.count))")
            print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")
        }

        // 3. Small widget with 3 enabled providers (Codex + Claude Code + Antigravity) — Dark & Light modes
        print("\n[QA Quotas 3] Small Quota Widget — 3 Enabled Providers (Codex + Claude Code + Antigravity) — Dark & Light")
        let snap3Prov = probe.makeThreeEnabledProvidersSnapshot()
        let entry3Prov = LoomWidgetEntry(date: Date(), snapshot: snap3Prov, readResult: .success(snap3Prov), providerID: "codex")
        for dark in [true, false] {
            let mode = dark ? "dark" : "light"
            let tokens = await probe.renderAndCapture(
                view: LoomQuotaWidgetView(entry: entry3Prov).padding(14),
                size: smallSize,
                isDark: dark,
                filename: "quota-03-small-3providers-\(mode).png"
            )
            print("  Captured: quota-03-small-3providers-\(mode).png (Tokens: \(tokens.count))")
            print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")
        }

        // 4. Small widget with all providers disabled ("No quota providers enabled" state) — Dark mode
        print("\n[QA Quotas 4] Small Quota Widget — All Providers Disabled (\"No quota providers enabled\" state) — Dark")
        let snapDisabled = probe.makeNoQuotaProvidersEnabledSnapshot()
        let entryDisabledQuota = LoomWidgetEntry(date: Date(), snapshot: snapDisabled, readResult: .success(snapDisabled), providerID: "codex")
        let tokensDisabled = await probe.renderAndCapture(
            view: LoomQuotaWidgetView(entry: entryDisabledQuota).padding(14),
            size: smallSize,
            isDark: true,
            filename: "quota-04-small-all-disabled-dark.png"
        )
        print("  Captured: quota-04-small-all-disabled-dark.png (Tokens: \(tokensDisabled.count))")
        print("  OCR: \(tokensDisabled.map(\.text).joined(separator: " | "))")

        // 5. Medium widget with 3 enabled providers — Dark & Light modes
        print("\n[QA Quotas 5] Medium Quota Widget — 3 Enabled Providers — Dark & Light")
        for dark in [true, false] {
            let mode = dark ? "dark" : "light"
            let tokens = await probe.renderAndCapture(
                view: LoomQuotaWidgetView(entry: entry3Prov).padding(14),
                size: mediumSize,
                isDark: dark,
                filename: "quota-05-medium-3providers-\(mode).png"
            )
            print("  Captured: quota-05-medium-3providers-\(mode).png (Tokens: \(tokens.count))")
            print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")
        }

        // 6. Large widget with 3 enabled providers — Dark & Light modes
        print("\n[QA Quotas 6] Large Quota Widget — 3 Enabled Providers — Dark & Light")
        for dark in [true, false] {
            let mode = dark ? "dark" : "light"
            let tokens = await probe.renderAndCapture(
                view: LoomQuotaWidgetView(entry: entry3Prov).padding(14),
                size: largeSize,
                isDark: dark,
                filename: "quota-06-large-3providers-\(mode).png"
            )
            print("  Captured: quota-06-large-3providers-\(mode).png (Tokens: \(tokens.count))")
            print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")
        }

        // Quota widgets baseline captures for regression compatibility
        for dark in [false, true] {
            _ = await probe.renderAndCapture(view: LoomQuotaWidgetView(entry: entry3Prov).padding(14),
                size: smallSize, isDark: dark, filename: "quota-available-\(dark ? "dark" : "light").png")
            var unsupported = entry3Prov
            unsupported.providerID = "claude"
            _ = await probe.renderAndCapture(view: LoomQuotaWidgetView(entry: unsupported).padding(14),
                size: smallSize, isDark: dark, filename: "quota-unavailable-\(dark ? "dark" : "light").png")
        }


        // 1. Active sessions (Preview)
        let activeSnapshot = probe.makeActiveSnapshot()
        let entryActive = LoomWidgetEntry(date: Date(), snapshot: activeSnapshot, readResult: .success(activeSnapshot))

        print("\n[QA Test 1] Active Sessions (Preview) — Dark & Light")
        var tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryActive).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-01-active-dark.png"
        )
        print("  Captured: small-01-active-dark.png (Tokens: \(tokens.count))")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryActive).padding(14),
            size: smallSize,
            isDark: false,
            filename: "small-01-active-light.png"
        )
        print("  Captured: small-01-active-light.png (Tokens: \(tokens.count))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryActive).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-01-active-dark.png"
        )
        print("  Captured: medium-01-active-dark.png (Tokens: \(tokens.count))")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryActive).padding(14),
            size: mediumSize,
            isDark: false,
            filename: "medium-01-active-light.png"
        )
        print("  Captured: medium-01-active-light.png (Tokens: \(tokens.count))")

        // 2. Zero Sessions (Idle)
        let zeroSnapshot = probe.makeZeroSessionsSnapshot()
        let entryZero = LoomWidgetEntry(date: Date(), snapshot: zeroSnapshot, readResult: .success(zeroSnapshot))
        print("\n[QA Test 2] Zero Sessions (Idle State)")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryZero).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-02-zero-sessions-dark.png"
        )
        print("  Captured: small-02-zero-sessions-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryZero).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-02-zero-sessions-dark.png"
        )
        print("  Captured: medium-02-zero-sessions-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 3. Attention Needed (Alert State)
        let attentionSnapshot = probe.makeAttentionSnapshot()
        let entryAttention = LoomWidgetEntry(date: Date(), snapshot: attentionSnapshot, readResult: .success(attentionSnapshot))
        print("\n[QA Test 3] Attention Sessions (Alert State)")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryAttention).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-03-attention-alert-dark.png"
        )
        print("  Captured: small-03-attention-alert-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryAttention).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-03-attention-alert-dark.png"
        )
        print("  Captured: medium-03-attention-alert-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 4. Degraded, Unavailable, and Error States
        let degradedSnapshot = probe.makeDegradedUnavailableSnapshot()
        let entryDegraded = LoomWidgetEntry(date: Date(), snapshot: degradedSnapshot, readResult: .success(degradedSnapshot))
        print("\n[QA Test 4] Degraded, Unavailable & Error States")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryDegraded).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-04-degraded-error-dark.png"
        )
        print("  Captured: small-04-degraded-error-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryDegraded).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-04-degraded-error-dark.png"
        )
        print("  Captured: medium-04-degraded-error-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 5. All Disabled State
        let disabledSnapshot = probe.makeAllDisabledSnapshot()
        let entryDisabled = LoomWidgetEntry(date: Date(), snapshot: disabledSnapshot, readResult: .success(disabledSnapshot))
        print("\n[QA Test 5] All Monitoring Disabled State")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryDisabled).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-05-all-disabled-dark.png"
        )
        print("  Captured: small-05-all-disabled-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryDisabled).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-05-all-disabled-dark.png"
        )
        print("  Captured: medium-05-all-disabled-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 6. Healthy & Low Quota State
        let quotaSnapshot = probe.makeHealthyAndLowQuotaSnapshot()
        let entryQuota = LoomWidgetEntry(date: Date(), snapshot: quotaSnapshot, readResult: .success(quotaSnapshot))
        print("\n[QA Test 6] Healthy & Low Quota State")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryQuota).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-06-low-quota-dark.png"
        )
        print("  Captured: small-06-low-quota-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryQuota).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-06-low-quota-dark.png"
        )
        print("  Captured: medium-06-low-quota-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 7. Stale Snapshot (>15 min)
        let staleSnapshot = probe.makeStaleSnapshot()
        let entryStale = LoomWidgetEntry(date: Date(), snapshot: staleSnapshot, readResult: .success(staleSnapshot))
        print("\n[QA Test 7] Stale Snapshot (> 15 min)")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryStale).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-07-stale-snapshot-dark.png"
        )
        print("  Captured: small-07-stale-snapshot-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryStale).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-07-stale-snapshot-dark.png"
        )
        print("  Captured: medium-07-stale-snapshot-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 8. No Snapshot / Loom Not Running
        let entryNotFound = LoomWidgetEntry(date: Date(), snapshot: nil, readResult: .notFound)
        print("\n[QA Test 8] No Snapshot / Launch Loom State")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryNotFound).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-08-not-found-dark.png"
        )
        print("  Captured: small-08-not-found-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryNotFound).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-08-not-found-dark.png"
        )
        print("  Captured: medium-08-not-found-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 9. Corrupted Data
        let entryCorrupt = LoomWidgetEntry(date: Date(), snapshot: nil, readResult: .corrupted("Invalid JSON"))
        print("\n[QA Test 9] Corrupted Data State")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryCorrupt).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-09-corrupted-dark.png"
        )
        print("  Captured: small-09-corrupted-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryCorrupt).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-09-corrupted-dark.png"
        )
        print("  Captured: medium-09-corrupted-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 10. Unsupported Version
        let entryVersion = LoomWidgetEntry(date: Date(), snapshot: nil, readResult: .unsupportedVersion(99))
        print("\n[QA Test 10] Unsupported Version State")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryVersion).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-10-version-mismatch-dark.png"
        )
        print("  Captured: small-10-version-mismatch-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryVersion).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-10-version-mismatch-dark.png"
        )
        print("  Captured: medium-10-version-mismatch-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 11. Long Text Truncation & Resilience
        let longSnapshot = probe.makeLongTextSnapshot()
        let entryLong = LoomWidgetEntry(date: Date(), snapshot: longSnapshot, readResult: .success(longSnapshot))
        print("\n[QA Test 11] Long Text Truncation Resilience")
        tokens = await probe.renderAndCapture(
            view: LoomSmallWidgetView(entry: entryLong).padding(14),
            size: smallSize,
            isDark: true,
            filename: "small-11-long-text-dark.png"
        )
        print("  Captured: small-11-long-text-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        tokens = await probe.renderAndCapture(
            view: LoomMediumWidgetView(entry: entryLong).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "medium-11-long-text-dark.png"
        )
        print("  Captured: medium-11-long-text-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // 12. Interactions QA Verification
        print("\n[QA Test 12] Widget Interactions & Deep Links")
        let controller = DockController()
        let settingsSuite = "test.loom.qa.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: settingsSuite)!
        defer { testDefaults.removePersistentDomain(forName: settingsSuite) }
        let settings = LoomSettings(defaults: testDefaults)

        var refreshInvoked = false
        controller.configure(settings: settings, onRefresh: {
            refreshInvoked = true
        })

        // Test loom://open
        controller.handleOpenURL(URL(string: "loom://open")!)
        print("  PASS: loom://open handled cleanly")

        // Test loom://refresh
        controller.handleOpenURL(URL(string: "loom://refresh")!)
        assert(refreshInvoked, "loom://refresh must invoke onRefresh callback")
        print("  PASS: loom://refresh invoked immediate refreshAction")

        // Test loom://settings
        controller.handleOpenURL(URL(string: "loom://settings")!)
        assert(controller.isSettingsWindowPresented, "loom://settings must present Settings window")
        print("  PASS: loom://settings presented settings window")

        // Test loom://provider/<id>
        controller.handleOpenURL(URL(string: "loom://provider/codex")!)
        assert(controller.isSettingsWindowPresented, "loom://provider/codex must present Settings window")
        print("  PASS: loom://provider/codex presented settings window")

        // 13. Loom Usage Overview Widget (Medium & Large) QA Verification
        print("\n[QA Test 13] Loom Usage Overview Widget (Medium & Large)")
        let previewEntry = LoomWidgetEntry(date: Date(), snapshot: .preview, readResult: .success(.preview))

        for dark in [true, false] {
            let mode = dark ? "dark" : "light"
            tokens = await probe.renderAndCapture(
                view: LoomUsageOverviewMediumView(entry: previewEntry).padding(14),
                size: mediumSize,
                isDark: dark,
                filename: "overview-01-preview-medium-\(mode).png"
            )
            print("  Captured: overview-01-preview-medium-\(mode).png (Tokens: \(tokens.count))")

            tokens = await probe.renderAndCapture(
                view: LoomUsageOverviewLargeView(entry: previewEntry).padding(14),
                size: largeSize,
                isDark: dark,
                filename: "overview-01-preview-large-\(mode).png"
            )
            print("  Captured: overview-01-preview-large-\(mode).png (Tokens: \(tokens.count))")
            print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")
        }

        // Stale usage overview
        tokens = await probe.renderAndCapture(
            view: LoomUsageOverviewMediumView(entry: entryStale).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "overview-02-stale-medium-dark.png"
        )
        print("  Captured: overview-02-stale-medium-dark.png")

        tokens = await probe.renderAndCapture(
            view: LoomUsageOverviewLargeView(entry: entryStale).padding(14),
            size: largeSize,
            isDark: true,
            filename: "overview-02-stale-large-dark.png"
        )
        print("  Captured: overview-02-stale-large-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // All disabled usage overview
        tokens = await probe.renderAndCapture(
            view: LoomUsageOverviewMediumView(entry: entryDisabled).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "overview-03-disabled-medium-dark.png"
        )
        print("  Captured: overview-03-disabled-medium-dark.png")

        tokens = await probe.renderAndCapture(
            view: LoomUsageOverviewLargeView(entry: entryDisabled).padding(14),
            size: largeSize,
            isDark: true,
            filename: "overview-03-disabled-large-dark.png"
        )
        print("  Captured: overview-03-disabled-large-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        // Long model names & overflow limits
        let longOverviewSnapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 5,
            attentionSessionCount: 0,
            totalSessionCount: 5,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "OpenAI Codex CLI Enterprise",
                    sessionCount: 3,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(
                        status: .available,
                        percentRemaining: 78,
                        summary: "78% left",
                        windows: [
                            WidgetQuotaWindow(id: "primary", label: "Primary 5-Hour Session Quota Window", percentRemaining: 78,
                                resetsAt: Date().addingTimeInterval(7200), observedAt: Date()),
                            WidgetQuotaWindow(id: "weekly", label: "Weekly Extended Organizational Limit", percentRemaining: 45,
                                resetsAt: Date().addingTimeInterval(86400), observedAt: Date())
                        ],
                        groups: [
                            WidgetQuotaGroup(id: "models", label: "Additional Model Quotas", windows: [
                                WidgetQuotaWindow(id: "gpt-4o", label: "GPT-4o Omnimodal Reasoning", percentRemaining: 60, resetsAt: nil, observedAt: Date()),
                                WidgetQuotaWindow(id: "o1", label: "o1 Full High-Compute Inference", percentRemaining: 15, resetsAt: nil, observedAt: Date()),
                                WidgetQuotaWindow(id: "o1-mini", label: "o1-mini Fast Reasoning Assistant", percentRemaining: 90, resetsAt: nil, observedAt: Date())
                            ])
                        ]
                    )
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Anthropic Claude Code Runner",
                    sessionCount: 2,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(
                        status: .unsupported,
                        summary: "Quota not supported"
                    )
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Google DeepMind Antigravity Studio",
                    sessionCount: 0,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: ProviderUsageWidgetSummary(
                        status: .available,
                        percentRemaining: 88,
                        summary: "88% left",
                        windows: [
                            WidgetQuotaWindow(id: "gemini-pro", label: "Gemini 1.5 Pro Long-Context Production", percentRemaining: 88,
                                resetsAt: Date().addingTimeInterval(14400), observedAt: Date()),
                            WidgetQuotaWindow(id: "gemini-flash", label: "Gemini 1.5 Flash High-Throughput Tier", percentRemaining: 99,
                                resetsAt: Date().addingTimeInterval(14400), observedAt: Date())
                        ]
                    )
                )
            ]
        )
        let entryLongOverview = LoomWidgetEntry(date: Date(), snapshot: longOverviewSnapshot, readResult: .success(longOverviewSnapshot))

        tokens = await probe.renderAndCapture(
            view: LoomUsageOverviewMediumView(entry: entryLongOverview).padding(14),
            size: mediumSize,
            isDark: true,
            filename: "overview-04-longtext-medium-dark.png"
        )
        print("  Captured: overview-04-longtext-medium-dark.png")

        tokens = await probe.renderAndCapture(
            view: LoomUsageOverviewLargeView(entry: entryLongOverview).padding(14),
            size: largeSize,
            isDark: true,
            filename: "overview-04-longtext-large-dark.png"
        )
        print("  Captured: overview-04-longtext-large-dark.png")
        print("  OCR: \(tokens.map(\.text).joined(separator: " | "))")

        probe.closeWindow()

        print("\n==================================================")
        print("TOTAL SCREENSHOTS CAPTURED: \(probe.capturedPaths.count)")
        for path in probe.capturedPaths {
            print("  \(path)")
        }
        print("==================================================")
        fflush(stdout)
    }
}
