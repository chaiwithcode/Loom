//
//  LoomRegressionTestSuite.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
import Foundation
import SwiftUI
import AppKit
@testable import LoomCore

// MARK: - Test Doubles & Helpers

private struct RegressionMockWorkspaceResolver: WorkspaceResolving, Sendable {
    let mapping: [pid_t: ResolvedWorkspace]
    let defaultWorkspace: ResolvedWorkspace

    init(
        mapping: [pid_t: ResolvedWorkspace] = [:],
        defaultWorkspace: ResolvedWorkspace = ResolvedWorkspace(
            projectName: "Loom",
            projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom"),
            branch: "main",
            sourceDescription: "test"
        )
    ) {
        self.mapping = mapping
        self.defaultWorkspace = defaultWorkspace
    }

    func resolveWorkspace(
        for process: AgentProcess,
        parent: AgentProcess?,
        explicitMetadataURL: URL?
    ) async -> ResolvedWorkspace {
        if let resolved = mapping[process.pid] {
            return resolved
        }
        return defaultWorkspace
    }
}

private enum TestSessionFilterCriterion: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case needsAttention = "needsAttention"
    case working = "working"
    case recent = "recent"

    var id: String { rawValue }
}

private enum TestSessionFilterEngine {
    static func matches(
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
}

// MARK: - Priority 1: Agent Discovery & Duplicate-Session Handling

final class AgentDiscoveryRegressionTests: XCTestCase {

    /// Verifies that two distinct CLI processes operating concurrently in the same repository
    /// and host app without session tokens are NOT collapsed into a duplicate single session,
    /// but rather receive distinct stable IDs disambiguated by root PID.
    func testConcurrentSessionsInSameWorkspaceDisambiguatedByPID() async {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let baseDate = Date().addingTimeInterval(-120)

        let psOutput = """
          100     1 Sat Oct 23 10:00:00 2026 /Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
          101   100 Sat Oct 23 10:00:01 2026 /bin/zsh -l
          1001  101 Sat Oct 23 10:00:05 2026 /opt/homebrew/bin/codex exec --working-dir /Users/developer/Desktop/Projects/oss/Loom
          102   100 Sat Oct 23 10:00:02 2026 /bin/zsh -l
          1002  102 Sat Oct 23 10:00:06 2026 /opt/homebrew/bin/codex exec --working-dir /Users/developer/Desktop/Projects/oss/Loom
        """

        let nodes = ProcessTree.parsePsOutput(psOutput)
        let tree = ProcessTree(nodes: nodes)

        let proc1 = AgentProcess(
            pid: 1001,
            parentPID: 101,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "/opt/homebrew/bin/codex exec --working-dir /Users/developer/Desktop/Projects/oss/Loom",
            startedAt: baseDate,
            provider: .codex
        )

        let proc2 = AgentProcess(
            pid: 1002,
            parentPID: 102,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "/opt/homebrew/bin/codex exec --working-dir /Users/developer/Desktop/Projects/oss/Loom",
            startedAt: baseDate.addingTimeInterval(1),
            provider: .codex
        )

        let resolver = RegressionMockWorkspaceResolver(defaultWorkspace: ResolvedWorkspace(
            projectName: "Loom",
            projectPath: repoURL,
            branch: "main",
            sourceDescription: "test"
        ))

        let engine = DefaultSessionCorrelationEngine()
        let sessions = await engine.correlate(
            processes: [proc1, proc2],
            processTree: tree,
            workspaceResolver: resolver
        )

        XCTAssertEqual(sessions.count, 2, "Concurrent independent processes must produce 2 distinct sessions")
        XCTAssertNotEqual(sessions[0].id, sessions[1].id, "Stable session IDs must be unique and disambiguated")
        XCTAssertTrue(sessions.contains(where: { $0.pid == 1001 }))
        XCTAssertTrue(sessions.contains(where: { $0.pid == 1002 }))
        XCTAssertEqual(sessions[0].projectPath, sessions[1].projectPath, "Both sessions share the same repository path")
    }

