//
//  StorageAndRefreshTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import LoomCore

final class StorageAndRefreshTests: XCTestCase {
    func testScanSkipsSymlinksAndDeduplicatesHardLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let data = root.appendingPathComponent("session.jsonl")
        try Data(repeating: 65, count: 8192).write(to: data)
        try fm.linkItem(at: data, to: root.appendingPathComponent("hardlink"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let locations = [StorageLocation(label: "Sessions", url: root)]
        let result = try XCTUnwrap(StorageScanner().measure(locations).first)
        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertGreaterThan(result.bytes, 0)
        let bounded = try XCTUnwrap(StorageScanner().measure(locations, maxFiles: 0).first)
        XCTAssertEqual(bounded.status, .partial)
    }

    func testMissingFolderIsNotReportedAsMeasuredZero() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = try XCTUnwrap(StorageScanner().measure([StorageLocation(label: "Absent", url: root)]).first)
        XCTAssertEqual(result.status, .missing)
    }

    func testLegacyWidgetSummaryStillDecodesWithoutNewWindows() throws {
        let json = Data(#"{"status":"available","summary":"41% left","percentRemaining":41}"#.utf8)
        let summary = try JSONDecoder().decode(ProviderUsageWidgetSummary.self, from: json)
        XCTAssertNil(summary.windows)
        XCTAssertEqual(summary.percentRemaining, 41)
    }

    @MainActor
    func testCancelledDiscoveryPreservesSessionsInsteadOfFinishingOrFailingThem() async {
        let provider = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [
            AgentSession(id: "one", provider: .codex, state: .working)
        ], usage: ProviderUsageSnapshot(providerID: .codex,
            primaryBucket: UsageBucket(identifier: "5h", label: "5 hours", usedFraction: 0.25)))
        let store = SessionStore(providers: [provider])
        await store.refresh()
        let observedAt = store.snapshot(for: .codex)?.usage?.updatedAt
        provider.setError(CancellationError())
        await store.refresh()
        XCTAssertEqual(store.allSessions.first?.state, .working)
        XCTAssertNil(store.snapshot(for: .codex)?.errorMessage)
        XCTAssertNil(store.snapshot(for: .codex)?.usageErrorMessage)
        XCTAssertEqual(store.snapshot(for: .codex)?.usage?.updatedAt, observedAt)
        XCTAssertEqual(store.snapshot(for: .codex)?.usage?.isStale, true)
    }

    @MainActor
    func testWidgetCarriesBothQuotaWindowsAndTheirOriginalObservationDate() async throws {
        let observedAt = Date(timeIntervalSince1970: 100)
        let usage = ProviderUsageSnapshot(providerID: .codex, updatedAt: observedAt,
            primaryBucket: UsageBucket(identifier: "5h", label: "5 hours", usedFraction: 0.59),
            secondaryBucket: UsageBucket(identifier: "weekly", label: "Weekly", usedFraction: 0.62))
        let store = SessionStore(providers: [MockAgentProvider(id: .codex, displayName: "Codex", usage: usage)])
        await store.refresh()
        let windows = try XCTUnwrap(LoomWidgetSnapshot.make(from: store).providers.first?.usage?.windows)
        XCTAssertEqual(windows.map(\.percentRemaining), [41, 38])
        XCTAssertEqual(windows.map(\.observedAt), [observedAt, observedAt])
        XCTAssertFalse(ProviderIssue.isCancellation(URLError(.timedOut)))
        XCTAssertTrue(ProviderIssue.isCancellation(URLError(.cancelled)))
    }

