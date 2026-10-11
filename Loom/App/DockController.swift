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
    private weak var settingsWindow: NSWindow?
    private weak var configuredStore: SessionStore?
    private var refreshAction: (@MainActor () -> Void)?

    public func configure(settings: LoomSettings, store: SessionStore? = nil, onRefresh: (@MainActor () -> Void)? = nil) {
        self.settings = settings
        self.configuredStore = store
        self.refreshAction = onRefresh

        settings.onShowInDockChanged = { [weak self] _ in
            self?.updateActivationPolicy()
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
        isSettingsWindowPresented = true
        updateActivationPolicy()

        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp?.activate(ignoringOtherApps: true)
            return
        }

        guard let settings else { return }

        let contentView = SettingsView(settings: settings, store: store ?? configuredStore)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 512, height: 382),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
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

    @objc private func openSettingsFromDock() {
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
        if (notification.object as? NSWindow) == settingsWindow {
            isSettingsWindowPresented = false
            updateActivationPolicy()
        }
    }
}