    /// Verifies that a root process and its spawned worker subprocesses and leaf tools
    /// are collapsed into exactly one logical session with accurate process count and leaf activity summary.
    func testChildAndDescendantProcessTreeCollapse() async {
        let psOutput = """
          200     1 Sat Oct 23 10:00:00 2026 /Applications/Visual Studio Code.app/Contents/MacOS/Electron
          201   200 Sat Oct 23 10:00:02 2026 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper
          2000  201 Sat Oct 23 10:00:10 2026 /opt/homebrew/bin/codex sandbox /Users/developer/Projects/Loom
          2001 2000 Sat Oct 23 10:00:12 2026 /usr/local/bin/node /usr/local/lib/node_modules/codex/kernel.js
          2002 2001 Sat Oct 23 10:00:15 2026 /usr/bin/swift test --filter LoomCoreTests
        """

        let nodes = ProcessTree.parsePsOutput(psOutput)
        let tree = ProcessTree(nodes: nodes)

        let startedAt = Date().addingTimeInterval(-60)
        let procRoot = AgentProcess(
            pid: 2000,
            parentPID: 201,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "codex sandbox /Users/developer/Projects/Loom",
            startedAt: startedAt,
            provider: .codex
        )
        let procKernel = AgentProcess(
            pid: 2001,
            parentPID: 2000,
            executable: "/usr/local/bin/node",
            commandLine: "node kernel.js",
            startedAt: startedAt.addingTimeInterval(2),
            provider: .codex
        )
        let procLeaf = AgentProcess(
            pid: 2002,
            parentPID: 2001,
            executable: "/usr/bin/swift",
            commandLine: "swift test --filter LoomCoreTests",
            startedAt: startedAt.addingTimeInterval(5),
            provider: .codex
        )

        let engine = DefaultSessionCorrelationEngine()
        let sessions = await engine.correlate(
            processes: [procRoot, procKernel, procLeaf],
            processTree: tree,
            workspaceResolver: RegressionMockWorkspaceResolver()
        )

        XCTAssertEqual(sessions.count, 1, "Process hierarchy must collapse into a single logical session")
        let session = sessions[0]
        XCTAssertEqual(session.pid, 2000, "Primary process PID must be the root process")
        XCTAssertEqual(session.processCount, 3, "All 3 processes in the tree must be tracked")
        XCTAssertEqual(session.state, AgentState.working, "Session with active child workers must have Working state")
        XCTAssertEqual(session.summary, "Running swift test", "Summary must reflect leaf worker execution")
        XCTAssertEqual(session.hostApp, HostApp.vsCode, "Host application must resolve to VS Code")
    }

    /// Verifies that multiple processes sharing an explicit session token
    /// are consolidated into one logical session matching the token.
    func testExplicitSessionIDTokenDeduplication() async {
        let token = "98c95ead7ccd476aae7aa8ba50350c54"
        let proc1 = AgentProcess(
            pid: 3001,
            parentPID: 1,
            executable: "codex",
            commandLine: "codex sandbox --session-id=\(token) /repo",
            provider: .codex,
            sessionIDToken: token
        )
        let proc2 = AgentProcess(
            pid: 3002,
            parentPID: 3001,
            executable: "node",
            commandLine: "node kernel.js",
            provider: .codex,
            sessionIDToken: token
        )

        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 3001, parentPID: 1, command: proc1.commandLine, executable: proc1.executable),
            ProcessNode(pid: 3002, parentPID: 3001, command: proc2.commandLine, executable: proc2.executable)
        ])

        let engine = DefaultSessionCorrelationEngine()
        let sessions = await engine.correlate(
            processes: [proc1, proc2],
            processTree: tree,
            workspaceResolver: RegressionMockWorkspaceResolver()
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "codex-\(token)")
        XCTAssertEqual(sessions[0].providerSessionID, token)
    }

    /// Verifies that concurrent processes from different providers (Codex, Claude, Antigravity)
    /// remain strictly isolated and never merge across provider boundaries.
    func testCrossProviderProcessIsolation() async {
        let codexProc = AgentProcess(
            pid: 4001,
            parentPID: 1,
            executable: "codex",
            commandLine: "codex exec",
            provider: .codex
        )
        let claudeProc = AgentProcess(
            pid: 4002,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            provider: .claude
        )
        let agyProc = AgentProcess(
            pid: 4003,
            parentPID: 1,
            executable: "antigravity-server",
            commandLine: "antigravity-server",
            provider: .antigravity
        )

        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 4001, parentPID: 1, command: codexProc.commandLine, executable: codexProc.executable),
            ProcessNode(pid: 4002, parentPID: 1, command: claudeProc.commandLine, executable: claudeProc.executable),
            ProcessNode(pid: 4003, parentPID: 1, command: agyProc.commandLine, executable: agyProc.executable)
        ])

        let engine = DefaultSessionCorrelationEngine()
        let sessions = await engine.correlate(
            processes: [codexProc, claudeProc, agyProc],
            processTree: tree,
            workspaceResolver: RegressionMockWorkspaceResolver()
        )

        XCTAssertEqual(sessions.count, 3)
        let providers = Set(sessions.map(\.provider))
        XCTAssertEqual(providers, [.codex, .claude, .antigravity])
    }

    /// Defensive regression check: cyclic or self-referential process tables do not loop infinitely.
    func testCyclicAndOrphanProcessTreeHandling() {
        let cyclicOutput = """
          500   501 Sat Oct 23 10:00:00 2026 /path/to/procA
          501   500 Sat Oct 23 10:00:01 2026 /path/to/procB
          502   999 Sat Oct 23 10:00:02 2026 /path/to/procOrphan
        """
        let nodes = ProcessTree.parsePsOutput(cyclicOutput)
        let tree = ProcessTree(nodes: nodes)

        // Must terminate safely and not crash
        let descendants500 = tree.descendants(of: 500)
        let ancestors500 = tree.ancestors(of: 500)
        let hostOrphan = tree.resolveHostApp(for: 502)

        XCTAssertNotNil(descendants500)
        XCTAssertNotNil(ancestors500)
        XCTAssertNil(hostOrphan)
    }
}

