//
//  LoomSettings.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
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
    @ObservationIgnored public var onRefreshIntervalChanged: (@MainActor (Int) -> Void)?
    @ObservationIgnored private var isNormalizingRefreshInterval = false

    public var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: Self.showInDockKey)
            onShowInDockChanged?(showInDock)
        }
    }

    public var refreshIntervalSeconds: Int {
        didSet {
            guard !isNormalizingRefreshInterval else { return }
            let sanitized = Self.supportedRefreshIntervals.contains(refreshIntervalSeconds)
                ? refreshIntervalSeconds
                : Self.defaultRefreshIntervalSeconds
            if sanitized != refreshIntervalSeconds {
                isNormalizingRefreshInterval = true
                refreshIntervalSeconds = sanitized
                isNormalizingRefreshInterval = false
            }
            defaults.set(sanitized, forKey: Self.refreshIntervalKey)
            if sanitized != oldValue {
                onRefreshIntervalChanged?(sanitized)
            }
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
