//
//  AntigravityProviderTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

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
        XCTAssertTrue(AntigravityParser.isAntigravityProcessCommand("/Users/developer/.gemini/bin/agy --hub --hub-port=52663 --app_data_dir=antigravity"))
        XCTAssertTrue(AntigravityParser.isAntigravityProcessCommand("agy --conversation 0b3caa3f-bf06-4f59-a41b-9c7aa8c4aa9a"))

        // False positives
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("grep -i antigravity"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("/Users/developer/Desktop/Projects/oss/Loom/.build/debug/Loom"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("swiftc Loom/Providers/Antigravity/AntigravityProvider.swift"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("xcodebuild -scheme Loom"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("/Users/developer/Library/Developer/Xcode/DerivedData/Loom/Build/Products/Debug/Loom"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("vim antigravity.txt"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("cat /path/to/agy/file"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("vim /tmp/agy"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("git diff containing /agy paths"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("git diff /agy/feature"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("python script.py --arg /agy"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("python -c \"import antigravity\""))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("node runner.js /agy"))
        XCTAssertFalse(AntigravityParser.isAntigravityProcessCommand("echo \"agy is great\""))
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
        let singleJSON = "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]"
        let singleURLs = AntigravityParser.parseWorkspaceURLs(from: singleJSON)
        XCTAssertEqual(singleURLs.count, 1)
        XCTAssertEqual(singleURLs.first?.path, "/Users/developer/Desktop/Projects/oss/Loom")

        // Percent-encoded URI with spaces and special characters
        let encodedJSON = "[\"file:///Users/developer/Projects/My%20App/Special%20Folder\"]"
        let encodedURLs = AntigravityParser.parseWorkspaceURLs(from: encodedJSON)
        XCTAssertEqual(encodedURLs.count, 1)
        XCTAssertEqual(encodedURLs.first?.path, "/Users/developer/Projects/My App/Special Folder")

        // Multiple workspace URIs
        let multipleJSON = "[\"file:///Users/developer/RepoA\", \"file:///Users/developer/RepoB\"]"
        let multipleURLs = AntigravityParser.parseWorkspaceURLs(from: multipleJSON)
        XCTAssertEqual(multipleURLs.count, 2)
        XCTAssertEqual(multipleURLs[0].path, "/Users/developer/RepoA")
        XCTAssertEqual(multipleURLs[1].path, "/Users/developer/RepoB")

        // Raw path without file:// scheme
        let rawJSON = "[\"/Users/developer/Projects/oss/RawRepo\"]"
        let rawURLs = AntigravityParser.parseWorkspaceURLs(from: rawJSON)
        XCTAssertEqual(rawURLs.count, 1)
        XCTAssertEqual(rawURLs.first?.path, "/Users/developer/Projects/oss/RawRepo")

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
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
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
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let recentModifiedTime = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-abc",
                title: "Refactor session discovery",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false,
                lastUserInputTime: "2026-10-03 12:20:00.000000+00:00",
                lastModifiedTime: recentModifiedTime
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
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-detached",
                title: "Detached testing",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
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
        let workspaceURL = URL(fileURLWithPath: "/Users/developer/Desktop/Notes")
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-notes",
                title: "Note taking",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Notes\"]",
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
        let repoA = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/RepoA")
        let repoB = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/RepoB")

        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-1",
                title: "Task in RepoA",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/RepoA\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            ),
            AntigravitySessionRecord(
                conversationId: "conv-2",
                title: "Task in RepoB",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/RepoB\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            ),
            AntigravitySessionRecord(
                conversationId: "conv-3",
                title: "Idle task",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/RepoA\"]",
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
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            ),
            AntigravitySessionRecord(
                conversationId: "conv-dup",
                title: "Duplicate row 2",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
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
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-shared-1",
                title: "Task 1",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false
            ),
            AntigravitySessionRecord(
                conversationId: "conv-shared-2",
                title: "Task 2",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
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
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
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
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
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

        // Store failure must degrade gracefully without throwing, producing a usable session with diagnostics
        let sessions = try await provider.discoverSessions()
        XCTAssertFalse(sessions.isEmpty)
        XCTAssertEqual(sessions[0].diagnostics?.metadataStatus, .unavailable)
        XCTAssertNotNil(sessions[0].diagnostics?.metadataError)
        XCTAssertTrue(sessions[0].diagnostics?.metadataError?.contains("Failed to read database") == true)
    }

    func testAntigravityGracefulDegradationWithRunningProcess() async throws {
        struct MockDiscovererWithProcesses: AntigravityProcessDiscovering {
            let isRunning: Bool
            let processes: [AgentProcess]
            func isAntigravityRunning() async -> Bool { isRunning }
            func discoverProcesses() async -> [AgentProcess] { processes }
        }

        let process = AgentProcess(
            pid: 8888,
            executable: "/opt/homebrew/bin/agy",
            commandLine: "/opt/homebrew/bin/agy --working-dir=/Users/developer/Desktop/Projects/oss/Loom",
            provider: .antigravity
        )
        let worker = AgentProcess(
            pid: 8889,
            parentPID: 8888,
            executable: "/bin/sh",
            commandLine: "sh -c cargo build",
            provider: .antigravity
        )
        let discoverer = MockDiscovererWithProcesses(isRunning: true, processes: [process, worker])
        let failingStore = MockAntigravityStoreInspector(records: [], shouldThrow: true)
        let provider = AntigravityProvider(processDiscoverer: discoverer, storeInspector: failingStore)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "antigravity-8888")
        XCTAssertEqual(sessions[0].projectName, "Loom")
        XCTAssertEqual(sessions[0].state, .working)
        XCTAssertEqual(sessions[0].diagnostics?.metadataStatus, .unavailable)
        XCTAssertNotNil(sessions[0].diagnostics?.metadataError)

        let availability = await provider.availability()
        switch availability {
        case .degraded:
            break
        default:
            XCTFail("Provider availability should be degraded when SQLite store throws")
        }
    }

    func testAntigravityDegradedModePreservesMultipleDistinctSessions() async throws {
        struct MockDiscovererWithProcesses: AntigravityProcessDiscovering {
            let isRunning: Bool
            let processes: [AgentProcess]
            func isAntigravityRunning() async -> Bool { isRunning }
            func discoverProcesses() async -> [AgentProcess] { processes }
        }

        let root1 = AgentProcess(
            pid: 1001,
            executable: "/opt/homebrew/bin/agy",
            commandLine: "/opt/homebrew/bin/agy --working-dir=/Users/developer/Desktop/Projects/oss/Loom",
            workingDirectory: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom"),
            startedAt: Date().addingTimeInterval(-600),
            provider: .antigravity,
            hostApp: .terminal
        )
        let worker1 = AgentProcess(
            pid: 1002,
            parentPID: 1001,
            executable: "/bin/sh",
            commandLine: "sh -c swift test",
            startedAt: Date().addingTimeInterval(-30),
            provider: .antigravity
        )

        let root2 = AgentProcess(
            pid: 2001,
            executable: "/opt/homebrew/bin/agy",
            commandLine: "/opt/homebrew/bin/agy --working-dir=/Users/developer/Desktop/Projects/indie/SmartRemote",
            workingDirectory: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/indie/SmartRemote"),
            startedAt: Date().addingTimeInterval(-300),
            provider: .antigravity,
            hostApp: .cursor
        )

        let discoverer = MockDiscovererWithProcesses(isRunning: true, processes: [root1, worker1, root2])
        let failingStore = MockAntigravityStoreInspector(records: [], shouldThrow: true)
        let provider = AntigravityProvider(processDiscoverer: discoverer, storeInspector: failingStore)

        let sessions = try await provider.discoverSessions()
        // Must preserve BOTH distinct sessions rather than collapsing to runningProcesses.first
        XCTAssertEqual(sessions.count, 2)

        let session1 = sessions.first { $0.id == "antigravity-1001" }
        XCTAssertNotNil(session1)
        XCTAssertEqual(session1?.projectName, "Loom")
        XCTAssertEqual(session1?.state, .working, "Session with active worker child should be .working")
        XCTAssertEqual(session1?.associatedProcesses.count, 2)
        XCTAssertEqual(session1?.hostApp, .terminal)
        XCTAssertEqual(session1?.diagnostics?.metadataStatus, .unavailable)

        let session2 = sessions.first { $0.id == "antigravity-2001" }
        XCTAssertNotNil(session2)
        XCTAssertEqual(session2?.projectName, "SmartRemote")
        XCTAssertEqual(session2?.state, .waiting, "Interactive CLI without workers should be .waiting")
        XCTAssertEqual(session2?.associatedProcesses.count, 1)
        XCTAssertEqual(session2?.hostApp, .cursor)
        XCTAssertEqual(session2?.diagnostics?.metadataStatus, .unavailable)

        let availability = await provider.availability()
        switch availability {
        case .degraded(let reason):
            XCTAssertTrue(reason.contains("unavailable") || reason.contains("Failed to read database"))
        default:
            XCTFail("Provider availability should be .degraded when metadata is unavailable, got: \(availability)")
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
        ('conv-active', 'Running task', '["file:///Users/developer/ProjectA"]', 'CASCADE_RUN_STATUS_RUNNING', 1, 0, '2026-10-03 12:00:00.000000+00:00', '2026-10-03 12:10:00.000000+00:00'),
        ('conv-idle', 'Idle task', '["file:///Users/developer/ProjectB"]', 'CASCADE_RUN_STATUS_IDLE', 0, 0, '2026-10-03 11:00:00.000000+00:00', '2026-10-03 11:10:00.000000+00:00'),
        ('conv-killed', 'Killed task', '["file:///Users/developer/ProjectC"]', 'CASCADE_RUN_STATUS_RUNNING', 1, 1, '2026-10-03 10:00:00.000000+00:00', '2026-10-03 10:10:00.000000+00:00');
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
            XCTAssertTrue(session.state == .working || session.state == .waiting || session.state == .idle || session.state == .finished || session.state == .unknown)
            XCTAssertNotNil(session.projectName)
            XCTAssertNil(session.startedAt, "Discovered Antigravity sessions must have startedAt nil")
        }
    }

    // MARK: 5. Truthful State Mapping & Nil Timestamp Tests

    func testAntigravityStateMappingTruthfulRules() {
        // Explicit RUNNING -> .working
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_RUNNING", notFullyIdle: false), .working)
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_RUNNING", notFullyIdle: true), .working)

        // Explicit IDLE:
        // When notFullyIdle is true, it is waiting for user prompt/turn (.waiting)
        // When notFullyIdle is false, it is fully idle (.idle)
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_IDLE", notFullyIdle: false), .idle)
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_IDLE", notFullyIdle: true), .waiting)

        // Explicit WAITING -> .waiting
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_WAITING", notFullyIdle: false), .waiting)
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_USER_INPUT_REQUIRED", notFullyIdle: false), .waiting)

        // Explicit FAILED -> .failed
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_ERROR", notFullyIdle: false), .failed)
        XCTAssertEqual(AntigravityParser.mapState(status: "CASCADE_RUN_STATUS_FAILED", notFullyIdle: false), .failed)

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
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
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
        XCTAssertEqual(session.state, .waiting)
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
        ('conv-wal-1', 'Initial WAL task', '["file:///Users/developer/Desktop/Projects/oss/Loom"]', 'CASCADE_RUN_STATUS_RUNNING', 1, 0, '2026-10-04 10:00:00.000000+00:00', '2026-10-04 10:10:00.000000+00:00');
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
        ('conv-wal-2', 'Second WAL task', '["file:///Users/developer/Desktop/Projects/oss/Other"]', 'CASCADE_RUN_STATUS_RUNNING', 1, 0, '2026-10-04 10:00:00.000000+00:00', '2026-10-04 10:15:00.000000+00:00');
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

    // MARK: 6. State Evidence, Transcript Parsing & Reconciler Regression Tests

    func testAntigravityStateEvidenceTruthfulOutputs() {
        XCTAssertEqual(
            AntigravityParser.stateEvidence(status: "CASCADE_RUN_STATUS_RUNNING", notFullyIdle: false),
            "State: Working (cascade run active)"
        )
        XCTAssertEqual(
            AntigravityParser.stateEvidence(status: "CASCADE_RUN_STATUS_IDLE", notFullyIdle: true),
            "State: Waiting (cascade run idle, not_fully_idle=true; awaiting user turn)"
        )
        XCTAssertEqual(
            AntigravityParser.stateEvidence(status: "CASCADE_RUN_STATUS_IDLE", notFullyIdle: false),
            "State: Idle (cascade run idle)"
        )
        XCTAssertEqual(
            AntigravityParser.stateEvidence(status: "CASCADE_RUN_STATUS_WAITING", notFullyIdle: false),
            "State: Waiting (user input required)"
        )
        XCTAssertEqual(
            AntigravityParser.stateEvidence(status: "CASCADE_RUN_STATUS_USER_INPUT_REQUIRED", notFullyIdle: false),
            "State: Waiting (user input required)"
        )
        XCTAssertEqual(
            AntigravityParser.stateEvidence(status: "CASCADE_RUN_STATUS_ERROR", notFullyIdle: false),
            "State: Failed (cascade run error)"
        )
        XCTAssertEqual(
            AntigravityParser.stateEvidence(status: "CASCADE_RUN_STATUS_FAILED", notFullyIdle: false),
            "State: Failed (cascade run error)"
        )
        XCTAssertEqual(
            AntigravityParser.stateEvidence(status: "CASCADE_RUN_STATUS_UNKNOWN", notFullyIdle: false),
            "State: Unknown (status: CASCADE_RUN_STATUS_UNKNOWN)"
        )
    }

    func testAntigravityTranscriptTailParserToolAction() {
        let transcript = """
        {"step_index":1,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"Fix the build"}
        {"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","tool_calls":[{"name":"view_file","args":{"AbsolutePath":"/tmp/test.swift","toolAction":"Viewing file","toolSummary":"View test.swift"}}]}
        """
        let parsed = AntigravityParser.parseTranscriptTail(from: transcript)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.action, "Viewing file")
        XCTAssertEqual(parsed?.toolName, "view_file")
        XCTAssertEqual(parsed?.type, "PLANNER_RESPONSE")
    }

    func testAntigravityTranscriptTailParserPlannerResponseWithoutTools() {
        let transcript = """
        {"step_index":1,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"Fix the build"}
        {"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","content":"I have completed the task."}
        """
        let parsed = AntigravityParser.parseTranscriptTail(from: transcript)
        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.action)
        XCTAssertNil(parsed?.toolName)
        XCTAssertEqual(parsed?.type, "PLANNER_RESPONSE")
    }

    func testAntigravityTranscriptTailParserEmptyOrMalformed() {
        XCTAssertNil(AntigravityParser.parseTranscriptTail(from: ""))
        XCTAssertNil(AntigravityParser.parseTranscriptTail(from: "not a json line\nanother non json"))
    }

    func testAntigravityActivitySummaryWithTranscript() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let transcriptURL = tempDir.appendingPathComponent("transcript.jsonl")
        let transcriptJSONL = """
        {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","tool_calls":[{"name":"run_command","args":{"toolAction":"Running test suite","toolSummary":"Run tests"}}]}
        """
        try transcriptJSONL.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let result = AntigravityParser.activitySummary(
            conversationId: "conv-1",
            status: "CASCADE_RUN_STATUS_RUNNING",
            title: "Task A",
            transcriptDirectory: tempDir
        )

        XCTAssertEqual(result.summary, "Running test suite · Task A")
        XCTAssertTrue(result.evidence.contains("Activity from transcript toolAction: 'Running test suite'"))
    }

    func testAntigravityActivitySummaryFallbackToTitle() {
        let result = AntigravityParser.activitySummary(
            conversationId: "conv-nonexistent",
            status: "CASCADE_RUN_STATUS_RUNNING",
            title: "Fallback Task",
            transcriptDirectory: URL(fileURLWithPath: "/nonexistent/dir")
        )

        XCTAssertEqual(result.summary, "Fallback Task")
        XCTAssertTrue(result.evidence.contains("Activity from conversation title"))
    }

    func testAntigravityLifecycleReconcilerTransitionsDepartedSessionToFinished() async throws {
        let discoverer = MockAntigravityProcessDiscoverer(isRunning: true)
        let recentModifiedTime = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30))
        let storeInspector = MockAntigravityStoreInspector(records: [
            AntigravitySessionRecord(
                conversationId: "conv-lifecycle",
                title: "Active Lifecycle Task",
                workspaceURIsJSON: "[\"file:///Users/developer/Desktop/Projects/oss/Loom\"]",
                status: "CASCADE_RUN_STATUS_RUNNING",
                notFullyIdle: true,
                killed: false,
                lastUserInputTime: "2026-10-03 12:00:00.000000+00:00",
                lastModifiedTime: recentModifiedTime
            )
        ])
        let provider = AntigravityProvider(processDiscoverer: discoverer, storeInspector: storeInspector)

        // 1. Initial discovery finds the active session
        let initialSessions = try await provider.discoverSessions()
        XCTAssertEqual(initialSessions.count, 1)
        XCTAssertEqual(initialSessions[0].state, .working)

        // 2. Antigravity daemon terminates: process discoverer reports not running
        discoverer.isRunning = false
        let reconciledSessions = try await provider.discoverSessions()

        // 3. The departed active session MUST transition to .finished and be retained
        XCTAssertEqual(reconciledSessions.count, 1)
        let finishedSession = reconciledSessions[0]
        XCTAssertEqual(finishedSession.id, "antigravity-conv-lifecycle")
        XCTAssertEqual(finishedSession.state, .finished)
        XCTAssertTrue(finishedSession.summary?.contains("Session finished") == true)
        XCTAssertTrue(finishedSession.discoveryEvidence.contains { $0.contains("Antigravity process terminated") })
    }
}
