//
//  CodexCLIDetectorTests.swift
//  LoomCoreTests
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation
@testable import LoomCore
import XCTest

final class CodexCLIDetectorTests: XCTestCase {
    var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexCLIDetectorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temporaryDirectory = temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        super.tearDown()
    }

    func testFindLiveCodexProcessesAndT3Deduplication() {
        let detector = CodexCLIDetector(baseDirectory: temporaryDirectory)

        let t3PID: pid_t = 500
        let standaloneCodexPID: pid_t = 600
        let t3ChildCodexPID: pid_t = 700
        let otherPID: pid_t = 800

        let table: [pid_t: MonitoredProcess] = [
            t3PID: MonitoredProcess(pid: t3PID, ppid: 1, name: "t3code", executablePath: "/usr/local/bin/t3code", cwd: "/tmp"),
            standaloneCodexPID: MonitoredProcess(pid: standaloneCodexPID, ppid: 1, name: "codex", executablePath: "/usr/local/bin/codex", cwd: "/Users/dev/standalone"),
            t3ChildCodexPID: MonitoredProcess(pid: t3ChildCodexPID, ppid: t3PID, name: "codex", executablePath: "/usr/local/bin/codex", cwd: "/Users/dev/t3project"),
            otherPID: MonitoredProcess(pid: otherPID, ppid: 1, name: "zsh", executablePath: "/bin/zsh", cwd: "/tmp")
        ]

        let t3AncestorPIDs: Set<pid_t> = [t3PID]
        let processes = detector.findLiveCodexProcesses(table: table, t3AncestorPIDs: t3AncestorPIDs)

        XCTAssertEqual(processes.count, 2)

        let standalone = try? XCTUnwrap(processes.first(where: { $0.pid == standaloneCodexPID }))
        XCTAssertEqual(standalone?.surface, .cli)
        XCTAssertNil(standalone?.parentT3PID)

        let child = try? XCTUnwrap(processes.first(where: { $0.pid == t3ChildCodexPID }))
        XCTAssertEqual(child?.surface, .t3Orchestrated)
        XCTAssertEqual(child?.parentT3PID, t3PID)
    }

    func testDetectSessionsAndCumulativeDailyTokenCalculation() throws {
        let calendar = Calendar.current
        let now = Date()
        let year = String(format: "%04d", calendar.component(.year, from: now))
        let month = String(format: "%02d", calendar.component(.month, from: now))
        let day = String(format: "%02d", calendar.component(.day, from: now))

        let dayDir = temporaryDirectory
            .appendingPathComponent("sessions")
            .appendingPathComponent(year)
            .appendingPathComponent(month)
            .appendingPathComponent(day)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        // Session 1: Has multiple token_count lines (cumulative).
        // Line 1: meta
        // Line 2: turn 1 (total 100)
        // Line 3: turn 2 (total 350)
        let session1URL = dayDir.appendingPathComponent("rollout-2026-10-31T10-00-00-session-1.jsonl")
        let session1Content = """
        {"timestamp": "2026-10-31T10:00:00Z", "type": "session_meta", "payload": {"id": "session-1", "cwd": "/Users/dev/ProjectA", "model": "o3"}}
        {"timestamp": "2026-10-31T10:01:00Z", "type": "event_msg", "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 80, "cached_input_tokens": 10, "output_tokens": 10, "reasoning_output_tokens": 0, "total_tokens": 100}}}}
        {"timestamp": "2026-10-31T10:02:00Z", "type": "event_msg", "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 250, "cached_input_tokens": 50, "output_tokens": 50, "reasoning_output_tokens": 10, "total_tokens": 350}}}}

        """
        try session1Content.data(using: .utf8)?.write(to: session1URL)

        // Session 2: Another session with final cumulative tokens: 200
        let session2URL = dayDir.appendingPathComponent("rollout-2026-10-31T11-00-00-session-2.jsonl")
        let session2Content = """
        {"timestamp": "2026-10-31T11:00:00Z", "type": "session_meta", "payload": {"id": "session-2", "cwd": "/Users/dev/ProjectB", "model": "o3-mini"}}
        {"timestamp": "2026-10-31T11:01:00Z", "type": "event_msg", "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 150, "cached_input_tokens": 20, "output_tokens": 30, "reasoning_output_tokens": 5, "total_tokens": 200}}}}

        """
        try session2Content.data(using: .utf8)?.write(to: session2URL)

        let detector = CodexCLIDetector(baseDirectory: temporaryDirectory)

        // Process running on ProjectA
        let runningPID: pid_t = 12345
        let table: [pid_t: MonitoredProcess] = [
            runningPID: MonitoredProcess(pid: runningPID, ppid: 1, name: "codex", executablePath: "/usr/local/bin/codex", cwd: "/Users/dev/ProjectA")
        ]

        let sessions = detector.detectSessions(table: table)
        XCTAssertEqual(sessions.count, 2)

        let s1 = try XCTUnwrap(sessions.first(where: { $0.sessionID == "session-1" }))
        XCTAssertEqual(s1.pid, runningPID)
        XCTAssertEqual(s1.state, .working)
        XCTAssertEqual(s1.cwd, "/Users/dev/ProjectA")
        XCTAssertEqual(s1.model, "o3")
        XCTAssertEqual(s1.tokenUsage?.inputTokens, 250)
        XCTAssertEqual(s1.tokenUsage?.outputTokens, 50)

        let s2 = try XCTUnwrap(sessions.first(where: { $0.sessionID == "session-2" }))
        XCTAssertNil(s2.pid)
        XCTAssertEqual(s2.state, .inactive)
        XCTAssertEqual(s2.tokenUsage?.inputTokens, 150)

        // Daily token sum must take session1 max (250 in, 50 cached, 50 out, 10 reasoning) + session2 max (150 in, 20 cached, 30 out, 5 reasoning)
        // NOT summing session1's intermediate line!
        // Expected Input: 250 + 150 = 400
        // Expected Cached: 50 + 20 = 70
        // Expected Output: 50 + 30 = 80
        // Expected Reasoning: 10 + 5 = 15
        let dailyTokens = detector.computeDailyTokenUsage(calendar: calendar, now: now)
        XCTAssertEqual(dailyTokens.inputTokens, 400)
        XCTAssertEqual(dailyTokens.cachedInputTokens, 70)
        XCTAssertEqual(dailyTokens.outputTokens, 80)
        XCTAssertEqual(dailyTokens.reasoningTokens, 15)
        XCTAssertEqual(dailyTokens.totalTokens, 400 + 70 + 80 + 15)
    }

    func testDetectMethodWithOrchestrationAndInactive() throws {
        let calendar = Calendar.current
        let now = Date()
        let year = String(format: "%04d", calendar.component(.year, from: now))
        let month = String(format: "%02d", calendar.component(.month, from: now))
        let day = String(format: "%02d", calendar.component(.day, from: now))

        let dayDir = temporaryDirectory
            .appendingPathComponent("sessions")
            .appendingPathComponent(year)
            .appendingPathComponent(month)
            .appendingPathComponent(day)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        let sessionURL = dayDir.appendingPathComponent("rollout-2026-10-31T12-00-00-session-active.jsonl")
        let sessionContent = """
        {"timestamp": "2026-10-31T12:00:00Z", "type": "session_meta", "payload": {"id": "session-active", "cwd": "/Users/dev/t3project", "model": "o3"}}
        {"timestamp": "2026-10-31T12:01:00Z", "type": "event_msg", "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 100, "cached_input_tokens": 10, "output_tokens": 20, "reasoning_output_tokens": 5, "total_tokens": 135}}}}

        """
        try sessionContent.data(using: .utf8)?.write(to: sessionURL)

        let t3PID: pid_t = 500
        let codexPID: pid_t = 700
        let table: [pid_t: MonitoredProcess] = [
            t3PID: MonitoredProcess(pid: t3PID, ppid: 1, name: "t3code", executablePath: "/usr/local/bin/t3code", cwd: "/tmp"),
            codexPID: MonitoredProcess(pid: codexPID, ppid: t3PID, name: "codex", executablePath: "/usr/local/bin/codex", cwd: "/Users/dev/t3project")
        ]

        let detector = CodexCLIDetector(baseDirectory: temporaryDirectory)
        let results = detector.detect(processTable: table, t3RootPIDs: [t3PID])

        XCTAssertFalse(results.isEmpty)
        let active = try XCTUnwrap(results.first(where: { $0.pid == codexPID }))
        XCTAssertEqual(active.surface, .t3Orchestrated)
        XCTAssertEqual(active.parentT3PID, t3PID)
        XCTAssertEqual(active.workspacePath, "/Users/dev/t3project")
        XCTAssertEqual(active.projectName, "t3project")
        XCTAssertEqual(active.modelName, "o3")
        XCTAssertEqual(active.tokenUsage?.inputTokens, 100)
    }
}