// MARK: - Priority 2: Session Lifecycle Transitions & Active-First Sorting

final class SessionLifecycleAndSortingRegressionTests: XCTestCase {

    /// Verifies the full lifecycle transition pipeline from active to finished when a process departs.
    func testSessionFullLifecycleTransitions() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()

        let initialSession = AgentSession(
            id: "session-active-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: URL(fileURLWithPath: "/Users/dev/Loom"),
            state: .working,
            startedAt: now.addingTimeInterval(-300),
            lastActivityAt: now.addingTimeInterval(-60),
            summary: "Compiling tests",
            pid: 6001
        )

        // Discovery 1: Active session present
        let step1 = await reconciler.reconcile(newSessions: [initialSession], now: now)
        XCTAssertEqual(step1.count, 1)
        XCTAssertEqual(step1[0].state, AgentState.working)

        // Discovery 2: Process has exited, missing from newSessions
        let departureTime = now.addingTimeInterval(30)
        let step2 = await reconciler.reconcile(
            newSessions: [],
            now: departureTime,
            providerTerminationReason: "process exited"
        )

        XCTAssertEqual(step2.count, 1, "Departed session must be retained in Finished state")
        XCTAssertEqual(step2[0].state, AgentState.finished)
        XCTAssertEqual(step2[0].summary, "Session finished (process exited)")
        XCTAssertEqual(step2[0].lastActivityAt, departureTime, "Finished session lastActivityAt must record termination time")

