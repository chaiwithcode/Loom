//
//  SessionLifecycleReconcilerTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import LoomCore

final class SessionLifecycleReconcilerTests: XCTestCase {
    func testActiveSessionTransitionsToFinishedWhenMissing() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()

        let initialSession = AgentSession(
            id: "codex-test-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom"),
            state: .working,
            startedAt: now.addingTimeInterval(-300),
            lastActivityAt: now.addingTimeInterval(-10),
            branch: "main",
            summary: "Running tests",
            pid: 1234,
            providerSessionID: "sess-1",
            associatedProcesses: [],
            hostApp: .terminal,
            diagnostics: nil,
            discoveryEvidence: ["Initial discovery"]
        )

        let cycle1 = await reconciler.reconcile(newSessions: [initialSession], now: now)
        XCTAssertEqual(cycle1.count, 1)
        XCTAssertEqual(cycle1[0].state, .working)

        // Cycle 2: session is gone (clean departure/exit)
        let cycle2Time = now.addingTimeInterval(5)
        let cycle2 = await reconciler.reconcile(newSessions: [], now: cycle2Time)
        XCTAssertEqual(cycle2.count, 1)
        XCTAssertEqual(cycle2[0].id, "codex-test-1")
        XCTAssertEqual(cycle2[0].state, .finished)
        XCTAssertEqual(cycle2[0].lastActivityAt, cycle2Time)
        XCTAssertTrue(cycle2[0].summary?.contains("finished") == true)
        XCTAssertTrue(cycle2[0].discoveryEvidence.contains { $0.contains("transitioned to Finished") })
    }

    func testFinishedSessionRetainedWithinWindow() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let t0 = Date()

        let session = AgentSession(
            id: "codex-test-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: nil,
            state: .working,
            startedAt: t0
        )

        _ = await reconciler.reconcile(newSessions: [session], now: t0)
        // Transitions to finished at t0 + 10
        _ = await reconciler.reconcile(newSessions: [], now: t0.addingTimeInterval(10))

        // Retained at t0 + 500 (8m20s later)
        let check1 = await reconciler.reconcile(newSessions: [], now: t0.addingTimeInterval(500))
        XCTAssertEqual(check1.count, 1)
        XCTAssertEqual(check1[0].state, .finished)
    }

    func testFinishedSessionPrunedAfterExpiration() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let t0 = Date()

        let session = AgentSession(
            id: "codex-test-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: nil,
            state: .working,
            startedAt: t0
        )

        _ = await reconciler.reconcile(newSessions: [session], now: t0)
        // Departed at t0 + 10 -> finished with lastActivityAt = t0 + 10
        _ = await reconciler.reconcile(newSessions: [], now: t0.addingTimeInterval(10))

        // Check at t0 + 915s (> 900s retention) -> should be pruned!
        let checkExpired = await reconciler.reconcile(newSessions: [], now: t0.addingTimeInterval(915))
        XCTAssertTrue(checkExpired.isEmpty, "Finished session must be pruned after retention window expires")
    }

    func testStaleWorkingSessionTransitionsToIdleWithoutPositiveWaitingEvidence() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()

        let staleSession = AgentSession(
            id: "codex-stale",
            provider: .codex,
            projectName: "Loom",
            projectPath: nil,
            state: .working,
            startedAt: now.addingTimeInterval(-4000),
            lastActivityAt: now.addingTimeInterval(-2000), // > 1800s ago
            branch: "main",
            summary: "Older background computation",
            pid: 5678,
            associatedProcesses: []
        )

        let result = await reconciler.reconcile(newSessions: [staleSession], now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].state, .idle, "Working session with generic inactivity must downgrade to Idle, not manufacture false Waiting state")
        XCTAssertTrue(result[0].discoveryEvidence.contains { $0.contains("Inactivity timeout") })
    }

    func testStaleWorkingSessionWithPositiveWaitingEvidenceTransitionsToWaiting() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()

        let staleWaitingSession = AgentSession(
            id: "codex-stale-input",
            provider: .codex,
            projectName: "Loom",
            projectPath: nil,
            state: .working,
            startedAt: now.addingTimeInterval(-4000),
            lastActivityAt: now.addingTimeInterval(-2000), // > 1800s ago
            branch: "main",
            summary: "Awaiting user input for confirmation",
            pid: 5678,
            associatedProcesses: [],
            discoveryEvidence: ["Turn complete: awaiting user prompt input"]
        )

        let result = await reconciler.reconcile(newSessions: [staleWaitingSession], now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].state, .waiting, "Working session with positive evidence for user input must transition to confirmed Waiting")
        XCTAssertTrue(result[0].discoveryEvidence.contains { $0.contains("confirmed Waiting state") })
    }

    func testCancelledRefreshDoesNotManufactureFinishedSession() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()

        let activeSession = AgentSession(
            id: "active-1",
            provider: .codex,
            projectName: "Loom",
            state: .working,
            startedAt: now
        )

        _ = await reconciler.reconcile(newSessions: [activeSession], now: now)

        // Cancelled scan cycle where newSessions is empty because the scan aborted
        let cancelledCycle = await reconciler.reconcile(
            newSessions: [],
            now: now.addingTimeInterval(5),
            isCancelled: true
        )

        XCTAssertEqual(cancelledCycle.count, 1)
        XCTAssertEqual(cancelledCycle[0].id, "active-1")
        XCTAssertEqual(cancelledCycle[0].state, .working, "Cancelled scan must preserve active session without manufacturing finished state")
    }

    func testProviderErrorDoesNotManufactureFinishedSession() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()

        let activeSession = AgentSession(
            id: "claude-active",
            provider: .claude,
            projectName: "Loom",
            state: .working,
            startedAt: now
        )

        _ = await reconciler.reconcile(newSessions: [activeSession], now: now)

        // Provider threw daemon/IPC error during scan
        let errorCycle = await reconciler.reconcile(
            newSessions: [],
            now: now.addingTimeInterval(5),
            providerError: "Connection to daemon failed"
        )

        XCTAssertEqual(errorCycle.count, 1)
        XCTAssertEqual(errorCycle[0].id, "claude-active")
        XCTAssertNotEqual(errorCycle[0].state, .finished, "Missing session during provider error must NOT transition to finished")
        XCTAssertEqual(errorCycle[0].state, .working, "Session must preserve prior state on provider discovery error")
        XCTAssertTrue(errorCycle[0].discoveryEvidence.contains { $0.contains("Provider error") })
    }

    func testStableLogicalSessionPreservedAcrossProcessRestart() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let t0 = Date()

        let initialSession = AgentSession(
            id: "codex-stable-session-xyz",
            provider: .codex,
            projectName: "Loom",
            state: .working,
            startedAt: t0,
            pid: 1001,
            providerSessionID: "token-abc-123"
        )

        let cycle1 = await reconciler.reconcile(newSessions: [initialSession], now: t0)
        XCTAssertEqual(cycle1[0].id, "codex-stable-session-xyz")

        // Codex daemon restarted or process respawned with PID 2002, temporary ID "codex-2002", but same providerSessionID
        let t1 = t0.addingTimeInterval(30)
        let restartedSession = AgentSession(
            id: "codex-2002",
            provider: .codex,
            projectName: "Loom",
            state: .working,
            startedAt: t1,
            pid: 2002,
            providerSessionID: "token-abc-123"
        )

        let cycle2 = await reconciler.reconcile(newSessions: [restartedSession], now: t1)
        XCTAssertEqual(cycle2.count, 1)
        XCTAssertEqual(cycle2[0].id, "codex-stable-session-xyz", "Session ID must be preserved from prior session across process restart")
        XCTAssertEqual(cycle2[0].startedAt, t0, "Original session startedAt must be preserved across process restart")
        XCTAssertEqual(cycle2[0].pid, 2002)
    }

    func testProviderTerminationReasonPropagated() async {
        let reconciler = SessionLifecycleReconciler()
        let now = Date()

        let session = AgentSession(
            id: "antigravity-active",
            provider: .antigravity,
            projectName: "Antigravity",
            state: .working,
            startedAt: now
        )

        _ = await reconciler.reconcile(newSessions: [session], now: now)

        let terminated = await reconciler.reconcile(
            newSessions: [],
            now: now.addingTimeInterval(5),
            providerTerminationReason: "Antigravity process terminated"
        )

        XCTAssertEqual(terminated.count, 1)
        XCTAssertEqual(terminated[0].state, .finished)
        XCTAssertTrue(terminated[0].summary?.contains("Antigravity process terminated") == true)
        XCTAssertTrue(terminated[0].discoveryEvidence.contains { $0.contains("Antigravity process terminated") })
    }

    func testFailedSessionProcessExitsRemainsVisibleDuringRetentionWindow() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let t0 = Date()

        let failedSession = AgentSession(
            id: "codex-failed-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom"),
            state: .failed,
            startedAt: t0.addingTimeInterval(-100),
            lastActivityAt: t0.addingTimeInterval(-10),
            branch: "main",
            summary: "Command exited with status 1",
            pid: 4321,
            diagnostics: nil,
            discoveryEvidence: ["Process crashed with exit code 1"]
        )

        let cycle1 = await reconciler.reconcile(newSessions: [failedSession], now: t0)
        XCTAssertEqual(cycle1.count, 1)
        XCTAssertEqual(cycle1[0].state, .failed)

        let t1 = t0.addingTimeInterval(480)
        let cycle2 = await reconciler.reconcile(newSessions: [], now: t1)
        XCTAssertEqual(cycle2.count, 1)
        XCTAssertEqual(cycle2[0].id, "codex-failed-1")
        XCTAssertEqual(cycle2[0].state, .failed, "Departed failed session must retain its .failed state")
        XCTAssertEqual(cycle2[0].summary, "Command exited with status 1")
        XCTAssertTrue(cycle2[0].discoveryEvidence.contains { $0.contains("Process crashed with exit code 1") })
    }

    func testFailedSessionPrunedAfterRetentionWindow() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let t0 = Date()

        let failedSession = AgentSession(
            id: "codex-failed-prune",
            provider: .codex,
            projectName: "Loom",
            projectPath: nil,
            state: .failed,
            startedAt: t0,
            lastActivityAt: t0
        )

        _ = await reconciler.reconcile(newSessions: [failedSession], now: t0)
        _ = await reconciler.reconcile(newSessions: [], now: t0.addingTimeInterval(10))

        let expired = await reconciler.reconcile(newSessions: [], now: t0.addingTimeInterval(915))
        XCTAssertTrue(expired.isEmpty, "Failed session must be pruned after retention window expires")
    }

    func testSameRepoDistinctSessionsDoNotOverwriteInReconciler() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()
        let repo = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")

        let session1 = AgentSession(
            id: "codex-terminal-loom-101",
            provider: .codex,
            projectName: "Loom",
            projectPath: repo,
            state: .working,
            startedAt: now,
            pid: 101,
            hostApp: .terminal
        )
        let session2 = AgentSession(
            id: "codex-terminal-loom-102",
            provider: .codex,
            projectName: "Loom",
            projectPath: repo,
            state: .working,
            startedAt: now,
            pid: 102,
            hostApp: .terminal
        )

        let reconciled = await reconciler.reconcile(newSessions: [session1, session2], now: now)
        XCTAssertEqual(reconciled.count, 2)
        XCTAssertTrue(reconciled.contains { $0.id == "codex-terminal-loom-101" })
        XCTAssertTrue(reconciled.contains { $0.id == "codex-terminal-loom-102" })
    }
}
