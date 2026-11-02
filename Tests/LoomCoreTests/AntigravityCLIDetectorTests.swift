//
//  AntigravityCLIDetectorTests.swift
//  LoomCoreTests
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation
@testable import LoomCore
import XCTest

final class AntigravityCLIDetectorTests: XCTestCase {
    var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityCLIDetectorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temporaryDirectory = temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        super.tearDown()
    }

    func testFindLiveAntigravityProcessesAndT3Deduplication() {
        let detector = AntigravityCLIDetector(baseDirectory: temporaryDirectory)

        let t3PID: pid_t = 1000
        let standaloneAgyPID: pid_t = 2000
        let t3ChildAgyPID: pid_t = 3000

        let table: [pid_t: MonitoredProcess] = [
            t3PID: MonitoredProcess(pid: t3PID, ppid: 1, name: "t3code", executablePath: "/usr/local/bin/t3code", cwd: "/tmp"),
            standaloneAgyPID: MonitoredProcess(pid: standaloneAgyPID, ppid: 1, name: "agy", executablePath: "/Users/dev/.local/bin/agy", cwd: "/Users/dev/standalone-project"),
            t3ChildAgyPID: MonitoredProcess(pid: t3ChildAgyPID, ppid: t3PID, name: "agy_acp_server.par", executablePath: "/Users/dev/.t3/tools/agy_acp_server.par", cwd: "/Users/dev/t3-project")
        ]

        let t3AncestorPIDs: Set<pid_t> = [t3PID]
        let processes = detector.findLiveAntigravityProcesses(table: table, t3AncestorPIDs: t3AncestorPIDs)

        XCTAssertEqual(processes.count, 2)

        let standalone = try? XCTUnwrap(processes.first(where: { $0.pid == standaloneAgyPID }))
        XCTAssertEqual(standalone?.surface, .cli)
        XCTAssertNil(standalone?.parentT3PID)
        XCTAssertEqual(standalone?.cwd, "/Users/dev/standalone-project")

        let child = try? XCTUnwrap(processes.first(where: { $0.pid == t3ChildAgyPID }))
        XCTAssertEqual(child?.surface, .t3Orchestrated)
        XCTAssertEqual(child?.parentT3PID, t3PID)
        XCTAssertEqual(child?.cwd, "/Users/dev/t3-project")
    }

    func testStateDetectionAwaitingApprovalVsWorkingVsIdle() throws {
        let brainDir = temporaryDirectory.appendingPathComponent("brain")

        // 1. Session A: asking question (ask_question tool call) -> .awaitingApproval
        let convID1 = "conv-ask-question"
        let logsDir1 = brainDir.appendingPathComponent(convID1).appendingPathComponent(".system_generated").appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsDir1, withIntermediateDirectories: true)
        let fileURL1 = logsDir1.appendingPathComponent("transcript.jsonl")

        let lines1 = [
            "{\"step_index\": 0, \"type\": \"USER_INPUT\", \"status\": \"DONE\", \"created_at\": \"2026-10-31T20:00:00Z\", \"content\": \"Refactor project\"}",
            "{\"step_index\": 1, \"type\": \"PLANNER_RESPONSE\", \"status\": \"DONE\", \"created_at\": \"2026-10-31T20:00:05Z\", \"input_tokens\": 500, \"output_tokens\": 100, \"tool_calls\": [{\"name\": \"ask_question\", \"args\": {\"question\": \"Which branch?\"}}]}"
        ]
        try (lines1.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: fileURL1)

        // 2. Session B: completed response without tool calls -> .idle
        let convID2 = "conv-idle"
        let logsDir2 = brainDir.appendingPathComponent(convID2).appendingPathComponent(".system_generated").appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsDir2, withIntermediateDirectories: true)
        let fileURL2 = logsDir2.appendingPathComponent("transcript.jsonl")

        let lines2 = [
            "{\"step_index\": 0, \"type\": \"USER_INPUT\", \"status\": \"DONE\", \"created_at\": \"2026-10-31T19:00:00Z\", \"content\": \"List files\"}",
            "{\"step_index\": 1, \"type\": \"PLANNER_RESPONSE\", \"status\": \"DONE\", \"created_at\": \"2026-10-31T19:00:05Z\", \"input_tokens\": 600, \"output_tokens\": 150, \"content\": \"Done!\"}"
        ]
        try (lines2.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: fileURL2)

        let now = Date()
        let oldModDate = now.addingTimeInterval(-10.0)
        try FileManager.default.setAttributes([.modificationDate: oldModDate], ofItemAtPath: fileURL1.path)
        try FileManager.default.setAttributes([.modificationDate: oldModDate], ofItemAtPath: fileURL2.path)

        let agyPID1: pid_t = 5001
        let agyPID2: pid_t = 5002
        let table: [pid_t: MonitoredProcess] = [
            agyPID1: MonitoredProcess(pid: agyPID1, ppid: 1, name: "agy", executablePath: "/usr/local/bin/agy", cwd: "/Users/dev/project1"),
            agyPID2: MonitoredProcess(pid: agyPID2, ppid: 1, name: "agy", executablePath: "/usr/local/bin/agy", cwd: "/Users/dev/project2")
        ]

        let detector = AntigravityCLIDetector(baseDirectory: temporaryDirectory)

        // Pre-seed CWD mapping for sessions (in live execution, discovered via proc_pidvnodepathinfo or DB)
        detector.recordCWD("/Users/dev/project1", for: convID1)
        detector.recordCWD("/Users/dev/project2", for: convID2)

        let sessions = detector.detectSessions(table: table, now: now)

        let s1 = try XCTUnwrap(sessions.first(where: { $0.sessionID == convID1 }))
        XCTAssertEqual(s1.state, .awaitingApproval, "ask_question tool call should set state to .awaitingApproval")

        let s2 = try XCTUnwrap(sessions.first(where: { $0.sessionID == convID2 }))
        XCTAssertEqual(s2.state, .idle, "Completed PLANNER_RESPONSE with no tool calls and past 2s should be .idle")
    }

    func testDailyTokenUsageComputation() throws {
        let brainDir = temporaryDirectory.appendingPathComponent("brain")
        let convID = "conv-daily-tokens"
        let logsDir = brainDir.appendingPathComponent(convID).appendingPathComponent(".system_generated").appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let fileURL = logsDir.appendingPathComponent("transcript.jsonl")

        let lines = [
            "{\"step_index\": 0, \"type\": \"USER_INPUT\", \"status\": \"DONE\", \"created_at\": \"2026-10-31T10:00:00Z\", \"content\": \"hello\"}",
            "{\"step_index\": 1, \"type\": \"PLANNER_RESPONSE\", \"status\": \"DONE\", \"created_at\": \"2026-10-31T10:00:05Z\", \"input_tokens\": 1000, \"cache_read_tokens\": 500, \"output_tokens\": 250}"
        ]
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: fileURL)

        let detector = AntigravityCLIDetector(baseDirectory: temporaryDirectory)
        let usage = detector.calculateDailyTokenUsage(now: Date())

        XCTAssertEqual(usage.inputTokens, 1000)
        XCTAssertEqual(usage.cachedInputTokens, 500)
        XCTAssertEqual(usage.outputTokens, 250)
        XCTAssertEqual(usage.totalTokens, 1750)
    }
}