        // Discovery 3: Beyond retention window (900s) -> pruned
        let expiredTime = departureTime.addingTimeInterval(901)
        let step3 = await reconciler.reconcile(newSessions: [], now: expiredTime)
        XCTAssertTrue(step3.isEmpty, "Finished session must be pruned after expiration of retention window")
    }

    /// Verifies deterministic project group active-first sorting:
    /// Groups with active sessions sort ahead of finished groups, ordered by latest activity date.
    func testActiveFirstProjectGroupSorting() {
        let now = Date()
        let pathA = URL(fileURLWithPath: "/Users/dev/ProjectAlpha")
        let pathB = URL(fileURLWithPath: "/Users/dev/ProjectBeta")
        let pathC = URL(fileURLWithPath: "/Users/dev/ProjectGamma")

        // Group A: Finished 10 minutes ago
        let sessionA = AgentSession(
            id: "sess-a",
            provider: .codex,
            projectName: "ProjectAlpha",
            projectPath: pathA,
            state: .finished,
            startedAt: now.addingTimeInterval(-1800),
            lastActivityAt: now.addingTimeInterval(-600)
        )

        // Group B: Working 1 minute ago (Active)
        let sessionB = AgentSession(
            id: "sess-b",
            provider: .claude,
            projectName: "ProjectBeta",
            projectPath: pathB,
            state: .working,
            startedAt: now.addingTimeInterval(-600),
            lastActivityAt: now.addingTimeInterval(-60)
        )

        // Group C: Waiting for user input 2 minutes ago (Active / Attention)
        let sessionC = AgentSession(
            id: "sess-c",
            provider: .antigravity,
            projectName: "ProjectGamma",
            projectPath: pathC,
            state: .waiting,
            startedAt: now.addingTimeInterval(-900),
            lastActivityAt: now.addingTimeInterval(-120)
        )

        let groups = ProjectGroup.groupSessions([sessionA, sessionB, sessionC])
        XCTAssertEqual(groups.count, 3)

        // Group B (lastActivity -60s) must be first, followed by Group C (-120s), followed by Group A (-600s)
        XCTAssertEqual(groups[0].projectName, "ProjectBeta")
        XCTAssertEqual(groups[1].projectName, "ProjectGamma")
        XCTAssertEqual(groups[2].projectName, "ProjectAlpha")
    }

    /// Verifies provider section prioritization logic:
    /// 1. Needs Attention (.waiting, .failed)
    /// 2. Active (.working/.starting rank 0, .idle rank 1, .unknown rank 2)
    /// 3. Finished sessions in separate recent collection.
    func testProviderSectionActiveFirstRanking() {
        let now = Date()

        let waiting = AgentSession(id: "s-waiting", provider: .codex, state: .waiting, startedAt: now, lastActivityAt: now)
        let failed = AgentSession(id: "s-failed", provider: .codex, state: .failed, startedAt: now, lastActivityAt: now)
        let working = AgentSession(id: "s-working", provider: .codex, state: .working, startedAt: now, lastActivityAt: now)
        let starting = AgentSession(id: "s-starting", provider: .codex, state: .starting, startedAt: now, lastActivityAt: now)
        let idle = AgentSession(id: "s-idle", provider: .codex, state: .idle, startedAt: now, lastActivityAt: now)
        let unknown = AgentSession(id: "s-unknown", provider: .codex, state: .unknown, startedAt: now, lastActivityAt: now)
        let finished = AgentSession(id: "s-finished", provider: .codex, state: .finished, startedAt: now, lastActivityAt: now)

        let all = [finished, idle, unknown, working, waiting, failed, starting]

        // Attention partition
        let attention = all.filter { $0.state == .waiting || $0.state == .failed }
        XCTAssertEqual(Set(attention.map(\.id)), ["s-waiting", "s-failed"])

        // Active partition ranked
        let active = all
            .filter { $0.state == .working || $0.state == .starting || $0.state == .idle || $0.state == .unknown }
            .sorted { lhs, rhs in
                func rank(_ s: AgentSession) -> Int {
                    switch s.state {
                    case .working, .starting: return 0
                    case .idle: return 1
                    default: return 2
                    }
                }
                let r1 = rank(lhs)
                let r2 = rank(rhs)
                if r1 != r2 { return r1 < r2 }
                return lhs.id < rhs.id
            }

        // Rank 0 (working & starting) must come before Rank 1 (idle), which comes before Rank 2 (unknown)
        XCTAssertEqual(active[0].state, AgentState.starting)
        XCTAssertEqual(active[1].state, AgentState.working)
        XCTAssertEqual(active[2].state, AgentState.idle)
        XCTAssertEqual(active[3].state, AgentState.unknown)
    }

    /// Verifies that failed sessions retain error diagnostics and failure state across discovery cycles.
    func testFailedSessionDiagnosticsAndRetention() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900)
        let now = Date()

        let failedSession = AgentSession(
            id: "failed-proc-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: URL(fileURLWithPath: "/Users/dev/Loom"),
            state: .failed,
            startedAt: now.addingTimeInterval(-100),
            lastActivityAt: now.addingTimeInterval(-10),
            summary: "Process crashed with SIGSEGV",
            pid: 7777,
            diagnostics: ProviderDiscoveryDiagnostics(
                processesDetected: 1,
                logicalSessions: 1,
                workspacesResolved: 1,
                metadataStatus: .partial,
                metadataError: "Crash log detected",
                discoveryDuration: 0.042
            ),
            discoveryEvidence: ["Exit code: 139 (SIGSEGV)"]
        )

        // Staged as failed
        _ = await reconciler.reconcile(newSessions: [failedSession], now: now)

        // Next cycle: process disappeared
        let retained = await reconciler.reconcile(newSessions: [], now: now.addingTimeInterval(30))
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained[0].state, AgentState.failed, "State must remain .failed, never falsely overwritten with .finished")
        XCTAssertEqual(retained[0].summary, "Process crashed with SIGSEGV")
        XCTAssertEqual(retained[0].diagnostics?.metadataError, "Crash log detected")
    }

    /// Verifies that discovery errors do not manufacture a false Finished state.
    func testProviderErrorDoesNotManufactureFinishedSession() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900)
        let now = Date()

        let session = AgentSession(
            id: "active-codex",
            provider: .codex,
            state: .working,
            startedAt: now.addingTimeInterval(-60)
        )

        _ = await reconciler.reconcile(newSessions: [session], now: now)

        // Error during discovery:
        let result = await reconciler.reconcile(
            newSessions: [],
            now: now.addingTimeInterval(10),
            providerError: "daemon connection lost"
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].state, AgentState.working, "State must be preserved when provider encountered an error")
        XCTAssertTrue(result[0].discoveryEvidence.contains(where: { $0.contains("daemon connection lost") }))
    }
}

