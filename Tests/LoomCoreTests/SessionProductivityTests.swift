//
//  SessionProductivityTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
import Foundation
@testable import LoomCore

// MARK: - Testable Productivity Evaluators

public enum TestSessionFilterCriterion: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case needsAttention = "needsAttention"
    case working = "working"
    case recent = "recent"

    public var id: String { rawValue }
}

public enum TestSessionFilterEngine {
    public static func matches(
        session: AgentSession,
        query: String,
        filter: TestSessionFilterCriterion,
        hideProjectPaths: Bool = false
    ) -> Bool {
        switch filter {
        case .all:
            break
        case .needsAttention:
            guard session.state == .waiting || session.state == .failed else { return false }
        case .working:
            guard session.state == .working || session.state == .starting else { return false }
        case .recent:
            guard session.state == .idle || session.state == .finished || session.state == .unknown else { return false }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let q = trimmed.lowercased()

        if let name = session.projectName, name.lowercased().contains(q) {
            return true
        }
        if let folderName = session.projectPath?.lastPathComponent, folderName.lowercased().contains(q) {
            return true
        }
        if let branch = session.branch, branch.lowercased().contains(q) {
            return true
        }
        if let summary = session.summary, summary.lowercased().contains(q) {
            return true
        }
        if session.provider.displayName.lowercased().contains(q) {
            return true
        }
        if let pid = session.pid, String(pid).contains(q) {
            return true
        }
        for proc in session.associatedProcesses {
            if String(proc.pid).contains(q) {
                return true
            }
        }
        if let sid = session.providerSessionID, sid.lowercased().contains(q) {
            return true
        }
        if session.id.lowercased().contains(q) {
            return true
        }
        if !hideProjectPaths, let fullPath = session.projectPath?.path, fullPath.lowercased().contains(q) {
            return true
        }
        if let host = session.hostApp?.displayName, host.lowercased().contains(q) {
            return true
        }

        return false
    }

    public static func filterSessions(
        _ sessions: [AgentSession],
        query: String,
        filter: TestSessionFilterCriterion,
        hideProjectPaths: Bool = false
    ) -> [AgentSession] {
        sessions.filter { matches(session: $0, query: query, filter: filter, hideProjectPaths: hideProjectPaths) }
    }
}

public struct TestMenuBarStatusResult: Equatable {
    public let text: String?
    public let hasAttention: Bool
    public let activeCount: Int
    public let lowestQuotaPercent: Int?
}

public enum TestMenuBarStatusEvaluator {
    public static func evaluate(
        mode: MenuBarStatusMode,
        snapshots: [ProviderSnapshot]
    ) -> TestMenuBarStatusResult {
        let enabledSnapshots = snapshots.filter(\.isEnabled)
        let allSessions = enabledSnapshots.flatMap(\.sessions)

        let activeCount = allSessions.filter { session in
            session.state == .working || session.state == .starting
        }.count

        let hasAttention = allSessions.contains { session in
            session.state == .waiting || session.state == .failed
        }

        var validRemainingPercentages: [Int] = []
        for snapshot in enabledSnapshots {
            guard let usage = snapshot.usage,
                  !usage.isStale,
                  snapshot.usageErrorMessage == nil,
                  usage.errorMessage == nil else {
                continue
            }

            for bucket in usage.allBuckets {
                if let rem = bucket.remainingPercent {
                    validRemainingPercentages.append(rem)
                }
            }
        }

        let lowestQuotaPercent = validRemainingPercentages.min()

        let text: String?
        switch mode {
        case .iconOnly:
            text = nil
        case .activeSessionCount:
            text = activeCount > 0 ? "\(activeCount)" : nil
        case .lowestQuota:
            text = lowestQuotaPercent.map { "\($0)%" }
        }

        return TestMenuBarStatusResult(
            text: text,
            hasAttention: hasAttention,
            activeCount: activeCount,
            lowestQuotaPercent: lowestQuotaPercent
        )
    }
}

public enum DiagnosticsSanitizer {
    public static func sanitizeErrorMessage(_ text: String, hidePaths: Bool) -> String {
        var sanitized = text

        let patterns = [
            #"sk-[A-Za-z0-9_-]{8,}"#,
            #"Bearer\s+[A-Za-z0-9._-]+"#,
            #"token=[A-Za-z0-9._-]+"#,
            #"key=[A-Za-z0-9._-]+"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: NSRange(sanitized.startIndex..., in: sanitized),
                    withTemplate: "[redacted]"
                )
            }
        }

        if hidePaths {
            if sanitized.contains("/") || sanitized.contains("~") {
                return "Error details sanitized by privacy setting"
            }
        } else {
            let home = NSHomeDirectory()
            if sanitized.contains(home) {
                sanitized = sanitized.replacingOccurrences(of: home, with: "~")
            }
        }
        return sanitized
    }
}

