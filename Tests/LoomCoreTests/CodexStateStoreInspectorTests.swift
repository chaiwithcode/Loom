//
//  CodexStateStoreInspectorTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
import SQLite3
@testable import LoomCore

final class CodexStateStoreInspectorTests: XCTestCase {
    private var tempDir: URL!
    private var dbURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("loom-codex-db-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("state_5.sqlite")
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        try await super.tearDown()
    }

    private func createTestDatabase() throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let validDB = db else {
            XCTFail("Failed to create test SQLite database")
            return
        }
        defer { sqlite3_close(validDB) }

        let schema = """
        CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            metadata TEXT NOT NULL DEFAULT '{}'
        );

        CREATE TABLE project_roots (
            project_id TEXT NOT NULL,
            position INTEGER NOT NULL,
            path TEXT NOT NULL,
            PRIMARY KEY (project_id, position)
        );

        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            cwd TEXT NOT NULL,
            title TEXT NOT NULL,
            git_branch TEXT,
            project_id TEXT
        );
        """

        XCTAssertEqual(sqlite3_exec(validDB, schema, nil, nil, nil), SQLITE_OK)

        let insertData = """
        INSERT INTO projects (id, name) VALUES ('proj-1', 'Naviik - SmartRemote');
        INSERT INTO projects (id, name) VALUES ('proj-2', 'Loom');

        INSERT INTO project_roots (project_id, position, path) VALUES
            ('proj-1', 0, '/Users/developer/.codex/.chatgpt-projects/g-p-6a1c1358a77c8191b1700dd481c5b2b1'),
            ('proj-2', 0, '/Users/developer/Desktop/Projects/oss/Loom');

        INSERT INTO threads (id, cwd, title, git_branch, project_id) VALUES
            ('thread-abc-123', '/Users/developer/.codex/.chatgpt-projects/g-p-6a1c1358a77c8191b1700dd481c5b2b1', 'Install skills and build app store', 'main', 'proj-1');
        """

        XCTAssertEqual(sqlite3_exec(validDB, insertData, nil, nil, nil), SQLITE_OK)
    }

    func testLoadProjectRootsAndPrefixMatching() async throws {
        try createTestDatabase()

        let inspector = DefaultCodexStateStoreInspector(databaseURL: dbURL)
        let roots = await inspector.loadProjectRoots()

        XCTAssertEqual(roots.count, 2)
        XCTAssertTrue(roots.contains { $0.projectName == "Naviik - SmartRemote" && $0.projectID == "proj-1" })
        XCTAssertTrue(roots.contains { $0.projectName == "Loom" && $0.projectID == "proj-2" })

        // Test exact path match
        let exactURL = URL(fileURLWithPath: "/Users/developer/.codex/.chatgpt-projects/g-p-6a1c1358a77c8191b1700dd481c5b2b1")
        let name1 = await inspector.projectName(forPath: exactURL)
        XCTAssertEqual(name1, "Naviik - SmartRemote")

        // Test subfolder match
        let subfolderURL = URL(fileURLWithPath: "/Users/developer/.codex/.chatgpt-projects/g-p-6a1c1358a77c8191b1700dd481c5b2b1/sources/app")
        let name2 = await inspector.projectName(forPath: subfolderURL)
        XCTAssertEqual(name2, "Naviik - SmartRemote")

        // Test unmatched path
        let unmatchedURL = URL(fileURLWithPath: "/tmp/some-random-folder")
        let name3 = await inspector.projectName(forPath: unmatchedURL)
        XCTAssertNil(name3)
    }

    func testThreadMetadataLookupBySessionID() async throws {
        try createTestDatabase()

        let inspector = DefaultCodexStateStoreInspector(databaseURL: dbURL)

        // Known thread
        let meta = await inspector.sessionMetadata(for: "thread-abc-123")
        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.sessionID, "thread-abc-123")
        XCTAssertEqual(meta?.projectName, "Naviik - SmartRemote")
        XCTAssertEqual(meta?.title, "Install skills and build app store")
        XCTAssertEqual(meta?.gitBranch, "main")
        XCTAssertEqual(meta?.workingDirectory?.path, "/Users/developer/.codex/.chatgpt-projects/g-p-6a1c1358a77c8191b1700dd481c5b2b1")

        // Unknown thread
        let unknownMeta = await inspector.sessionMetadata(for: "thread-nonexistent")
        XCTAssertNil(unknownMeta)
    }

    func testInspectorHandlesMissingDatabaseGracefully() async {
        let missingURL = tempDir.appendingPathComponent("nonexistent.sqlite")
        let inspector = DefaultCodexStateStoreInspector(databaseURL: missingURL)

        let roots = await inspector.loadProjectRoots()
        XCTAssertTrue(roots.isEmpty)

        let name = await inspector.projectName(forPath: URL(fileURLWithPath: "/some/path"))
        XCTAssertNil(name)

        let meta = await inspector.sessionMetadata(for: "any-id")
        XCTAssertNil(meta)
    }

    func testAutomaticLatestStateDatabaseResolution() throws {
        // Create state_4.sqlite and state_5.sqlite
        let state4 = tempDir.appendingPathComponent("state_4.sqlite")
        let state5 = tempDir.appendingPathComponent("state_5.sqlite")
        FileManager.default.createFile(atPath: state4.path, contents: Data())
        FileManager.default.createFile(atPath: state5.path, contents: Data())

        let inspector = DefaultCodexStateStoreInspector(databaseURL: nil, stateDirectoryURL: tempDir)
        let resolved = inspector.resolveDatabaseURL()

        XCTAssertEqual(resolved?.lastPathComponent, "state_5.sqlite")
    }
}