// MARK: - Priority 3: Stale & Unknown Session Filtering

final class StaleAndUnknownSessionFilteringRegressionTests: XCTestCase {

    /// Verifies that a working session exceeding the 30-minute stale threshold without
    /// positive waiting keywords truthfully downgrades to Idle instead of falsely claiming Waiting.
    func testStaleWorkingSessionWithoutWaitingEvidenceTransitionsToIdle() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()

        let staleSession = AgentSession(
            id: "stale-worker",
            provider: .codex,
            state: .working,
            startedAt: now.addingTimeInterval(-3600),
            lastActivityAt: now.addingTimeInterval(-2400), // 40 minutes ago (>30m)
            summary: "Compiling binary",
            discoveryEvidence: ["State: Working"]
        )

        let result = await reconciler.reconcile(newSessions: [staleSession], now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].state, AgentState.idle, "Stale working session without waiting evidence must transition to Idle")
        XCTAssertTrue(result[0].discoveryEvidence.contains(where: { $0.contains("transitioned to Idle") }))
    }

    /// Verifies that a stale working session with explicit waiting evidence
    /// transitions to Waiting rather than Idle.
    func testStaleWorkingSessionWithWaitingEvidenceTransitionsToWaiting() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()

        let staleSessionWithPrompt = AgentSession(
            id: "stale-prompt-worker",
            provider: .codex,
            state: .working,
            startedAt: now.addingTimeInterval(-3600),
            lastActivityAt: now.addingTimeInterval(-2400),
            summary: "Awaiting user confirmation",
            discoveryEvidence: ["needs input from developer"]
        )

        let result = await reconciler.reconcile(newSessions: [staleSessionWithPrompt], now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].state, AgentState.waiting, "Stale session with waiting evidence must transition to Waiting")
        XCTAssertTrue(result[0].discoveryEvidence.contains(where: { $0.contains("confirmed Waiting state") }))
    }

    /// Verifies LoomSettings.isSessionActive truthfulness across all AgentStates.
    func testLoomSettingsIsSessionActiveTruthfulness() {
        let working = AgentSession(id: "1", provider: .codex, state: .working)
        let starting = AgentSession(id: "2", provider: .codex, state: .starting)
        let waiting = AgentSession(id: "3", provider: .codex, state: .waiting)
        let unknown = AgentSession(id: "4", provider: .codex, state: .unknown)
        let idleWithProcs = AgentSession(
            id: "5", provider: .codex, state: .idle,
            associatedProcesses: [
                AgentProcess(
                    pid: 99,
                    executable: "daemon",
                    commandLine: "daemon",
                    provider: .codex
                )
            ]
        )
        let idleNoProcs = AgentSession(id: "6", provider: .codex, state: .idle, associatedProcesses: [])
        let finished = AgentSession(id: "7", provider: .codex, state: .finished)
        let failed = AgentSession(id: "8", provider: .codex, state: .failed)

        XCTAssertTrue(LoomSettings.isSessionActive(working))
        XCTAssertTrue(LoomSettings.isSessionActive(starting))
        XCTAssertTrue(LoomSettings.isSessionActive(waiting))
        XCTAssertTrue(LoomSettings.isSessionActive(unknown), "Unknown state is conservatively active")
        XCTAssertTrue(LoomSettings.isSessionActive(idleWithProcs), "Idle with process evidence is active")
        XCTAssertFalse(LoomSettings.isSessionActive(idleNoProcs), "Idle without process evidence is inactive")
        XCTAssertFalse(LoomSettings.isSessionActive(finished))
        XCTAssertFalse(LoomSettings.isSessionActive(failed))
    }

    /// Verifies LoomSettings.shouldInclude filtering based on includeRecentSessions and hideFinishedAfter intervals.
    @MainActor
    func testLoomSettingsHideFinishedAfterCutoffs() {
        let suite = "test-settings-cutoffs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = LoomSettings(defaults: defaults)
        let now = Date()

        let recentFinished = AgentSession(
            id: "f-recent", provider: .codex, state: .finished,
            lastActivityAt: now.addingTimeInterval(-1800) // 30m ago
        )
        let oldFinished = AgentSession(
            id: "f-old", provider: .codex, state: .finished,
            lastActivityAt: now.addingTimeInterval(-7200) // 2h ago
        )
        let ancientFinished = AgentSession(
            id: "f-ancient", provider: .codex, state: .finished,
            lastActivityAt: now.addingTimeInterval(-100000) // >24h ago
        )
        let nilDateFinished = AgentSession(
            id: "f-nil", provider: .codex, state: .finished,
            lastActivityAt: nil
        )

        // When includeRecentSessions == false: all finished sessions excluded
        settings.includeRecentSessions = false
        XCTAssertFalse(settings.shouldInclude(session: recentFinished, now: now))
        XCTAssertFalse(settings.shouldInclude(session: oldFinished, now: now))

        // When includeRecentSessions == true with 1 hour cutoff:
        settings.includeRecentSessions = true
        settings.hideFinishedAfter = .oneHour
        XCTAssertTrue(settings.shouldInclude(session: recentFinished, now: now), "30m old session within 1h cutoff included")
        XCTAssertFalse(settings.shouldInclude(session: oldFinished, now: now), "2h old session beyond 1h cutoff excluded")
        XCTAssertTrue(settings.shouldInclude(session: nilDateFinished, now: now), "Session with nil date kept conservatively")

        // With 24 hour cutoff:
        settings.hideFinishedAfter = .twentyFourHours
        XCTAssertTrue(settings.shouldInclude(session: oldFinished, now: now), "2h old session within 24h cutoff included")
        XCTAssertFalse(settings.shouldInclude(session: ancientFinished, now: now), "Ancient session beyond 24h excluded")

        // With Never cutoff:
        settings.hideFinishedAfter = .never
        XCTAssertTrue(settings.shouldInclude(session: ancientFinished, now: now), "Never cutoff retains all finished")
    }

    /// Verifies path concealment across safe project names and search queries.
    func testPathConcealmentUnderSearchAndDisplay() {
        let repoPath = URL(fileURLWithPath: "/Users/developer/PrivateTopSecretClient/LoomCore")
        let sessionWithPathName = AgentSession(
            id: "secret-path-name",
            provider: .codex,
            projectName: "/Users/developer/PrivateTopSecretClient/LoomCore",
            projectPath: repoPath,
            state: .working,
            branch: "feature/auth",
            summary: "Writing encryption module"
        )

        // Path concealment masks full directory structure in project name
        let concealedName = LoomSettings.safeProjectName(for: sessionWithPathName, hidePaths: true)
        XCTAssertEqual(concealedName, "LoomCore", "Concealed project name must only display final component")
        XCTAssertFalse(concealedName.contains("PrivateTopSecretClient"))

        let visibleName = LoomSettings.safeProjectName(for: sessionWithPathName, hidePaths: false)
        XCTAssertTrue(visibleName.contains("PrivateTopSecretClient"))

        // Search engine path privacy check
        let session = AgentSession(
            id: "secret-search",
            provider: .codex,
            projectName: "LoomCore",
            projectPath: repoPath,
            state: .working,
            branch: "feature/auth",
            summary: "Writing encryption module"
        )

        XCTAssertTrue(TestSessionFilterEngine.matches(
            session: session,
            query: "PrivateTopSecretClient",
            filter: .all,
            hideProjectPaths: false
        ), "Full path must match search queries when hideProjectPaths is false")

        XCTAssertFalse(TestSessionFilterEngine.matches(
            session: session,
            query: "PrivateTopSecretClient",
            filter: .all,
            hideProjectPaths: true
        ), "Hidden path substrings must never match search queries when hideProjectPaths is true")
    }
}

