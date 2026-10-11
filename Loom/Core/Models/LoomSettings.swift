//
//  LoomSettings.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
import Observation

public enum HideFinishedInterval: String, CaseIterable, Identifiable, Sendable {
    case never = "never"
    case oneHour = "1h"
    case twentyFourHours = "24h"
    case sevenDays = "7d"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .never: return "Never (default)"
        case .oneHour: return "1 hour"
        case .twentyFourHours: return "24 hours"
        case .sevenDays: return "7 days"
        }
    }

    public var timeInterval: TimeInterval? {
        switch self {
        case .never: return nil
        case .oneHour: return 3600
        case .twentyFourHours: return 86400
        case .sevenDays: return 604800
        }
    }
}

@Observable
@MainActor
public final class LoomSettings {
    public static let showInDockKey = "com.loom.showInDock"
    public static let refreshIntervalKey = "com.loom.refreshIntervalSeconds"
    public static let enabledProviderIDsKey = "com.loom.enabledProviderIDs"
    public static let defaultProviderIDKey = "com.loom.defaultProviderID"
    public static let includeRecentSessionsKey = "com.loom.includeRecentSessions"
    public static let hideFinishedAfterKey = "com.loom.hideFinishedAfter"
    public static let hideProjectPathsKey = "com.loom.hideProjectPaths"

    public static let defaultShowInDock = false
    public static let defaultRefreshIntervalSeconds = 60
    public static let supportedRefreshIntervals = [30, 60, 120, 300]
    public static let defaultProviderIDs: Set<ProviderID> = [.codex, .claude, .antigravity]
    public static let defaultProviderID: ProviderID = .codex
    public static let defaultIncludeRecentSessions = true
    public static let defaultHideFinishedAfter: HideFinishedInterval = .never
    public static let defaultHideProjectPaths = false

    private let defaults: UserDefaults

    public var onShowInDockChanged: (@MainActor (Bool) -> Void)?
    @ObservationIgnored public var onRefreshIntervalChanged: (@MainActor (Int) -> Void)?
    public var onEnabledProvidersChanged: (@MainActor (Set<ProviderID>) -> Void)?
    public var onDefaultProviderChanged: (@MainActor (ProviderID) -> Void)?
    public var onIncludeRecentSessionsChanged: (@MainActor (Bool) -> Void)?
    public var onHideFinishedAfterChanged: (@MainActor (HideFinishedInterval) -> Void)?
    public var onHideProjectPathsChanged: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private var isNormalizingRefreshInterval = false
    @ObservationIgnored private var isNormalizingDefaultProvider = false

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

    public var enabledProviderIDs: Set<ProviderID> {
        didSet {
            let valid = enabledProviderIDs.filter { Self.defaultProviderIDs.contains($0) }
            if valid != enabledProviderIDs {
                enabledProviderIDs = valid
                return
            }
            let rawList = Array(enabledProviderIDs.map(\.rawValue)).sorted()
            defaults.set(rawList, forKey: Self.enabledProviderIDsKey)
            if enabledProviderIDs != oldValue {
                onEnabledProvidersChanged?(enabledProviderIDs)
            }
        }
    }

    public var defaultProviderID: ProviderID {
        didSet {
            guard !isNormalizingDefaultProvider else { return }
            let sanitized = Self.defaultProviderIDs.contains(defaultProviderID)
                ? defaultProviderID
                : Self.defaultProviderID
            if sanitized != defaultProviderID {
                isNormalizingDefaultProvider = true
                defaultProviderID = sanitized
                isNormalizingDefaultProvider = false
            }
            defaults.set(sanitized.rawValue, forKey: Self.defaultProviderIDKey)
            if sanitized != oldValue {
                onDefaultProviderChanged?(sanitized)
            }
        }
    }

    public var includeRecentSessions: Bool {
        didSet {
            defaults.set(includeRecentSessions, forKey: Self.includeRecentSessionsKey)
            if includeRecentSessions != oldValue {
                onIncludeRecentSessionsChanged?(includeRecentSessions)
            }
        }
    }

    public var hideFinishedAfter: HideFinishedInterval {
        didSet {
            defaults.set(hideFinishedAfter.rawValue, forKey: Self.hideFinishedAfterKey)
            if hideFinishedAfter != oldValue {
                onHideFinishedAfterChanged?(hideFinishedAfter)
            }
        }
    }

