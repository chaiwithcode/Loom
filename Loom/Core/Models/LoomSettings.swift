//
//  LoomSettings.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
import Observation

extension ProviderID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

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

public enum MenuBarStatusMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case iconOnly = "iconOnly"
    case activeSessionCount = "activeSessionCount"
    case lowestQuota = "lowestQuota"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .iconOnly: return "Icon Only"
        case .activeSessionCount: return "Active Sessions"
        case .lowestQuota: return "Lowest Quota"
        }
    }
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var notificationsEnabled: Bool
    public var notifyQuota15Percent: Bool
    public var notifyQuota5Percent: Bool
    public var notifyQuotaReset: Bool
    public var notifySessionWaiting: Bool
    public var notifySessionFinished: Bool
    public var notifySessionFailed: Bool
    public var menuBarStatusMode: MenuBarStatusMode

    public init(
        notificationsEnabled: Bool = LoomSettings.defaultNotificationsEnabled,
        notifyQuota15Percent: Bool = LoomSettings.defaultNotifyQuota15Percent,
        notifyQuota5Percent: Bool = LoomSettings.defaultNotifyQuota5Percent,
        notifyQuotaReset: Bool = LoomSettings.defaultNotifyQuotaReset,
        notifySessionWaiting: Bool = LoomSettings.defaultNotifySessionWaiting,
        notifySessionFinished: Bool = LoomSettings.defaultNotifySessionFinished,
        notifySessionFailed: Bool = LoomSettings.defaultNotifySessionFailed,
        menuBarStatusMode: MenuBarStatusMode = LoomSettings.defaultMenuBarStatusMode
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.notifyQuota15Percent = notifyQuota15Percent
        self.notifyQuota5Percent = notifyQuota5Percent
        self.notifyQuotaReset = notifyQuotaReset
        self.notifySessionWaiting = notifySessionWaiting
        self.notifySessionFinished = notifySessionFinished
        self.notifySessionFailed = notifySessionFailed
        self.menuBarStatusMode = menuBarStatusMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? LoomSettings.defaultNotificationsEnabled
        self.notifyQuota15Percent = try container.decodeIfPresent(Bool.self, forKey: .notifyQuota15Percent) ?? LoomSettings.defaultNotifyQuota15Percent
        self.notifyQuota5Percent = try container.decodeIfPresent(Bool.self, forKey: .notifyQuota5Percent) ?? LoomSettings.defaultNotifyQuota5Percent
        self.notifyQuotaReset = try container.decodeIfPresent(Bool.self, forKey: .notifyQuotaReset) ?? LoomSettings.defaultNotifyQuotaReset
        self.notifySessionWaiting = try container.decodeIfPresent(Bool.self, forKey: .notifySessionWaiting) ?? LoomSettings.defaultNotifySessionWaiting
        self.notifySessionFinished = try container.decodeIfPresent(Bool.self, forKey: .notifySessionFinished) ?? LoomSettings.defaultNotifySessionFinished
        self.notifySessionFailed = try container.decodeIfPresent(Bool.self, forKey: .notifySessionFailed) ?? LoomSettings.defaultNotifySessionFailed
        self.menuBarStatusMode = try container.decodeIfPresent(MenuBarStatusMode.self, forKey: .menuBarStatusMode) ?? LoomSettings.defaultMenuBarStatusMode
    }
}

@Observable
@MainActor
public final class LoomSettings {
    public nonisolated static let showInDockKey = "com.loom.showInDock"
    public nonisolated static let refreshIntervalKey = "com.loom.refreshIntervalSeconds"
    public nonisolated static let enabledProviderIDsKey = "com.loom.enabledProviderIDs"
    public nonisolated static let defaultProviderIDKey = "com.loom.defaultProviderID"
    public nonisolated static let includeRecentSessionsKey = "com.loom.includeRecentSessions"
    public nonisolated static let hideFinishedAfterKey = "com.loom.hideFinishedAfter"
    public nonisolated static let hideProjectPathsKey = "com.loom.hideProjectPaths"
    public nonisolated static let showVersionInMenuBarKey = "com.loom.showVersionInMenuBar"