    func testStorageOverviewProportions() {
        // Zero bytes across all providers
        let zeroOverview = StorageOverview(summaries: [
            ProviderStorageSummary(providerID: .codex, name: "Codex", totalBytes: 0, fileCount: 0, isComplete: true, hasData: false),
            ProviderStorageSummary(providerID: .claude, name: "Claude", totalBytes: 0, fileCount: 0, isComplete: true, hasData: false)
        ])
        XCTAssertEqual(zeroOverview.totalBytes, 0)
        XCTAssertEqual(zeroOverview.totalFiles, 0)
        XCTAssertTrue(zeroOverview.isComplete)
        XCTAssertFalse(zeroOverview.hasData)
        XCTAssertEqual(zeroOverview.proportion(for: .codex), 0.0)
        XCTAssertEqual(zeroOverview.proportion(for: .claude), 0.0)
        XCTAssertEqual(zeroOverview.proportion(for: .antigravity), 0.0)

        // Single provider with positive bytes
        let singleOverview = StorageOverview(summaries: [
            ProviderStorageSummary(providerID: .codex, name: "Codex", totalBytes: 500, fileCount: 5, isComplete: true, hasData: true)
        ])
        XCTAssertEqual(singleOverview.totalBytes, 500)
        XCTAssertEqual(singleOverview.totalFiles, 5)
        XCTAssertTrue(singleOverview.isComplete)
        XCTAssertTrue(singleOverview.hasData)
        XCTAssertEqual(singleOverview.proportion(for: .codex), 1.0)
        XCTAssertEqual(singleOverview.proportion(for: .claude), 0.0)

        // Multiple providers
        let multiOverview = StorageOverview(summaries: [
            ProviderStorageSummary(providerID: .codex, name: "Codex", totalBytes: 300, fileCount: 3, isComplete: true, hasData: true),
            ProviderStorageSummary(providerID: .claude, name: "Claude", totalBytes: 700, fileCount: 7, isComplete: true, hasData: true),
            ProviderStorageSummary(providerID: .antigravity, name: "Antigravity", totalBytes: 0, fileCount: 0, isComplete: false, hasData: false)
        ])
        XCTAssertEqual(multiOverview.totalBytes, 1000)
        XCTAssertEqual(multiOverview.totalFiles, 10)
        XCTAssertFalse(multiOverview.isComplete)
        XCTAssertTrue(multiOverview.hasData)
        XCTAssertEqual(multiOverview.proportion(for: .codex), 0.3, accuracy: 1e-6)
        XCTAssertEqual(multiOverview.proportion(for: .claude), 0.7, accuracy: 1e-6)
        XCTAssertEqual(multiOverview.proportion(for: .antigravity), 0.0)
        XCTAssertEqual(multiOverview.proportion(for: ProviderID("unknown")), 0.0)

        // Proportions sum to 1.0 within floating point error
        let sum = multiOverview.proportion(for: .codex)
            + multiOverview.proportion(for: .claude)
            + multiOverview.proportion(for: .antigravity)
        XCTAssertEqual(sum, 1.0, accuracy: 1e-6)

        // Verify summary lookup
        XCTAssertEqual(multiOverview.summary(for: .codex)?.name, "Codex")
        XCTAssertNil(multiOverview.summary(for: ProviderID("unknown")))
    }

    func testStorageScannerMeasureOverview() throws {
        let scanner = StorageScanner()

        // Empty providers
        let emptyOverview = try scanner.measureOverview(for: [])
        XCTAssertTrue(emptyOverview.summaries.isEmpty)
        XCTAssertEqual(emptyOverview.totalBytes, 0)
        XCTAssertEqual(emptyOverview.totalFiles, 0)
        XCTAssertTrue(emptyOverview.isComplete)
        XCTAssertFalse(emptyOverview.hasData)

        // Mock locations
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let provider1Dir = tempRoot.appendingPathComponent("p1")
        try fm.createDirectory(at: provider1Dir, withIntermediateDirectories: true)
        let sampleFile = provider1Dir.appendingPathComponent("sample.txt")
        let sampleData = Data(repeating: 42, count: 2048)
        try sampleData.write(to: sampleFile)

        let provider2Dir = tempRoot.appendingPathComponent("missing_dir")
        // Don't create provider2Dir, so it's missing

        let provider3Dir = tempRoot.appendingPathComponent("p3_empty")
        try fm.createDirectory(at: provider3Dir, withIntermediateDirectories: true)

        let providers = [
            ProviderStorageLocations(id: .codex, name: "Codex", locations: [
                StorageLocation(label: "P1 Data", url: provider1Dir)
            ]),
            ProviderStorageLocations(id: .claude, name: "Claude", locations: [
                StorageLocation(label: "P2 Data", url: provider2Dir)
            ]),
            ProviderStorageLocations(id: .antigravity, name: "Antigravity", locations: [
                StorageLocation(label: "P3 Data", url: provider3Dir)
            ])
        ]

        let overview = try scanner.measureOverview(for: providers)
        XCTAssertEqual(overview.summaries.count, 3)

        let codexSummary = try XCTUnwrap(overview.summary(for: .codex))
        XCTAssertEqual(codexSummary.name, "Codex")
        XCTAssertGreaterThan(codexSummary.totalBytes, 0)
        XCTAssertEqual(codexSummary.fileCount, 1)
        XCTAssertTrue(codexSummary.isComplete)
        XCTAssertTrue(codexSummary.hasData)

        let claudeSummary = try XCTUnwrap(overview.summary(for: .claude))
        XCTAssertEqual(claudeSummary.name, "Claude")
        XCTAssertEqual(claudeSummary.totalBytes, 0)
        XCTAssertEqual(claudeSummary.fileCount, 0)
        XCTAssertTrue(claudeSummary.isComplete)
        XCTAssertFalse(claudeSummary.hasData)

        let antigravitySummary = try XCTUnwrap(overview.summary(for: .antigravity))
        XCTAssertEqual(antigravitySummary.name, "Antigravity")
        XCTAssertEqual(antigravitySummary.totalBytes, 0)
        XCTAssertEqual(antigravitySummary.fileCount, 0)
        XCTAssertTrue(antigravitySummary.isComplete)
        XCTAssertTrue(antigravitySummary.hasData)

        XCTAssertTrue(overview.isComplete)
        XCTAssertTrue(overview.hasData)
        XCTAssertEqual(overview.totalFiles, 1)
        XCTAssertEqual(overview.totalBytes, codexSummary.totalBytes)
        XCTAssertEqual(overview.proportion(for: .codex), 1.0, accuracy: 1e-6)
        XCTAssertEqual(overview.proportion(for: .claude), 0.0)
        XCTAssertEqual(overview.proportion(for: .antigravity), 0.0)
    }