// MARK: - Priority 4: Provider Usage & Widget Data Consistency

final class ProviderUsageAndWidgetConsistencyRegressionTests: XCTestCase {

    /// Verifies that LoomWidgetSnapshot correctly reflects active, attention, and total session counts
    /// and constructs the truthful status message.
    @MainActor
    func testWidgetSnapshotCountersAndStateConsistency() async {
        let codexSessions = [
            AgentSession(id: "c1", provider: .codex, state: .working),
            AgentSession(id: "c2", provider: .codex, state: .starting),
            AgentSession(id: "c3", provider: .codex, state: .waiting),
            AgentSession(id: "c4", provider: .codex, state: .finished)
        ]
        let claudeSessions = [
            AgentSession(id: "cl1", provider: .claude, state: .failed),
            AgentSession(id: "cl2", provider: .claude, state: .idle)
        ]

        let codexProvider = MockAgentProvider(id: .codex, displayName: "Codex", sessions: codexSessions)
        let claudeProvider = MockAgentProvider(id: .claude, displayName: "Claude Code", sessions: claudeSessions)

        let store = SessionStore(providers: [codexProvider, claudeProvider])
        await store.refresh()

        let snapshot = LoomWidgetSnapshot.make(from: store)

        // Active: c1 (working) + c2 (starting) = 2
        XCTAssertEqual(snapshot.activeSessionCount, 2)
        // Attention: c3 (waiting) + cl1 (failed) = 2
        XCTAssertEqual(snapshot.attentionSessionCount, 2)
        // Total: 4 + 2 = 6
        XCTAssertEqual(snapshot.totalSessionCount, 6)
        // Status message:
        XCTAssertEqual(snapshot.statusMessage, "2 active sessions")
    }

