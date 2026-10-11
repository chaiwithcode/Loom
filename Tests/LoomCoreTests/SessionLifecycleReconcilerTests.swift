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

        // Cycle 2: session is gone (e.g. process terminated)
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

    func testStaleWorkingSessionTransitionsToWaiting() async {
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
            summary: "Older task",
            pid: 5678,
            associatedProcesses: [] // No active child workers
        )

        let result = await reconciler.reconcile(newSessions: [staleSession], now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].state, .waiting, "Working session with no child workers and stale lastActivityAt should transition to Waiting")
        XCTAssertTrue(result[0].discoveryEvidence.contains { $0.contains("Stale activity") })
    }

    func testStaleWorkingSessionWithHungWorkerProcessTransitionsToWaiting() async {
        let reconciler = SessionLifecycleReconciler(retentionWindow: 900, staleThreshold: 1800)
        let now = Date()

        let rootProcess = AgentProcess(
            pid: 5678,
            executable: "/usr/local/bin/codex",
            commandLine: "codex run",
            provider: .codex
        )
        let hungWorker = AgentProcess(
            pid: 5679,
            parentPID: 5678,
            executable: "/bin/sleep",
            commandLine: "sleep 10000",
            provider: .codex
        )

        let staleSession = AgentSession(
            id: "codex-hung-worker",
            provider: .codex,
            projectName: "Loom",
            projectPath: nil,
            state: .working,
            startedAt: now.addingTimeInterval(-4000),
            lastActivityAt: now.addingTimeInterval(-2000), // > 1800s ago
            branch: "main",
            summary: "Hung worker task",
            pid: 5678,
            associatedProcesses: [rootProcess, hungWorker] // 2 processes: root + hung worker
        )

        let result = await reconciler.reconcile(newSessions: [staleSession], now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].state, .waiting, "Working session with hung surviving worker processes must transition to Waiting when last activity is stale")
        XCTAssertTrue(result[0].discoveryEvidence.contains { $0.contains("Stale activity") })
        XCTAssertTrue(result[0].discoveryEvidence.contains { $0.contains("surviving worker processes") })
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

        // Cycle 1: Discovered as failed while process alive
        let cycle1 = await reconciler.reconcile(newSessions: [failedSession], now: t0)
        XCTAssertEqual(cycle1.count, 1)
        XCTAssertEqual(cycle1[0].state, .failed)

        // Cycle 2: Process exited, newSessions is empty (8m later, within 15m window)
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

        // Cycle 1: Session is tracked
        _ = await reconciler.reconcile(newSessions: [failedSession], now: t0)

        // Cycle 2: Process exits at t0 + 10
        _ = await reconciler.reconcile(newSessions: [], now: t0.addingTimeInterval(10))

        // Cycle 3: Check at t0 + 915s (> 900s retention) -> pruned!
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

        // Both sessions in same repo are tracked concurrently
        let reconciled = await reconciler.reconcile(newSessions: [session1, session2], now: now)
        XCTAssertEqual(reconciled.count, 2)
        XCTAssertTrue(reconciled.contains { $0.id == "codex-terminal-loom-101" })
        XCTAssertTrue(reconciled.contains { $0.id == "codex-terminal-loom-102" })
    }
}
