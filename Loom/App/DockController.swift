//
//  DockController.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import AppKit
import SwiftUI
import LoomCore

@MainActor
public final class DockController: NSObject, NSApplicationDelegate {
    public static let shared = DockController()

    public private(set) var settings: LoomSettings?
    public private(set) var isSettingsWindowPresented: Bool = false
    public private(set) var settingsWindow: NSWindow?
    public private(set) var settingsProviderContextID: ProviderID?
    private weak var configuredStore: SessionStore?
    private weak var presentedStore: SessionStore?
    private var refreshAction: (@MainActor () -> Void)?

    public override init() {
        super.init()
    }

    public func configure(settings: LoomSettings, store: SessionStore? = nil, onRefresh: (@MainActor () -> Void)? = nil) {
        let settingsChanged = self.settings !== settings
        self.settings = settings
        self.configuredStore = store
        self.refreshAction = onRefresh

        settings.onShowInDockChanged = { [weak self] _ in
            self?.updateActivationPolicy()
        }

        if let existing = settingsWindow {
            let targetStore = store ?? configuredStore
            if settingsChanged || targetStore !== presentedStore {
                self.presentedStore = targetStore
                existing.contentView = NSHostingView(rootView: SettingsView(
                    settings: settings,
                    store: targetStore,
                    initialTab: settingsProviderContextID != nil ? .providers : .general,
                    initialProviderID: settingsProviderContextID
                ))
            }
        }

        if NSApp != nil {
            updateActivationPolicy()
        }
    }

    public func updateActivationPolicy() {
        guard let settings else { return }
        guard let app = NSApp else { return }

        let shouldShowInDock = settings.showInDock || isSettingsWindowPresented
        let targetPolicy: NSApplication.ActivationPolicy = shouldShowInDock ? .regular : .accessory

        if app.activationPolicy() != targetPolicy {
            app.setActivationPolicy(targetPolicy)
        }

        if shouldShowInDock {
            app.activate(ignoringOtherApps: true)
        }
    }

    public func showSettings(store: SessionStore? = nil, tab: SettingsTab? = nil, providerID: ProviderID? = nil, resetTab: Bool = false) {
        guard let settings else { return }
        if let providerID, !LoomSettings.defaultProviderIDs.contains(providerID) { return }

        let effectiveStore = store ?? configuredStore
        let effectiveTab = providerID != nil ? SettingsTab.providers : (tab ?? .general)
        let contextChanged = settingsProviderContextID != providerID || tab != nil || resetTab
        settingsProviderContextID = providerID
        isSettingsWindowPresented = true
        updateActivationPolicy()

        if let existing = settingsWindow {
            let storeChanged = store != nil && store !== presentedStore
            if contextChanged || storeChanged {
                self.presentedStore = effectiveStore
                existing.contentView = NSHostingView(rootView: SettingsView(
                    settings: settings,
                    store: effectiveStore,
                    initialTab: effectiveTab,
                    initialProviderID: providerID
                ))
            }
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp?.activate(ignoringOtherApps: true)
            return
        }

        self.presentedStore = effectiveStore
        let contentView = SettingsView(
            settings: settings,
            store: effectiveStore,
            initialTab: effectiveTab,
            initialProviderID: providerID
        )
        let minContentSize = NSSize(width: 480, height: 360)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 520, height: 460)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = minContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size
        window.center()
        window.title = "Loom Settings"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp?.activate(ignoringOtherApps: true)
    }

    public func buildDockMenu() -> NSMenu {
        let menu = NSMenu(title: "Loom Dock Menu")

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromDock), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshFromDock), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromDock), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = UpdateController.shared.canCheckForUpdates
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Loom", action: #selector(quitFromDock), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc public func openSettingsFromDock() {
        showSettings()
    }

    @objc private func refreshFromDock() {
        refreshAction?()
    }

    @objc private func checkForUpdatesFromDock() {
        UpdateController.shared.checkForUpdates()
    }

    @objc private func quitFromDock() {
        NSApp?.terminate(nil)
    }

    @discardableResult
    public func handleReopen(hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showSettings()
        }
        return true
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        handleReopen(hasVisibleWindows: flag)
    }

    public func handleOpenURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "loom",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return }
        let host = components.host?.lowercased() ?? ""
        switch host {
        case "settings":
            guard components.path.isEmpty else { return }
            showSettings(resetTab: true)
        case "provider":
            let path = components.path
            guard components.percentEncodedPath == path,
                  path.hasPrefix("/"), path.count > 1,
                  !path.dropFirst().contains("/"),
                  LoomSettings.defaultProviderIDs.contains(ProviderID(String(path.dropFirst()))) else { return }
            showSettings(providerID: ProviderID(String(path.dropFirst())), resetTab: true)
        case "refresh":
            guard components.path.isEmpty else { return }
            refreshAction?()
            NSApp?.activate(ignoringOtherApps: true)
        case "open", "":
            guard components.path.isEmpty else { return }
            NSApp?.activate(ignoringOtherApps: true)
        default:
            return
        }
    }
}

extension DockController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            isSettingsWindowPresented = false
            updateActivationPolicy()
        }
    }
}