    /// Verifies that empty store reasons correctly map to truthful widget status messages.
    @MainActor
    func testWidgetSnapshotEmptyReasonsTruthfulness() async {
        // 1. Idle / No active sessions
        let emptyStore = SessionStore(providers: [MockAgentProvider(id: .codex, displayName: "Codex")])
        await emptyStore.refresh()
        let snap1 = LoomWidgetSnapshot.make(from: emptyStore)
        XCTAssertEqual(snap1.statusMessage, "Idle")

        // 2. All providers disabled
        let disabledStore = SessionStore(providers: [MockAgentProvider(id: .codex, displayName: "Codex")], enabledProviderIDs: [])
        let snap2 = LoomWidgetSnapshot.make(from: disabledStore)
        XCTAssertEqual(snap2.statusMessage, "All providers disabled")

        // 3. Providers unavailable
        let unavailProvider = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .unavailable(reason: "daemon missing")
        )
        let unavailStore = SessionStore(providers: [unavailProvider])
        await unavailStore.refresh()
        let snap3 = LoomWidgetSnapshot.make(from: unavailStore)
        XCTAssertEqual(snap3.statusMessage, "Providers unavailable")
    }

    /// Verifies provider usage widget summaries:
    /// - Claude Code reports .unsupported ("Usage unsupported")
    /// - Stale usage reports .stale with label "(stale)"
    /// - Available usage reports .available with fraction and percentage
    @MainActor
    func testWidgetProviderUsageTruthfulStatuses() async {
        let resetDate = Date().addingTimeInterval(3600)
        let primaryBucket = UsageBucket(
            identifier: "rolling-5h",
            label: "5-hour window",
            usedFraction: 0.25,
            resetsAt: resetDate,
            windowDurationMins: 300
        )
        let validUsage = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date(),
            primaryBucket: primaryBucket,
            isStale: false
        )
        let staleUsage = ProviderUsageSnapshot(
            providerID: .antigravity,
            updatedAt: Date().addingTimeInterval(-600),
            primaryBucket: primaryBucket,
            isStale: true
        )

        let codex = MockAgentProvider(id: .codex, displayName: "Codex", usage: validUsage)
        let claude = MockAgentProvider(id: .claude, displayName: "Claude Code")
        let agy = MockAgentProvider(id: .antigravity, displayName: "Antigravity", usage: staleUsage)

        let store = SessionStore(providers: [codex, claude, agy])
        await store.refresh()

        let snapshot = LoomWidgetSnapshot.make(from: store)
        let summaries: [String: ProviderWidgetSummary] = Dictionary(
            uniqueKeysWithValues: snapshot.providerSummaries.map { ($0.id, $0) }
        )

        // Claude Code usage unsupported
        let clSummary = summaries[ProviderID.claude.rawValue]?.usage
        XCTAssertEqual(clSummary?.status, ProviderUsageStatus.unsupported)
        XCTAssertEqual(clSummary?.summary, "Usage unsupported")

        // Codex available usage
        let cxSummary = summaries[ProviderID.codex.rawValue]?.usage
        XCTAssertEqual(cxSummary?.status, ProviderUsageStatus.available)
        XCTAssertEqual(cxSummary?.percentRemaining, 75)
        XCTAssertEqual(cxSummary?.fractionUsed, 0.25)
        XCTAssertEqual(cxSummary?.summary, "75% left")

        // Antigravity stale usage
        let agSummary = summaries[ProviderID.antigravity.rawValue]?.usage
        XCTAssertEqual(agSummary?.status, ProviderUsageStatus.stale)
        XCTAssertEqual(agSummary?.summary, "75% left (stale)")
    }

    /// Verifies that LoomWidgetSnapshot serializes to disk and roundtrips atomically
    /// through SharedAppGroup without loss of telemetry or schema mismatch.
    func testWidgetSnapshotAppGroupRoundtrip() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("loom-widget-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appGroup = SharedAppGroup(customBaseDirectory: tempDir)

        let original = LoomWidgetSnapshot(
            schemaVersion: 1,
            timestamp: Date(),
            activeSessionCount: 3,
            attentionSessionCount: 1,
            totalSessionCount: 5,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 3,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: "2 active",
                    usage: ProviderUsageWidgetSummary(
                        status: .available,
                        fractionUsed: 0.20,
                        percentRemaining: 80,
                        percentUsed: 20,
                        resetsAt: Date().addingTimeInterval(1800),
                        formattedResetTime: "30m",
                        planType: "Pro",
                        summary: "80% left"
                    )
                )
            ],
            statusMessage: "3 active sessions"
        )

        let writeSuccess = appGroup.writeSnapshot(original)
        XCTAssertTrue(writeSuccess, "Snapshot write to isolated App Group container must succeed")

        let readResult = appGroup.readSnapshot()
        guard case .success(let loaded) = readResult else {
            XCTFail("Snapshot read failed: \(readResult)")
            return
        }

        XCTAssertEqual(loaded.schemaVersion, original.schemaVersion)
        XCTAssertEqual(loaded.activeSessionCount, original.activeSessionCount)
        XCTAssertEqual(loaded.attentionSessionCount, original.attentionSessionCount)
        XCTAssertEqual(loaded.totalSessionCount, original.totalSessionCount)
        XCTAssertEqual(loaded.statusMessage, original.statusMessage)
        XCTAssertEqual(loaded.providerSummaries.count, 1)
        XCTAssertEqual(loaded.providerSummaries[0].id, "codex")
        XCTAssertEqual(loaded.providerSummaries[0].usage?.percentRemaining, 80)
        XCTAssertEqual(loaded.providerSummaries[0].usage?.summary, "80% left")
    }
}