    public var hideProjectPaths: Bool {
        didSet {
            defaults.set(hideProjectPaths, forKey: Self.hideProjectPathsKey)
            if hideProjectPaths != oldValue {
                onHideProjectPathsChanged?(hideProjectPaths)
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // showInDock: validate boolean type
        if let num = defaults.object(forKey: Self.showInDockKey) as? NSNumber {
            self.showInDock = num.boolValue
        } else {
            self.showInDock = Self.defaultShowInDock
        }

        // refreshIntervalSeconds: validate integer
        let storedInterval = defaults.integer(forKey: Self.refreshIntervalKey)
        if Self.supportedRefreshIntervals.contains(storedInterval) {
            self.refreshIntervalSeconds = storedInterval
        } else {
            self.refreshIntervalSeconds = Self.defaultRefreshIntervalSeconds
        }

        // enabledProviderIDs:
        // empty saved array legitimately disables all
        // nonempty entirely invalid list should restore defaults
        // mixed valid/invalid keeps valid
        if let rawArray = defaults.object(forKey: Self.enabledProviderIDsKey) as? [String] {
            if rawArray.isEmpty {
                self.enabledProviderIDs = []
            } else {
                let validIDs = Set(rawArray.compactMap { raw -> ProviderID? in
                    let pid = ProviderID(raw)
                    return Self.defaultProviderIDs.contains(pid) ? pid : nil
                })
                if validIDs.isEmpty {
                    self.enabledProviderIDs = Self.defaultProviderIDs
                } else {
                    self.enabledProviderIDs = validIDs
                }
            }
        } else {
            self.enabledProviderIDs = Self.defaultProviderIDs
        }

        // defaultProviderID: invalid restores Codex
        if let rawDefault = defaults.string(forKey: Self.defaultProviderIDKey) {
            let candidate = ProviderID(rawDefault)
            if Self.defaultProviderIDs.contains(candidate) {
                self.defaultProviderID = candidate
            } else {
                self.defaultProviderID = Self.defaultProviderID
            }
        } else {
            self.defaultProviderID = Self.defaultProviderID
        }

        // includeRecentSessions: validate boolean type, default true
        if let num = defaults.object(forKey: Self.includeRecentSessionsKey) as? NSNumber {
            self.includeRecentSessions = num.boolValue
        } else {
            self.includeRecentSessions = Self.defaultIncludeRecentSessions
        }

        // hideFinishedAfter
        if let storedHideStr = defaults.string(forKey: Self.hideFinishedAfterKey),
           let interval = HideFinishedInterval(rawValue: storedHideStr) {
            self.hideFinishedAfter = interval
        } else {
            self.hideFinishedAfter = Self.defaultHideFinishedAfter
        }

        // hideProjectPaths: validate boolean type, default false
        if let num = defaults.object(forKey: Self.hideProjectPathsKey) as? NSNumber {
            self.hideProjectPaths = num.boolValue
        } else {
            self.hideProjectPaths = Self.defaultHideProjectPaths
        }
    }

    public func isProviderEnabled(_ providerID: ProviderID) -> Bool {
        enabledProviderIDs.contains(providerID)
    }

    public func setProvider(_ providerID: ProviderID, enabled: Bool) {
        var current = enabledProviderIDs
        if enabled {
            if Self.defaultProviderIDs.contains(providerID) {
                current.insert(providerID)
            }
        } else {
            current.remove(providerID)
        }
        enabledProviderIDs = current
    }

    public func effectiveDefaultProvider(among available: [ProviderID]) -> ProviderID? {
        if available.contains(defaultProviderID) && isProviderEnabled(defaultProviderID) {
            return defaultProviderID
        }
        return available.first(where: { isProviderEnabled($0) }) ?? available.first
    }

    public func resetToDefaults() {
        showInDock = Self.defaultShowInDock
        refreshIntervalSeconds = Self.defaultRefreshIntervalSeconds
        enabledProviderIDs = Self.defaultProviderIDs
        defaultProviderID = Self.defaultProviderID
        includeRecentSessions = Self.defaultIncludeRecentSessions
        hideFinishedAfter = Self.defaultHideFinishedAfter
        hideProjectPaths = Self.defaultHideProjectPaths
    }

    public static func isSessionActive(_ session: AgentSession) -> Bool {
        switch session.state {
        case .working, .starting, .waiting:
            return true
        case .unknown:
            // Conservative keep: never hide an unknown session solely because state is uncertain
            return true
        case .idle:
            // Idle with positive process evidence is active
            return session.processCount > 0
        case .finished, .failed:
            return false
        }
    }

    public func shouldInclude(session: AgentSession, now: Date = Date()) -> Bool {
        let isActive = Self.isSessionActive(session)
        if !includeRecentSessions {
            return isActive
        }
        if isActive {
            return true
        }
        // Finished terminal session retention uses ONLY lastActivityAt:
        // startedAt is NOT completion evidence, so a finished session with nil
        // lastActivityAt remains visible even if startedAt is old.
        if session.state == .finished {
            guard let cutoff = hideFinishedAfter.timeInterval else {
                return true
            }
            guard let lastActivity = session.lastActivityAt else {
                // Missing lastActivityAt: kept rather than guessing
                return true
            }
            let age = now.timeIntervalSince(lastActivity)
            return age <= cutoff
        }
        return true
    }

    public static func safeProjectName(for session: AgentSession, hidePaths: Bool) -> String {
        let raw = session.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = session.projectPath?.lastPathComponent ?? "Untitled Project"
        let candidate = (raw == nil || raw!.isEmpty) ? fallback : raw!
        if hidePaths {
            if candidate.contains("/") || candidate.contains("~") {
                let last = URL(fileURLWithPath: candidate).lastPathComponent
                return last.isEmpty ? "Project" : last
            }
        }
        return candidate
    }
}
