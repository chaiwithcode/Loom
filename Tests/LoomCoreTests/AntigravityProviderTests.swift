import XCTest
import Foundation
import SQLite3
@testable import LoomCore

// MARK: - Mocks & Test Doubles

final class MockAntigravityProcessDiscoverer: AntigravityProcessDiscovering, @unchecked Sendable {
    var isRunning: Bool

    init(isRunning: Bool = true) {
        self.isRunning = isRunning
    }

    func isAntigravityRunning() async -> Bool {
        return isRunning
    }
}

final class MockAntigravityStoreInspector: AntigravityStoreInspecting, @unchecked Sendable {
    var records: [AntigravitySessionRecord]
    var shouldThrow: Bool

    init(records: [AntigravitySessionRecord] = [], shouldThrow: Bool = false) {
        self.records = records
        self.shouldThrow = shouldThrow
    }

    func fetchActiveSessions() async throws -> [AntigravitySessionRecord] {
        if shouldThrow {
            throw NSError(domain: "MockAntigravityStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read database"])
        }
        return records
    }
}

final class MockFileSystemForAntigravity: FileSystemInspecting, Sendable {
    let files: [String: String]
    let directories: Set<String>

    init(files: [String: String] = [:], directories: Set<String> = []) {
        self.files = files
        self.directories = directories
    }

    convenience init(existingDirectories: [String] = [], fileContents: [String: String] = [:]) {
        self.init(files: fileContents, directories: Set(existingDirectories))
    }

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        if directories.contains(path) {
            isDirectory?.pointee = true
            return true
        }
        if files[path] != nil {
            isDirectory?.pointee = false
            return true
        }
        return false
    }

    func readFile(atPath path: String) throws -> String {
        guard let content = files[path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return content
    }
}

final class MockProcessExecutorForAntigravity: ProcessExecuting, @unchecked Sendable {
    var output: String
    var shouldThrow: Bool

    init(output: String = "", shouldThrow: Bool = false) {
        self.output = output
        self.shouldThrow = shouldThrow
    }

    func execute(executablePath: String, arguments: [String]) async throws -> String {
        if shouldThrow {
            throw NSError(domain: "MockExecutor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Process execution failed"])
        }
        return output
    }
}

// MARK: - AntigravityProviderTests

final class AntigravityProviderTests: XCTestCase {

    // MARK: 1. Process Liveness & Command Matching Tests

