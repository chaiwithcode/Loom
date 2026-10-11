//
//  LiveSessionTruthfulnessTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import LoomCore

final class LiveSessionTruthfulnessTests: XCTestCase {

    // MARK: - 1. Model & Health Separation Tests

    func testProviderAvailabilityStates() {
        let avail = ProviderAvailability.available
        XCTAssertTrue(avail.isAvailable)
        XCTAssertFalse(avail.isDegraded)
        XCTAssertNil(avail.unavailabilityReason)
        XCTAssertEqual(avail.displayName, "Available")

        let degraded = ProviderAvailability.degraded(reason: "Partial rate limit active")
        XCTAssertTrue(degraded.isAvailable)
        XCTAssertTrue(degraded.isDegraded)
        XCTAssertEqual(degraded.unavailabilityReason, "Partial rate limit active")
        XCTAssertEqual(degraded.displayName, "Degraded")

        let unavail = ProviderAvailability.unavailable(reason: "Daemon not running")
        XCTAssertFalse(unavail.isAvailable)
        XCTAssertFalse(unavail.isDegraded)
        XCTAssertEqual(unavail.unavailabilityReason, "Daemon not running")
        XCTAssertEqual(unavail.displayName, "Unavailable")

        let err = ProviderAvailability.error(reason: "IPC socket crashed")
        XCTAssertFalse(err.isAvailable)
        XCTAssertFalse(err.isDegraded)
        XCTAssertEqual(err.unavailabilityReason, "IPC socket crashed")
        XCTAssertEqual(err.displayName, "Error")

        let unknown = ProviderAvailability.unknown
        XCTAssertFalse(unknown.isAvailable)
        XCTAssertTrue(unknown.isUnknown)
        XCTAssertEqual(unknown.displayName, "Checking")
    }

    func testAgentLifecycleStates() {
        let expectedStates: [AgentState] = [
            .starting,
            .working,
            .waiting,
            .idle,
            .finished,
            .failed,
            .unknown
        ]

        XCTAssertEqual(AgentState.allCases, expectedStates)
        XCTAssertEqual(AgentState.starting.displayName, "Starting")
        XCTAssertEqual(AgentState.working.displayName, "Working")
        XCTAssertEqual(AgentState.waiting.displayName, "Waiting")
        XCTAssertEqual(AgentState.idle.displayName, "Idle")
        XCTAssertEqual(AgentState.finished.displayName, "Finished")
        XCTAssertEqual(AgentState.failed.displayName, "Failed")
        XCTAssertEqual(AgentState.unknown.displayName, "Unknown")
    }

    // MARK: - 2. Repository-First Session Model Formatting

    func testAgentSessionRepositoryFormatting() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let repoPath = URL(fileURLWithPath: "\(homeDir)/Desktop/Projects/oss/Loom")

        let session = AgentSession(
            id: "codex-test-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: repoPath,
            state: .working,
            startedAt: Date().addingTimeInterval(-300),
            lastActivityAt: Date().addingTimeInterval(-10),
            branch: "main",
            summary: "Active pair programming",
            pid: 4567,
            providerSessionID: "sess-abc-123",
            associatedProcesses: [
                AgentProcess(pid: 4567, commandLine: "codex", provider: .codex),
                AgentProcess(pid: 4568, parentPID: 4567, commandLine: "node worker.js", provider: .codex)
            ],
            hostApp: .vsCode,
            diagnostics: nil,
            discoveryEvidence: [
                "Session token (--session-id): sess-abc-123",
                "Collapsed 2 processes via process tree"
            ]
        )

