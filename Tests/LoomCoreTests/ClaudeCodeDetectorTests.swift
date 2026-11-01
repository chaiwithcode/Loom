//
//  ClaudeCodeDetectorTests.swift
//  LoomCoreTests
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation
@testable import LoomCore
import XCTest

final class ClaudeCodeDetectorTests: XCTestCase {
    var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCodeDetectorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temporaryDirectory = temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        super.tearDown()
    }

    func testFindLiveClaudeProcessesAndT3Deduplication() {
        let detector = ClaudeCodeDetector(baseDirectory: temporaryDirectory)

        let t3PID: pid_t = 1000
        let standaloneClaudePID: pid_t = 2000
        let t3ChildClaudePID: pid_t = 3000
        let bashChildPID: pid_t = 3001

        let table: [pid_t: MonitoredProcess] = [
            t3PID: MonitoredProcess(pid: t3PID, ppid: 1, name: "t3code", executablePath: "/usr/local/bin/t3code", cwd: "/tmp"),
            standaloneClaudePID: MonitoredProcess(pid: standaloneClaudePID, ppid: 1, name: "claude", executablePath: "/usr/local/bin/claude", cwd: "/Users/dev/standalone"),
            t3ChildClaudePID: MonitoredProcess(pid: t3ChildClaudePID, ppid: t3PID, name: "claude", executablePath: "/usr/local/bin/claude", cwd: "/Users/dev/t3project"),
            bashChildPID: MonitoredProcess(pid: bashChildPID, ppid: t3ChildClaudePID, name: "bash", executablePath: "/bin/bash", cwd: "/Users/dev/t3project")
        ]

        let t3AncestorPIDs: Set<pid_t> = [t3PID]
        let processes = detector.findLiveClaudeProcesses(table: table, t3AncestorPIDs: t3AncestorPIDs)

        XCTAssertEqual(processes.count, 2)

        let standalone = try? XCTUnwrap(processes.first(where: { $0.pid == standaloneClaudePID }))
        XCTAssertEqual(standalone?.surface, .cli)
        XCTAssertNil(standalone?.parentT3PID)
        XCTAssertTrue(standalone?.childPIDs.isEmpty ?? false)

        let child = try? XCTUnwrap(processes.first(where: { $0.pid == t3ChildClaudePID }))
        XCTAssertEqual(child?.surface, .t3Orchestrated)
        XCTAssertEqual(child?.parentT3PID, t3PID)
        XCTAssertEqual(child?.childPIDs, [bashChildPID])
    }

    func testStateDetectionAwaitingApprovalVsWorking() throws {
        let projectsDir = temporaryDirectory.appendingPathComponent("projects").appendingPathComponent("-Users-dev-ProjectApp")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let fileURL = projectsDir.appendingPathComponent("session-claude-1.jsonl")

        // Tool use stop reason
        let lines = [
            "{\"sessionId\": \"claude-tool-wait\", \"cwd\": \"/Users/dev/ProjectApp\", \"type\": \"assistant\", \"timestamp\": \"2026-10-31T18:00:00Z\", \"message\": {\"id\": \"msg-1\", \"model\": \"claude-sonnet\", \"stop_reason\": \"tool_use\", \"usage\": {\"input_tokens\": 100, \"output_tokens\": 50}}}"
        ]
        let content = lines.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)?.write(to: fileURL)

        // Case 1: Live process has NO running child processes, modified 10 seconds ago -> .awaitingApproval
        let now = Date()
        let oldModDate = now.addingTimeInterval(-10.0)
        try FileManager.default.setAttributes([.modificationDate: oldModDate], ofItemAtPath: fileURL.path)

        let claudePID: pid_t = 4500
        let tableNoChild: [pid_t: MonitoredProcess] = [
            claudePID: MonitoredProcess(pid: claudePID, ppid: 1, name: "claude", executablePath: "/usr/local/bin/claude", cwd: "/Users/dev/ProjectApp")
        ]

        let detector = ClaudeCodeDetector(baseDirectory: temporaryDirectory)
        let sessionsWaiting = detector.detectSessions(table: tableNoChild, now: now)

        let s1 = try XCTUnwrap(sessionsWaiting.first(where: { $0.sessionID == "claude-tool-wait" }))
        XCTAssertEqual(s1.state, .awaitingApproval, "Claude should be awaitingApproval when stopped for tool_use with no active child processes")

        // Case 2: Live process HAS a running child subprocess -> .working
        let childSubprocPID: pid_t = 4501
        let tableWithChild: [pid_t: MonitoredProcess] = [
            claudePID: MonitoredProcess(pid: claudePID, ppid: 1, name: "claude", executablePath: "/usr/local/bin/claude", cwd: "/Users/dev/ProjectApp"),
            childSubprocPID: MonitoredProcess(pid: childSubprocPID, ppid: claudePID, name: "swift", executablePath: "/usr/bin/swift", cwd: "/Users/dev/ProjectApp")
        ]

        let sessionsWorking = detector.detectSessions(table: tableWithChild, now: now)
        let s2 = try XCTUnwrap(sessionsWorking.first(where: { $0.sessionID == "claude-tool-wait" }))
        XCTAssertEqual(s2.state, .working, "Claude should be working when a child process (e.g. tool execution) is actively running")
    }

    func testDailyTokenUsageDeduplicatesMessageIDs() throws {
        let projectsDir = temporaryDirectory.appendingPathComponent("projects").appendingPathComponent("-Users-dev-ProjectApp")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let fileURL = projectsDir.appendingPathComponent("session-stream.jsonl")

        // 3 lines for the same message id (streaming updates with increasing token counts)
        let lines = [
            "{\"sessionId\": \"s1\", \"cwd\": \"/Users/dev/ProjectApp\", \"type\": \"assistant\", \"message\": {\"id\": \"msg-1\", \"model\": \"sonnet\", \"usage\": {\"input_tokens\": 100, \"cache_read_input_tokens\": 500, \"output_tokens\": 10}}}",
            "{\"sessionId\": \"s1\", \"cwd\": \"/Users/dev/ProjectApp\", \"type\": \"assistant\", \"message\": {\"id\": \"msg-1\", \"model\": \"sonnet\", \"usage\": {\"input_tokens\": 100, \"cache_read_input_tokens\": 500, \"output_tokens\": 50}}}",
            "{\"sessionId\": \"s1\", \"cwd\": \"/Users/dev/ProjectApp\", \"type\": \"assistant\", \"message\": {\"id\": \"msg-1\", \"model\": \"sonnet\", \"usage\": {\"input_tokens\": 100, \"cache_read_input_tokens\": 500, \"output_tokens\": 120}}}"
        ]
        let content = lines.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)?.write(to: fileURL)

        let detector = ClaudeCodeDetector(baseDirectory: temporaryDirectory)
        let now = Date()
        let usage = detector.computeDailyTokenUsage(now: now)

        // Must deduplicate by msg-1, taking the final values (100 in, 500 cached, 120 out)
        // NOT 3x values (300 in, 1500 cached, 180 out)!
        XCTAssertEqual(usage.inputTokens, 100)
        XCTAssertEqual(usage.cachedInputTokens, 500)
        XCTAssertEqual(usage.outputTokens, 120)
    }

    func testDetectMethodWithOrchestrationAndInactive() throws {
        let projectsDir = temporaryDirectory.appendingPathComponent("projects").appendingPathComponent("-Users-dev-T3ClaudeApp")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let fileURL = projectsDir.appendingPathComponent("session-active.jsonl")

        let lines = [
            "{\"sessionId\": \"claude-active-1\", \"cwd\": \"/Users/dev/T3ClaudeApp\", \"gitBranch\": \"feature/login\", \"type\": \"assistant\", \"message\": {\"id\": \"msg-1\", \"model\": \"claude-3-7-sonnet\", \"usage\": {\"input_tokens\": 300, \"cache_read_input_tokens\": 100, \"output_tokens\": 80}}}"
        ]
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: fileURL)

        let t3PID: pid_t = 1000
        let claudePID: pid_t = 2000
        let table: [pid_t: MonitoredProcess] = [
            t3PID: MonitoredProcess(pid: t3PID, ppid: 1, name: "t3code", executablePath: "/usr/local/bin/t3code", cwd: "/tmp"),
            claudePID: MonitoredProcess(pid: claudePID, ppid: t3PID, name: "claude", executablePath: "/usr/local/bin/claude", cwd: "/Users/dev/T3ClaudeApp")
        ]

        let detector = ClaudeCodeDetector(baseDirectory: temporaryDirectory)
        let results = detector.detect(processTable: table, t3RootPIDs: [t3PID])

        XCTAssertFalse(results.isEmpty)
        let active = try XCTUnwrap(results.first(where: { $0.pid == claudePID }))
        XCTAssertEqual(active.surface, .t3Orchestrated)
        XCTAssertEqual(active.parentT3PID, t3PID)
        XCTAssertEqual(active.workspacePath, "/Users/dev/T3ClaudeApp")
        XCTAssertEqual(active.projectName, "T3ClaudeApp")
        XCTAssertEqual(active.gitBranch, "feature/login")
        XCTAssertEqual(active.modelName, "claude-3-7-sonnet")
        XCTAssertEqual(active.tokenUsage?.inputTokens, 300)
    }
}