    func testAntigravityProcessCommandMatching() {
        // Positive matches
        XCTAssertTrue(AntigravityParser.isAntigravityProcessCommand("/Applications/Antigravity.app/Contents/MacOS/Antigravity"))
        XCTAssertTrue(AntigravityParser.isAntigravityProcessCommand("/Applications/Antigravity.app/Contents/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper --type=renderer"))
        XCTAssertTrue(AntigravityParser.isAntigravityProcessCommand("/Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --override_ide_name antigravity --subclient_type hub"))
        XCTAssertTrue(AntigravityParser.isAntigravityProcessCommand("/Users/deepak/.gemini/bin/agy --hub --hub-port=52663 --app_data_dir=antigravity"))
        XCTAssertTrue(AntigravityParser.isAntigravityProcessCommand("agy --conversation 0b3caa3f-bf06-4f59-a41b-9c7aa8c4aa9a"))

        // False positives
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("grep -i antigravity"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("/Users/deepak/Desktop/Projects/oss/Loom/.build/debug/Loom"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("swiftc Loom/Providers/Antigravity/AntigravityProvider.swift"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("xcodebuild -scheme Loom"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("/Users/deepak/Library/Developer/Xcode/DerivedData/Loom/Build/Products/Debug/Loom"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("vim antigravity.txt"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand(""))
    }

    func testDefaultAntigravityProcessDiscoverer() async {
        let runningPsOutput = """
        /sbin/launchd
        /Applications/Antigravity.app/Contents/MacOS/Antigravity
        /Applications/Antigravity.app/Contents/Resources/bin/language_server --subclient_type hub
        """
        let executor = MockProcessExecutorForAntigravity(output: runningPsOutput)
        let discoverer = DefaultAntigravityProcessDiscoverer(executor: executor)
        let isRunning = await discoverer.isAntigravityRunning()
        XCTAssertTrue(isRunning)

        // When ps outputs unrelated processes
        let idlePsOutput = """
        /sbin/launchd
        /usr/libexec/logd
        """
        let idleExecutor = MockProcessExecutorForAntigravity(output: idlePsOutput)
        let idleDiscoverer = DefaultAntigravityProcessDiscoverer(executor: idleExecutor)
        let isIdle = await idleDiscoverer.isAntigravityRunning()
        XCTAssertFalse(isIdle)

        // When ps fails
        let failingExecutor = MockProcessExecutorForAntigravity(shouldThrow: true)
        let failingDiscoverer = DefaultAntigravityProcessDiscoverer(executor: failingExecutor)
        let didFail = await failingDiscoverer.isAntigravityRunning()
        XCTAssertFalse(didFail)
    }

    // MARK: 2. Workspace URIs & Date Parsing Tests

    func testWorkspaceURIsParsing() {
        // Standard single URI
        let singleJSON = "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]"
        let singleURLs = AntigravityParser.parseWorkspaceURLs(from: singleJSON)
        XCTAssertEqual(singleURLs.count, 1)
        XCTAssertEqual(singleURLs.first?.path, "/Users/deepak/Desktop/Projects/oss/Loom")

        // Percent-encoded URI with spaces and special characters
        let encodedJSON = "[\"file:///Users/deepak/Projects/My%20App/Special%20Folder\"]"
        let encodedURLs = AntigravityParser.parseWorkspaceURLs(from: encodedJSON)
        XCTAssertEqual(encodedURLs.count, 1)
        XCTAssertEqual(encodedURLs.first?.path, "/Users/deepak/Projects/My App/Special Folder")

        // Multiple workspace URIs
        let multipleJSON = "[\"file:///Users/deepak/RepoA\", \"file:///Users/deepak/RepoB\"]"
        let multipleURLs = AntigravityParser.parseWorkspaceURLs(from: multipleJSON)
        XCTAssertEqual(multipleURLs.count, 2)
        XCTAssertEqual(multipleURLs[0].path, "/Users/deepak/RepoA")
        XCTAssertEqual(multipleURLs[1].path, "/Users/deepak/RepoB")

        // Raw path without file:// scheme
        let rawJSON = "[\"/Users/deepak/Projects/oss/RawRepo\"]"
        let rawURLs = AntigravityParser.parseWorkspaceURLs(from: rawJSON)
        XCTAssertEqual(rawURLs.count, 1)
        XCTAssertEqual(rawURLs.first?.path, "/Users/deepak/Projects/oss/RawRepo")

        // Empty array
        XCTAssertTrue(AntigravityParser.parseWorkspaceURLs(from: "[]").isEmpty)

        // Malformed JSON strings
        XCTAssertTrue(AntigravityParser.parseWorkspaceURLs(from: "not a json").isEmpty)
        XCTAssertTrue(AntigravityParser.parseWorkspaceURLs(from: "").isEmpty)
        XCTAssertTrue(AntigravityParser.parseWorkspaceURLs(from: "{\"key\": \"val\"}").isEmpty)
        XCTAssertTrue(AntigravityParser.parseWorkspaceURLs(from: "[123, 456]").isEmpty)
    }

    func testDateParsing() {
        // Space separated with microsecond timestamp and offset (from conversation_summaries.db)
        let dbDateStr = "2026-10-03 12:29:53.903014+00:00"
        let parsedDate1 = AntigravityParser.parseDate(from: dbDateStr)
        XCTAssertNotNil(parsedDate1)

        // Standard ISO8601 with Z
        let isoZ = "2026-10-03T12:29:53Z"
        let parsedDate2 = AntigravityParser.parseDate(from: isoZ)
        XCTAssertNotNil(parsedDate2)

        // ISO8601 with fractional seconds
        let isoFractional = "2026-10-03T12:29:53.903Z"
        let parsedDate3 = AntigravityParser.parseDate(from: isoFractional)
        XCTAssertNotNil(parsedDate3)

        // Standard space separated
        let standardSpace = "2026-10-03 12:29:53"
        let parsedDate4 = AntigravityParser.parseDate(from: standardSpace)
        XCTAssertNotNil(parsedDate4)

        // Malformed
        XCTAssertNil(AntigravityParser.parseDate(from: "invalid-date"))
        XCTAssertNil(AntigravityParser.parseDate(from: ""))
    }

    func testActiveSessionCondition() {
        // CASCADE_RUN_STATUS_RUNNING
        XCTAssertTrue(AntigravityParser.isActiveSession(status: "CASCADE_RUN_STATUS_RUNNING", notFullyIdle: false, killed: false))
        // notFullyIdle = true
        XCTAssertTrue(AntigravityParser.isActiveSession(status: "CASCADE_RUN_STATUS_IDLE", notFullyIdle: true, killed: false))
        // both
        XCTAssertTrue(AntigravityParser.isActiveSession(status: "CASCADE_RUN_STATUS_RUNNING", notFullyIdle: true, killed: false))

        // Idle
        XCTAssertFalse(AntigravityParser.isActiveSession(status: "CASCADE_RUN_STATUS_IDLE", notFullyIdle: false, killed: false))
        // Killed takes precedence
        XCTAssertFalse(AntigravityParser.isActiveSession(status: "CASCADE_RUN_STATUS_RUNNING", notFullyIdle: true, killed: true))
        XCTAssertFalse(AntigravityParser.isActiveSession(status: "CASCADE_RUN_STATUS_RUNNING", notFullyIdle: false, killed: true))
    }

    // MARK: 3. Provider Discovery & Normalization Tests

    func testAntigravityProviderWhenProcessNotRunning() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: false)
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-1",
                title: "Active task",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            )
        ])
        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector
        )