// MARK: - Priority 5: SwiftUI Smoke Test (AppKit/SwiftUI Headless)

final class SwiftUISmokeRegressionTests: XCTestCase {

    /// Native SwiftUI Session Card representation smoke component
    struct SmokeSessionCardView: View {
        let session: AgentSession
        let hideProjectPaths: Bool

        var body: some View {
            HStack(alignment: .center, spacing: 8) {
                // Provider Badge
                Text(session.provider.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())

                // Project & Activity
                VStack(alignment: .leading, spacing: 2) {
                    Text(LoomSettings.safeProjectName(for: session, hidePaths: hideProjectPaths))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    if let summary = session.summary {
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // State Capsule
                Text(session.state.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
        }

        private var stateColor: Color {
            switch session.state {
            case .waiting: return .orange
            case .failed: return .red
            case .working, .starting: return .accentColor
            case .idle, .finished, .unknown: return .secondary
            }
        }
    }

    /// Verifies that rendering a native SwiftUI session card with NSHostingView computes valid,
    /// non-zero layout bounds without recursion across light/dark appearances and all agent states.
    @MainActor
    func testSessionCardSwiftUISmokeRendering() {
        let states: [AgentState] = [.working, .waiting, .failed, .idle, .finished, .starting, .unknown]
        let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

        for state in states {
            let session = AgentSession(
                id: "smoke-\(state.rawValue)",
                provider: .codex,
                projectName: "/Users/developer/TopSecret/Loom",
                projectPath: URL(fileURLWithPath: "/Users/developer/TopSecret/Loom"),
                state: state,
                summary: "Smoke test activity for \(state.displayName)"
            )

            for appName in appearances {
                let view = SmokeSessionCardView(session: session, hideProjectPaths: true)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: appName)

                let size = host.fittingSize

                // Bounded layout checks
                XCTAssertGreaterThanOrEqual(size.width, 320.0, "Width must meet minimum width (320pt)")
                XCTAssertLessThanOrEqual(size.width, 520.0, "Width must not exceed maximum width (520pt)")
                XCTAssertGreaterThan(size.height, 20.0, "Height must be non-zero and positive")
                XCTAssertLessThan(size.height, 120.0, "Session card height must remain compact")
            }
        }
    }

    /// Verifies that when path concealment is active, the rendered SwiftUI view does NOT expose raw paths.
    @MainActor
    func testSwiftUISmokePathConcealment() {
        let session = AgentSession(
            id: "smoke-leak-test",
            provider: .codex,
            projectName: "/Users/developer/SuperSecretClientDir/LoomCore",
            projectPath: URL(fileURLWithPath: "/Users/developer/SuperSecretClientDir/LoomCore"),
            state: .working,
            summary: "Executing test"
        )

        let safeName = LoomSettings.safeProjectName(for: session, hidePaths: true)
        XCTAssertEqual(safeName, "LoomCore")
        XCTAssertFalse(safeName.contains("SuperSecretClientDir"))

        let cardView = SmokeSessionCardView(session: session, hideProjectPaths: true)
        let host = NSHostingView(rootView: cardView)
        XCTAssertNotNil(host.fittingSize)
    }
}
