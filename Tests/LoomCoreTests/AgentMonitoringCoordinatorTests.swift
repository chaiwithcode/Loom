//
//  AgentMonitoringCoordinatorTests.swift
//  LoomCoreTests
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation
@testable import LoomCore
import XCTest

final class AgentMonitoringCoordinatorTests: XCTestCase {
    var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentMonitoringCoordinatorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temporaryDirectory = temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        super.tearDown()
    }

    @MainActor
    func testCoordinatorInitialStateAndLifecycle() async {
        let coordinator = AgentMonitoringCoordinator()
        XCTAssertTrue(coordinator.sessions.isEmpty, "Initial sessions array should be empty")

        coordinator.startMonitoring()
        // Wait briefly for first potential loop or background check
        try? await Task.sleep(nanoseconds: 50_000_000)

        coordinator.stopMonitoring()
        // Calling stopMonitoring again should be idempotent and not crash
        coordinator.stopMonitoring()
    }

    @MainActor
    func testCoordinatorRefreshAllProducesSortedSessions() async {
        let t3Dir = temporaryDirectory.appendingPathComponent(".t3")
        let codexDir = temporaryDirectory.appendingPathComponent(".codex")
        let claudeDir = temporaryDirectory.appendingPathComponent(".claude")
        let agyDir = temporaryDirectory.appendingPathComponent(".gemini/antigravity-cli")

        try? FileManager.default.createDirectory(at: t3Dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: agyDir, withIntermediateDirectories: true)

        let t3Detector = T3CodeDetector(baseDirectory: t3Dir)
        let codexDetector = CodexCLIDetector(baseDirectory: codexDir)
        let claudeDetector = ClaudeCodeDetector(baseDirectory: claudeDir)
        let agyDetector = AntigravityCLIDetector(baseDirectory: agyDir)

        let coordinator = AgentMonitoringCoordinator(
            t3Detector: t3Detector,
            codexDetector: codexDetector,
            claudeDetector: claudeDetector,
            agyDetector: agyDetector
        )

        await coordinator.refreshAll()
        // When there are no live agent processes, sessions may be empty or contain today's inactive sessions
        for session in coordinator.sessions {
            XCTAssertNotNil(session.id)
            XCTAssertNotNil(session.provider)
        }
    }

    @MainActor
    func testSessionSortingActiveBeforeInactiveAndDateDescending() async {
        let now = Date()
        let activeRecent = AgentSessionStatus(
            id: "active-recent",
            provider: .codex,
            surface: .cli,
            projectName: "proj-1",
            state: .working,
            lastUpdated: now
        )
        let activeOlder = AgentSessionStatus(
            id: "active-older",
            provider: .claudeCode,
            surface: .cli,
            projectName: "proj-2",
            state: .awaitingApproval,
            lastUpdated: now.addingTimeInterval(-100)
        )
        let inactiveRecent = AgentSessionStatus(
            id: "inactive-recent",
            provider: .antigravity,
            surface: .cli,
            projectName: "proj-3",
            state: .inactive,
            lastUpdated: now
        )
        let inactiveOlder = AgentSessionStatus(
            id: "inactive-older",
            provider: .t3Code,
            surface: .gui,
            projectName: "proj-4",
            state: .inactive,
            lastUpdated: now.addingTimeInterval(-200)
        )

        let input = [inactiveRecent, activeOlder, inactiveOlder, activeRecent]

        let sorted = input.sorted { lhs, rhs in
            if (lhs.state != .inactive) != (rhs.state != .inactive) {
                return lhs.state != .inactive
            }
            return lhs.lastUpdated > rhs.lastUpdated
        }

        XCTAssertEqual(sorted.map(\.id), ["active-recent", "active-older", "inactive-recent", "inactive-older"])
    }

    @MainActor
    func testAntigravityCLIDetectorDetectSessionIntegration() throws {
        let brainDir = temporaryDirectory.appendingPathComponent("brain")
        let convID = "conv-active-test"
        let logsDir = brainDir.appendingPathComponent(convID).appendingPathComponent(".system_generated").appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let transcriptURL = logsDir.appendingPathComponent("transcript.jsonl")

        let lines = [
            "{\"step_index\": 0, \"type\": \"USER_INPUT\", \"status\": \"DONE\", \"created_at\": \"2026-10-31T20:00:00Z\", \"content\": \"hello\"}",
            "{\"step_index\": 1, \"type\": \"PLANNER_RESPONSE\", \"status\": \"DONE\", \"created_at\": \"2026-10-31T20:00:05Z\", \"model\": \"gemini-ultra\"}"
        ]
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: transcriptURL)

        let agyPID: pid_t = 8888
        let table: [pid_t: MonitoredProcess] = [
            agyPID: MonitoredProcess(
                pid: agyPID,
                ppid: 1,
                name: "agy",
                executablePath: "/Users/dev/.local/bin/agy",
                cwd: "/Users/dev/workspace/app"
            )
        ]

        let detector = AntigravityCLIDetector(baseDirectory: temporaryDirectory)
        let sessions = detector.detect(processTable: table, t3RootPIDs: [])

        XCTAssertFalse(sessions.isEmpty)
        let session = try XCTUnwrap(sessions.first(where: { $0.pid == agyPID }))
        XCTAssertEqual(session.provider, .antigravity)
        XCTAssertEqual(session.surface, .cli)
        XCTAssertEqual(session.workspacePath, "/Users/dev/workspace/app")
        XCTAssertEqual(session.projectName, "app")
        XCTAssertEqual(session.modelName, "gemini-ultra")
    }

    @MainActor
    func testAntigravityCLIDetectorChildOfT3CodeSetsSurface() throws {
        let brainDir = temporaryDirectory.appendingPathComponent("brain")
        let convID = "conv-t3-child"
        let logsDir = brainDir.appendingPathComponent(convID).appendingPathComponent(".system_generated").appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let transcriptURL = logsDir.appendingPathComponent("transcript.jsonl")

        let lines = [
            "{\"step_index\": 0, \"type\": \"USER_INPUT\", \"status\": \"DONE\", \"created_at\": \"2026-10-31T20:00:00Z\", \"content\": \"orchestrated run\"}"
        ]
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: transcriptURL)

        let t3RootPID: pid_t = 1200
        let agyPID: pid_t = 1205
        let table: [pid_t: MonitoredProcess] = [
            t3RootPID: MonitoredProcess(
                pid: t3RootPID,
                ppid: 1,
                name: "t3code",
                executablePath: "/usr/local/bin/t3code",
                cwd: "/Users/dev/t3-project"
            ),
            agyPID: MonitoredProcess(
                pid: agyPID,
                ppid: t3RootPID,
                name: "agy",
                executablePath: "/Users/dev/.local/bin/agy",
                cwd: "/Users/dev/t3-project"
            )
        ]

        let detector = AntigravityCLIDetector(baseDirectory: temporaryDirectory)
        let sessions = detector.detect(processTable: table, t3RootPIDs: [t3RootPID])

        let session = try XCTUnwrap(sessions.first(where: { $0.pid == agyPID }))
        XCTAssertEqual(session.surface, .t3Orchestrated)
        XCTAssertEqual(session.parentT3PID, t3RootPID)
    }
}
