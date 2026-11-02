//
//  T3CodeDetectorTests.swift
//  LoomCoreTests
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation
@testable import LoomCore
import SQLite3
import XCTest

final class T3CodeDetectorTests: XCTestCase {
    var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T3CodeDetectorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temporaryDirectory = temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        super.tearDown()
    }

    func testResolveServerRuntimeRejectsStalePID() throws {
        let userdata = temporaryDirectory.appendingPathComponent("userdata")
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        let runtimeURL = userdata.appendingPathComponent("server-runtime.json")

        // Use an intentionally stale/dead PID
        let stalePID: pid_t = 999999
        let json = "{\"version\": 1, \"pid\": \(stalePID), \"port\": 3773, \"origin\": \"http://127.0.0.1:3773\"}"
        try json.data(using: .utf8)?.write(to: runtimeURL)

        let detector = T3CodeDetector(baseDirectory: temporaryDirectory)
        // With an empty process table, stale PID must be rejected
        let runtime = detector.resolveServerRuntime(processTable: [:])
        XCTAssertNil(runtime, "Stale PID should be rejected when not in process table")
    }

    func testResolveServerRuntimeAcceptsValidPID() throws {
        let userdata = temporaryDirectory.appendingPathComponent("userdata")
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        let runtimeURL = userdata.appendingPathComponent("server-runtime.json")

        let myPID = getpid()
        let json = "{\"version\": 1, \"pid\": \(myPID), \"port\": 3773, \"origin\": \"http://127.0.0.1:3773\"}"
        try json.data(using: .utf8)?.write(to: runtimeURL)

        let detector = T3CodeDetector(baseDirectory: temporaryDirectory)
        let table: [pid_t: MonitoredProcess] = [
            myPID: MonitoredProcess(pid: myPID, ppid: getppid(), name: "test", executablePath: "/bin/test", cwd: "/tmp")
        ]
        let runtime = detector.resolveServerRuntime(processTable: table)
        XCTAssertNotNil(runtime, "Valid running PID in table should be accepted")
        XCTAssertEqual(runtime?.pid, myPID)
        XCTAssertEqual(runtime?.port, 3773)
    }

    func testReadActiveThreadsFromMockSQLite() throws {
        let userdata = temporaryDirectory.appendingPathComponent("userdata")
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        let dbURL = userdata.appendingPathComponent("statev2.sqlite")

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let schema = """
        CREATE TABLE projection_projects (
            project_id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            workspace_root TEXT NOT NULL,
            scripts_json TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL DEFAULT '',
            deleted_at TEXT
        );

        CREATE TABLE orchestration_v2_projection_threads (
            thread_id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            default_provider TEXT NOT NULL,
            runtime_mode TEXT NOT NULL DEFAULT 'standard',
            interaction_mode TEXT NOT NULL DEFAULT 'chat',
            active_provider_thread_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            archived_at TEXT,
            deleted_at TEXT,
            payload_json TEXT NOT NULL DEFAULT '{}'
        );

        CREATE TABLE orchestration_v2_projection_runs (
            run_id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL,
            provider TEXT NOT NULL,
            provider_thread_id TEXT,
            status TEXT NOT NULL,
            requested_at TEXT NOT NULL,
            completed_at TEXT,
            payload_json TEXT NOT NULL DEFAULT '{}'
        );

        CREATE TABLE orchestration_v2_projection_runtime_requests (
            runtime_request_id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            node_id TEXT NOT NULL DEFAULT '',
            provider_turn_id TEXT,
            kind TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            resolved_at TEXT,
            payload_json TEXT NOT NULL DEFAULT '{}'
        );
        """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)

        let insertData = """
        INSERT INTO projection_projects (project_id, title, workspace_root)
        VALUES ('proj-1', 'Loom Test', '/Users/dev/Loom');

        -- Thread 1: Working (run is running)
        INSERT INTO orchestration_v2_projection_threads (thread_id, project_id, title, default_provider, created_at, updated_at)
        VALUES ('thread-1', 'proj-1', 'Build Feature', 'codex', '2026-10-31T20:00:00Z', '2026-10-31T20:05:00Z');

        INSERT INTO orchestration_v2_projection_runs (run_id, thread_id, ordinal, provider, status, requested_at)
        VALUES ('run-1', 'thread-1', 1, 'codex', 'running', '2026-10-31T20:05:00Z');

        -- Thread 2: Awaiting Approval (has pending request)
        INSERT INTO orchestration_v2_projection_threads (thread_id, project_id, title, default_provider, created_at, updated_at)
        VALUES ('thread-2', 'proj-1', 'Review PR', 'claude', '2026-10-31T20:10:00Z', '2026-10-31T20:15:00Z');

        INSERT INTO orchestration_v2_projection_runtime_requests (runtime_request_id, thread_id, kind, status, created_at)
        VALUES ('req-1', 'thread-2', 'user_approval', 'pending', '2026-10-31T20:15:00Z');

        -- Thread 3: Idle (run completed)
        INSERT INTO orchestration_v2_projection_threads (thread_id, project_id, title, default_provider, created_at, updated_at)
        VALUES ('thread-3', 'proj-1', 'Fix Bug', 'antigravity', '2026-10-31T20:20:00Z', '2026-10-31T20:25:00Z');

        INSERT INTO orchestration_v2_projection_runs (run_id, thread_id, ordinal, provider, status, requested_at, completed_at)
        VALUES ('run-2', 'thread-3', 1, 'antigravity', 'completed', '2026-10-31T20:20:00Z', '2026-10-31T20:25:00Z');
        """
        XCTAssertEqual(sqlite3_exec(db, insertData, nil, nil, nil), SQLITE_OK)

        let detector = T3CodeDetector(baseDirectory: temporaryDirectory)
        let threads = detector.readActiveThreads()

        XCTAssertEqual(threads.count, 3)

        // Find thread 1 (working)
        let t1 = try XCTUnwrap(threads.first(where: { $0.threadID == "thread-1" }))
        XCTAssertEqual(t1.state, .working)
        XCTAssertEqual(t1.projectTitle, "Loom Test")
        XCTAssertEqual(t1.workspaceRoot, "/Users/dev/Loom")

        // Find thread 2 (awaitingApproval)
        let t2 = try XCTUnwrap(threads.first(where: { $0.threadID == "thread-2" }))
        XCTAssertEqual(t2.state, .awaitingApproval)
        XCTAssertEqual(t2.pendingRequestsCount, 1)

        // Find thread 3 (idle)
        let t3 = try XCTUnwrap(threads.first(where: { $0.threadID == "thread-3" }))
        XCTAssertEqual(t3.state, .idle)
    }

    func testCollectT3AncestorPIDsAndDeduplication() {
        let detector = T3CodeDetector(baseDirectory: temporaryDirectory)
        let serverPID: pid_t = 1000
        let desktopAppPID: pid_t = 1050
        let childCLITerminalPID: pid_t = 2000
        let otherAppPID: pid_t = 3000

        let table: [pid_t: MonitoredProcess] = [
            serverPID: MonitoredProcess(pid: serverPID, ppid: 1, name: "t3code", executablePath: "/usr/local/bin/t3code", cwd: "/tmp"),
            desktopAppPID: MonitoredProcess(pid: desktopAppPID, ppid: 1, name: "T3 Code", executablePath: "/Applications/T3 Code.app/Contents/MacOS/T3 Code", cwd: "/tmp"),
            childCLITerminalPID: MonitoredProcess(pid: childCLITerminalPID, ppid: serverPID, name: "codex", executablePath: "/usr/local/bin/codex", cwd: "/tmp"),
            otherAppPID: MonitoredProcess(pid: otherAppPID, ppid: 1, name: "xcode", executablePath: "/Applications/Xcode.app", cwd: nil)
        ]

        let t3PIDs = detector.collectT3AncestorPIDs(table: table, serverPID: serverPID)
        XCTAssertTrue(t3PIDs.contains(serverPID))
        XCTAssertTrue(t3PIDs.contains(desktopAppPID))
        XCTAssertFalse(t3PIDs.contains(childCLITerminalPID))
        XCTAssertFalse(t3PIDs.contains(otherAppPID))

        // Child process should resolve to T3Code ancestor
        let ancestor = ProcessTreeScanner.findAncestor(of: childCLITerminalPID, in: table, matching: t3PIDs)
        XCTAssertEqual(ancestor, serverPID, "codex spawned by t3code server should be identified as child of T3Code")
    }

    func testT3CodeProviderDiscoverSessions() async throws {
        let userdata = temporaryDirectory.appendingPathComponent("userdata")
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        let runtimeURL = userdata.appendingPathComponent("server-runtime.json")

        let myPID = getpid()
        let json = "{\"version\": 1, \"pid\": \(myPID), \"port\": 65530, \"origin\": \"http://127.0.0.1:65530\"}"
        try json.data(using: .utf8)?.write(to: runtimeURL)

        let dbURL = userdata.appendingPathComponent("statev2.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let nowISO = ISO8601DateFormatter().string(from: Date())
        let schema = """
        CREATE TABLE projection_projects (
            project_id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            workspace_root TEXT NOT NULL,
            scripts_json TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL DEFAULT '',
            deleted_at TEXT
        );

        CREATE TABLE orchestration_v2_projection_threads (
            thread_id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            default_provider TEXT NOT NULL,
            runtime_mode TEXT NOT NULL DEFAULT 'standard',
            interaction_mode TEXT NOT NULL DEFAULT 'chat',
            active_provider_thread_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            archived_at TEXT,
            deleted_at TEXT,
            payload_json TEXT NOT NULL DEFAULT '{}'
        );

        CREATE TABLE orchestration_v2_projection_runs (
            run_id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL,
            provider TEXT NOT NULL,
            provider_thread_id TEXT,
            status TEXT NOT NULL,
            requested_at TEXT NOT NULL,
            completed_at TEXT,
            payload_json TEXT NOT NULL DEFAULT '{}'
        );

        CREATE TABLE orchestration_v2_projection_runtime_requests (
            runtime_request_id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            node_id TEXT NOT NULL DEFAULT '',
            provider_turn_id TEXT,
            kind TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            resolved_at TEXT,
            payload_json TEXT NOT NULL DEFAULT '{}'
        );

        INSERT INTO projection_projects (project_id, title, workspace_root)
        VALUES ('proj-loom', 'Loom Desktop', '/Users/deepak/Desktop/Projects/OSS/Loom');

        INSERT INTO orchestration_v2_projection_threads (thread_id, project_id, title, default_provider, created_at, updated_at)
        VALUES ('t3-thread-live', 'proj-loom', 'Active Task', 'acpRegistry_google_antigravity', '\(nowISO)', '\(nowISO)');

        INSERT INTO orchestration_v2_projection_runs (run_id, thread_id, ordinal, provider, status, requested_at)
        VALUES ('run-live', 't3-thread-live', 1, 'acpRegistry_google_antigravity', 'running', '\(nowISO)');
        """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)

        let detector = T3CodeDetector(baseDirectory: temporaryDirectory)
        let provider = T3CodeProvider(detector: detector)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.id, "t3-thread-live")
        XCTAssertEqual(session.provider, .t3Code)
        XCTAssertEqual(session.projectName, "Loom Desktop")
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.pid, Int(myPID))
    }
}