    public nonisolated static let notificationsEnabledKey = "com.loom.notificationsEnabled"
    public nonisolated static let notifyQuota15PercentKey = "com.loom.notifyQuota15Percent"
    public nonisolated static let notifyQuota5PercentKey = "com.loom.notifyQuota5Percent"
    public nonisolated static let notifyQuotaResetKey = "com.loom.notifyQuotaReset"
    public nonisolated static let notifySessionWaitingKey = "com.loom.notifySessionWaiting"
    public nonisolated static let notifySessionFinishedKey = "com.loom.notifySessionFinished"
    public nonisolated static let notifySessionFailedKey = "com.loom.notifySessionFailed"
    public nonisolated static let menuBarStatusModeKey = "com.loom.menuBarStatusMode"

    public nonisolated static let defaultShowInDock = false
    public nonisolated static let defaultRefreshIntervalSeconds = 60
    public nonisolated static let supportedRefreshIntervals = [30, 60, 120, 300]
    public nonisolated static let defaultProviderIDs: Set<ProviderID> = [.codex, .claude, .antigravity]
    public nonisolated static let defaultProviderID: ProviderID = .codex
    public nonisolated static let defaultIncludeRecentSessions = true
    public nonisolated static let defaultHideFinishedAfter: HideFinishedInterval = .never
    public nonisolated static let defaultHideProjectPaths = false
    public nonisolated static let defaultShowVersionInMenuBar = false

    public nonisolated static let defaultNotificationsEnabled: Bool = true
    public nonisolated static let defaultNotifyQuota15Percent: Bool = true
    public nonisolated static let defaultNotifyQuota5Percent: Bool = true
    public nonisolated static let defaultNotifyQuotaReset: Bool = true
    public nonisolated static let defaultNotifySessionWaiting: Bool = true
    public nonisolated static let defaultNotifySessionFinished: Bool = false
    public nonisolated static let defaultNotifySessionFailed: Bool = true
    public nonisolated static let defaultMenuBarStatusMode: MenuBarStatusMode = .iconOnly

    private let defaults: UserDefaults

    public var onShowInDockChanged: (@MainActor (Bool) -> Void)?
    @ObservationIgnored public var onRefreshIntervalChanged: (@MainActor (Int) -> Void)?
    public var onEnabledProvidersChanged: (@MainActor (Set<ProviderID>) -> Void)?
    public var onDefaultProviderChanged: (@MainActor (ProviderID) -> Void)?
    public var onIncludeRecentSessionsChanged: (@MainActor (Bool) -> Void)?
    public var onHideFinishedAfterChanged: (@MainActor (HideFinishedInterval) -> Void)?
    public var onHideProjectPathsChanged: (@MainActor (Bool) -> Void)?
    public var onShowVersionInMenuBarChanged: (@MainActor (Bool) -> Void)?

    public var onNotificationsEnabledChanged: (@MainActor (Bool) -> Void)?
    public var onNotifyQuota15PercentChanged: (@MainActor (Bool) -> Void)?
    public var onNotifyQuota5PercentChanged: (@MainActor (Bool) -> Void)?
    public var onNotifyQuotaResetChanged: (@MainActor (Bool) -> Void)?
    public var onNotifySessionWaitingChanged: (@MainActor (Bool) -> Void)?
    public var onNotifySessionFinishedChanged: (@MainActor (Bool) -> Void)?
    public var onNotifySessionFailedChanged: (@MainActor (Bool) -> Void)?
    public var onMenuBarStatusModeChanged: (@MainActor (MenuBarStatusMode) -> Void)?

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

    public var showVersionInMenuBar: Bool {
        didSet {
            defaults.set(showVersionInMenuBar, forKey: Self.showVersionInMenuBarKey)
            if showVersionInMenuBar != oldValue {
                onShowVersionInMenuBarChanged?(showVersionInMenuBar)
            }
        }
    }

