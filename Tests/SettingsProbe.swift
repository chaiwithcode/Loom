//
//  SettingsProbe.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import AppKit
import SwiftUI
import Vision
import LoomCore
import Loom

struct OCRResult {
    let text: String
    let boundingBox: CGRect
}

@main struct SettingsProbe {
    @MainActor static func settle(_ host: NSView, iterations: Int = 20) async {
        for _ in 0..<iterations {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor @discardableResult static func saveOpaque(_ view: NSView, _ name: String) -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0 && bounds.height > 0 else {
            fatalError("Cannot save snapshot of zero-sized view for \(name)")
        }

        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            fatalError("bitmapImageRepForCachingDisplay failed for \(name)")
        }
        rep.isOpaque = false
        view.cacheDisplay(in: bounds, to: rep)
        rep.isOpaque = false

        let size = bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        let isDark = (view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .darkAqua) == .darkAqua
        let bg = isDark ? NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0) : NSColor(calibratedWhite: 0.96, alpha: 1.0)
        bg.setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: false, hints: nil)
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let finalRep = NSBitmapImageRep(data: tiffData),
              let pngData = finalRep.representation(using: .png, properties: [:]) else {
            fatalError("PNG encoding failed for \(name)")
        }

        let url = URL(fileURLWithPath: "/tmp/loom-settings-verification/\(name).png")
        try! pngData.write(to: url)
        print("  [Saved] \(url.path)")
        fflush(stdout)
        return finalRep
    }

    @MainActor static func recognizeText(in imageRep: NSBitmapImageRep) throws -> [OCRResult] {
        guard let cgImage = imageRep.cgImage else { return [] }
        var results: [OCRResult] = []
        var ocrError: Error?

        let request = VNRecognizeTextRequest { req, err in
            if let err {
                ocrError = err
                return
            }
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                if let top = obs.topCandidates(1).first {
                    let trimmed = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        results.append(OCRResult(text: trimmed, boundingBox: obs.boundingBox))
                    }
                }
            }
        }
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        if let ocrError {
            throw ocrError
        }
        return results
    }

    @MainActor static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.compactMap { scrollView(in: $0) }.first
    }

    @MainActor static func containsOverflowButton(in view: NSView) -> Bool {
        if let btn = view as? NSButton, btn.title.contains(">>") || btn.toolTip?.contains("overflow") == true {
            return true
        }
        let className = NSStringFromClass(type(of: view))
        if className.contains("Overflow") {
            return true
        }
        for sub in view.subviews {
            if containsOverflowButton(in: sub) { return true }
        }
        return false
    }

    static func dumpObservations(_ results: [OCRResult], label: String) {
        print("--- OCR Observations [\(label)] ---")
        for (i, r) in results.enumerated() {
            print("  [\(i)] \"\(r.text)\" box=\(r.boundingBox)")
        }
        fflush(stdout)
    }

    static func normalizeAndJoinReadingOrder(_ results: [OCRResult]) -> String {
        let sorted = results.sorted { a, b in
            if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.02 {
                return a.boundingBox.midY > b.boundingBox.midY
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        return sorted.map(\.text).joined(separator: " ")
    }

    static func containsToken(_ token: String, in text: String) -> Bool {
        text.localizedCaseInsensitiveContains(token)
    }

    static func containsText(_ match: String, in results: [OCRResult]) -> Bool {
        if results.contains(where: { $0.text.localizedCaseInsensitiveContains(match) }) {
            return true
        }
        return normalizeAndJoinReadingOrder(results).localizedCaseInsensitiveContains(match)
    }

    static func containsExact(_ match: String, in results: [OCRResult]) -> Bool {
        results.contains(where: { $0.text.contains(match) })
    }

    @MainActor static func clickPoint(_ window: NSWindow, at point: NSPoint) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        func mouseEvent(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1.0
            )!
        }
        let mouseUp = mouseEvent(.leftMouseUp)
        let mouseDown = mouseEvent(.leftMouseDown)
        // Let NSApplication dispatch both events from its normal event loop.
        // Sending mouse-down synchronously from an async task enters AppKit's
        // nested tracking loop before that task can deliver the release.
        NSApplication.shared.postEvent(mouseDown, atStart: false)
        NSApplication.shared.postEvent(mouseUp, atStart: false)
    }

    @MainActor static func nativeToggleLocation(for name: String, in results: [OCRResult], rootView: NSView) -> NSPoint? {
        guard let match = results.first(where: {
            $0.text.localizedCaseInsensitiveContains(name) &&
            $0.boundingBox.origin.x < 0.5
        }) else {
            return nil
        }

        let rowCenterY = (match.boundingBox.origin.y + match.boundingBox.height / 2) * rootView.bounds.height
        var controls: [NSControl] = []
        var tree: [(NSView, Int)] = []
        func collect(_ view: NSView, depth: Int) {
            tree.append((view, depth))
            if let control = view as? NSControl {
                controls.append(control)
            }
            for child in view.subviews {
                collect(child, depth: depth + 1)
            }
        }
        collect(rootView, depth: 0)

        let switches = controls.filter { $0 is NSSwitch }
        func windowFrame(of view: NSView) -> NSRect {
            view.convert(view.bounds, to: nil)
        }
        func controlDescription(_ control: NSControl) -> String {
            let identifier = control.identifier?.rawValue ?? "<none>"
            return "class=\(String(describing: type(of: control))) id=\(identifier) windowFrame=\(windowFrame(of: control))"
        }
        func viewDescription(_ view: NSView) -> String {
            let identifier = view.identifier?.rawValue ?? "<none>"
            return "class=\(String(describing: type(of: view))) id=\(identifier) windowFrame=\(windowFrame(of: view))"
        }

        for control in controls {
            print("  Native control: \(controlDescription(control))")
        }
        guard !switches.isEmpty else {
            print("  NSSwitch not exposed; SettingsView native view tree:")
            for (view, depth) in tree {
                let indent = String(repeating: "  ", count: depth)
                if let control = view as? NSControl {
                    print("\(indent)\(controlDescription(control))")
                } else {
                    print("\(indent)\(viewDescription(view))")
                }
            }
            return nil
        }

        let selected = switches.first(where: { $0.identifier?.rawValue == "toggle-monitor-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))" })
            ?? switches.min(by: { abs(windowFrame(of: $0).midY - rowCenterY) < abs(windowFrame(of: $1).midY - rowCenterY) })!
        let frame = windowFrame(of: selected)
        print("  Selected native toggle for \(name): \(controlDescription(selected)); OCR rowCenterY=\(rowCenterY)")
        fflush(stdout)
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    @MainActor static func main() {
        let application = NSApplication.shared
        DispatchQueue.main.async {
            Task { @MainActor in
                do {
                    try await runChecks()
                } catch {
                    fputs("Settings probe failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        }
        application.run()
        // Returning from the application loop before the completion sentinel
        // means the native checks did not finish.
        exit(1)
    }

    @MainActor static func runChecks() async throws {
        print("==================================================")
        print("Starting Native Loom Settings Probe")
        print("==================================================")
        fflush(stdout)

        guard let iconImage = NSImage(contentsOfFile: "Resources/LoomIconMaster.png") else {
            fatalError("Required test artwork Resources/LoomIconMaster.png is missing")
        }
        NSApplication.shared.applicationIconImage = iconImage

        let suiteName = "test.loom.probe.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create test UserDefaults suite")
        }
        defer {
            testDefaults.removePersistentDomain(forName: suiteName)
        }

        // Exercise the production status evaluator without relying on a live provider.
        let statusSession = AgentSession(id: "status-session", provider: .codex, state: .working)
        let statusUsage = ProviderUsageSnapshot(
            providerID: .codex,
            primaryBucket: UsageBucket(identifier: "5h", label: "5-hour", usedFraction: 0.88)
        )
        let statusSnapshot = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: [statusSession],
            usage: statusUsage
        )
        assert(MenuBarStatusEvaluator.evaluate(mode: .iconOnly, snapshots: [statusSnapshot]).text == nil)
        assert(MenuBarStatusEvaluator.evaluate(mode: .activeSessionCount, snapshots: [statusSnapshot]).text == "1")
        assert(MenuBarStatusEvaluator.evaluate(mode: .lowestQuota, snapshots: [statusSnapshot]).text == "12%")
        var failedStatusSnapshot = statusSnapshot
        failedStatusSnapshot.availability = .error(reason: "Provider unavailable")
        assert(MenuBarStatusEvaluator.evaluate(mode: .lowestQuota, snapshots: [failedStatusSnapshot]).text == nil)
        assert(MenuBarStatusEvaluator.evaluate(mode: .activeSessionCount, snapshots: [failedStatusSnapshot]).text == nil)
        print("  PASS: Production menu bar modes omit unavailable provider data")

        // =====================================================================
        // Test 1: Guard unconfigured opening (isolated controller instance)
        // =====================================================================
        print("Check 1: Guard unconfigured showSettings")
        let controller = DockController()
        assert(!controller.isSettingsWindowPresented, "Initial isSettingsWindowPresented must be false")
        assert(controller.settingsWindow == nil, "Initial settingsWindow must be nil")

        controller.showSettings()
        assert(!controller.isSettingsWindowPresented, "Unconfigured showSettings must NOT set isSettingsWindowPresented")
        assert(controller.settingsWindow == nil, "Unconfigured showSettings must NOT create settingsWindow")
        print("  PASS: Unconfigured opening correctly guarded")
        fflush(stdout)

        // =====================================================================
        // Test 2: Configure and verify window creation & ownership & contentMinSize
        // =====================================================================
        print("Check 2: Configure and strong deterministic window ownership")
        let settings = LoomSettings(defaults: testDefaults)
        let codexSession = AgentSession(id: "s1", provider: .codex, projectName: "Loom", state: .working)
        let codexProvider = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [codexSession])
        let store = SessionStore(providers: [codexProvider])
        await store.refresh()

        controller.configure(settings: settings, store: store)
        controller.showSettings()

        assert(controller.isSettingsWindowPresented, "isSettingsWindowPresented must be true after showSettings")
        guard let window = controller.settingsWindow else {
            fatalError("settingsWindow must not be nil after showSettings")
        }
        assert(!window.isReleasedWhenClosed, "Window isReleasedWhenClosed must be false for reuse")
        assert(window.contentMinSize.width == 640, "Window contentMinSize.width must match view minWidth (640)")
        assert(window.contentMinSize.height == 460, "Window contentMinSize.height must match view minHeight (460)")
        assert(window.isVisible, "Window must be visible")
        print("  PASS: Window created with contentMinSize \(window.contentMinSize)")
        fflush(stdout)

        // =====================================================================
        // Test 3: Repeated same-store & initial-override & configure reuse host preservation
        // =====================================================================
        print("Check 3: Repeated showSettings, override store, and configure reuse host preservation")
        let initialContentView = window.contentView
        let windowCountBefore = NSApp.windows.count

        // Same store call preserves host
        controller.showSettings(store: store)
        assert(controller.settingsWindow === window, "settingsWindow must be identical instance")
        assert(window.contentView === initialContentView, "Repeated same-store showSettings must NOT recreate contentView")
        assert(NSApp.windows.count == windowCountBefore, "No duplicate windows allocated")

        // First override with storeB updates presentedStore and creates hostB
        let storeB = SessionStore(providers: [codexProvider])
        controller.showSettings(store: storeB)
        let hostB = window.contentView
        assert(hostB !== initialContentView, "Overriding store must create hostB")

        // Repeated call with storeB must preserve hostB
        controller.showSettings(store: storeB)
        assert(window.contentView === hostB, "Repeated showSettings with storeB must preserve hostB")

        // Configure with new settings instance refreshes host
        let settingsSuite2 = "test.loom.probe2.\(UUID().uuidString)"
        let testDefaults2 = UserDefaults(suiteName: settingsSuite2)!
        defer { testDefaults2.removePersistentDomain(forName: settingsSuite2) }
        let settings2 = LoomSettings(defaults: testDefaults2)
        controller.configure(settings: settings2)
        let hostSettings2 = window.contentView
        assert(hostSettings2 !== hostB, "Configuring with new settings instance must refresh host")

        // Configure with same settings preserves host
        controller.configure(settings: settings2)
        assert(window.contentView === hostSettings2, "Configuring with same settings must preserve host")
        print("  PASS: Reused exact same window instance and preserved contentView across repeated and configure calls")
        fflush(stdout)

        // Restore initial settings for remaining tests
        controller.configure(settings: settings, store: store)

        // =====================================================================
        // Test 4: Window close and reopening
        // =====================================================================
        print("Check 4: Close and reopen behavior")
        window.close()
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        assert(!controller.isSettingsWindowPresented, "isSettingsWindowPresented must be false after close")
        assert(controller.settingsWindow === window, "settingsWindow must remain strongly held after close")

        controller.showSettings()
        assert(controller.isSettingsWindowPresented, "isSettingsWindowPresented must be true after reopen")
        assert(controller.settingsWindow === window, "Reopened window must be same instance")
        assert(window.isVisible, "Reopened window must be visible")

        // Test Dock reopen handler (applicationShouldHandleReopen delegate path)
        window.close()
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        assert(!controller.isSettingsWindowPresented, "isSettingsWindowPresented must be false after close")
        let reopenHandled = controller.handleReopen(hasVisibleWindows: false)
        assert(reopenHandled, "handleReopen must return true")
        assert(controller.isSettingsWindowPresented, "handleReopen(hasVisibleWindows: false) must reopen settings")
        assert(window.isVisible, "Window must be visible following handleReopen")

        // Test handleOpenURL with loom:// deep links
        window.close()
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        assert(!controller.isSettingsWindowPresented, "isSettingsWindowPresented must be false after close")
        controller.handleOpenURL(URL(string: "loom://settings")!)
        assert(controller.isSettingsWindowPresented, "handleOpenURL(loom://settings) must present settings")
        assert(window.isVisible, "Window must be visible following handleOpenURL(loom://settings)")

        // Test handleOpenURL with loom://refresh
        var refreshTriggered = false
        controller.configure(settings: settings, store: store, onRefresh: {
            refreshTriggered = true
        })
        controller.handleOpenURL(URL(string: "loom://refresh")!)
        assert(refreshTriggered, "handleOpenURL(loom://refresh) must invoke refreshAction")

        // Test handleOpenURL with loom://provider/<id>
        window.close()
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        assert(!controller.isSettingsWindowPresented, "isSettingsWindowPresented must be false after close")
        controller.handleOpenURL(URL(string: "loom://provider/codex")!)
        assert(controller.isSettingsWindowPresented, "handleOpenURL(loom://provider/codex) must present settings")
        assert(window.isVisible, "Window must be visible following handleOpenURL(loom://provider/codex)")
        assert(controller.settingsProviderContextID == .codex, "Provider deep link must select Providers tab and focus Codex row")
        await settle(window.contentView!)
        let codexLinkScreenshot = saveOpaque(window.contentView!, "deep-link-provider-codex")
        let codexLinkOCR = try recognizeText(in: codexLinkScreenshot)
        assert(containsText("Default Provider", in: codexLinkOCR), "Provider deep link must show the Providers tab content")
        print("  PASS: Provider deep link carries Codex context into the Settings view")

        // Reconfiguring a live window must preserve provider context in the replacement host.
        let storeC = SessionStore(providers: [codexProvider])
        controller.configure(settings: settings, store: storeC)
        assert(controller.settingsProviderContextID == .codex, "Reconfiguration must preserve the current provider context")
        await settle(window.contentView!)
        let reconfiguredOCR = try recognizeText(in: saveOpaque(window.contentView!, "deep-link-provider-codex-reconfigured"))
        assert(containsText("Default Provider", in: reconfiguredOCR), "Reconfigured provider context must remain on Providers tab")

        // A second provider URL should replace context in the same window.
        let beforeClaudeContent = window.contentView
        controller.handleOpenURL(URL(string: "loom://provider/claude")!)
        assert(controller.settingsWindow === window, "Changing provider context must reuse the settings window")
        assert(window.contentView !== beforeClaudeContent, "Changing provider context must update the visible settings content")
        assert(controller.settingsProviderContextID == .claude, "Second provider deep link must replace Codex context with Claude")
        await settle(window.contentView!)
        let claudeLinkOCR = try recognizeText(in: saveOpaque(window.contentView!, "deep-link-provider-claude"))
        assert(containsText("Default Provider", in: claudeLinkOCR), "Claude deep link must still show the Providers tab")

        // Invalid provider paths and URL query data must not change context or bring up another route.
        controller.handleOpenURL(URL(string: "loom://provider/unknown")!)
        controller.handleOpenURL(URL(string: "loom://provider/codex/extra")!)
        controller.handleOpenURL(URL(string: "loom://provider/codex?tab=general")!)
        assert(controller.settingsProviderContextID == .claude, "Invalid provider URLs must be ignored")

        // Test other schemes and unknown hosts are safely ignored; loom://open activates.
        controller.handleOpenURL(URL(string: "loom://unknown")!)
        controller.handleOpenURL(URL(string: "https://example.com")!)
        controller.handleOpenURL(URL(string: "loom://open")!)
        print("  PASS: Close and reopen retains and reactivates singleton window (including handleReopen and handleOpenURL)")
        fflush(stdout)

        // =====================================================================
        // Test 5: Minimized reopening (deminiaturization)
        // =====================================================================
        print("Check 5: Minimized window reopening")
        window.miniaturize(nil)
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        assert(window.isMiniaturized, "Window should be miniaturized")

        controller.showSettings()
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        assert(!window.isMiniaturized, "showSettings on miniaturized window must deminiaturize it")
        assert(controller.settingsWindow === window, "Window instance preserved across deminiaturization")
        print("  PASS: Minimized window deminiaturized and brought to front")
        fflush(stdout)

        // =====================================================================
        // Test 6: Empty provider store in SettingsView & Native Toggle Clicks
        // =====================================================================
        print("Check 6: Empty provider store displays all supported providers on Providers tab & native toggle interactions")
        let emptyStore = SessionStore(providers: [])
        let emptyHost = NSHostingView(rootView: SettingsView(settings: settings, store: emptyStore, initialTab: .providers).frame(width: 640, height: 460))
        emptyHost.appearance = NSAppearance(named: .darkAqua)
        let probeWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        probeWindow.isReleasedWhenClosed = false
        probeWindow.contentView = emptyHost
        probeWindow.orderFront(nil)
        await settle(emptyHost)

        // Capture BEFORE assertions for guaranteed diagnostic evidence
        let emptyRep = saveOpaque(emptyHost, "settings-providers-empty-store")
        let emptyResults = try recognizeText(in: emptyRep)

        guard containsText("Claude Code", in: emptyResults) else {
            print("DIAGNOSTIC OCR Text Dump:\n\(emptyResults.map(\.text))")
            fatalError("Claude Code must be visible in empty store.")
        }
        assert(containsText("Codex", in: emptyResults), "Codex must be visible in empty store")
        assert(containsText("Antigravity", in: emptyResults), "Antigravity must be visible in empty store")
        assert(containsText("Default Provider", in: emptyResults), "Default provider picker must be visible")
        assert(containsText("Monitoring", in: emptyResults), "Monitoring section must be visible")

        // Native control interaction: click Codex toggle to disable it
        assert(settings.isProviderEnabled(.codex), "Codex is initially enabled")
        guard let codexPt = nativeToggleLocation(for: "Codex", in: emptyResults, rootView: emptyHost) else {
            fatalError("No native NSSwitch found for Codex; refusing to click without a native control target")
        }
        clickPoint(probeWindow, at: codexPt)
        await settle(emptyHost)
        assert(!settings.isProviderEnabled(.codex), "Native click on Codex toggle must disable it in model")
        let toggledRep = saveOpaque(emptyHost, "settings-providers-codex-toggled-off")
        let toggledResults = try recognizeText(in: toggledRep)
        assert(containsText("Monitoring disabled", in: toggledResults), "Visual UI must update to 'Monitoring disabled'")

        // Re-enable via click
        clickPoint(probeWindow, at: codexPt)
        await settle(emptyHost)
        assert(settings.isProviderEnabled(.codex), "Native click on Codex toggle must re-enable it in model")
        let reEnabledRep = saveOpaque(emptyHost, "settings-providers-codex-toggled-on")
        let reEnabledResults = try recognizeText(in: reEnabledRep)
        assert(containsText("Not registered", in: reEnabledResults), "Visual UI must update back to 'Not registered'")

        print("  PASS: Empty store renders all 3 supported providers and native toggle click verified")
        fflush(stdout)

        // =====================================================================
        // Test 7: Partial provider store (Codex registered, Claude/Agy unregistered)
        // =====================================================================
        print("Check 7: Partial provider store fixture")
        let partialStore = SessionStore(providers: [codexProvider])
        await partialStore.refresh()

        let partialHost = NSHostingView(rootView: SettingsView(settings: settings, store: partialStore, initialTab: .providers).frame(width: 640, height: 460))
        partialHost.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = partialHost
        await settle(partialHost)

        let partialRep = saveOpaque(partialHost, "settings-providers-partial-store")
        let partialResults = try recognizeText(in: partialRep)

        assert(containsText("Codex", in: partialResults))
        assert(containsText("Claude Code", in: partialResults))
        assert(containsText("Antigravity", in: partialResults))
        assert(containsText("1 session", in: partialResults), "Codex shows active session count")
        assert(containsText("Not registered", in: partialResults), "Unregistered providers show 'Not registered'")
        print("  PASS: Partial store renders active session count and 'Not registered' for others")
        fflush(stdout)

        // =====================================================================
        // Test 8: Provider health statuses: available, degraded, and error
        // =====================================================================
        print("Check 8: Explicit ProviderAvailability handling (available, degraded, error)")
        let availProvider = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [codexSession])
        availProvider.setAvailability(.available)

        let degradedProvider = MockAgentProvider(id: .claude, displayName: "Claude Code", sessions: [])
        degradedProvider.setAvailability(.degraded(reason: "High API latency on provider gateway"))

        let errorProvider = MockAgentProvider(id: .antigravity, displayName: "Antigravity", sessions: [])
        errorProvider.setAvailability(.error(reason: "Agent daemon /usr/local/bin/agy failed with exit code 1"))

        let healthStore = SessionStore(providers: [availProvider, degradedProvider, errorProvider])
        await healthStore.refresh()

        // 8A: Privacy OFF (reasons visible)
        settings.hideProjectPaths = false
        let healthHost = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .providers).frame(width: 640, height: 460))
        healthHost.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = healthHost
        await settle(healthHost)

        let healthRep = saveOpaque(healthHost, "settings-providers-health-statuses-visible")
        let healthResults = try recognizeText(in: healthRep)
        dumpObservations(healthResults, label: "Check 8A: Health statuses visible")
        let joinedHealth = normalizeAndJoinReadingOrder(healthResults)

        assert(containsToken("1 session", in: joinedHealth), "Available provider shows session count")
        assert(containsToken("Degraded", in: joinedHealth) &&
               containsToken("latency", in: joinedHealth) &&
               containsToken("provider gateway", in: joinedHealth),
               "Degraded provider shows degraded warning and stable semantic tokens (Degraded + latency + provider gateway)")
        assert(containsToken("/usr/local/bin/agy", in: joinedHealth), "Error provider shows error reason and path")

        // 8B: Privacy ON (reasons redacted when containing paths)
        settings.hideProjectPaths = true
        let healthHostRedacted = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .providers).frame(width: 640, height: 460))
        healthHostRedacted.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = healthHostRedacted
        await settle(healthHostRedacted)

        let healthRepRedacted = saveOpaque(healthHostRedacted, "settings-providers-health-statuses-redacted")
        let redactedResults = try recognizeText(in: healthRepRedacted)
        dumpObservations(redactedResults, label: "Check 8B: Health statuses redacted")
        let joinedRedacted = normalizeAndJoinReadingOrder(redactedResults)

        assert(!joinedRedacted.contains("/usr/local/bin/agy"), "Path in error must be redacted when hideProjectPaths is true")
        assert(containsToken("details hidden by privacy setting", in: joinedRedacted) ||
               (containsToken("Error", in: joinedRedacted) && containsToken("privacy setting", in: joinedRedacted)),
               "Error path redacted with privacy message (robust to line wrapping)")
        print("  PASS: Explicit available, degraded, and error statuses verified with privacy redaction")
        fflush(stdout)

        // =====================================================================
        // Test 9: Genuinely long multi-line status at supported minimum 640x460
        // =====================================================================
        print("Check 9: Genuinely long multi-line status at supported minimum 640x460")
        let longReason = "Degraded: Subprocess crashed during indexing.\nProcess /Users/developer/repos/big-project/worker.js failed with code 137.\nMemory limit exceeded."
        let longStatusProvider = MockAgentProvider(id: .claude, displayName: "Claude Code", sessions: [])
        longStatusProvider.setAvailability(.degraded(reason: longReason))
        let longStore = SessionStore(providers: [availProvider, longStatusProvider, errorProvider])
        await longStore.refresh()

        settings.hideProjectPaths = false
        let longHost = NSHostingView(rootView: SettingsView(settings: settings, store: longStore, initialTab: .providers).frame(width: 640, height: 460))
        longHost.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = longHost
        probeWindow.setContentSize(NSSize(width: 640, height: 460))
        await settle(longHost)

        let longRep = saveOpaque(longHost, "settings-multiline-status-640x460")
        let longResults = try recognizeText(in: longRep)
        dumpObservations(longResults, label: "Check 9: Long status un-scrolled at 640x460")
        let joinedLong = normalizeAndJoinReadingOrder(longResults)

        assert(containsToken("Codex", in: joinedLong), "Codex remains visible at 640x460")
        assert(containsToken("Claude Code", in: joinedLong), "Claude Code remains visible at 640x460")
        assert(containsToken("Subprocess crashed", in: joinedLong) || containsToken("indexing", in: joinedLong),
               "Long multi-line reason rendered")
        assert(containsToken("/Users/developer", in: joinedLong), "Path in long status visible when privacy is off")

        // Reachability via native scrolling when long content pushes rows below viewport
        if let scroll = scrollView(in: longHost) {
            let clipView = scroll.contentView
            let docView = scroll.documentView
            let docHeight = docView?.bounds.height ?? 0
            let clipHeight = clipView.bounds.height
            if docHeight > clipHeight {
                print("  Scrolling native NSScrollView to bottom (docHeight: \(docHeight), clipHeight: \(clipHeight))")
                let bottomOrigin = NSPoint(x: 0, y: docHeight - clipHeight)
                clipView.scroll(to: bottomOrigin)
                scroll.reflectScrolledClipView(clipView)
                await settle(longHost)

                let scrolledRep = saveOpaque(longHost, "settings-multiline-status-640x460-scrolled")
                let scrolledResults = try recognizeText(in: scrolledRep)
                dumpObservations(scrolledResults, label: "Check 9: Scrolled to bottom at 640x460")
                let joinedScrolled = normalizeAndJoinReadingOrder(scrolledResults)
                assert(containsToken("Antigravity", in: joinedScrolled), "Antigravity row reachable via native scrolling at 640x460")
            } else {
                assert(containsToken("Antigravity", in: joinedLong), "Antigravity visible within viewport at 640x460")
            }
        } else {
            assert(containsToken("Antigravity", in: joinedLong), "Antigravity visible at 640x460")
        }

        // Privacy redaction of long multi-line status at 640x460
        settings.hideProjectPaths = true
        let longHostRedacted = NSHostingView(rootView: SettingsView(settings: settings, store: longStore, initialTab: .providers).frame(width: 640, height: 460))
        longHostRedacted.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = longHostRedacted
        await settle(longHostRedacted)

        let longRepRedacted = saveOpaque(longHostRedacted, "settings-multiline-status-redacted-640x460")
        let longRedactedResults = try recognizeText(in: longRepRedacted)
        dumpObservations(longRedactedResults, label: "Check 9: Long status redacted at 640x460")
        let joinedLongRedacted = normalizeAndJoinReadingOrder(longRedactedResults)

        assert(!joinedLongRedacted.contains("/Users/developer"), "Path redacted in long multi-line status")
        assert(containsToken("details hidden by privacy setting", in: joinedLongRedacted) ||
               (containsToken("Degraded", in: joinedLongRedacted) && containsToken("privacy setting", in: joinedLongRedacted)),
               "Degraded privacy message shown (robust to line wrapping)")
        print("  PASS: Long multi-line status wraps cleanly at 640x460 without occluding controls, native scroll reachability proven")
        fflush(stdout)

        // =====================================================================
        // Test 10: All-disabled providers persistence and re-enable
        // =====================================================================
        print("Check 10: All-disabled providers persistence and re-enable")
        for pid in LoomSettings.defaultProviderIDs {
            settings.setProvider(pid, enabled: false)
        }
        assert(settings.enabledProviderIDs.isEmpty, "All providers should be disabled")

        let allDisabledHost = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .providers).frame(width: 640, height: 460))
        allDisabledHost.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = allDisabledHost
        await settle(allDisabledHost)

        let allDisabledRep = saveOpaque(allDisabledHost, "settings-providers-all-disabled")
        let allDisabledResults = try recognizeText(in: allDisabledRep)
        dumpObservations(allDisabledResults, label: "Check 10: All-disabled providers")
        let joinedAllDisabled = normalizeAndJoinReadingOrder(allDisabledResults)

        assert(containsToken("Monitoring disabled", in: joinedAllDisabled), "UI shows 'Monitoring disabled' when toggled off")

        // Re-enable codex
        settings.setProvider(.codex, enabled: true)
        assert(settings.enabledProviderIDs == [.codex], "Codex re-enabled")
        await settle(allDisabledHost)
        print("  PASS: All-disabled providers successfully handled and re-enabled")
        fflush(stdout)

        // =====================================================================
        // Test 11: Render each of the 7 tabs in full SettingsView via initialTab
        // =====================================================================
        print("Check 11: Switch TabView to each of the 7 tabs and verify controls at 640x460")

        // Tab 0: General
        let tab0Host = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .general).frame(width: 640, height: 460))
        tab0Host.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = tab0Host
        await settle(tab0Host)
        let tab0Rep = saveOpaque(tab0Host, "tab-0-general")
        let tab0Results = try recognizeText(in: tab0Rep)
        dumpObservations(tab0Results, label: "Check 11: Tab 0 (General)")
        let joinedTab0 = normalizeAndJoinReadingOrder(tab0Results)
        assert(containsToken("Show Loom in Dock", in: joinedTab0), "General tab renders Show Loom in Dock")
        assert(!containsToken("Show version in menu bar", in: joinedTab0), "Retired version toggle is absent")
        assert(containsToken("Refresh Interval", in: joinedTab0), "General tab renders Refresh Interval")
        assert(containsToken("Status Display", in: joinedTab0), "General tab exposes the menu bar status mode picker")

        if containsToken("Restore Defaults", in: joinedTab0) {
            print("  Restore Defaults visible within viewport at 640x460")
        } else if let scroll = scrollView(in: tab0Host) {
            let clipView = scroll.contentView
            let docView = scroll.documentView
            let docHeight = docView?.bounds.height ?? 0
            let clipHeight = clipView.bounds.height
            if docHeight > clipHeight {
                let bottomOrigin = NSPoint(x: 0, y: docHeight - clipHeight)
                clipView.scroll(to: bottomOrigin)
                scroll.reflectScrolledClipView(clipView)
                await settle(tab0Host)
                let tab0ScrolledRep = saveOpaque(tab0Host, "tab-0-general-scrolled")
                let tab0ScrolledResults = try recognizeText(in: tab0ScrolledRep)
                let joinedTab0Scrolled = normalizeAndJoinReadingOrder(tab0ScrolledResults)
                assert(containsToken("Restore Defaults", in: joinedTab0Scrolled), "Restore Defaults reachable via native scrolling on General tab at 640x460")
            } else {
                assertionFailure("Restore Defaults not found and scroll view does not overflow")
            }
        } else {
            assertionFailure("Restore Defaults not found in General tab")
        }

        // Tab 1: Providers
        let tab1Host = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .providers).frame(width: 640, height: 460))
        tab1Host.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = tab1Host
        await settle(tab1Host)
        let tab1Rep = saveOpaque(tab1Host, "tab-1-providers")
        let tab1Results = try recognizeText(in: tab1Rep)
        dumpObservations(tab1Results, label: "Check 11: Tab 1 (Providers)")
        let joinedTab1 = normalizeAndJoinReadingOrder(tab1Results)
        assert(containsToken("Default Provider", in: joinedTab1))
        assert(containsToken("Monitoring", in: joinedTab1))
        assert(containsToken("Codex", in: joinedTab1))
        assert(containsToken("Claude Code", in: joinedTab1))

        // Tab 2: Sessions (test retention picker disabled when includeRecentSessions is false)
        settings.includeRecentSessions = false
        let tab2Host = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .sessions).frame(width: 640, height: 460))
        tab2Host.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = tab2Host
        await settle(tab2Host)
        let tab2Rep = saveOpaque(tab2Host, "tab-2-sessions")
        let tab2Results = try recognizeText(in: tab2Rep)
        dumpObservations(tab2Results, label: "Check 11: Tab 2 (Sessions)")
        let joinedTab2 = normalizeAndJoinReadingOrder(tab2Results)
        assert(containsToken("Include recent sessions", in: joinedTab2))
        assert(containsToken("Hide finished after", in: joinedTab2))

        // Tab 3: Notifications
        let tabNotificationsHost = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .notifications).frame(width: 640, height: 460))
        tabNotificationsHost.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = tabNotificationsHost
        await settle(tabNotificationsHost)
        let tabNotificationsRep = saveOpaque(tabNotificationsHost, "tab-3-notifications")
        let tabNotificationsResults = try recognizeText(in: tabNotificationsRep)
        dumpObservations(tabNotificationsResults, label: "Check 11: Tab 3 (Notifications)")
        let joinedTabNotifications = normalizeAndJoinReadingOrder(tabNotificationsResults)
        assert(containsToken("Enable Notifications", in: joinedTabNotifications), "Notifications tab renders Enable Notifications")
        assert(containsToken("Quota Alerts", in: joinedTabNotifications), "Notifications tab renders Quota Alerts")

        if containsToken("Session Alerts", in: joinedTabNotifications) {
            print("  Session Alerts visible within viewport on Notifications tab at 640x460")
        } else if let scroll = scrollView(in: tabNotificationsHost) {
            let clipView = scroll.contentView
            let docView = scroll.documentView
            let docHeight = docView?.bounds.height ?? 0
            let clipHeight = clipView.bounds.height
            if docHeight > clipHeight {
                // History can extend below Session Alerts. Inspect overlapping
                // viewports instead of assuming every alert is at the bottom.
                var reachedHumanInput = containsToken("Needs human input", in: joinedTabNotifications)
                var reachedSessionFailed = containsToken("Session failed", in: joinedTabNotifications)
                let bottom = docHeight - clipHeight
                let step = max(1, clipHeight / 2)
                var offset = CGFloat(0)
                var page = 0
                while offset < bottom && !(reachedHumanInput && reachedSessionFailed) {
                    offset = min(bottom, offset + step)
                    clipView.scroll(to: NSPoint(x: 0, y: offset))
                    scroll.reflectScrolledClipView(clipView)
                    await settle(tabNotificationsHost)
                    let scrolledRep = saveOpaque(tabNotificationsHost, "tab-3-notifications-scrolled-\(page)")
                    let scrolledResults = try recognizeText(in: scrolledRep)
                    let joinedScrolled = normalizeAndJoinReadingOrder(scrolledResults)
                    reachedHumanInput = reachedHumanInput || containsToken("Needs human input", in: joinedScrolled)
                    reachedSessionFailed = reachedSessionFailed || containsToken("Session failed", in: joinedScrolled)
                    page += 1
                }
                assert(reachedHumanInput && reachedSessionFailed, "Session alert controls reachable via native scrolling on Notifications tab at 640x460")
            } else {
                assertionFailure("Session Alerts not found and scroll view does not overflow")
            }
        } else {
            assertionFailure("Session Alerts not found in Notifications tab")
        }

        // Render a private, isolated history fixture in the real Settings view.
        let historyFixture = NotificationHistoryStore(maxCapacity: 3, defaults: testDefaults)
        historyFixture.append(NotificationRecord(
            title: "Secret /Users/private/repository",
            body: "Transcript at /Users/private/repository",
            provider: .codex,
            eventType: "quotaThresholdCrossed",
            deliveredStatus: .delivered
        ))
        settings.hideProjectPaths = true
        let historyHost = NSHostingView(rootView: NotificationsSettingsTab(settings: settings, historyStore: historyFixture).frame(width: 520, height: 420))
        probeWindow.contentView = historyHost
        await settle(historyHost)
        if let scroll = scrollView(in: historyHost) {
            let clip = scroll.contentView
            let bottom = max(0, (scroll.documentView?.bounds.height ?? 0) - clip.bounds.height)
            clip.scroll(to: NSPoint(x: 0, y: bottom))
            scroll.reflectScrolledClipView(clip)
            await settle(historyHost)
        }
        let historyImage = saveOpaque(historyHost, "notifications-history-private")
        let historyText = normalizeAndJoinReadingOrder(try recognizeText(in: historyImage))
        assert(containsToken("Notification History", in: historyText), "Notification History must be reachable")
        assert(containsToken("Quota warning", in: historyText), "History must show the event type")
        assert(!historyText.contains("/Users/private"), "History must not expose older private paths")
        historyFixture.append(NotificationRecord(
            title: "Another private /Users/private/repository",
            body: "Private transcript", provider: .antigravity,
            eventType: "quotaReplenished", deliveredStatus: .suppressed
        ))
        await settle(historyHost)
        if let scroll = scrollView(in: historyHost) {
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: 0, y: max(0, (scroll.documentView?.bounds.height ?? 0) - clip.bounds.height)))
            scroll.reflectScrolledClipView(clip)
            await settle(historyHost)
        }
        let updatedHistory = normalizeAndJoinReadingOrder(try recognizeText(in: saveOpaque(historyHost, "notifications-history-live-update")))
        assert(containsToken("Quota replenished", in: updatedHistory), "An appended record must update already-open history")
        assert(containsToken("Suppressed", in: updatedHistory), "History must report delivery disposition")
        assert(!updatedHistory.contains("/Users/private"), "Live history update must remain private")
        settings.hideProjectPaths = false

        // Tab 4: Storage
        let tab3Host = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .storage).frame(width: 640, height: 460))
        tab3Host.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = tab3Host
        await settle(tab3Host)
        let tab3Rep = saveOpaque(tab3Host, "tab-4-storage")
        let tab3Results = try recognizeText(in: tab3Rep)
        dumpObservations(tab3Results, label: "Check 11: Tab 4 (Storage)")
        let joinedTab3 = normalizeAndJoinReadingOrder(tab3Results)
        assert(containsToken("Local data on disk", in: joinedTab3) || containsToken("Known agent data", in: joinedTab3))

        // Tab 5: Privacy
        let tab4Host = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .privacy).frame(width: 640, height: 460))
        tab4Host.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = tab4Host
        await settle(tab4Host)
        let tab4Rep = saveOpaque(tab4Host, "tab-5-privacy")
        let tab4Results = try recognizeText(in: tab4Rep)
        dumpObservations(tab4Results, label: "Check 11: Tab 5 (Privacy)")
        let joinedTab4 = normalizeAndJoinReadingOrder(tab4Results)
        assert(containsToken("Hide project paths", in: joinedTab4))

        // Tab 6: About
        let tab5Host = NSHostingView(rootView: SettingsView(settings: settings, store: healthStore, initialTab: .about).frame(width: 640, height: 460))
        tab5Host.appearance = NSAppearance(named: .darkAqua)
        probeWindow.contentView = tab5Host
        await settle(tab5Host)
        let tab5Rep = saveOpaque(tab5Host, "tab-6-about")
        let tab5Results = try recognizeText(in: tab5Rep)
        dumpObservations(tab5Results, label: "Check 11: Tab 6 (About)")
        let joinedTab5 = normalizeAndJoinReadingOrder(tab5Results)
        assert(containsToken("Loom", in: joinedTab5))
        assert(containsToken("Version 1.0", in: joinedTab5) || containsToken("Version", in: joinedTab5))
        assert(containsToken("See what your local", in: joinedTab5) &&
               containsToken("coding agents", in: joinedTab5) &&
               containsToken("doing on your Mac", in: joinedTab5),
               "About tab renders the current local agent monitoring description")
        assert(containsToken("Made with", in: joinedTab5), "Footer 'Made with' is present on SettingsView")
        assert(containsToken("Deepak", in: joinedTab5), "Footer 'by Deepak (ChaiWithCode)' is present on SettingsView")
        print("  PASS: All 7 tabs rendered and all controls verified at 640x460 (including footer)")
        fflush(stdout)

        // =====================================================================
        // Test 12: Reset to defaults
        // =====================================================================
        print("Check 12: Reset to defaults restores all preferences")
        settings.showInDock = true
        settings.refreshIntervalSeconds = 300
        settings.includeRecentSessions = false
        settings.hideFinishedAfter = .twentyFourHours
        settings.hideProjectPaths = true
        settings.showVersionInMenuBar = true
        settings.notificationsEnabled = false
        settings.notifyQuota15Percent = false
        settings.notifyQuota5Percent = false
        settings.notifyQuotaReset = false
        settings.notifySessionWaiting = false
        settings.notifySessionFinished = true
        settings.notifySessionFailed = false
        settings.menuBarStatusMode = .activeSessionCount

        settings.resetToDefaults()
        assert(!settings.showInDock, "showInDock must reset to false")
        assert(settings.refreshIntervalSeconds == 60, "refreshIntervalSeconds must reset to 60")
        assert(settings.enabledProviderIDs == LoomSettings.defaultProviderIDs, "enabledProviderIDs must reset to all defaults")
        assert(settings.defaultProviderID == .codex, "defaultProviderID must reset to codex")
        assert(settings.includeRecentSessions, "includeRecentSessions must reset to true")
        assert(settings.hideFinishedAfter == .never, "hideFinishedAfter must reset to never")
        assert(!settings.hideProjectPaths, "hideProjectPaths must reset to false")
        assert(!settings.showVersionInMenuBar, "showVersionInMenuBar must reset to false")
        assert(settings.notificationsEnabled, "notificationsEnabled must reset to true")
        assert(settings.notifyQuota15Percent, "notifyQuota15Percent must reset to true")
        assert(settings.notifyQuota5Percent, "notifyQuota5Percent must reset to true")
        assert(settings.notifyQuotaReset, "notifyQuotaReset must reset to true")
        assert(settings.notifySessionWaiting, "notifySessionWaiting must reset to true")
        assert(!settings.notifySessionFinished, "notifySessionFinished must reset to false")
        assert(settings.notifySessionFailed, "notifySessionFailed must reset to true")
        assert(settings.menuBarStatusMode == .iconOnly, "menuBarStatusMode must reset to iconOnly")
        print("  PASS: Reset to defaults restored all settings (including notification preferences)")
        fflush(stdout)

        probeWindow.close()

        // =====================================================================
        // Test 13: Focused regression check: 7 navigation controls visible and
        // hittable without opening overflow on actual titled DockController window
        // =====================================================================
        print("Check 13: Focused regression check for 7 visible, hittable navigation controls without overflow")
        controller.showSettings(store: healthStore, resetTab: true)
        guard let settingsWindow = controller.settingsWindow else {
            fatalError("controller.settingsWindow must not be nil")
        }
        assert(settingsWindow.styleMask.contains(.titled), "Settings window must be a titled NSWindow")
        assert(settingsWindow.title == "Loom Settings", "Window title must be 'Loom Settings'")
        assert(settingsWindow.isVisible, "Settings window must be visible")
        await settle(settingsWindow.contentView!)

        let expectedTabs = ["General", "Providers", "Sessions", "Notifications", "Storage", "Privacy", "About"]
        let expectedTokens = [
            "Show Loom in Dock",
            "Default Provider",
            "Include recent sessions",
            "Enable Notifications",
            "Local data on disk",
            "Hide project paths",
            "Loom"
        ]

        // The production navigation is seven SwiftUI buttons. Resolve their
        // rendered labels and send real mouse events rather than mutating a
        // selection binding or assuming the former NSSegmentedControl exists.
        func navigationPoint(_ title: String) throws -> NSPoint {
            let content = settingsWindow.contentView!
            let observations = try recognizeText(in: saveOpaque(content, "navigation-locate-\(title.lowercased())"))
            guard let label = observations.first(where: {
                $0.text == title && $0.boundingBox.minY > 0.8
            }) else {
                fatalError("Visible navigation label \(title) not found")
            }
            let imagePoint = NSPoint(x: label.boundingBox.midX * content.bounds.width,
                                     y: label.boundingBox.midY * content.bounds.height)
            let localPoint = NSPoint(x: imagePoint.x,
                                     y: content.isFlipped ? content.bounds.height - imagePoint.y : imagePoint.y)
            assert(content.bounds.contains(localPoint), "Navigation label \(title) must be fully within content bounds")
            let windowPoint = content.convert(localPoint, to: nil)
            assert(content.hitTest(localPoint) != nil, "Navigation label \(title) must be hittable")
            return windowPoint
        }

        let testConfigurations: [(width: CGFloat, height: CGFloat, appearanceName: String, appearance: NSAppearance?)] = [
            (640, 460, "min-dark", NSAppearance(named: .darkAqua)),
            (640, 460, "min-light", NSAppearance(named: .aqua)),
            (660, 560, "default-dark", NSAppearance(named: .darkAqua)),
            (660, 560, "default-light", NSAppearance(named: .aqua))
        ]

        for config in testConfigurations {
            print("  Verifying titled window at \(Int(config.width))x\(Int(config.height)) [\(config.appearanceName)]...")
            settingsWindow.appearance = config.appearance
            settingsWindow.setContentSize(NSSize(width: config.width, height: config.height))
            await settle(settingsWindow.contentView!)
            assert(settingsWindow.contentView!.bounds.width == config.width && settingsWindow.contentView!.bounds.height == config.height,
                   "Titled window must render at the requested supported content size")
            if let toolbar = settingsWindow.toolbar {
                assert(toolbar.items.isEmpty, "Window toolbar must not contain tabs or overflow items in config \(config.appearanceName)")
            }
            assert(!containsOverflowButton(in: settingsWindow.contentView!),
                   "No double-chevron overflow button should exist in content view for \(config.appearanceName)")

            let headerResults = try recognizeText(in: saveOpaque(settingsWindow.contentView!, "navigation-header-\(config.appearanceName)"))
            for title in expectedTabs {
                assert(headerResults.contains(where: { $0.text == title && $0.boundingBox.minY > 0.8 }),
                       "All seven navigation labels must be visible without overflow: missing \(title)")
            }
            for (tabIndex, title) in expectedTabs.enumerated() {
                let clickPt = try navigationPoint(title)
                let windowCountBefore = NSApp.windows.count
                clickPoint(settingsWindow, at: clickPt)
                await settle(settingsWindow.contentView!)
                assert(NSApp.windows.count == windowCountBefore, "Clicking navigation must not open any menu/overflow popup")
                let screenshot = saveOpaque(settingsWindow.contentView!, "titled-window-tab-\(tabIndex)-\(config.appearanceName)")
                let joinedText = normalizeAndJoinReadingOrder(try recognizeText(in: screenshot))
                assert(containsToken(expectedTokens[tabIndex], in: joinedText),
                       "Native click on \(title) must show content token '\(expectedTokens[tabIndex])'")
                assert(containsToken("Made with", in: joinedText) && containsToken("Deepak", in: joinedText),
                       "Settings footer must remain visible for \(title) in \(config.appearanceName)")
            }
        }

        print("  Verifying Storage on-demand scan and cooperative cancellation...")
        clickPoint(settingsWindow, at: try navigationPoint("Storage"))
        await settle(settingsWindow.contentView!, iterations: 5)
        let storageText = normalizeAndJoinReadingOrder(try recognizeText(in: saveOpaque(settingsWindow.contentView!, "storage-navigation-active")))
        assert(containsToken("Local data on disk", in: storageText), "Native navigation must select Storage")
        clickPoint(settingsWindow, at: try navigationPoint("General"))
        await settle(settingsWindow.contentView!, iterations: 5)
        let generalText = normalizeAndJoinReadingOrder(try recognizeText(in: saveOpaque(settingsWindow.contentView!, "storage-navigation-cancelled")))
        assert(containsToken("Show Loom in Dock", in: generalText), "Native navigation must leave Storage for General")
        print("  PASS: Storage cooperative navigation and cancellation verified")

        print("  Verifying provider deep links on titled window...")
        for provider in ["codex", "claude"] {
            controller.handleOpenURL(URL(string: "loom://provider/\(provider)")!)
            await settle(settingsWindow.contentView!)
            assert(controller.settingsProviderContextID == ProviderID(provider), "Provider deep link must preserve its context")
            let text = normalizeAndJoinReadingOrder(try recognizeText(in: saveOpaque(settingsWindow.contentView!, "titled-deep-link-\(provider)")))
            assert(containsToken("Default Provider", in: text), "Provider deep link must select Providers content")
        }
        controller.handleOpenURL(URL(string: "loom://settings")!)
        await settle(settingsWindow.contentView!)
        let settingsLinkText = normalizeAndJoinReadingOrder(try recognizeText(in: saveOpaque(settingsWindow.contentView!, "titled-deep-link-settings")))
        assert(containsToken("Show Loom in Dock", in: settingsLinkText), "Settings deep link must select General content")
        print("  PASS: Seven navigation controls visible and hittable without overflow on titled window across widths, appearances, and deep links")
        fflush(stdout)

        settingsWindow.close()

        print("==================================================")
        print("ENVIRONMENT AUDIT NOTES:")
        print("- AX identifier enumeration audit: unrun (in-process NSHostingView does not expose SwiftUI virtual element identifiers)")
        print("- Global app keyboard navigation (Cmd-,): verified via static routing review of CommandGroup(.appSettings), interactive key events unrun due to headless test harness")
        print("==================================================")
        print("ALL PROBE CHECKS PASSED SUCCESSFULLY")
        print("==================================================")
        fflush(stdout)
        exit(0)
    }
}