        let sessions = try await provider.discoverSessions()
        // Stale database record should be ignored because process is not running!
        XCTAssertTrue(sessions.isEmpty)
    }

    func testAntigravityProviderSingleActiveSessionInGitRepo() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let repoURL = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom")
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-abc",
                title: "Refactor session discovery",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false,
                lastUserInputTime: "2026-10-03 12:20:00.000000+00:00",
                lastModifiedTime: "2026-10-03 12:29:53.903014+00:00"
            )
        ])

        let mockFS = MockFileSystemForAntigravity(
            existingDirectories: [repoURL.appendingPathComponent(".git").path],
            fileContents: [
                repoURL.appendingPathComponent(".git/HEAD").path: "ref: refs/heads/main\n"
            ]
        )
        let gitResolver = DefaultGitRepositoryResolver(fileSystem: mockFS)

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector,
            gitResolver: gitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.id, "antigravity-conv-abc")
        XCTAssertEqual(session.provider, ProviderID.antigravity)
        XCTAssertEqual(session.projectName, "Loom")
        XCTAssertEqual(session.projectPath, repoURL.standardizedFileURL)
        XCTAssertEqual(session.branch, "main")
        XCTAssertEqual(session.state, AgentState.working)
        XCTAssertEqual(session.summary, "Refactor session discovery")
        XCTAssertNil(session.startedAt, "Antigravity has no true start timestamp field")
        XCTAssertNotNil(session.lastActivityAt)
    }

    func testAntigravityProviderDetachedHead() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let repoURL = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom")
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-detached",
                title: "Detached testing",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            )
        ])

        let mockFS = MockFileSystemForAntigravity(
            existingDirectories: [repoURL.appendingPathComponent(".git").path],
            fileContents: [
                repoURL.appendingPathComponent(".git/HEAD").path: "0123456789abcdef0123456789abcdef01234567\n"
            ]
        )
        let gitResolver = DefaultGitRepositoryResolver(fileSystem: mockFS)

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector,
            gitResolver: gitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].branch, "0123456")
    }

    func testAntigravityProviderNonGitWorkspace() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let workspaceURL = URL(fileURLWithPath: "/Users/deepak/Desktop/Notes")
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-notes",
                title: "Note taking",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Notes\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            )
        ])

        let mockFS = MockFileSystemForAntigravity(existingDirectories: [], fileContents: [:])
        let gitResolver = DefaultGitRepositoryResolver(fileSystem: mockFS)

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector,
            gitResolver: gitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].projectName, "Notes")
        XCTAssertEqual(sessions[0].projectPath, workspaceURL.standardizedFileURL)
        XCTAssertNil(sessions[0].branch)
    }

    func testAntigravityProviderMultipleActiveSessionsInDifferentRepos() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let repoA = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/RepoA")
        let repoB = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/RepoB")

        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-1",
                title: "Task in RepoA",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/RepoA\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            ),
            AntigravitySessionRecord(
                conversationId: "conv-2",
                title: "Task in RepoB",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/RepoB\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            ),
            AntigravitySessionRecord(
                conversationId: "conv-3",
                title: "Idle task",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/RepoA\"]",
                status: "CASCADE_RUN_STATUS_IDLE",
                notFullyIdle: false,
                killed: false
            )
        ])

        let mockFS = MockFileSystemForAntigravity(
            existingDirectories: [
                repoA.appendingPathComponent(".git").path,
                repoB.appendingPathComponent(".git").path
            ],
            fileContents: [
                repoA.appendingPathComponent(".git/HEAD").path: "ref: refs/heads/feature-a\n",
                repoB.appendingPathComponent(".git/HEAD").path: "ref: refs/heads/feature-b\n"
            ]
        )
        let gitResolver = DefaultGitRepositoryResolver(fileSystem: mockFS)

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector,
            gitResolver: gitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].projectName, "RepoA")
        XCTAssertEqual(sessions[0].branch, "feature-a")
        XCTAssertEqual(sessions[1].projectName, "RepoB")
        XCTAssertEqual(sessions[1].branch, "feature-b")
    }

    func testAntigravityProviderDeduplicatesSameConversationId() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-dup",
                title: "Duplicate row 1",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            ),
            AntigravitySessionRecord(
                conversationId: "conv-dup",
                title: "Duplicate row 2",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            )
        ])

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector,
            gitResolver: DefaultGitRepositoryResolver(fileSystem: MockFileSystemForAntigravity(existingDirectories: [], fileContents: [:]))
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "antigravity-conv-dup")
    }

    func testAntigravityProviderMultipleConversationsSharingSameRepo() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let repoURL = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom")
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-shared-1",
                title: "Task 1",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            ),
            AntigravitySessionRecord(
                conversationId: "conv-shared-2",
                title: "Task 2",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            )
        ])

        let mockFS = MockFileSystemForAntigravity(
            existingDirectories: [repoURL.appendingPathComponent(".git").path],
            fileContents: [
                repoURL.appendingPathComponent(".git/HEAD").path: "ref: refs/heads/main\n"
            ]
        )
        let gitResolver = DefaultGitRepositoryResolver(fileSystem: mockFS)

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector,
            gitResolver: gitResolver
        )

        let sessions = try await provider.discoverSessions()
        // Genuinely separate active conversations sharing a repo should BOTH be preserved
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].id, "antigravity-conv-shared-1")
        XCTAssertEqual(sessions[1].id, "antigravity-conv-shared-2")
    }

    func testAntigravityProviderAllIdleReturnsEmpty() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-idle",
                title: "Idle task",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_IDLE",
                notFullyIdle: false,
                killed: false
            )
        ])

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testAntigravityProviderKilledRecordIsIgnored() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-killed",
                title: "Killed task",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: true
            )
        ])

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testAntigravityProviderStoreErrorHandledGracefully() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let storeInspector = MockAntigravityStoreInspector(records: [], shouldThrow: true)

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector
        )

        do {
            _ = try await provider.discoverSessions()
            XCTFail("Should propagate store inspection error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Failed to read database"))
        }
    }

    // MARK: 4. Native SQLite Database Inspector Integration Test

    func testDefaultAntigravityStoreInspectorRealSQLite() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let dbURL = tempDir.appendingPathComponent("conversation_summaries.db")

        // Create and populate SQLite database
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)

        let schema = """
        CREATE TABLE conversation_summaries (
            conversation_id text PRIMARY KEY,
            title text NOT NULL DEFAULT "",
            workspace_uris text NOT NULL,
            status text NOT NULL DEFAULT "",
            not_fully_idle numeric NOT NULL DEFAULT false,
            killed numeric NOT NULL DEFAULT false,
            last_user_input_time datetime NOT NULL,
            last_modified_time datetime NOT NULL
        );
        """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)

        let insert = """
        INSERT INTO conversation_summaries VALUES
        ('conv-active', 'Running task', '["file:///Users/deepak/ProjectA"]', 'CASCADE_RUN_STATUS_RUNNING', 1, 0, '2026-10-03 12:00:00.000000+00:00', '2026-10-03 12:10:00.000000+00:00'),
        ('conv-idle', 'Idle task', '["file:///Users/deepak/ProjectB"]', 'CASCADE_RUN_STATUS_IDLE', 0, 0, '2026-10-03 11:00:00.000000+00:00', '2026-10-03 11:10:00.000000+00:00'),
        ('conv-killed', 'Killed task', '["file:///Users/deepak/ProjectC"]', 'CASCADE_RUN_STATUS_RUNNING', 1, 1, '2026-10-03 10:00:00.000000+00:00', '2026-10-03 10:10:00.000000+00:00');
        """
        XCTAssertEqual(sqlite3_exec(db, insert, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        // Read using DefaultAntigravityStoreInspector
        let inspector = DefaultAntigravityStoreInspector(databaseURL: dbURL)
        let records = try await inspector.fetchActiveSessions()

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].conversationId, "conv-active")
        XCTAssertEqual(records[0].title, "Running task")
        XCTAssertEqual(records[0].status, "CASCADE_RUN_STATUS_RUNNING")
        XCTAssertTrue(records[0].notFullyIdle)
        XCTAssertFalse(records[0].killed)
    }

    func testDefaultAntigravityStoreInspectorMissingFileReturnsEmpty() async throws {
        let nonExistentURL = URL(fileURLWithPath: "/non/existent/path/db.sqlite")
        let inspector = DefaultAntigravityStoreInspector(databaseURL: nonExistentURL)
        let records = try await inspector.fetchActiveSessions()
        XCTAssertTrue(records.isEmpty)
    }

    func testRealAntigravityDiscoverySmokeTest() async throws {
        let provider = AntigravityProvider()
        let availability = await provider.availability()
        XCTAssertEqual(availability, .available)

        let sessions = try await provider.discoverSessions()
        for session in sessions {
            XCTAssertEqual(session.provider, ProviderID.antigravity)
            XCTAssertTrue(session.state == .working || session.state == .idle || session.state == .unknown)
            XCTAssertNotNil(session.projectName)
            XCTAssertNil(session.startedAt, "Discovered Antigravity sessions must have startedAt nil")
        }
    }

    // MARK: 5. Truthful State Mapping & Nil Timestamp Tests

    func testAntigravityStateMappingTruthfulRules() {
        // Explicit RUNNING -> .working
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_RUNNING", notFullyIdle: false), .working)
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_RUNNING", notFullyIdle: true), .working)

        // Explicit IDLE -> .idle
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_IDLE", notFullyIdle: false), .idle)
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_IDLE", notFullyIdle: true), .idle)

        // Ambiguous combinations / unknown states -> .unknown
        // not_fully_idle alone is ambiguous and must NOT imply Working
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_UNKNOWN", notFullyIdle: true), .unknown)
        XCTAssertEqual(AntigravityParser.mapState(status: "", notFullyIdle: true), .unknown)
        XCTAssertEqual(AntigravityParser.mapState(status: "WAITING", notFullyIdle: true), .unknown)
        XCTAssertEqual(AntigravityParser.mapState(status: "OTHER", notFullyIdle: false), .unknown)
    }

    func testAntigravityTimestampsNeverManufactured() async throws {
        let processDiscoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-timestamps",
                title: "Timestamp Test",
                workspaceURIsJSON: "[\"file:///Users/deepak/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_IDLE",
                notFullyIdle: true,
                killed: false,
                lastUserInputTime: "2026-10-03 12:00:00.000000+00:00",
                lastModifiedTime: "" // missing modified time
            )
        ])

        let provider = AntigravityProvider(
            processDiscoverer: processDiscoverer,
            storeInspector: storeInspector,
            gitResolver: DefaultGitRepositoryResolver(fileSystem: MockFileSystemForAntigravity(existingDirectories: [], fileContents: [:]))
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertNil(session.startedAt, "startedAt must be nil without true start field")
        XCTAssertNil(session.lastActivityAt, "lastActivityAt must be nil when lastModifiedTime is empty (no Date() fallback)")
        XCTAssertEqual(session.state, .idle)
    }

    func testDefaultAntigravityStoreInspectorPropagatesErrorsOnCorruptDatabase() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let corruptDBURL = tempDir.appendingPathComponent("corrupt.db")
        try "NOT A VALID SQLITE DATABASE FILE".write(to: corruptDBURL, atomically: true, encoding: .utf8)

        let inspector = DefaultAntigravityStoreInspector(databaseURL: corruptDBURL)
        do {
            _ = try await inspector.fetchActiveSessions()
            XCTFail("Should throw error on corrupt database file")
        } catch {
            // Verify real error is propagated through
            XCTAssertTrue(error is AntigravityStoreError || error.localizedDescription.contains("database") || error.localizedDescription.contains("prepare"))
        }
    }

    func testDefaultAntigravityStoreInspectorWALVisibilityWithHeldOpenWriter() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let dbURL = tempDir.appendingPathComponent("conversation_summaries.db")

        // 1. Open writer connection and configure WAL mode
        var writeDb: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &writeDb), SQLITE_OK)
        defer {
            if let writeDb = writeDb {
                sqlite3_close(writeDb)
            }
        }

        XCTAssertEqual(sqlite3_exec(writeDb, "PRAGMA journal_mode=WAL;", nil, nil, nil), SQLITE_OK)

        let schema = """
        CREATE TABLE conversation_summaries (
            conversation_id text PRIMARY KEY,
            title text NOT NULL DEFAULT "",
            workspace_uris text NOT NULL,
            status text NOT NULL DEFAULT "",
            not_fully_idle numeric NOT NULL DEFAULT false,
            killed numeric NOT NULL DEFAULT false,
            last_user_input_time datetime NOT NULL,
            last_modified_time datetime NOT NULL
        );
        """
        XCTAssertEqual(sqlite3_exec(writeDb, schema, nil, nil, nil), SQLITE_OK)

        // 2. Insert initial committed record into WAL; writer remains held open (uncheckpointed WAL)
        let insert1 = """
        INSERT INTO conversation_summaries VALUES
        ('conv-wal-1', 'Initial WAL task', '["file:///Users/deepak/Desktop/Projects/oss/Loom"]', 'CASCADE_RUN_STATUS_RUNNING', 1, 0, '2026-10-04 10:00:00.000000+00:00', '2026-10-04 10:10:00.000000+00:00');
        """
        XCTAssertEqual(sqlite3_exec(writeDb, insert1, nil, nil, nil), SQLITE_OK)

        // 3. Reader inspects database while writer is still open
        let inspector = DefaultAntigravityStoreInspector(databaseURL: dbURL)
        let firstRefresh = try await inspector.fetchActiveSessions()
        XCTAssertEqual(firstRefresh.count, 1)
        XCTAssertEqual(firstRefresh[0].conversationId, "conv-wal-1")
        XCTAssertEqual(firstRefresh[0].title, "Initial WAL task")
        XCTAssertEqual(firstRefresh[0].status, "CASCADE_RUN_STATUS_RUNNING")

        // 4. Writer modifies record in WAL and inserts a second record, still holding connection open
        let updateAndInsert = """
        UPDATE conversation_summaries SET title = 'Updated WAL task' WHERE conversation_id = 'conv-wal-1';
        INSERT INTO conversation_summaries VALUES
        ('conv-wal-2', 'Second WAL task', '["file:///Users/deepak/Desktop/Projects/oss/Other"]', 'CASCADE_RUN_STATUS_RUNNING', 1, 0, '2026-10-04 10:00:00.000000+00:00', '2026-10-04 10:15:00.000000+00:00');
        """
        XCTAssertEqual(sqlite3_exec(writeDb, updateAndInsert, nil, nil, nil), SQLITE_OK)

        // 5. Subsequent reader refresh must observe latest committed WAL state
        let secondRefresh = try await inspector.fetchActiveSessions()
        XCTAssertEqual(secondRefresh.count, 2)
        let wal1 = secondRefresh.first(where: { $0.conversationId == "conv-wal-1" })
        let wal2 = secondRefresh.first(where: { $0.conversationId == "conv-wal-2" })
        XCTAssertEqual(wal1?.title, "Updated WAL task", "Reader must observe updated state from uncheckpointed WAL")
        XCTAssertEqual(wal2?.title, "Second WAL task", "Reader must observe newly committed row in uncheckpointed WAL")
    }

    func testDefaultAntigravityStoreInspectorPropagatesPrepareAndStepErrors() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 1. Prepare failure test: valid SQLite database but missing conversation_summaries table
        let missingTableDBURL = tempDir.appendingPathComponent("wrong_schema.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(missingTableDBURL.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE unrelated_table (id INT);", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let inspector = DefaultAntigravityStoreInspector(databaseURL: missingTableDBURL)
        do {
            _ = try await inspector.fetchActiveSessions()
            XCTFail("Should throw queryPrepareFailed when table is missing")
        } catch let AntigravityStoreError.queryPrepareFailed(code, message) {
            XCTAssertEqual(code, 1) // SQLITE_ERROR
            XCTAssertTrue(message.contains("no such table: conversation_summaries"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        // 2. Error descriptions & Step failure enum check
        let openErr = AntigravityStoreError.databaseOpenFailed(code: 14, message: "cannot open")
        XCTAssertEqual(openErr.errorDescription, "Failed to open Antigravity database (code: 14): cannot open")

        let prepErr = AntigravityStoreError.queryPrepareFailed(code: 1, message: "syntax error")
        XCTAssertEqual(prepErr.errorDescription, "Failed to prepare query on Antigravity database (code: 1): syntax error")

        let stepErr = AntigravityStoreError.queryStepFailed(code: 11, message: "database disk image is malformed")
        XCTAssertEqual(stepErr.errorDescription, "Failed to execute query step on Antigravity database (code: 11): database disk image is malformed")
        XCTAssertEqual(stepErr, AntigravityStoreError.queryStepFailed(code: 11, message: "database disk image is malformed"))
    }
}