        XCTAssertEqual(session.projectName, "Loom")
        XCTAssertEqual(session.formattedProjectPath, "~/Desktop/Projects/oss/Loom")
        XCTAssertEqual(session.processCount, 2)
        XCTAssertEqual(session.discoveryEvidence.count, 2)
        XCTAssertEqual(session.hostApp, .vsCode)
        XCTAssertEqual(session.state, .working)
    }

    func testAgentSessionProcessCountFallback() {
        // Fallback with no associated processes but single pid
        let sessionSingle = AgentSession(
            id: "s-single",
            provider: .codex,
            state: .idle,
            pid: 1234
        )
        XCTAssertEqual(sessionSingle.processCount, 1)

        // Fallback with no pid and empty processes
        let sessionEmpty = AgentSession(
            id: "s-empty",
            provider: .codex,
            state: .unknown
        )
        XCTAssertEqual(sessionEmpty.processCount, 0)
    }

    // MARK: - 3. Provider Discovery Diagnostics Tests

    func testDiscoveryDiagnosticsDurationFormatting() {
        let diag1 = ProviderDiscoveryDiagnostics(
            processesDetected: 7,
            logicalSessions: 3,
            workspacesResolved: 3,
            metadataStatus: .available,
            metadataError: nil,
            discoveryDuration: 0.0924
        )

        XCTAssertEqual(diag1.processesDetected, 7)
        XCTAssertEqual(diag1.logicalSessions, 3)
        XCTAssertEqual(diag1.workspacesResolved, 3)
        XCTAssertEqual(diag1.metadataStatus, .available)
        XCTAssertEqual(diag1.discoveryDurationMsFormatted, "92 ms")

        let diag2 = ProviderDiscoveryDiagnostics(
            processesDetected: 0,
            logicalSessions: 0,
            workspacesResolved: 0,
            metadataStatus: .skipped,
            discoveryDuration: nil
        )
        XCTAssertNil(diag2.discoveryDurationMsFormatted)
    }

    // MARK: - 4. Stale Session Lifecycle Transitions

    private final class ControllableCodexDiscoverer: CodexProcessDiscovering, @unchecked Sendable {
        var processesToReturn: [AgentProcess] = []
        var treeToReturn: ProcessTree = ProcessTree(nodes: [])

        func findRunningProcesses() async throws -> [CodexProcessInfo] { [] }
        func discoverProcesses() async throws -> (processes: [AgentProcess], processTree: ProcessTree) {
            return (processes: processesToReturn, processTree: treeToReturn)
        }
    }

    private final class MockGitResolver: GitRepositoryResolving, Sendable {
        func resolveRepository(for directoryURL: URL) async -> GitRepositoryInfo? {
            GitRepositoryInfo(rootURL: directoryURL, projectName: directoryURL.lastPathComponent, branch: "main")
        }
    }

    func testCodexProviderTransitionsExitedProcessToFinished() async throws {
        let repo = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let p1 = AgentProcess(
            pid: 1001,
            commandLine: "codex sandbox --session-id=sess-live /Users/developer/Desktop/Projects/oss/Loom",
            workingDirectory: repo,
            startedAt: Date().addingTimeInterval(-60),
            provider: .codex,
            hostApp: .vsCode,
            sessionIDToken: "sess-live"
        )
        let p2 = AgentProcess(
            pid: 1002,
            parentPID: 1001,
            commandLine: "node worker.js",
            workingDirectory: repo,
            startedAt: Date().addingTimeInterval(-30),
            provider: .codex,
            hostApp: .vsCode,
            sessionIDToken: "sess-live"
        )

        let nodes = [
            ProcessNode(pid: 1001, parentPID: nil, command: p1.commandLine, executable: "codex"),
            ProcessNode(pid: 1002, parentPID: 1001, command: p2.commandLine, executable: "node")
        ]
        let tree = ProcessTree(nodes: nodes)

        let discoverer = ControllableCodexDiscoverer()
        discoverer.processesToReturn = [p1, p2]
        discoverer.treeToReturn = tree

        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: MockGitResolver())

        // Cycle 1: Agent is running with workers -> .working
        let cycle1Sessions = try await provider.discoverSessions()
        XCTAssertEqual(cycle1Sessions.count, 1)
        let liveSession = cycle1Sessions[0]
        XCTAssertEqual(liveSession.state, .working)
        XCTAssertEqual(liveSession.associatedProcesses.count, 2)
        XCTAssertEqual(liveSession.hostApp, .vsCode)

        // Cycle 2: Process exited (e.g. root process terminated or VS Code closed)
        discoverer.processesToReturn = []
        discoverer.treeToReturn = ProcessTree(nodes: [])

        let cycle2Sessions = try await provider.discoverSessions()
        XCTAssertEqual(cycle2Sessions.count, 1, "Session should not vanish immediately upon termination; it must transition to Finished")
        let finishedSession = cycle2Sessions[0]
        XCTAssertEqual(finishedSession.id, liveSession.id)
        XCTAssertEqual(finishedSession.state, .finished, "Dead session must transition to .finished")
        XCTAssertEqual(finishedSession.associatedProcesses.count, 0)
        XCTAssertNotNil(finishedSession.lastActivityAt)
    }

    @MainActor
    func testSessionStoreProtectsWorkingSessionsOnProviderCrash() async {
        let initialSession = AgentSession(
            id: "codex-crash-test",
            provider: .codex,
            projectName: "Loom",
            state: .working
        )

        let mockProvider = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: [initialSession]
        )

        let store = SessionStore(providers: [mockProvider])
        await store.refresh()

        // Initially session is working
        XCTAssertEqual(store.snapshot(for: .codex)?.sessions.first?.state, .working)

        // Provider crashes / throws error
        let crashError = NSError(domain: "Codex", code: 1, userInfo: [NSLocalizedDescriptionKey: "Daemon connection lost (SIGSEGV)"])
        mockProvider.setError(crashError)
        mockProvider.setSessions([])

        await store.refresh()

        let snapshot = store.snapshot(for: .codex)
        XCTAssertNotNil(snapshot?.errorMessage)
        let sessionAfterCrash = snapshot?.sessions.first
        XCTAssertNotEqual(sessionAfterCrash?.state, .working, "Session must NOT remain stuck in .working after provider crash")
        XCTAssertEqual(sessionAfterCrash?.state, .failed)
    }

    @MainActor
    func testSessionStoreProtectsWorkingSessionsOnProviderUnavailability() async {
        let initialSession = AgentSession(
            id: "ag-unavail-test",
            provider: .antigravity,
            projectName: "Experiment",
            state: .working
        )

        let mockProvider = MockAgentProvider(
            id: .antigravity,
            displayName: "Antigravity",
            availability: .available,
            sessions: [initialSession]
        )

        let store = SessionStore(providers: [mockProvider])
        await store.refresh()

        XCTAssertEqual(store.snapshot(for: .antigravity)?.sessions.first?.state, .working)

        // Provider becomes unavailable
        mockProvider.setAvailability(.unavailable(reason: "Process terminated"))
        mockProvider.setSessions([])

        await store.refresh()

        let snapshot = store.snapshot(for: .antigravity)
        XCTAssertFalse(snapshot?.availability.isAvailable ?? true)
        let sessionAfterUnavail = snapshot?.sessions.first
        XCTAssertNotEqual(sessionAfterUnavail?.state, .working, "Session must NOT remain stuck in .working when provider is unavailable")
    }

    @MainActor
    func testSessionStoreWakeNotificationTriggersRefresh() async {
        let mockProvider = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: []
        )

        let store = SessionStore(providers: [mockProvider])
        XCTAssertNil(store.lastRefreshedAt)

        // Post NSWorkspace.didWakeNotification on NSWorkspace.shared.notificationCenter
        #if canImport(AppKit)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        // Allow MainActor task to run
        for _ in 0..<10 {
            if store.lastRefreshedAt != nil { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(store.lastRefreshedAt, "didWakeNotification must trigger a fresh refresh")
        #endif
    }

    // MARK: - 5. Live Runtime Host Discovery & Truthfulness Validation

    func testLiveHostRuntimeDiscoveryAndDiagnostics() async throws {
        // Antigravity Live Discovery
        let agy = AntigravityProvider()
        let agyAvail = await agy.availability()
        let agySessions = try await agy.discoverSessions()
        print("[LiveValidation] Antigravity: availability=\(agyAvail.displayName), sessions=\(agySessions.count)")
        for s in agySessions {
            print("[LiveValidation]   AG Session: id=\(s.id), state=\(s.state.displayName), project=\(s.projectName ?? "none"), evidence=\(s.discoveryEvidence)")
        }

        // Codex Live Discovery
        let codex = CodexProvider()
        let codexAvail = await codex.availability()
        let codexSessions = try await codex.discoverSessions()
        print("[LiveValidation] Codex: availability=\(codexAvail.displayName), sessions=\(codexSessions.count)")
        for s in codexSessions {
            print("[LiveValidation]   Codex Session: id=\(s.id), state=\(s.state.displayName), project=\(s.projectName ?? "none"), procs=\(s.processCount), evidence=\(s.discoveryEvidence)")
        }

        // Claude Live Discovery
        let claude = ClaudeProvider()
        let claudeAvail = await claude.availability()
        let claudeSessions = try await claude.discoverSessions()
        print("[LiveValidation] Claude: availability=\(claudeAvail.displayName), sessions=\(claudeSessions.count)")
        for s in claudeSessions {
            print("[LiveValidation]   Claude Session: id=\(s.id), state=\(s.state.displayName), project=\(s.projectName ?? "none"), evidence=\(s.discoveryEvidence)")
        }

        // Verify that discovery produces truthful sessions with non-colliding IDs and valid diagnostics
        let allLive = agySessions + codexSessions + claudeSessions
        let ids = Set(allLive.map(\.id))
        XCTAssertEqual(ids.count, allLive.count, "All live session IDs across providers must be distinct")
    }
}