    public var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: Self.notificationsEnabledKey)
            persistToSharedAppGroup()
            if notificationsEnabled != oldValue {
                onNotificationsEnabledChanged?(notificationsEnabled)
            }
        }
    }

    public var notifyQuota15Percent: Bool {
        didSet {
            defaults.set(notifyQuota15Percent, forKey: Self.notifyQuota15PercentKey)
            persistToSharedAppGroup()
            if notifyQuota15Percent != oldValue {
                onNotifyQuota15PercentChanged?(notifyQuota15Percent)
            }
        }
    }

    public var notifyQuota5Percent: Bool {
        didSet {
            defaults.set(notifyQuota5Percent, forKey: Self.notifyQuota5PercentKey)
            persistToSharedAppGroup()
            if notifyQuota5Percent != oldValue {
                onNotifyQuota5PercentChanged?(notifyQuota5Percent)
            }
        }
    }

    public var notifyQuotaReset: Bool {
        didSet {
            defaults.set(notifyQuotaReset, forKey: Self.notifyQuotaResetKey)
            persistToSharedAppGroup()
            if notifyQuotaReset != oldValue {
                onNotifyQuotaResetChanged?(notifyQuotaReset)
            }
        }
    }

    public var notifySessionWaiting: Bool {
        didSet {
            defaults.set(notifySessionWaiting, forKey: Self.notifySessionWaitingKey)
            persistToSharedAppGroup()
            if notifySessionWaiting != oldValue {
                onNotifySessionWaitingChanged?(notifySessionWaiting)
            }
        }
    }

    public var notifySessionFinished: Bool {
        didSet {
            defaults.set(notifySessionFinished, forKey: Self.notifySessionFinishedKey)
            persistToSharedAppGroup()
            if notifySessionFinished != oldValue {
                onNotifySessionFinishedChanged?(notifySessionFinished)
            }
        }
    }

    public var notifySessionFailed: Bool {
        didSet {
            defaults.set(notifySessionFailed, forKey: Self.notifySessionFailedKey)
            persistToSharedAppGroup()
            if notifySessionFailed != oldValue {
                onNotifySessionFailedChanged?(notifySessionFailed)
            }
        }
    }

    public var menuBarStatusMode: MenuBarStatusMode {
        didSet {
            defaults.set(menuBarStatusMode.rawValue, forKey: Self.menuBarStatusModeKey)
            persistToSharedAppGroup()
            if menuBarStatusMode != oldValue {
                onMenuBarStatusModeChanged?(menuBarStatusMode)
            }
        }
    }

    public var notificationPreferences: NotificationPreferences {
        get {
            NotificationPreferences(
                notificationsEnabled: notificationsEnabled,
                notifyQuota15Percent: notifyQuota15Percent,
                notifyQuota5Percent: notifyQuota5Percent,
                notifyQuotaReset: notifyQuotaReset,
                notifySessionWaiting: notifySessionWaiting,
                notifySessionFinished: notifySessionFinished,
                notifySessionFailed: notifySessionFailed,
                menuBarStatusMode: menuBarStatusMode
            )
        }
        set {
            notificationsEnabled = newValue.notificationsEnabled
            notifyQuota15Percent = newValue.notifyQuota15Percent
            notifyQuota5Percent = newValue.notifyQuota5Percent
            notifyQuotaReset = newValue.notifyQuotaReset
            notifySessionWaiting = newValue.notifySessionWaiting
            notifySessionFinished = newValue.notifySessionFinished
            notifySessionFailed = newValue.notifySessionFailed
            menuBarStatusMode = newValue.menuBarStatusMode
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

        // showVersionInMenuBar: validate boolean type, default false
        if let num = defaults.object(forKey: Self.showVersionInMenuBarKey) as? NSNumber {
            self.showVersionInMenuBar = num.boolValue
        } else {
            self.showVersionInMenuBar = Self.defaultShowVersionInMenuBar
        }

        // notificationsEnabled: validate boolean type, default true; preserve a stored opt-out
        if let num = defaults.object(forKey: Self.notificationsEnabledKey) as? NSNumber {
            self.notificationsEnabled = num.boolValue
        } else {
            self.notificationsEnabled = Self.defaultNotificationsEnabled
        }

        // notifyQuota15Percent: validate boolean type, default true
        if let num = defaults.object(forKey: Self.notifyQuota15PercentKey) as? NSNumber {
            self.notifyQuota15Percent = num.boolValue
        } else {
            self.notifyQuota15Percent = Self.defaultNotifyQuota15Percent
        }

        // notifyQuota5Percent: validate boolean type, default true
        if let num = defaults.object(forKey: Self.notifyQuota5PercentKey) as? NSNumber {
            self.notifyQuota5Percent = num.boolValue
        } else {
            self.notifyQuota5Percent = Self.defaultNotifyQuota5Percent
        }

        // notifyQuotaReset: validate boolean type, default true
        if let num = defaults.object(forKey: Self.notifyQuotaResetKey) as? NSNumber {
            self.notifyQuotaReset = num.boolValue
        } else {
            self.notifyQuotaReset = Self.defaultNotifyQuotaReset
        }

        // notifySessionWaiting: validate boolean type, default true
        if let num = defaults.object(forKey: Self.notifySessionWaitingKey) as? NSNumber {
            self.notifySessionWaiting = num.boolValue
        } else {
            self.notifySessionWaiting = Self.defaultNotifySessionWaiting
        }

        // notifySessionFinished: validate boolean type, default false
        if let num = defaults.object(forKey: Self.notifySessionFinishedKey) as? NSNumber {
            self.notifySessionFinished = num.boolValue
        } else {
            self.notifySessionFinished = Self.defaultNotifySessionFinished
        }

        // notifySessionFailed: validate boolean type, default true
        if let num = defaults.object(forKey: Self.notifySessionFailedKey) as? NSNumber {
            self.notifySessionFailed = num.boolValue
        } else {
            self.notifySessionFailed = Self.defaultNotifySessionFailed
        }

        // menuBarStatusMode: validate enum value, default .iconOnly
        if let raw = defaults.string(forKey: Self.menuBarStatusModeKey),
           let mode = MenuBarStatusMode(rawValue: raw) {
            self.menuBarStatusMode = mode
        } else {
            self.menuBarStatusMode = Self.defaultMenuBarStatusMode
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
        showVersionInMenuBar = Self.defaultShowVersionInMenuBar
        notificationsEnabled = Self.defaultNotificationsEnabled
        notifyQuota15Percent = Self.defaultNotifyQuota15Percent
        notifyQuota5Percent = Self.defaultNotifyQuota5Percent
        notifyQuotaReset = Self.defaultNotifyQuotaReset
        notifySessionWaiting = Self.defaultNotifySessionWaiting
        notifySessionFinished = Self.defaultNotifySessionFinished
        notifySessionFailed = Self.defaultNotifySessionFailed
        menuBarStatusMode = Self.defaultMenuBarStatusMode
    }

    public func persistToSharedAppGroup(appGroup: SharedAppGroup = .shared) {
        guard let containerURL = appGroup.containerURL else { return }
        let settingsURL = containerURL.appendingPathComponent("settings.json", isDirectory: false)
        do {
            let directory = settingsURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(notificationPreferences)
            try data.write(to: settingsURL, options: [.atomic])
        } catch {
            // Non-critical persistence failure in restricted or unentitled environments
        }
    }

    public nonisolated static func isSessionActive(_ session: AgentSession) -> Bool {
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

    public nonisolated static func safeProjectName(for session: AgentSession, hidePaths: Bool) -> String {
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

extension LoomSettings: @preconcurrency Codable {
    enum CodingKeys: String, CodingKey {
        case showInDock
        case refreshIntervalSeconds
        case enabledProviderIDs
        case defaultProviderID
        case includeRecentSessions
        case hideFinishedAfter
        case hideProjectPaths
        case showVersionInMenuBar
        case notificationsEnabled
        case notifyQuota15Percent
        case notifyQuota5Percent
        case notifyQuotaReset
        case notifySessionWaiting
        case notifySessionFinished
        case notifySessionFailed
        case menuBarStatusMode
    }

    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(defaults: .standard)

        if let dock = try container.decodeIfPresent(Bool.self, forKey: .showInDock) {
            self.showInDock = dock
        }
        if let interval = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) {
            self.refreshIntervalSeconds = interval
        }
        if let pids = try container.decodeIfPresent([String].self, forKey: .enabledProviderIDs) {
            self.enabledProviderIDs = Set(pids.compactMap {
                let pid = ProviderID($0)
                return Self.defaultProviderIDs.contains(pid) ? pid : nil
            })
        }
        if let defPid = try container.decodeIfPresent(String.self, forKey: .defaultProviderID) {
            let pid = ProviderID(defPid)
            self.defaultProviderID = Self.defaultProviderIDs.contains(pid) ? pid : Self.defaultProviderID
        }
        if let recent = try container.decodeIfPresent(Bool.self, forKey: .includeRecentSessions) {
            self.includeRecentSessions = recent
        }
        if let hideStr = try container.decodeIfPresent(String.self, forKey: .hideFinishedAfter),
           let val = HideFinishedInterval(rawValue: hideStr) {
            self.hideFinishedAfter = val
        }
        if let hidePaths = try container.decodeIfPresent(Bool.self, forKey: .hideProjectPaths) {
            self.hideProjectPaths = hidePaths
        }
        if let ver = try container.decodeIfPresent(Bool.self, forKey: .showVersionInMenuBar) {
            self.showVersionInMenuBar = ver
        }

        // Notification preferences with backward-compatible defaults:
        self.notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? Self.defaultNotificationsEnabled
        self.notifyQuota15Percent = try container.decodeIfPresent(Bool.self, forKey: .notifyQuota15Percent) ?? Self.defaultNotifyQuota15Percent
        self.notifyQuota5Percent = try container.decodeIfPresent(Bool.self, forKey: .notifyQuota5Percent) ?? Self.defaultNotifyQuota5Percent
        self.notifyQuotaReset = try container.decodeIfPresent(Bool.self, forKey: .notifyQuotaReset) ?? Self.defaultNotifyQuotaReset
        self.notifySessionWaiting = try container.decodeIfPresent(Bool.self, forKey: .notifySessionWaiting) ?? Self.defaultNotifySessionWaiting
        self.notifySessionFinished = try container.decodeIfPresent(Bool.self, forKey: .notifySessionFinished) ?? Self.defaultNotifySessionFinished
        self.notifySessionFailed = try container.decodeIfPresent(Bool.self, forKey: .notifySessionFailed) ?? Self.defaultNotifySessionFailed
        self.menuBarStatusMode = try container.decodeIfPresent(MenuBarStatusMode.self, forKey: .menuBarStatusMode) ?? Self.defaultMenuBarStatusMode
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showInDock, forKey: .showInDock)
        try container.encode(refreshIntervalSeconds, forKey: .refreshIntervalSeconds)
        try container.encode(Array(enabledProviderIDs.map(\.rawValue)).sorted(), forKey: .enabledProviderIDs)
        try container.encode(defaultProviderID.rawValue, forKey: .defaultProviderID)
        try container.encode(includeRecentSessions, forKey: .includeRecentSessions)
        try container.encode(hideFinishedAfter.rawValue, forKey: .hideFinishedAfter)
        try container.encode(hideProjectPaths, forKey: .hideProjectPaths)
        try container.encode(showVersionInMenuBar, forKey: .showVersionInMenuBar)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(notifyQuota15Percent, forKey: .notifyQuota15Percent)
        try container.encode(notifyQuota5Percent, forKey: .notifyQuota5Percent)
        try container.encode(notifyQuotaReset, forKey: .notifyQuotaReset)
        try container.encode(notifySessionWaiting, forKey: .notifySessionWaiting)
        try container.encode(notifySessionFinished, forKey: .notifySessionFinished)
        try container.encode(notifySessionFailed, forKey: .notifySessionFailed)
        try container.encode(menuBarStatusMode, forKey: .menuBarStatusMode)
    }
}