    @MainActor
    func testSessionStoreRefreshStoragePopulatesOverviewAndRespectsCooldown() async {
        let store = SessionStore(providers: [])
        XCTAssertNil(store.storageOverview)
        XCTAssertFalse(store.isStorageScanning)

        await store.refreshStorage(force: true)

        XCTAssertNotNil(store.storageOverview)
        XCTAssertFalse(store.isStorageScanning)

        let firstOverview = store.storageOverview
        // Calling refreshStorage without force immediately after should respect the 30s cooldown and preserve identical overview instance
        await store.refreshStorage(force: false)
        XCTAssertEqual(store.storageOverview?.scannedAt, firstOverview?.scannedAt)
    }

    func testProviderStorageLocationsRespectsEnvironmentOverrides() {
        let customHome = URL(fileURLWithPath: "/Users/testuser", isDirectory: true)

        // 1. With absolute path overrides
        let envOverrides = [
            "CODEX_HOME": "/custom/path/to/codex",
            "CLAUDE_CONFIG_DIR": "/custom/path/to/claude"
        ]
        let overridden = ProviderStorageLocations.local(home: customHome, environment: envOverrides)

        let codexLocations = overridden.first(where: { $0.id == .codex })?.locations
        XCTAssertEqual(codexLocations?.first?.url.path, "/custom/path/to/codex")

        let claudeLocations = overridden.first(where: { $0.id == .claude })?.locations
        XCTAssertEqual(claudeLocations?.first?.url.path, "/custom/path/to/claude")

        // 2. Reject non-absolute (relative) paths and fallback to home
        let relativeEnv = [
            "CODEX_HOME": "relative/codex",
            "CLAUDE_CONFIG_DIR": "relative/claude"
        ]
        let fallback = ProviderStorageLocations.local(home: customHome, environment: relativeEnv)
        let codexFallback = fallback.first(where: { $0.id == .codex })?.locations
        XCTAssertEqual(codexFallback?.first?.url.path, "/Users/testuser/.codex")

        let claudeFallback = fallback.first(where: { $0.id == .claude })?.locations
        XCTAssertEqual(claudeFallback?.first?.url.path, "/Users/testuser/.claude")

        // 3. Verify Antigravity explicitly scopes to Gemini subfolders only
        let antigravityLocations = fallback.first(where: { $0.id == .antigravity })?.locations
        let antigravityPaths = Set(antigravityLocations?.map(\.url.path) ?? [])
        XCTAssertTrue(antigravityPaths.contains("/Users/testuser/.antigravity"))
        XCTAssertTrue(antigravityPaths.contains("/Users/testuser/.gemini/antigravity"))
        XCTAssertTrue(antigravityPaths.contains("/Users/testuser/.gemini/antigravity-cli"))
        XCTAssertFalse(antigravityPaths.contains("/Users/testuser/.gemini"), "Must not include parent .gemini root")
    }

    func testStorageScannerRootStatusTransitions() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let targetDir = tempDir.appendingPathComponent("target_folder")
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // 1. Root is a symbolic link
        let symlinkRoot = tempDir.appendingPathComponent("symlink_root")
        try fm.createSymbolicLink(at: symlinkRoot, withDestinationURL: targetDir)

        let scanner = StorageScanner()
        let symlinkResult = try XCTUnwrap(scanner.measure([StorageLocation(label: "Symlink", url: symlinkRoot)]).first)
        XCTAssertEqual(symlinkResult.status, .symbolicLink)

        // 2. Root is a regular file (inaccessible as a storage directory)
        let regularFile = tempDir.appendingPathComponent("file.txt")
        try Data("dummy".utf8).write(to: regularFile)
        let fileResult = try XCTUnwrap(scanner.measure([StorageLocation(label: "File", url: regularFile)]).first)
        XCTAssertEqual(fileResult.status, .inaccessible)
    }

    func testProviderIssueDiagnosticsAndCancellation() {
        // Cancellation checks
        XCTAssertTrue(ProviderIssue.isCancellation(CancellationError()))
        XCTAssertTrue(ProviderIssue.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(ProviderIssue.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(ProviderIssue.isCancellation(URLError(.badServerResponse)))
        XCTAssertFalse(ProviderIssue.isCancellation(NSError(domain: "LoomError", code: 999)))

        // Usage issues
        let usageWithSaved = ProviderIssue.usage(hasSavedData: true)
        XCTAssertEqual(usageWithSaved.title, "Couldn’t refresh usage")
        XCTAssertEqual(usageWithSaved.recovery, "Showing saved data. Try refreshing again.")

        let usageWithoutSaved = ProviderIssue.usage(hasSavedData: false)
        XCTAssertEqual(usageWithoutSaved.title, "Couldn’t refresh usage")
        XCTAssertEqual(usageWithoutSaved.recovery, "Open the provider app, then try refreshing again.")

        // Discovery issue
        let discovery = ProviderIssue.discovery
        XCTAssertEqual(discovery.title, "Couldn’t check sessions")
        XCTAssertEqual(discovery.recovery, "Open the provider app, then refresh Loom.")
    }
}
