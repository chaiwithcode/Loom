//
//  UpdateController.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import AppKit
import Foundation
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

/// Manages application update checking and Sparkle 2 updater lifecycle.
/// Isolates Sparkle APIs from the rest of the application.
@MainActor
public final class UpdateController: NSObject, ObservableObject {
    public static let shared = UpdateController()

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    #endif

    @Published public private(set) var canCheckForUpdates: Bool = false

    public override init() {
        super.init()
        #if canImport(Sparkle)
        let isConfiguredBundle = Bundle.main.bundleIdentifier != nil && Bundle.main.infoDictionary?["SUFeedURL"] != nil
        if isConfiguredBundle {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
            self.updaterController = controller
            self.canCheckForUpdates = controller.updater.canCheckForUpdates

            controller.updater.addObserver(
                self,
                forKeyPath: "canCheckForUpdates",
                options: [.new],
                context: nil
            )
        } else {
            self.canCheckForUpdates = false
        }
        #else
        self.canCheckForUpdates = false
        #endif
    }

    #if canImport(Sparkle)
    nonisolated public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "canCheckForUpdates" {
            Task { @MainActor in
                self.canCheckForUpdates = self.updaterController?.updater.canCheckForUpdates ?? false
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    #endif

    /// Whether Sparkle is configured to automatically check for updates.
    public var automaticallyChecksForUpdates: Bool {
        get {
            #if canImport(Sparkle)
            return updaterController?.updater.automaticallyChecksForUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            updaterController?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
            #endif
        }
    }

    /// Whether Sparkle is configured to automatically download updates in the background.
    public var automaticallyDownloadsUpdates: Bool {
        get {
            #if canImport(Sparkle)
            return updaterController?.updater.automaticallyDownloadsUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            updaterController?.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
            #endif
        }
    }

    /// Triggers a user-initiated update check via Sparkle.
    public func checkForUpdates() {
        #if canImport(Sparkle)
        guard let updater = updaterController?.updater, updater.canCheckForUpdates else { return }
        NSApp?.activate(ignoringOtherApps: true)
        updater.checkForUpdates()
        #endif
    }
}

#if canImport(Sparkle)
extension UpdateController: SPUUpdaterDelegate {
    // Delegate hooks for custom feed inspection or logging if needed
}
#endif
