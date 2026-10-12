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
                existing.contentView = NSHostingView(rootView: SettingsView(settings: settings, store: targetStore))
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

    public func showSettings(store: SessionStore? = nil) {
        guard let settings else { return }

        let effectiveStore = store ?? configuredStore
        isSettingsWindowPresented = true
        updateActivationPolicy()

        if let existing = settingsWindow {
            if let store, store !== presentedStore {
                self.presentedStore = store
                existing.contentView = NSHostingView(rootView: SettingsView(settings: settings, store: store))
            }
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp?.activate(ignoringOtherApps: true)
            return
        }

        self.presentedStore = effectiveStore
        let contentView = SettingsView(settings: settings, store: effectiveStore)
        let minContentSize = NSSize(width: 480, height: 360)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 520, height: 420)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = minContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size
        window.center()
        window.title = "Loom Settings"
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

    @objc private func quitFromDock() {
        NSApp?.terminate(nil)
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
