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
