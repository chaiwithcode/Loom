//
//  SettingsTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import LoomCore

final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.loom.settings.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        if let suiteName, let testDefaults {
            testDefaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    @MainActor
    func testDefaultValuesWhenNoPriorStorage() {
        let settings = LoomSettings(defaults: testDefaults)
        XCTAssertFalse(settings.showInDock, "Default showInDock must be false")
        XCTAssertEqual(settings.refreshIntervalSeconds, 60, "Default refresh interval must be 60 seconds")
        XCTAssertEqual(settings.enabledProviderIDs, LoomSettings.defaultProviderIDs, "Default enabled providers must be all known providers")
        XCTAssertEqual(settings.defaultProviderID, .codex, "Default provider must be Codex")
        XCTAssertTrue(settings.includeRecentSessions, "Default includeRecentSessions must be true")
        XCTAssertEqual(settings.hideFinishedAfter, .never, "Default hideFinishedAfter must be .never")
        XCTAssertFalse(settings.hideProjectPaths, "Default hideProjectPaths must be false")
    }

    @MainActor
    func testShowInDockPersistenceAndCallback() {
        let settings = LoomSettings(defaults: testDefaults)
        var callbackValue: Bool?
        settings.onShowInDockChanged = { val in
            callbackValue = val
        }

        settings.showInDock = true
        XCTAssertTrue(testDefaults.bool(forKey: LoomSettings.showInDockKey))
        XCTAssertEqual(callbackValue, true)

        let reloaded = LoomSettings(defaults: testDefaults)
        XCTAssertTrue(reloaded.showInDock, "Persisted showInDock value should load on re-initialization")
    }

    @MainActor
    func testRefreshIntervalPersistenceAndSanitization() {
        let settings = LoomSettings(defaults: testDefaults)

        settings.refreshIntervalSeconds = 120
        XCTAssertEqual(testDefaults.integer(forKey: LoomSettings.refreshIntervalKey), 120)

        let reloaded = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.refreshIntervalSeconds, 120)

        // Invalid interval resets to default (60)
        settings.refreshIntervalSeconds = 999
        XCTAssertEqual(settings.refreshIntervalSeconds, 60, "Unsupported interval should sanitize to 60")
    }

    @MainActor
    func testRefreshIntervalCallbackUsesEffectiveValueOncePerChange() {
        let settings = LoomSettings(defaults: testDefaults)
        var intervals: [Int] = []
        settings.onRefreshIntervalChanged = { interval in
            intervals.append(interval)
            XCTAssertEqual(settings.refreshIntervalSeconds, interval)
            XCTAssertEqual(self.testDefaults.integer(forKey: LoomSettings.refreshIntervalKey), interval)
        }

        settings.refreshIntervalSeconds = 120
        settings.refreshIntervalSeconds = 120
        settings.refreshIntervalSeconds = 999
        settings.refreshIntervalSeconds = -1
        XCTAssertEqual(intervals, [120, 60])
        XCTAssertEqual(settings.refreshIntervalSeconds, 60)
        XCTAssertEqual(testDefaults.integer(forKey: LoomSettings.refreshIntervalKey), 60)
    }

    @MainActor
    func testEnabledProvidersPersistenceAndSanitization() {
        let settings = LoomSettings(defaults: testDefaults)
        var notifiedIDs: Set<ProviderID>?
        settings.onEnabledProvidersChanged = { notifiedIDs = $0 }

        // Setting a subset
        settings.enabledProviderIDs = [.codex, .antigravity]
        XCTAssertEqual(notifiedIDs, [.codex, .antigravity])

        let reloaded = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.enabledProviderIDs, [.codex, .antigravity])

        // Empty saved array legitimately disables all
        settings.enabledProviderIDs = []
        let reloadedEmpty = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloadedEmpty.enabledProviderIDs, [], "Empty saved list legitimately disables all providers")

        // Nonempty entirely invalid list should restore defaults
        testDefaults.set(["unknown_provider_1", "fake_agent"], forKey: LoomSettings.enabledProviderIDsKey)
        let reloadedInvalid = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloadedInvalid.enabledProviderIDs, LoomSettings.defaultProviderIDs, "Nonempty entirely invalid list must restore defaults")

        // Mixed valid/invalid keeps only valid
        testDefaults.set(["codex", "fake_agent"], forKey: LoomSettings.enabledProviderIDsKey)
        let reloadedMixed = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloadedMixed.enabledProviderIDs, [.codex], "Mixed list must keep valid providers")
    }

    @MainActor
    func testDefaultProviderPersistenceAndSanitization() {
        let settings = LoomSettings(defaults: testDefaults)
        var notifiedDefault: ProviderID?
        settings.onDefaultProviderChanged = { notifiedDefault = $0 }

        settings.defaultProviderID = .antigravity
        XCTAssertEqual(notifiedDefault, .antigravity)
        XCTAssertEqual(testDefaults.string(forKey: LoomSettings.defaultProviderIDKey), "antigravity")

        let reloaded = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.defaultProviderID, .antigravity)

        // Setting invalid default resets to Codex
        settings.defaultProviderID = ProviderID("invalid_agent")
        XCTAssertEqual(settings.defaultProviderID, .codex)

        // Corrupted default in UserDefaults restores Codex
        testDefaults.set("unknown_provider", forKey: LoomSettings.defaultProviderIDKey)
        let reloadedCorrupt = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloadedCorrupt.defaultProviderID, .codex, "Corrupted default provider string must restore Codex")
    }

    @MainActor
    func testCorruptBooleanStorageFallsBackToDefaults() {
        // Test includeRecentSessions fallback to default true when corrupted with string or array
        testDefaults.set("notABool", forKey: LoomSettings.includeRecentSessionsKey)
        let settingsWithCorruptRecent = LoomSettings(defaults: testDefaults)
        XCTAssertTrue(settingsWithCorruptRecent.includeRecentSessions, "Corrupt includeRecentSessions must fall back to default true")

        // Test showInDock fallback to default false when corrupted
        testDefaults.set(["corrupt", "array"], forKey: LoomSettings.showInDockKey)
        let settingsWithCorruptDock = LoomSettings(defaults: testDefaults)
        XCTAssertFalse(settingsWithCorruptDock.showInDock, "Corrupt showInDock must fall back to default false")

        // Test hideProjectPaths fallback to default false when corrupted
        testDefaults.set("yes_please", forKey: LoomSettings.hideProjectPathsKey)
        let settingsWithCorruptPrivacy = LoomSettings(defaults: testDefaults)
        XCTAssertFalse(settingsWithCorruptPrivacy.hideProjectPaths, "Corrupt hideProjectPaths must fall back to default false")
    }

    @MainActor
    func testIncludeRecentSessionsPersistenceAndCallback() {
        let settings = LoomSettings(defaults: testDefaults)
        var callbackValue: Bool?
        settings.onIncludeRecentSessionsChanged = { callbackValue = $0 }

        settings.includeRecentSessions = false
        XCTAssertEqual(callbackValue, false)
        XCTAssertEqual(testDefaults.bool(forKey: LoomSettings.includeRecentSessionsKey), false)

        let reloaded = LoomSettings(defaults: testDefaults)
        XCTAssertFalse(reloaded.includeRecentSessions)
    }

    @MainActor
    func testHideFinishedAfterPersistenceAndSanitization() {
        let settings = LoomSettings(defaults: testDefaults)
        var callbackValue: HideFinishedInterval?
        settings.onHideFinishedAfterChanged = { callbackValue = $0 }

        settings.hideFinishedAfter = .oneHour
        XCTAssertEqual(callbackValue, .oneHour)
        XCTAssertEqual(testDefaults.string(forKey: LoomSettings.hideFinishedAfterKey), "1h")

        let reloaded = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.hideFinishedAfter, .oneHour)

        // Corrupted string restores default (.never)
        testDefaults.set("corrupted_interval", forKey: LoomSettings.hideFinishedAfterKey)
        let reloadedCorrupt = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloadedCorrupt.hideFinishedAfter, .never)
    }

    @MainActor
    func testHideProjectPathsPersistenceAndCallback() {
        let settings = LoomSettings(defaults: testDefaults)
        var callbackValue: Bool?
        settings.onHideProjectPathsChanged = { callbackValue = $0 }

        settings.hideProjectPaths = true
        XCTAssertEqual(callbackValue, true)
        XCTAssertTrue(testDefaults.bool(forKey: LoomSettings.hideProjectPathsKey))

        let reloaded = LoomSettings(defaults: testDefaults)
        XCTAssertTrue(reloaded.hideProjectPaths)
    }

    @MainActor
    func testResetToDefaultsRestoresAllAndNotifiesCallbacks() {
        let settings = LoomSettings(defaults: testDefaults)
        settings.showInDock = true
        settings.refreshIntervalSeconds = 300
        settings.enabledProviderIDs = [.claude]
        settings.defaultProviderID = .claude
        settings.includeRecentSessions = false
        settings.hideFinishedAfter = .twentyFourHours
        settings.hideProjectPaths = true

        var dockNotified = false
        var refreshNotified = false
        var enabledNotified = false
        var defaultNotified = false
        var recentNotified = false
        var hideFinishedNotified = false
        var privacyNotified = false

        settings.onShowInDockChanged = { _ in dockNotified = true }
        settings.onRefreshIntervalChanged = { _ in refreshNotified = true }
        settings.onEnabledProvidersChanged = { _ in enabledNotified = true }
        settings.onDefaultProviderChanged = { _ in defaultNotified = true }
        settings.onIncludeRecentSessionsChanged = { _ in recentNotified = true }
        settings.onHideFinishedAfterChanged = { _ in hideFinishedNotified = true }
        settings.onHideProjectPathsChanged = { _ in privacyNotified = true }

        settings.resetToDefaults()

        XCTAssertFalse(settings.showInDock)
        XCTAssertEqual(settings.refreshIntervalSeconds, 60)
        XCTAssertEqual(settings.enabledProviderIDs, LoomSettings.defaultProviderIDs)
        XCTAssertEqual(settings.defaultProviderID, .codex)
        XCTAssertTrue(settings.includeRecentSessions)
        XCTAssertEqual(settings.hideFinishedAfter, .never)
        XCTAssertFalse(settings.hideProjectPaths)

        XCTAssertTrue(dockNotified)
        XCTAssertTrue(refreshNotified)
        XCTAssertTrue(enabledNotified)
        XCTAssertTrue(defaultNotified)
        XCTAssertTrue(recentNotified)
        XCTAssertTrue(hideFinishedNotified)
        XCTAssertTrue(privacyNotified)
    }

    @MainActor
    func testEffectiveDefaultProviderFallback() {
        let settings = LoomSettings(defaults: testDefaults)
        let available: [ProviderID] = [.codex, .claude, .antigravity]

        // Default Codex is available and enabled
        XCTAssertEqual(settings.effectiveDefaultProvider(among: available), .codex)

        // Disable Codex: should fall back to next enabled available provider (Claude)
        settings.setProvider(.codex, enabled: false)
        XCTAssertEqual(settings.effectiveDefaultProvider(among: available), .claude)

        // Disable Claude as well: should fall back to Antigravity
        settings.setProvider(.claude, enabled: false)
        XCTAssertEqual(settings.effectiveDefaultProvider(among: available), .antigravity)

        // Disable all: fallback to first available
        settings.setProvider(.antigravity, enabled: false)
        XCTAssertEqual(settings.effectiveDefaultProvider(among: available), .codex)
    }

    @MainActor
    func testIsSessionActiveClassification() {
        let workingSession = AgentSession(id: "1", provider: .codex, state: .working)
        let startingSession = AgentSession(id: "2", provider: .codex, state: .starting)
        let waitingSession = AgentSession(id: "3", provider: .codex, state: .waiting)
        let unknownNoProcess = AgentSession(id: "4", provider: .codex, state: .unknown)
        let unknownWithProcess = AgentSession(id: "5", provider: .codex, state: .unknown, pid: 1234)
        let idleWithProcess = AgentSession(id: "6", provider: .codex, state: .idle, pid: 5678)
        let idleNoProcess = AgentSession(id: "7", provider: .codex, state: .idle)
        let finishedSession = AgentSession(id: "8", provider: .codex, state: .finished)
        let failedSession = AgentSession(id: "9", provider: .codex, state: .failed)

        XCTAssertTrue(LoomSettings.isSessionActive(workingSession))
        XCTAssertTrue(LoomSettings.isSessionActive(startingSession))
        XCTAssertTrue(LoomSettings.isSessionActive(waitingSession))
        XCTAssertTrue(LoomSettings.isSessionActive(unknownNoProcess), "Conservative keep: unknown without process retained")
        XCTAssertTrue(LoomSettings.isSessionActive(unknownWithProcess), "Unknown with positive process evidence is active")
        XCTAssertTrue(LoomSettings.isSessionActive(idleWithProcess), "Idle with positive process evidence is active")
        XCTAssertFalse(LoomSettings.isSessionActive(idleNoProcess), "Idle without process is not active")
        XCTAssertFalse(LoomSettings.isSessionActive(finishedSession), "Finished session is not active")
        XCTAssertFalse(LoomSettings.isSessionActive(failedSession), "Failed session is not active")
    }

    @MainActor
    func testShouldIncludeSessionFilteringAndRetention() {
        let settings = LoomSettings(defaults: testDefaults)
        let now = Date()

        let workingSession = AgentSession(id: "w1", provider: .codex, state: .working)
        let finishedRecent = AgentSession(
            id: "f1",
            provider: .codex,
            state: .finished,
            lastActivityAt: now.addingTimeInterval(-1800) // 30 min ago
        )
        let finishedOlderThan1h = AgentSession(
            id: "f2",
            provider: .codex,
            state: .finished,
            lastActivityAt: now.addingTimeInterval(-7200) // 2 hours ago
        )
        // Critical primary review test case: finished session with nil lastActivityAt and old startedAt
        let finishedNilLastActivityOldStarted = AgentSession(
            id: "f3",
            provider: .codex,
            state: .finished,
            startedAt: now.addingTimeInterval(-86400 * 10), // 10 days ago
            lastActivityAt: nil
        )

        // 1. includeRecentSessions == false (Show active only)
        settings.includeRecentSessions = false
        XCTAssertTrue(settings.shouldInclude(session: workingSession, now: now))
        XCTAssertFalse(settings.shouldInclude(session: finishedRecent, now: now), "Finished sessions excluded when includeRecentSessions is false")
        XCTAssertFalse(settings.shouldInclude(session: finishedOlderThan1h, now: now))
        XCTAssertFalse(settings.shouldInclude(session: finishedNilLastActivityOldStarted, now: now))

        // 2. includeRecentSessions == true, hideFinishedAfter == .never
        settings.includeRecentSessions = true
        settings.hideFinishedAfter = .never
        XCTAssertTrue(settings.shouldInclude(session: workingSession, now: now))
        XCTAssertTrue(settings.shouldInclude(session: finishedRecent, now: now))
        XCTAssertTrue(settings.shouldInclude(session: finishedOlderThan1h, now: now))
        XCTAssertTrue(settings.shouldInclude(session: finishedNilLastActivityOldStarted, now: now))

        // 3. includeRecentSessions == true, hideFinishedAfter == .oneHour
        settings.hideFinishedAfter = .oneHour
        XCTAssertTrue(settings.shouldInclude(session: workingSession, now: now), "Active working session never hidden by finished cutoff")
        XCTAssertTrue(settings.shouldInclude(session: finishedRecent, now: now), "30m old finished session kept under 1h cutoff")
        XCTAssertFalse(settings.shouldInclude(session: finishedOlderThan1h, now: now), "2h old finished session hidden under 1h cutoff")
        XCTAssertTrue(
            settings.shouldInclude(session: finishedNilLastActivityOldStarted, now: now),
            "Finished session with nil lastActivityAt MUST remain visible because startedAt is not completion evidence!"
        )

        // Boundary tests for .oneHour (3600s)
        let finished3590s = AgentSession(id: "b1", provider: .codex, state: .finished, lastActivityAt: now.addingTimeInterval(-3590))
        let finished3610s = AgentSession(id: "b2", provider: .codex, state: .finished, lastActivityAt: now.addingTimeInterval(-3610))
        XCTAssertTrue(settings.shouldInclude(session: finished3590s, now: now), "3590s <= 3600s must be kept")
        XCTAssertFalse(settings.shouldInclude(session: finished3610s, now: now), "3610s > 3600s must be hidden")

        // Boundary tests for .twentyFourHours (86400s)
        settings.hideFinishedAfter = .twentyFourHours
        let finished86390s = AgentSession(id: "b3", provider: .codex, state: .finished, lastActivityAt: now.addingTimeInterval(-86390))
        let finished86410s = AgentSession(id: "b4", provider: .codex, state: .finished, lastActivityAt: now.addingTimeInterval(-86410))
        XCTAssertTrue(settings.shouldInclude(session: finished86390s, now: now))
        XCTAssertFalse(settings.shouldInclude(session: finished86410s, now: now))

        // Boundary tests for .sevenDays (604800s)
        settings.hideFinishedAfter = .sevenDays
        let finished604790s = AgentSession(id: "b5", provider: .codex, state: .finished, lastActivityAt: now.addingTimeInterval(-604790))
        let finished604810s = AgentSession(id: "b6", provider: .codex, state: .finished, lastActivityAt: now.addingTimeInterval(-604810))
        XCTAssertTrue(settings.shouldInclude(session: finished604790s, now: now))
        XCTAssertFalse(settings.shouldInclude(session: finished604810s, now: now))
    }

    @MainActor
    func testSafeProjectNameSanitization() {
        let sessionWithPathName = AgentSession(
            id: "p1",
            provider: .codex,
            projectName: "/Users/developer/Projects/Loom",
            state: .working
        )
        let sessionWithTildePath = AgentSession(
            id: "p2",
            provider: .codex,
            projectName: "~/Documents/Work/SecretTool",
            state: .working
        )
        let sessionWithCleanName = AgentSession(
            id: "p3",
            provider: .codex,
            projectName: "MobileApp",
            state: .working
        )
        let sessionNilName = AgentSession(
            id: "p4",
            provider: .codex,
            projectName: nil,
            projectPath: URL(fileURLWithPath: "/Users/developer/Projects/BackendAPI"),
            state: .working
        )

        // When hidePaths is false: paths kept
        XCTAssertEqual(LoomSettings.safeProjectName(for: sessionWithPathName, hidePaths: false), "/Users/developer/Projects/Loom")
        XCTAssertEqual(LoomSettings.safeProjectName(for: sessionWithTildePath, hidePaths: false), "~/Documents/Work/SecretTool")
        XCTAssertEqual(LoomSettings.safeProjectName(for: sessionWithCleanName, hidePaths: false), "MobileApp")
        XCTAssertEqual(LoomSettings.safeProjectName(for: sessionNilName, hidePaths: false), "BackendAPI")

        // When hidePaths is true: paths trimmed to last component
        XCTAssertEqual(LoomSettings.safeProjectName(for: sessionWithPathName, hidePaths: true), "Loom")
        XCTAssertEqual(LoomSettings.safeProjectName(for: sessionWithTildePath, hidePaths: true), "SecretTool")
        XCTAssertEqual(LoomSettings.safeProjectName(for: sessionWithCleanName, hidePaths: true), "MobileApp")
        XCTAssertEqual(LoomSettings.safeProjectName(for: sessionNilName, hidePaths: true), "BackendAPI")
    }
}
