//
//  LoomApp.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
import LoomCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DockController.shared.updateActivationPolicy()
        if ProcessInfo.processInfo.arguments.contains("--show-settings") && DemoFixture.resolve().isDemo {
            DockController.shared.showSettings()
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        DockController.shared.buildDockMenu()
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
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(store: store, settings: settings)
        } label: {
            Image(nsImage: LoomIcon.menuBarImage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, store: store)
        }
    }
}