// MARK: - Unit Tests

final class SessionProductivityTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSession(
        id: String,
        provider: ProviderID = .codex,
        projectName: String? = "Loom",
        path: String? = "/Users/deepak/Desktop/Projects/oss/Loom",
        state: AgentState = .working,
        branch: String? = "feature/v1.2",
        summary: String? = "Refactoring session view",
        pid: Int? = 42000,
        providerSessionID: String? = "sess-001"
    ) -> AgentSession {
        AgentSession(
            id: id,
            provider: provider,
            projectName: projectName,
            projectPath: path.map { URL(fileURLWithPath: $0) },
            state: state,
            startedAt: Date().addingTimeInterval(-300),
            lastActivityAt: Date(),
            branch: branch,
            summary: summary,
            pid: pid,
            providerSessionID: providerSessionID
        )
    }

    // MARK: - Filter Criterion Tests

    func testFilterByAllIncludesEveryState() {
        let sessions = [
            makeSession(id: "1", state: .working),
            makeSession(id: "2", state: .waiting),
            makeSession(id: "3", state: .failed),
            makeSession(id: "4", state: .finished),
            makeSession(id: "5", state: .idle)
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "", filter: .all)
        XCTAssertEqual(results.count, 5)
    }

    func testFilterByNeedsAttentionOnlyIncludesWaitingAndFailed() {
        let sessions = [
            makeSession(id: "1", state: .working),
            makeSession(id: "2", state: .waiting),
            makeSession(id: "3", state: .failed),
            makeSession(id: "4", state: .finished),
            makeSession(id: "5", state: .idle),
            makeSession(id: "6", state: .starting)
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "", filter: .needsAttention)
        XCTAssertEqual(results.map(\.id), ["2", "3"])
    }

    func testFilterByWorkingOnlyIncludesWorkingAndStarting() {
        let sessions = [
            makeSession(id: "1", state: .working),
            makeSession(id: "2", state: .waiting),
            makeSession(id: "3", state: .failed),
            makeSession(id: "4", state: .finished),
            makeSession(id: "5", state: .starting)
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "", filter: .working)
        XCTAssertEqual(results.map(\.id), ["1", "5"])
    }

    func testFilterByRecentIncludesIdleFinishedAndUnknown() {
        let sessions = [
            makeSession(id: "1", state: .working),
            makeSession(id: "2", state: .waiting),
            makeSession(id: "3", state: .finished),
            makeSession(id: "4", state: .idle),
            makeSession(id: "5", state: .unknown)
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "", filter: .recent)
        XCTAssertEqual(results.map(\.id), ["3", "4", "5"])
    }

    // MARK: - Search Query Matching Tests

    func testSearchQueryMatchesProjectName() {
        let sessions = [
            makeSession(id: "1", projectName: "Loom"),
            makeSession(id: "2", projectName: "ChaiWithCode"),
            makeSession(id: "3", projectName: "AntigravityCLI")
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "chai", filter: .all)
        XCTAssertEqual(results.map(\.id), ["2"])
    }

    func testSearchQueryMatchesBranchName() {
        let sessions = [
            makeSession(id: "1", branch: "main"),
            makeSession(id: "2", branch: "feature/redesign"),
            makeSession(id: "3", branch: "fix/parser")
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "redesign", filter: .all)
        XCTAssertEqual(results.map(\.id), ["2"])
    }

    func testSearchQueryMatchesActivitySummary() {
        let sessions = [
            makeSession(id: "1", summary: "Writing unit tests"),
            makeSession(id: "2", summary: "Fixing memory leak"),
            makeSession(id: "3", summary: "Designing Liquid Glass")
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "memory", filter: .all)
        XCTAssertEqual(results.map(\.id), ["2"])
    }

    func testSearchQueryMatchesPID() {
        let sessions = [
            makeSession(id: "1", pid: 12345),
            makeSession(id: "2", pid: 67890)
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "12345", filter: .all)
        XCTAssertEqual(results.map(\.id), ["1"])
    }

    func testSearchQueryMatchesProviderSessionID() {
        let sessions = [
            makeSession(id: "1", providerSessionID: "sess-abc-111"),
            makeSession(id: "2", providerSessionID: "sess-xyz-999")
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "xyz", filter: .all)
        XCTAssertEqual(results.map(\.id), ["2"])
    }

    func testSearchQueryCaseInsensitiveAndTrimming() {
        let sessions = [
            makeSession(id: "1", projectName: "Loom")
        ]

        XCTAssertEqual(TestSessionFilterEngine.filterSessions(sessions, query: "  lOoM  ", filter: .all).count, 1)
        XCTAssertEqual(TestSessionFilterEngine.filterSessions(sessions, query: "LOOM", filter: .all).count, 1)
        XCTAssertEqual(TestSessionFilterEngine.filterSessions(sessions, query: "notfound", filter: .all).count, 0)
    }

    func testPrivacyModeSearchConcealment() {
        let sessions = [
            makeSession(
                id: "1",
                projectName: "Loom",
                path: "/Users/deepak/Desktop/PrivateSecretDir/Loom"
            )
        ]

        // When hideProjectPaths is false: matches internal path string
        let matchVisible = TestSessionFilterEngine.filterSessions(sessions, query: "PrivateSecretDir", filter: .all, hideProjectPaths: false)
        XCTAssertEqual(matchVisible.count, 1)

        // When hideProjectPaths is true: does NOT match internal hidden path string
        let matchConcealed = TestSessionFilterEngine.filterSessions(sessions, query: "PrivateSecretDir", filter: .all, hideProjectPaths: true)
        XCTAssertEqual(matchConcealed.count, 0)

        // But still matches the safe project name
        let matchName = TestSessionFilterEngine.filterSessions(sessions, query: "Loom", filter: .all, hideProjectPaths: true)
        XCTAssertEqual(matchName.count, 1)
    }

    func testFilterPreservesDeterministicOrder() {
        let sessions = [
            makeSession(id: "alpha", projectName: "Loom Alpha", state: .working),
            makeSession(id: "beta", projectName: "Loom Beta", state: .working),
            makeSession(id: "gamma", projectName: "Loom Gamma", state: .working)
        ]

        let results = TestSessionFilterEngine.filterSessions(sessions, query: "Loom", filter: .working)
        XCTAssertEqual(results.map(\.id), ["alpha", "beta", "gamma"])
    }

    // MARK: - Menu Bar Status Mode Tests

    func testMenuBarModeIconOnly() {
        let sessions = [
            makeSession(id: "1", state: .working),
            makeSession(id: "2", state: .working)
        ]
        let snapshot = ProviderSnapshot(providerID: .codex, displayName: "Codex", sessions: sessions)

        let result = TestMenuBarStatusEvaluator.evaluate(mode: .iconOnly, snapshots: [snapshot])
        XCTAssertNil(result.text, "Icon only mode must have nil status text")
        XCTAssertFalse(result.hasAttention)
        XCTAssertEqual(result.activeCount, 2)
    }

    func testMenuBarModeIconOnlyWithAttention() {
        let sessions = [
            makeSession(id: "1", state: .working),
            makeSession(id: "2", state: .waiting)
        ]
        let snapshot = ProviderSnapshot(providerID: .codex, displayName: "Codex", sessions: sessions)

        let result = TestMenuBarStatusEvaluator.evaluate(mode: .iconOnly, snapshots: [snapshot])
        XCTAssertNil(result.text)
        XCTAssertTrue(result.hasAttention, "Session in .waiting must trigger attention")
    }

    func testMenuBarModeActiveSessionCount() {
        let sessions = [
            makeSession(id: "1", state: .working),
            makeSession(id: "2", state: .starting),
            makeSession(id: "3", state: .finished)
        ]
        let snapshot = ProviderSnapshot(providerID: .codex, displayName: "Codex", sessions: sessions)

        let result = TestMenuBarStatusEvaluator.evaluate(mode: .activeSessionCount, snapshots: [snapshot])
        XCTAssertEqual(result.text, "2", "Active count mode must show working + starting count")
        XCTAssertEqual(result.activeCount, 2)
        XCTAssertFalse(result.hasAttention)
    }

    func testMenuBarModeActiveSessionCountZeroReturnsNil() {
        let sessions = [
            makeSession(id: "1", state: .finished),
            makeSession(id: "2", state: .idle)
        ]
        let snapshot = ProviderSnapshot(providerID: .codex, displayName: "Codex", sessions: sessions)

        let result = TestMenuBarStatusEvaluator.evaluate(mode: .activeSessionCount, snapshots: [snapshot])
        XCTAssertNil(result.text, "Zero active sessions must return nil text to avoid crowding menu bar")
        XCTAssertEqual(result.activeCount, 0)
    }

    func testMenuBarModeLowestQuotaFormatting() {
        let bucket5h = UsageBucket(identifier: "5h", label: "5-hour", usedFraction: 0.58) // 42% remaining
        let bucketWeekly = UsageBucket(identifier: "7d", label: "Weekly", usedFraction: 0.20) // 80% remaining
        let usage = ProviderUsageSnapshot(
            providerID: .codex,
            primaryBucket: bucket5h,
            secondaryBucket: bucketWeekly
        )
        let snapshot = ProviderSnapshot(providerID: .codex, displayName: "Codex", usage: usage)

        let result = TestMenuBarStatusEvaluator.evaluate(mode: .lowestQuota, snapshots: [snapshot])
        XCTAssertEqual(result.text, "42%", "Lowest quota mode must format lowest remaining percentage")
        XCTAssertEqual(result.lowestQuotaPercent, 42)
    }

    func testMenuBarModeLowestQuotaNeverInterpretsMissingOrStaleAsZero() {
        // Case 1: Missing usage snapshot entirely
        let emptySnapshot = ProviderSnapshot(providerID: .claude, displayName: "Claude Code", usage: nil)
        let emptyResult = TestMenuBarStatusEvaluator.evaluate(mode: .lowestQuota, snapshots: [emptySnapshot])
        XCTAssertNil(emptyResult.text, "Missing usage must return nil text, NEVER 0%")
        XCTAssertNil(emptyResult.lowestQuotaPercent)

        // Case 2: Stale usage snapshot
        let staleUsage = ProviderUsageSnapshot(
            providerID: .codex,
            primaryBucket: UsageBucket(identifier: "5h", label: "5-hour", usedFraction: 0.90),
            isStale: true
        )
        let staleSnapshot = ProviderSnapshot(providerID: .codex, displayName: "Codex", usage: staleUsage)
        let staleResult = TestMenuBarStatusEvaluator.evaluate(mode: .lowestQuota, snapshots: [staleSnapshot])
        XCTAssertNil(staleResult.text, "Stale usage snapshot must be excluded and return nil, NEVER 0%")

        // Case 3: Errored usage snapshot
        let errorUsage = ProviderUsageSnapshot(
            providerID: .antigravity,
            primaryBucket: UsageBucket(identifier: "gemini", label: "Gemini", usedFraction: 0.50),
            errorMessage: "Connection timeout"
        )
        let errorSnapshot = ProviderSnapshot(providerID: .antigravity, displayName: "Antigravity", usage: errorUsage)
        let errorResult = TestMenuBarStatusEvaluator.evaluate(mode: .lowestQuota, snapshots: [errorSnapshot])
        XCTAssertNil(errorResult.text, "Errored usage must be excluded and return nil, NEVER 0%")
    }

    func testMenuBarModeLowestQuotaMultipleProvidersPicksMinimumValid() {
        let codexUsage = ProviderUsageSnapshot(
            providerID: .codex,
            primaryBucket: UsageBucket(identifier: "5h", label: "5-hour", usedFraction: 0.30) // 70% remaining
        )
        let agyUsage = ProviderUsageSnapshot(
            providerID: .antigravity,
            primaryBucket: UsageBucket(identifier: "gemini", label: "Gemini", usedFraction: 0.65) // 35% remaining
        )

        let snapCodex = ProviderSnapshot(providerID: .codex, displayName: "Codex", usage: codexUsage)
        let snapAgy = ProviderSnapshot(providerID: .antigravity, displayName: "Antigravity", usage: agyUsage)

        let result = TestMenuBarStatusEvaluator.evaluate(mode: .lowestQuota, snapshots: [snapCodex, snapAgy])
        XCTAssertEqual(result.text, "35%", "Must choose lowest valid remaining percentage across all enabled providers")
        XCTAssertEqual(result.lowestQuotaPercent, 35)
    }

    func testMenuBarModeIgnoresDisabledProviders() {
        let bucket = UsageBucket(identifier: "5h", label: "5-hour", usedFraction: 0.95) // 5% remaining
        let usage = ProviderUsageSnapshot(providerID: .codex, primaryBucket: bucket)
        let disabledSnapshot = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessions: [makeSession(id: "1", state: .waiting)],
            usage: usage,
            isEnabled: false
        )

        let result = TestMenuBarStatusEvaluator.evaluate(mode: .lowestQuota, snapshots: [disabledSnapshot])
        XCTAssertNil(result.text, "Disabled provider quota must be excluded")
        XCTAssertFalse(result.hasAttention, "Disabled provider waiting session must not trigger attention")
    }

    // MARK: - Diagnostics Sanitization Tests

    func testDiagnosticsSanitizationRedactsTokensAndPasswords() {
        let rawError = "Failed to authenticate with token sk-ant-api03-abcdef123456789 and Bearer secret-token-xyz"
        let sanitized = DiagnosticsSanitizer.sanitizeErrorMessage(rawError, hidePaths: false)

        XCTAssertFalse(sanitized.contains("sk-ant-api03-abcdef123456789"))
        XCTAssertFalse(sanitized.contains("secret-token-xyz"))
        XCTAssertTrue(sanitized.contains("[redacted]"))
    }

    func testDiagnosticsSanitizationConcealsPathsWhenPrivacyModeActive() {
        let rawError = "Cannot access /Users/deepak/Desktop/PrivateRepo/config.json"
        let sanitized = DiagnosticsSanitizer.sanitizeErrorMessage(rawError, hidePaths: true)

        XCTAssertEqual(sanitized, "Error details sanitized by privacy setting")
    }
}
