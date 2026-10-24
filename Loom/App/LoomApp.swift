//
//  LoomApp.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
import UserNotifications
import LoomCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = NotificationCoordinator.shared
        DockController.shared.updateActivationPolicy()
        let fixture = DemoFixture.resolve()
        if let demoAlert = DemoAlertScenario.resolve(
            arguments: ProcessInfo.processInfo.arguments,
            fixture: fixture
        ) {
            Task { @MainActor in
                await Self.postDemoAlert(demoAlert)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-settings") && fixture.isDemo {
            DockController.shared.showSettings()
        }
        if !fixture.isDemo {
            Task { @MainActor in
                guard let settings = DockController.shared.settings,
                      settings.notificationsEnabled else { return }
                let coordinator = NotificationCoordinator.shared
                guard await coordinator.checkAuthorizationStatus() == .notDetermined,
                      settings.notificationsEnabled else { return }
                _ = await coordinator.requestAuthorization()
            }
        }
    }

    @MainActor
    private static func postDemoAlert(_ scenario: DemoAlertScenario) async {
        guard let settings = DockController.shared.settings, settings.notificationsEnabled else {
            NSLog("Loom demo alert was not sent: notifications are disabled in Loom settings.")
            return
        }

        let coordinator = NotificationCoordinator.shared
        let status = await coordinator.checkAuthorizationStatus()
        if status == .notDetermined {
            guard await coordinator.requestAuthorization() else {
                NSLog("Loom demo alert was not sent: notification authorization was not granted.")
                return
            }
        } else if status != .authorized && status != .provisional {
            NSLog("Loom demo alert was not sent: notifications are disabled in System Settings.")
            return
        }

        do {
            try await Task.sleep(for: .seconds(3))
            let formatted = NotificationPolicy().formatNotification(for: scenario.event)
            try await coordinator.postNotification(
                title: formatted.title,
                subtitle: "Demo · \(scenario.windowName)",
                body: formatted.body,
                targetTab: "usage",
                providerID: formatted.provider,
                eventType: "demo"
            )
        } catch {
            NSLog("Loom demo alert failed: %@", String(describing: error))
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        DockController.shared.buildDockMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockController.shared.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DockController.shared.handleOpenURL(url)
        }
    }
}

private struct DemoAlertScenario {
    let event: MonitoringEvent
    let windowName: String

    static func resolve(arguments: [String], fixture: DemoFixture) -> DemoAlertScenario? {
        guard fixture == .mock,
              let optionIndex = arguments.firstIndex(of: "--demo-alert"),
              arguments.indices.contains(optionIndex + 1) else { return nil }

        switch arguments[optionIndex + 1] {
        case "codex-warning":
            return quotaScenario(provider: .codex, remainingPercent: 12, threshold: .fifteenPercent, windowName: "5-hour window")
        case "codex-critical":
            return quotaScenario(provider: .codex, remainingPercent: 3, threshold: .fivePercent, windowName: "5-hour window")
        case "antigravity-warning":
            return quotaScenario(provider: .antigravity, remainingPercent: 12, threshold: .fifteenPercent, windowName: "Weekly window")
        case "antigravity-critical":
            return quotaScenario(provider: .antigravity, remainingPercent: 3, threshold: .fivePercent, windowName: "Weekly window")
        case "codex-reset":
            return resetScenario(provider: .codex, windowName: "5-hour window")
        case "antigravity-reset":
            return resetScenario(provider: .antigravity, windowName: "Weekly window")
        default:
            NSLog("Loom demo alert ignored: expected codex-warning, codex-critical, antigravity-warning, antigravity-critical, codex-reset, or antigravity-reset after --demo-alert.")
            return nil
        }
    }

    private static func quotaScenario(
        provider: ProviderID,
        remainingPercent: Double,
        threshold: QuotaThreshold,
        windowName: String
    ) -> DemoAlertScenario {
        DemoAlertScenario(
            event: .quotaThresholdCrossed(
                provider: provider,
                bucket: windowName,
                remainingPercent: remainingPercent,
                windowId: windowName,
                threshold: threshold
            ),
            windowName: windowName
        )
    }

    private static func resetScenario(provider: ProviderID, windowName: String) -> DemoAlertScenario {
        DemoAlertScenario(
            event: .quotaReplenished(provider: provider, bucket: windowName, windowId: windowName),
            windowName: windowName
        )
    }
}

@main
struct LoomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: SessionStore
    @State private var settings = LoomSettings()

    init() {
        let fixture = DemoFixture.resolve()
        let providers = fixture.makeProviders()
        let initialSettings = LoomSettings()
        let initialStore = SessionStore(
            providers: providers,
            fixture: fixture,
            enabledProviderIDs: initialSettings.enabledProviderIDs
        )
        initialStore.startPeriodicRefresh(interval: TimeInterval(initialSettings.refreshIntervalSeconds))
        initialSettings.onRefreshIntervalChanged = { [weak initialStore] interval in
            initialStore?.startPeriodicRefresh(interval: TimeInterval(interval))
        }
        initialSettings.onEnabledProvidersChanged = { [weak initialStore] enabledIDs in
            initialStore?.updateEnabledProviders(enabledIDs)
        }
        _store = State(initialValue: initialStore)
        _settings = State(initialValue: initialSettings)

        DockController.shared.configure(settings: initialSettings, store: initialStore) { [weak initialStore] in
            Task { @MainActor in
                await initialStore?.refresh()
            }
        }

        let coordinator = NotificationCoordinator.shared
        coordinator.configure(settings: initialSettings, store: initialStore)
        coordinator.setupCategories()
        UNUserNotificationCenter.current().delegate = coordinator
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(store: store, settings: settings)
        } label: {
            MenuBarStatusLabel(store: store, settings: settings)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    DockController.shared.showSettings(store: store)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateController.shared.checkForUpdates()
                }
                .disabled(!UpdateController.shared.canCheckForUpdates)
            }
        }
    }
}
