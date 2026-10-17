//
//  SharedAppGroupTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import LoomCore

final class SharedAppGroupTests: XCTestCase {
    private var tempDir: URL!
    private var appGroup: SharedAppGroup!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("loom-test-group-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        appGroup = SharedAppGroup(customBaseDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSnapshotEncodingAndDecoding() throws {
        let original = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            activeSessionCount: 3,
            attentionSessionCount: 1,
            totalSessionCount: 5,
            providerSummaries: [
                ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 3, healthStatus: "available", isDegradedOrUnavailable: false),
                ProviderWidgetSummary(id: "antigravity", displayName: "Antigravity", sessionCount: 2, healthStatus: "degraded", isDegradedOrUnavailable: true)
            ],
            statusMessage: "3 active sessions"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LoomWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, original.schemaVersion)
        XCTAssertEqual(decoded.activeSessionCount, original.activeSessionCount)
        XCTAssertEqual(decoded.attentionSessionCount, original.attentionSessionCount)
        XCTAssertEqual(decoded.totalSessionCount, original.totalSessionCount)
        XCTAssertEqual(decoded.providerSummaries.count, 2)
        XCTAssertEqual(decoded.providerSummaries[0].id, "codex")
        XCTAssertEqual(decoded.providerSummaries[0].displayName, "Codex")
        XCTAssertEqual(decoded.providerSummaries[1].id, "antigravity")
        XCTAssertTrue(decoded.providerSummaries[1].isDegradedOrUnavailable)
        XCTAssertEqual(decoded.statusMessage, "3 active sessions")
    }

    func testAtomicWriteAndRead() {
        let snapshot = LoomWidgetSnapshot.preview
        let writeSuccess = appGroup.writeSnapshot(snapshot)
        XCTAssertTrue(writeSuccess, "Atomic write to shared container must succeed")

        let readResult = appGroup.readSnapshot()
        guard case .success(let readSnapshot) = readResult else {
            XCTFail("Expected .success, got \(readResult)")
            return
        }

        XCTAssertEqual(readSnapshot.schemaVersion, snapshot.schemaVersion)
        XCTAssertEqual(readSnapshot.activeSessionCount, snapshot.activeSessionCount)
        XCTAssertEqual(readSnapshot.attentionSessionCount, snapshot.attentionSessionCount)
        XCTAssertEqual(readSnapshot.providerSummaries.count, snapshot.providerSummaries.count)
    }

    func testMissingSnapshotReturnsNotFound() {
        let readResult = appGroup.readSnapshot()
        XCTAssertEqual(readResult, .notFound)
    }

    func testCorruptDataReturnsCorrupted() throws {
        guard let fileURL = appGroup.snapshotFileURL else {
            XCTFail("Missing snapshot file URL")
            return
        }

        try "This is not valid JSON {[[[".write(to: fileURL, atomically: true, encoding: .utf8)

        let readResult = appGroup.readSnapshot()
        guard case .corrupted = readResult else {
            XCTFail("Expected .corrupted, got \(readResult)")
            return
        }
    }

    func testUnsupportedVersionHandling() throws {
        let futureSnapshotJSON = """
        {
            "schemaVersion": 999,
            "timestamp": "2026-10-14T12:00:00Z",
            "activeSessionCount": 0,
            "attentionSessionCount": 0,
            "totalSessionCount": 0,
            "providerSummaries": []
        }
        """

        guard let fileURL = appGroup.snapshotFileURL else {
            XCTFail("Missing snapshot file URL")
            return
        }

        try futureSnapshotJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let readResult = appGroup.readSnapshot()
        XCTAssertEqual(readResult, .unsupportedVersion(999))
    }

    @MainActor
    func testSnapshotFromSessionStore() async {
        let s1 = AgentSession(id: "s1", provider: .codex, projectName: "Loom", state: .working)
        let s2 = AgentSession(id: "s2", provider: .codex, projectName: "Loom", state: .waiting)
        let s3 = AgentSession(id: "s3", provider: .antigravity, projectName: "Experiment", state: .finished)

        let codexProv = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [s1, s2])
        let agyProv = MockAgentProvider(id: .antigravity, displayName: "Antigravity", sessions: [s3])
        let claudeProv = MockAgentProvider(id: .claude, displayName: "Claude Code", sessions: [])
        claudeProv.setAvailability(.unavailable(reason: "CLI not found"))

        let store = SessionStore(providers: [codexProv, agyProv, claudeProv])
        await store.refresh()

        let snapshot = LoomWidgetSnapshot.make(from: store)
        XCTAssertEqual(snapshot.activeSessionCount, 1) // s1 working
        XCTAssertEqual(snapshot.attentionSessionCount, 1) // s2 waiting
        XCTAssertEqual(snapshot.totalSessionCount, 3)

        XCTAssertEqual(snapshot.providerSummaries.count, 3)
        let codexSummary = snapshot.providerSummaries.first { $0.id == "codex" }
        XCTAssertNotNil(codexSummary)
        XCTAssertEqual(codexSummary?.sessionCount, 2)
        XCTAssertEqual(codexSummary?.healthStatus, "available")

        let claudeSummary = snapshot.providerSummaries.first { $0.id == "claude" }
        XCTAssertNotNil(claudeSummary)
        XCTAssertEqual(claudeSummary?.sessionCount, 0)
        XCTAssertEqual(claudeSummary?.healthStatus, "unavailable")
        XCTAssertTrue(claudeSummary?.isDegradedOrUnavailable == true)

        // Verify publishWidgetSnapshot writes cleanly to app group
        let publishSuccess = store.publishWidgetSnapshot(to: appGroup)
        XCTAssertTrue(publishSuccess)

        let readResult = appGroup.readSnapshot()
        guard case .success(let publishedSnapshot) = readResult else {
            XCTFail("Expected .success, got \(readResult)")
            return
        }
        XCTAssertEqual(publishedSnapshot.activeSessionCount, 1)
        XCTAssertEqual(publishedSnapshot.attentionSessionCount, 1)
    }

    @MainActor
    func testSnapshotDoesNotSerializeProviderErrorDetails() async throws {
        let sensitiveDetail = "/Users/private/SecretProject/session.json token=private-token"
        let provider = MockAgentProvider(id: .codex, displayName: "Codex")
        let store = SessionStore(providers: [provider])

        provider.setError(MockProviderError.sessionCorrupt(sensitiveDetail))
        await store.refresh()
        var snapshot = LoomWidgetSnapshot.make(from: store)
        XCTAssertEqual(snapshot.statusMessage, "Session discovery failed")
        XCTAssertTrue(store.publishWidgetSnapshot(to: appGroup))
        var data = try Data(contentsOf: XCTUnwrap(appGroup.snapshotFileURL))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(sensitiveDetail))

        provider.setError(nil)
        provider.setAvailability(.unavailable(reason: sensitiveDetail))
        await store.refresh()
        snapshot = LoomWidgetSnapshot.make(from: store)
        XCTAssertEqual(snapshot.statusMessage, "Providers unavailable")
        XCTAssertTrue(store.publishWidgetSnapshot(to: appGroup))
        data = try Data(contentsOf: XCTUnwrap(appGroup.snapshotFileURL))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(sensitiveDetail))
    }

    func testRemoveSnapshot() {
        XCTAssertTrue(appGroup.writeSnapshot(.preview))
        XCTAssertTrue(appGroup.removeSnapshot())
        XCTAssertEqual(appGroup.readSnapshot(), .notFound)
    }

    func testStalenessCalculation() {
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        let snapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: baseTime,
            activeSessionCount: 2,
            attentionSessionCount: 0,
            totalSessionCount: 2,
            providerSummaries: []
        )

        // Same time
        XCTAssertFalse(snapshot.isStale(at: baseTime))
        // 10 minutes later (600s < 900s)
        XCTAssertFalse(snapshot.isStale(at: baseTime.addingTimeInterval(600)))
        // Exactly 15 minutes (900s)
        XCTAssertFalse(snapshot.isStale(at: baseTime.addingTimeInterval(900)))
        // 15 minutes + 1 second (901s > 900s) -> stale!
        XCTAssertTrue(snapshot.isStale(at: baseTime.addingTimeInterval(901)))
    }

    func testSnapshotStateComputation() {
        let now = Date()

        // 1. Stale state
        let staleSnapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: now.addingTimeInterval(-1000),
            activeSessionCount: 3,
            attentionSessionCount: 0,
            totalSessionCount: 3,
            providerSummaries: [
                ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 3, healthStatus: "available", isDegradedOrUnavailable: false)
            ]
        )
        XCTAssertEqual(staleSnapshot.state(at: now), .stale)

        // 2. All disabled state
        let disabledSnapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: now,
            activeSessionCount: 0,
            attentionSessionCount: 0,
            totalSessionCount: 0,
            providerSummaries: [
                ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 0, healthStatus: "disabled", isDegradedOrUnavailable: false),
                ProviderWidgetSummary(id: "claude", displayName: "Claude Code", sessionCount: 0, healthStatus: "disabled", isDegradedOrUnavailable: false)
            ]
        )
        XCTAssertEqual(disabledSnapshot.state(at: now), .allDisabled)

        // 3. Attention needed state
        let attentionSnapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: now,
            activeSessionCount: 2,
            attentionSessionCount: 1,
            totalSessionCount: 3,
            providerSummaries: [
                ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 2, healthStatus: "available", isDegradedOrUnavailable: false)
            ]
        )
        XCTAssertEqual(attentionSnapshot.state(at: now), .attentionNeeded)

        // 4. Degraded state
        let degradedSnapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: now,
            activeSessionCount: 1,
            attentionSessionCount: 0,
            totalSessionCount: 1,
            providerSummaries: [
                ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 1, healthStatus: "degraded", isDegradedOrUnavailable: true)
            ]
        )
        XCTAssertEqual(degradedSnapshot.state(at: now), .degraded)

        // 5. Empty / idle state
        let emptySnapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: now,
            activeSessionCount: 0,
            attentionSessionCount: 0,
            totalSessionCount: 0,
            providerSummaries: [
                ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 0, healthStatus: "available", isDegradedOrUnavailable: false)
            ]
        )
        XCTAssertEqual(emptySnapshot.state(at: now), .empty)

        // 6. Normal state
        let normalSnapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: now,
            activeSessionCount: 2,
            attentionSessionCount: 0,
            totalSessionCount: 2,
            providerSummaries: [
                ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 2, healthStatus: "available", isDegradedOrUnavailable: false)
            ]
        )
        XCTAssertEqual(normalSnapshot.state(at: now), .normal)
    }

    func testPrivacyEnforcementNoSensitiveDataLeaked() throws {
        let snapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 2,
            attentionSessionCount: 1,
            totalSessionCount: 3,
            providerSummaries: [
                ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 2, healthStatus: "available", isDegradedOrUnavailable: false),
                ProviderWidgetSummary(id: "claude", displayName: "Claude Code", sessionCount: 1, healthStatus: "available", isDegradedOrUnavailable: false)
            ],
            statusMessage: "Active"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to convert encoded JSON data to string")
            return
        }

        let forbiddenKeys = [
            "projectName",
            "projectPath",
            "cwd",
            "workingDirectory",
            "commandLine",
            "command",
            "arguments",
            "transcript",
            "repo",
            "repository",
            "branch",
            "git",
            "pid",
            "processId",
            "credential",
            "token",
            "apiKey"
        ]

        for forbidden in forbiddenKeys {
            XCTAssertFalse(
                jsonString.lowercased().contains(forbidden.lowercased()),
                "Snapshot JSON must NEVER leak sensitive key or field: '\(forbidden)'. Found in: \(jsonString)"
            )
        }
    }

    func testProviderSummaryEnabledProperty() {
        let enabled = ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 1, healthStatus: "available", isDegradedOrUnavailable: false)
        XCTAssertTrue(enabled.isEnabled)

        let degraded = ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 1, healthStatus: "degraded", isDegradedOrUnavailable: true)
        XCTAssertTrue(degraded.isEnabled)

        let disabled = ProviderWidgetSummary(id: "codex", displayName: "Codex", sessionCount: 0, healthStatus: "disabled", isDegradedOrUnavailable: false)
        XCTAssertFalse(disabled.isEnabled)
    }

    func testSnapshotEncodingAndDecodingWithFullUsageModel() throws {
        let resetDate = Date(timeIntervalSince1970: 1700050000)
        let usageAvailable = ProviderUsageWidgetSummary(
            status: .available,
            fractionUsed: 0.27,
            percentRemaining: 73,
            percentUsed: 27,
            resetsAt: resetDate,
            formattedResetTime: "resets in 2h 10m",
            planType: "Pro",
            summary: "73% left"
        )
        let usageUnavailable = ProviderUsageWidgetSummary(
            status: .unavailable,
            summary: "Usage unavailable"
        )
        let usageUnsupported = ProviderUsageWidgetSummary(
            status: .unsupported,
            summary: "Usage unsupported"
        )
        let usageStale = ProviderUsageWidgetSummary(
            status: .stale,
            fractionUsed: 0.50,
            percentRemaining: 50,
            percentUsed: 50,
            summary: "50% left (stale)"
        )

        let snapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            activeSessionCount: 2,
            attentionSessionCount: 1,
            totalSessionCount: 3,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 2,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: "2 active",
                    usage: usageAvailable
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 1,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: "1 active",
                    usage: usageUnavailable
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "unknown",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: nil,
                    usage: usageUnsupported
                ),
                ProviderWidgetSummary(
                    id: "mock",
                    displayName: "Mock",
                    sessionCount: 0,
                    healthStatus: "degraded",
                    isDegradedOrUnavailable: true,
                    lifecycleSummary: nil,
                    usage: usageStale
                )
            ],
            statusMessage: "3 active sessions"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LoomWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.providerSummaries.count, 4)

        // Provider 0: Available usage
        let codex = decoded.providerSummaries[0]
        XCTAssertEqual(codex.id, "codex")
        XCTAssertEqual(codex.usageStatus, .available)
        XCTAssertEqual(codex.usage?.percentRemaining, 73)
        XCTAssertEqual(codex.usage?.percentUsed, 27)
        XCTAssertEqual(codex.usage?.formattedResetTime, "resets in 2h 10m")
        XCTAssertEqual(codex.usage?.planType, "Pro")
        XCTAssertEqual(codex.usageSummaryText, "73% left")
        XCTAssertEqual(codex.lifecycleSummary, "2 active")

        // Provider 1: Unavailable usage
        let claude = decoded.providerSummaries[1]
        XCTAssertEqual(claude.usageStatus, .unavailable)
        XCTAssertEqual(claude.usageSummaryText, "Usage unavailable")

        // Provider 2: Unsupported usage
        let agy = decoded.providerSummaries[2]
        XCTAssertEqual(agy.usageStatus, .unsupported)
        XCTAssertEqual(agy.usageSummaryText, "Usage unsupported")

        // Provider 3: Stale usage
        let mock = decoded.providerSummaries[3]
        XCTAssertEqual(mock.usageStatus, .stale)
        XCTAssertEqual(mock.usageSummaryText, "50% left (stale)")
    }

    @MainActor
    func testProviderUsageNormalizationAvailable() async {
        let bucket = UsageBucket(
            identifier: "quota",
            label: "5-hour window",
            usedFraction: 0.27,
            resetsAt: Date().addingTimeInterval(7200),
            windowDurationMins: 300
        )
        let usage = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date(),
            planType: "Pro",
            primaryBucket: bucket,
            isStale: false
        )
        let codexProv = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [])
        codexProv.setUsage(usage)

        let store = SessionStore(providers: [codexProv])
        await store.refresh()

        let snapshot = LoomWidgetSnapshot.make(from: store)
        let codexSummary = snapshot.providerSummaries.first { $0.id == "codex" }
        XCTAssertNotNil(codexSummary)
        XCTAssertEqual(codexSummary?.usageStatus, .available)
        XCTAssertEqual(codexSummary?.usage?.percentRemaining, 73)
        XCTAssertEqual(codexSummary?.usage?.percentUsed, 27)
        XCTAssertEqual(codexSummary?.usage?.planType, "Pro")
        XCTAssertEqual(codexSummary?.usageSummaryText, "73% left")
    }

    @MainActor
    func testProviderUsageNormalizationUnavailableAndUnsupported() async {
        let claudeProv = MockAgentProvider(id: .claude, displayName: "Claude Code", sessions: [])
        let codexProv = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [])
        codexProv.setError(MockProviderError.daemonUnavailable("Quota server unreachable"))

        let store = SessionStore(providers: [claudeProv, codexProv])
        await store.refresh()

        let snapshot = LoomWidgetSnapshot.make(from: store)

        // Claude is inherently unsupported
        let claudeSummary = snapshot.providerSummaries.first { $0.id == "claude" }
        XCTAssertEqual(claudeSummary?.usageStatus, .unsupported)
        XCTAssertEqual(claudeSummary?.usageSummaryText, "Usage unsupported")

        // Codex with usage error is unavailable
        let codexSummary = snapshot.providerSummaries.first { $0.id == "codex" }
        XCTAssertEqual(codexSummary?.usageStatus, .unavailable)
        XCTAssertEqual(codexSummary?.usageSummaryText, "Usage unavailable")
    }

    @MainActor
    func testProviderWithSessionsButNoUsage() async {
        let s1 = AgentSession(id: "c1", provider: .claude, projectName: "Loom", state: .working)
        let s2 = AgentSession(id: "c2", provider: .claude, projectName: "Loom", state: .starting)
        let claudeProv = MockAgentProvider(id: .claude, displayName: "Claude Code", sessions: [s1, s2])

        let store = SessionStore(providers: [claudeProv])
        await store.refresh()

        let snapshot = LoomWidgetSnapshot.make(from: store)
        let claudeSummary = snapshot.providerSummaries.first { $0.id == "claude" }
        XCTAssertEqual(claudeSummary?.sessionCount, 2)
        XCTAssertEqual(claudeSummary?.lifecycleSummary, "2 active")
        XCTAssertEqual(claudeSummary?.usageStatus, .unsupported)
        XCTAssertEqual(claudeSummary?.usageSummaryText, "Usage unsupported")
    }

    @MainActor
    func testProviderWithUsageButNoActiveSessions() async {
        let bucket = UsageBucket(
            identifier: "quota",
            label: "Daily Quota",
            usedFraction: 0.20,
            resetsAt: nil,
            windowDurationMins: nil
        )
        let usage = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date(),
            primaryBucket: bucket,
            isStale: false
        )
        let codexProv = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [])
        codexProv.setUsage(usage)

        let store = SessionStore(providers: [codexProv])
        await store.refresh()

        let snapshot = LoomWidgetSnapshot.make(from: store)
        let codexSummary = snapshot.providerSummaries.first { $0.id == "codex" }
        XCTAssertEqual(codexSummary?.sessionCount, 0)
        XCTAssertNil(codexSummary?.lifecycleSummary)
        XCTAssertEqual(codexSummary?.usageStatus, .available)
        XCTAssertEqual(codexSummary?.usage?.percentRemaining, 80)
        XCTAssertEqual(codexSummary?.usageSummaryText, "80% left")
    }

    @MainActor
    func testStaleUsageHandling() async {
        let bucket = UsageBucket(
            identifier: "quota",
            label: "5-hour window",
            usedFraction: 0.35,
            resetsAt: nil,
            windowDurationMins: nil
        )
        let staleUsage = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date().addingTimeInterval(-1800),
            primaryBucket: bucket,
            isStale: true
        )
        let codexProv = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [])
        codexProv.setUsage(staleUsage)

        let store = SessionStore(providers: [codexProv])
        await store.refresh()

        let snapshot = LoomWidgetSnapshot.make(from: store)
        let codexSummary = snapshot.providerSummaries.first { $0.id == "codex" }
        XCTAssertEqual(codexSummary?.usageStatus, .stale)
        XCTAssertEqual(codexSummary?.usageSummaryText, "65% left (stale)")
    }

    func testSnapshotBackwardCompatibilityWithoutGroups() throws {
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "timestamp": "2026-10-16T12:00:00Z",
            "activeSessionCount": 1,
            "attentionSessionCount": 0,
            "totalSessionCount": 1,
            "providerSummaries": [
                {
                    "id": "codex",
                    "displayName": "Codex",
                    "sessionCount": 1,
                    "healthStatus": "available",
                    "isDegradedOrUnavailable": false,
                    "usage": {
                        "status": "available",
                        "percentRemaining": 80,
                        "summary": "80% left",
                        "windows": [
                            {
                                "id": "5h",
                                "label": "5 hours",
                                "percentRemaining": 80,
                                "observedAt": "2026-10-16T12:00:00Z"
                            }
                        ]
                    }
                }
            ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoomWidgetSnapshot.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.providerSummaries.count, 1)
        let codex = snapshot.providerSummaries[0]
        XCTAssertNil(codex.usage?.groups, "Legacy snapshots without groups field must decode with groups == nil")
        XCTAssertEqual(codex.allQuotaWindows.count, 1)
        XCTAssertEqual(codex.allQuotaWindows[0].id, "5h")
    }

    func testSnapshotEncodingAndDecodingWithGroups() throws {
        let obsDate = Date(timeIntervalSince1970: 1700000000)
        let resetDate = obsDate.addingTimeInterval(3600)
        let group = WidgetQuotaGroup(
            id: "models",
            label: "Model Limits",
            windows: [
                WidgetQuotaWindow(id: "gpt-4o", label: "GPT-4o", percentRemaining: 65, resetsAt: resetDate, observedAt: obsDate),
                WidgetQuotaWindow(id: "o1", label: "o1", percentRemaining: 20, resetsAt: resetDate, observedAt: obsDate)
            ]
        )
        let summary = ProviderUsageWidgetSummary(
            status: .available,
            summary: "Available",
            windows: [
                WidgetQuotaWindow(id: "5h", label: "5 hours", percentRemaining: 75, resetsAt: resetDate, observedAt: obsDate)
            ],
            groups: [group]
        )
        let snapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: obsDate,
            activeSessionCount: 1,
            attentionSessionCount: 0,
            totalSessionCount: 1,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 1,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: summary
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LoomWidgetSnapshot.self, from: data)

        let provider = decoded.providerSummaries[0]
        XCTAssertEqual(provider.usage?.groups?.count, 1)
        XCTAssertEqual(provider.usage?.groups?[0].id, "models")
        XCTAssertEqual(provider.usage?.groups?[0].windows.count, 2)
        XCTAssertEqual(provider.usage?.groups?[0].windows[0].id, "gpt-4o")
        XCTAssertEqual(provider.allQuotaWindows.count, 3)
    }

    func testProviderWidgetSummaryAllQuotaWindowsDeduplication() {
        let obs = Date()
        let w1 = WidgetQuotaWindow(id: "primary", label: "Primary Window", percentRemaining: 90, resetsAt: nil, observedAt: obs)
        let w2 = WidgetQuotaWindow(id: "model-1", label: "Model 1", percentRemaining: 50, resetsAt: nil, observedAt: obs)
        let wDuplicate = WidgetQuotaWindow(id: "primary", label: "Duplicate Primary", percentRemaining: 90, resetsAt: nil, observedAt: obs)

        let summary = ProviderUsageWidgetSummary(
            status: .available,
            summary: "Available",
            windows: [w1],
            groups: [
                WidgetQuotaGroup(id: "g1", label: "Group 1", windows: [wDuplicate, w2])
            ]
        )
        let provider = ProviderWidgetSummary(
            id: "test",
            displayName: "Test",
            sessionCount: 0,
            healthStatus: "available",
            isDegradedOrUnavailable: false,
            usage: summary
        )

        let all = provider.allQuotaWindows
        XCTAssertEqual(all.count, 2, "Should deduplicate windows sharing the same ID")
        XCTAssertEqual(all.map(\.id), ["primary", "model-1"])
    }

    func testMultiProviderQuotaSnapshotSerializationWithMixedStates() throws {
        let obsDate = Date(timeIntervalSince1970: 1700000000)
        let reset5h = obsDate.addingTimeInterval(18000)
        let resetWeekly = obsDate.addingTimeInterval(604800)

        // 1. Codex with 2 windows + model group
        let codexWindows = [
            WidgetQuotaWindow(id: "5h", label: "5 hours", percentRemaining: 73, resetsAt: reset5h, observedAt: obsDate, windowDurationMins: 300),
            WidgetQuotaWindow(id: "weekly", label: "Weekly Limit", percentRemaining: 38, resetsAt: resetWeekly, observedAt: obsDate, windowDurationMins: 10080)
        ]
        let codexGroup = WidgetQuotaGroup(
            id: "models",
            label: "Model Limits",
            windows: [
                WidgetQuotaWindow(id: "gpt-4o", label: "GPT-4o", percentRemaining: 65, resetsAt: reset5h, observedAt: obsDate),
                WidgetQuotaWindow(id: "o1", label: "o1", percentRemaining: 20, resetsAt: resetWeekly, observedAt: obsDate)
            ]
        )
        let codexUsage = ProviderUsageWidgetSummary(
            status: .available,
            fractionUsed: 0.27,
            percentRemaining: 73,
            percentUsed: 27,
            resetsAt: reset5h,
            formattedResetTime: "resets in 5h 0m",
            planType: "Pro",
            summary: "73% left",
            windows: codexWindows,
            groups: [codexGroup]
        )
        let codexSummary = ProviderWidgetSummary(
            id: "codex",
            displayName: "Codex",
            sessionCount: 2,
            healthStatus: "available",
            isDegradedOrUnavailable: false,
            lifecycleSummary: "2 active",
            usage: codexUsage
        )

        // 2. Claude with .unsupported
        let claudeUsage = ProviderUsageWidgetSummary(
            status: .unsupported,
            summary: "Usage unsupported"
        )
        let claudeSummary = ProviderWidgetSummary(
            id: "claude",
            displayName: "Claude Code",
            sessionCount: 1,
            healthStatus: "available",
            isDegradedOrUnavailable: false,
            lifecycleSummary: "1 active",
            usage: claudeUsage
        )

        // 3. Antigravity with 1 window + Gemini group
        let agyWindows = [
            WidgetQuotaWindow(id: "ag-5h", label: "5 hours", percentRemaining: 60, resetsAt: reset5h, observedAt: obsDate, windowDurationMins: 300)
        ]
        let geminiGroup = WidgetQuotaGroup(
            id: "gemini",
            label: "Gemini Models",
            windows: [
                WidgetQuotaWindow(id: "gemini-pro", label: "Gemini 1.5 Pro", percentRemaining: 82, resetsAt: reset5h, observedAt: obsDate),
                WidgetQuotaWindow(id: "gemini-flash", label: "Gemini 1.5 Flash", percentRemaining: 95, resetsAt: reset5h, observedAt: obsDate)
            ]
        )
        let agyUsage = ProviderUsageWidgetSummary(
            status: .available,
            fractionUsed: 0.40,
            percentRemaining: 60,
            percentUsed: 40,
            resetsAt: reset5h,
            formattedResetTime: "resets in 5h 0m",
            planType: "Standard",
            summary: "60% left",
            windows: agyWindows,
            groups: [geminiGroup]
        )
        let agySummary = ProviderWidgetSummary(
            id: "antigravity",
            displayName: "Antigravity",
            sessionCount: 0,
            healthStatus: "available",
            isDegradedOrUnavailable: false,
            lifecycleSummary: nil,
            usage: agyUsage
        )

        // 4. Disabled provider
        let disabledUsage = ProviderUsageWidgetSummary(
            status: .unavailable,
            summary: "Monitoring disabled"
        )
        let disabledSummary = ProviderWidgetSummary(
            id: "mock",
            displayName: "Mock Agent",
            sessionCount: 0,
            healthStatus: "disabled",
            isDegradedOrUnavailable: false,
            lifecycleSummary: nil,
            usage: disabledUsage
        )

        let original = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: obsDate,
            activeSessionCount: 3,
            attentionSessionCount: 0,
            totalSessionCount: 3,
            providerSummaries: [codexSummary, claudeSummary, agySummary, disabledSummary],
            statusMessage: "3 active sessions"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LoomWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.activeSessionCount, 3)
        XCTAssertEqual(decoded.providerSummaries.count, 4)

        // Verify Codex (2 windows + model group)
        let decodedCodex = try XCTUnwrap(decoded.providerSummaries.first { $0.id == "codex" })
        XCTAssertTrue(decodedCodex.isEnabled)
        XCTAssertEqual(decodedCodex.usageStatus, .available)
        XCTAssertEqual(decodedCodex.usage?.windows?.count, 2)
        XCTAssertEqual(decodedCodex.usage?.groups?.count, 1)
        XCTAssertEqual(decodedCodex.usage?.groups?[0].id, "models")
        XCTAssertEqual(decodedCodex.usage?.groups?[0].label, "Model Limits")
        XCTAssertEqual(decodedCodex.usage?.groups?[0].windows.count, 2)
        XCTAssertEqual(decodedCodex.allQuotaWindows.count, 4)
        XCTAssertEqual(decodedCodex.allQuotaWindows.map(\.id), ["5h", "weekly", "gpt-4o", "o1"])

        // Verify Claude (.unsupported)
        let decodedClaude = try XCTUnwrap(decoded.providerSummaries.first { $0.id == "claude" })
        XCTAssertTrue(decodedClaude.isEnabled)
        XCTAssertEqual(decodedClaude.usageStatus, .unsupported)
        XCTAssertEqual(decodedClaude.usageSummaryText, "Usage unsupported")
        XCTAssertNil(decodedClaude.usage?.windows)
        XCTAssertNil(decodedClaude.usage?.groups)
        XCTAssertTrue(decodedClaude.allQuotaWindows.isEmpty)

        // Verify Antigravity (1 window + Gemini group)
        let decodedAgy = try XCTUnwrap(decoded.providerSummaries.first { $0.id == "antigravity" })
        XCTAssertTrue(decodedAgy.isEnabled)
        XCTAssertEqual(decodedAgy.usageStatus, .available)
        XCTAssertEqual(decodedAgy.usage?.windows?.count, 1)
        XCTAssertEqual(decodedAgy.usage?.groups?.count, 1)
        XCTAssertEqual(decodedAgy.usage?.groups?[0].id, "gemini")
        XCTAssertEqual(decodedAgy.usage?.groups?[0].label, "Gemini Models")
        XCTAssertEqual(decodedAgy.usage?.groups?[0].windows.count, 2)
        XCTAssertEqual(decodedAgy.allQuotaWindows.count, 3)
        XCTAssertEqual(decodedAgy.allQuotaWindows.map(\.id), ["ag-5h", "gemini-pro", "gemini-flash"])

        // Verify Disabled provider
        let decodedDisabled = try XCTUnwrap(decoded.providerSummaries.first { $0.id == "mock" })
        XCTAssertFalse(decodedDisabled.isEnabled)
        XCTAssertEqual(decodedDisabled.healthStatus, "disabled")
        XCTAssertFalse(decodedDisabled.isDegradedOrUnavailable)
        XCTAssertEqual(decodedDisabled.usageStatus, .unavailable)
        XCTAssertEqual(decodedDisabled.usageSummaryText, "Monitoring disabled")
    }

    @MainActor
    func testCanonicalProviderOrderingAndUserEnablementFiltering() async {
        let codexProv = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [])
        let claudeProv = MockAgentProvider(id: .claude, displayName: "Claude Code", sessions: [])
        let agyProv = MockAgentProvider(id: .antigravity, displayName: "Antigravity", sessions: [])

        let store = SessionStore(
            providers: [codexProv, claudeProv, agyProv],
            enabledProviderIDs: [.codex, .claude, .antigravity]
        )
        await store.refresh()

        // 1. When Codex, Claude, and Antigravity are enabled -> all 3 appear in canonical order
        var snapshot = LoomWidgetSnapshot.make(from: store)
        var enabledProviders = snapshot.providers.filter(\.isEnabled)
        XCTAssertEqual(enabledProviders.count, 3)
        XCTAssertEqual(enabledProviders.map(\.id), ["codex", "claude", "antigravity"])
        XCTAssertEqual(enabledProviders.map(\.displayName), ["Codex", "Claude Code", "Antigravity"])

        // 2. When Claude is disabled -> only Codex and Antigravity appear
        store.updateEnabledProviders([.codex, .antigravity])
        await store.refresh()

        snapshot = LoomWidgetSnapshot.make(from: store)
        enabledProviders = snapshot.providers.filter(\.isEnabled)
        XCTAssertEqual(enabledProviders.count, 2)
        XCTAssertEqual(enabledProviders.map(\.id), ["codex", "antigravity"])
        XCTAssertEqual(enabledProviders.map(\.displayName), ["Codex", "Antigravity"])

        // Verify Claude still exists in snapshot with disabled status
        let claudeSummary = snapshot.providers.first { $0.id == "claude" }
        XCTAssertNotNil(claudeSummary)
        XCTAssertFalse(claudeSummary?.isEnabled ?? true)
        XCTAssertEqual(claudeSummary?.healthStatus, "disabled")

        // 3. When all providers are disabled -> enabled providers list is empty
        store.updateEnabledProviders([])
        await store.refresh()

        snapshot = LoomWidgetSnapshot.make(from: store)
        enabledProviders = snapshot.providers.filter(\.isEnabled)
        XCTAssertTrue(enabledProviders.isEmpty)
        XCTAssertEqual(snapshot.state(), .allDisabled)
        XCTAssertEqual(snapshot.statusMessage, "All providers disabled")
    }

    func testBackwardsCompatibilityOlderSnapshotDecodingGracefulDefaults() throws {
        // Legacy JSON without groups, windowDurationMins, lifecycleSummary, or statusMessage
        let olderJSON = """
        {
            "schemaVersion": 1,
            "timestamp": "2026-10-10T08:00:00Z",
            "activeSessionCount": 2,
            "attentionSessionCount": 0,
            "totalSessionCount": 2,
            "providerSummaries": [
                {
                    "id": "codex",
                    "displayName": "Codex",
                    "sessionCount": 2,
                    "healthStatus": "available",
                    "isDegradedOrUnavailable": false,
                    "usage": {
                        "status": "available",
                        "percentRemaining": 70,
                        "summary": "70% left",
                        "windows": [
                            {
                                "id": "primary",
                                "label": "5-Hour Quota",
                                "percentRemaining": 70,
                                "observedAt": "2026-10-10T08:00:00Z"
                            }
                        ]
                    }
                },
                {
                    "id": "claude",
                    "displayName": "Claude Code",
                    "sessionCount": 0,
                    "healthStatus": "available",
                    "isDegradedOrUnavailable": false
                }
            ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoomWidgetSnapshot.self, from: Data(olderJSON.utf8))

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertNil(snapshot.statusMessage)
        XCTAssertEqual(snapshot.providerSummaries.count, 2)

        // Codex: usage without groups or windowDurationMins
        let codex = snapshot.providerSummaries[0]
        XCTAssertEqual(codex.id, "codex")
        XCTAssertNil(codex.lifecycleSummary)
        XCTAssertEqual(codex.usageStatus, .available)
        XCTAssertNil(codex.usage?.groups)
        XCTAssertNil(codex.usage?.fractionUsed)
        XCTAssertNil(codex.usage?.planType)
        XCTAssertEqual(codex.allQuotaWindows.count, 1)

        let window = codex.allQuotaWindows[0]
        XCTAssertEqual(window.id, "primary")
        XCTAssertEqual(window.label, "5-Hour Quota")
        XCTAssertNil(window.windowDurationMins)
        XCTAssertEqual(window.compactLabel, "5-Hour Quota", "Without windowDurationMins, compactLabel must fall back to label")
        XCTAssertNil(window.resetsAt)

        // Claude: completely missing usage
        let claude = snapshot.providerSummaries[1]
        XCTAssertEqual(claude.id, "claude")
        XCTAssertNil(claude.usage)
        XCTAssertEqual(claude.usageStatus, .unknown)
        XCTAssertEqual(claude.usageSummaryText, "Usage unknown")
        XCTAssertTrue(claude.allQuotaWindows.isEmpty)
    }

    func testWindowLabelAndResetIntervalPreservationAcrossSerialization() throws {
        let obsDate = Date(timeIntervalSince1970: 1700000000)
        let resetDate1 = obsDate.addingTimeInterval(3600)
        let resetDate2 = obsDate.addingTimeInterval(86400)
        let resetDate3 = obsDate.addingTimeInterval(604800)

        let windows = [
            WidgetQuotaWindow(
                id: "w-5h",
                label: "Primary 5-Hour Session Quota Window",
                percentRemaining: 80,
                resetsAt: resetDate1,
                observedAt: obsDate,
                windowDurationMins: 300
            ),
            WidgetQuotaWindow(
                id: "w-weekly",
                label: "Weekly Extended Organizational Limit",
                percentRemaining: 50,
                resetsAt: resetDate3,
                observedAt: obsDate,
                windowDurationMins: 10080
            ),
            WidgetQuotaWindow(
                id: "w-daily",
                label: "Daily Request Tier",
                percentRemaining: 95,
                resetsAt: resetDate2,
                observedAt: obsDate,
                windowDurationMins: 1440
            ),
            WidgetQuotaWindow(
                id: "w-custom",
                label: "Short Burst Window",
                percentRemaining: 30,
                resetsAt: resetDate1,
                observedAt: obsDate,
                windowDurationMins: 45
            ),
            WidgetQuotaWindow(
                id: "w-nolimit",
                label: "Unbounded Rate Limit",
                percentRemaining: 100,
                resetsAt: nil,
                observedAt: obsDate,
                windowDurationMins: nil
            )
        ]

        let usage = ProviderUsageWidgetSummary(
            status: .available,
            summary: "Available",
            windows: Array(windows.prefix(2)),
            groups: [
                WidgetQuotaGroup(id: "extra", label: "Extra Limits", windows: Array(windows.suffix(3)))
            ]
        )

        let snapshot = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: obsDate,
            activeSessionCount: 1,
            attentionSessionCount: 0,
            totalSessionCount: 1,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 1,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    usage: usage
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LoomWidgetSnapshot.self, from: data)

        let decodedWindows = decoded.providerSummaries[0].allQuotaWindows
        XCTAssertEqual(decodedWindows.count, 5)

        // Window 0: 5h
        XCTAssertEqual(decodedWindows[0].id, "w-5h")
        XCTAssertEqual(decodedWindows[0].label, "Primary 5-Hour Session Quota Window")
        XCTAssertEqual(decodedWindows[0].windowDurationMins, 300)
        XCTAssertEqual(decodedWindows[0].compactLabel, "5h")
        XCTAssertEqual(decodedWindows[0].resetsAt?.timeIntervalSince1970, resetDate1.timeIntervalSince1970)
        XCTAssertEqual(decodedWindows[0].resetsAt?.timeIntervalSince(decoded.timestamp), 3600)

        // Window 1: Weekly
        XCTAssertEqual(decodedWindows[1].id, "w-weekly")
        XCTAssertEqual(decodedWindows[1].label, "Weekly Extended Organizational Limit")
        XCTAssertEqual(decodedWindows[1].windowDurationMins, 10080)
        XCTAssertEqual(decodedWindows[1].compactLabel, "Weekly")
        XCTAssertEqual(decodedWindows[1].resetsAt?.timeIntervalSince1970, resetDate3.timeIntervalSince1970)
        XCTAssertEqual(decodedWindows[1].resetsAt?.timeIntervalSince(decoded.timestamp), 604800)

        // Window 2: Daily (1d)
        XCTAssertEqual(decodedWindows[2].id, "w-daily")
        XCTAssertEqual(decodedWindows[2].label, "Daily Request Tier")
        XCTAssertEqual(decodedWindows[2].windowDurationMins, 1440)
        XCTAssertEqual(decodedWindows[2].compactLabel, "1d")
        XCTAssertEqual(decodedWindows[2].resetsAt?.timeIntervalSince1970, resetDate2.timeIntervalSince1970)
        XCTAssertEqual(decodedWindows[2].resetsAt?.timeIntervalSince(decoded.timestamp), 86400)

        // Window 3: 45m
        XCTAssertEqual(decodedWindows[3].id, "w-custom")
        XCTAssertEqual(decodedWindows[3].label, "Short Burst Window")
        XCTAssertEqual(decodedWindows[3].windowDurationMins, 45)
        XCTAssertEqual(decodedWindows[3].compactLabel, "45m")
        XCTAssertEqual(decodedWindows[3].resetsAt?.timeIntervalSince1970, resetDate1.timeIntervalSince1970)

        // Window 4: Unbounded (nil resetsAt, nil duration)
        XCTAssertEqual(decodedWindows[4].id, "w-nolimit")
        XCTAssertEqual(decodedWindows[4].label, "Unbounded Rate Limit")
        XCTAssertNil(decodedWindows[4].windowDurationMins)
        XCTAssertEqual(decodedWindows[4].compactLabel, "Unbounded Rate Limit")
        XCTAssertNil(decodedWindows[4].resetsAt)
    }
}
