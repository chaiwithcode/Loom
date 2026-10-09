//
//  LoomSettings.swift
//  Loom
//
//  Created by Deepak Sharma on 03/10/2026.
//  Copyright © 2026 ChaiWithCode. All rights reserved.
//

import Foundation
import Observation

@Observable
@MainActor
public final class LoomSettings {
    public static let showInDockKey = "com.loom.showInDock"
    public static let refreshIntervalKey = "com.loom.refreshIntervalSeconds"

    public static let defaultShowInDock = false
    public static let defaultRefreshIntervalSeconds = 60
    public static let supportedRefreshIntervals = [30, 60, 120, 300]

    private let defaults: UserDefaults
    public var onShowInDockChanged: (@MainActor (Bool) -> Void)?

    public var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: Self.showInDockKey)
            onShowInDockChanged?(showInDock)
        }
    }

    public var refreshIntervalSeconds: Int {
        didSet {
            let sanitized = Self.supportedRefreshIntervals.contains(refreshIntervalSeconds)
                ? refreshIntervalSeconds
                : Self.defaultRefreshIntervalSeconds
            if sanitized != refreshIntervalSeconds {
                refreshIntervalSeconds = sanitized
                return
            }
            defaults.set(sanitized, forKey: Self.refreshIntervalKey)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Self.showInDockKey) != nil {
            self.showInDock = defaults.bool(forKey: Self.showInDockKey)
        } else {
            self.showInDock = Self.defaultShowInDock
        }

        let storedInterval = defaults.integer(forKey: Self.refreshIntervalKey)
        if Self.supportedRefreshIntervals.contains(storedInterval) {
            self.refreshIntervalSeconds = storedInterval
        } else {
            self.refreshIntervalSeconds = Self.defaultRefreshIntervalSeconds
        }
    }

    public func resetToDefaults() {
        showInDock = Self.defaultShowInDock
        refreshIntervalSeconds = Self.defaultRefreshIntervalSeconds
    }
}
