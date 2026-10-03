import XCTest
@testable import LoomCore

final class CodexProviderTests: XCTestCase {

    // MARK: - Parser Tests

    func testCodexParserPsOutputEmpty() {
        let output = ""
        let results = CodexParser.parsePsOutput(output)
        XCTAssertTrue(results.isEmpty)
    }

    func testCodexParserPsOutputIgnoresNonCodex() {
        let output = """
          101 Sat Oct  3 10:00:00 2026 /usr/bin/login -pf deepak
          102 Sat Oct  3 10:00:05 2026 /bin/zsh
          103 Sat Oct  3 10:00:10 2026 grep codex
          104 Sat Oct  3 10:00:15 2026 /Applications/Loom.app/Contents/MacOS/Loom
        """
        let results = CodexParser.parsePsOutput(output)
        XCTAssertTrue(results.isEmpty)
    }

    func testCodexParserPsOutputDirectBinary() {
        let output = """
        54321 Sat Oct  3 10:15:30 2026 /opt/homebrew/bin/codex resume --session 123
        """
        let results = CodexParser.parsePsOutput(output)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].pid, 54321)
        XCTAssertTrue(results[0].command.contains("/opt/homebrew/bin/codex resume"))
        XCTAssertNotNil(results[0].startedAt)
    }

    func testCodexParserPsOutputNodeWrapper() {
        let output = """
        65432 Sat Oct  3 11:20:00 2026 /usr/local/bin/node /usr/local/lib/node_modules/@openai/codex/bin/codex.js
        """
        let results = CodexParser.parsePsOutput(output)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].pid, 65432)
        XCTAssertTrue(results[0].command.contains("codex.js"))
    }

    func testCodexParserLsofCwd() {
        let lsofOutput = """
        p54321
        fcwd
        n/Users/deepak/Desktop/Projects/oss/Loom
        """
        let url = CodexParser.parseLsofCwdOutput(lsofOutput)
        XCTAssertEqual(url?.path, "/Users/deepak/Desktop/Projects/oss/Loom")
    }

    func testCodexParserLsofCwdEmpty() {
        let lsofOutput = "p54321\ntcwd\n"
        let url = CodexParser.parseLsofCwdOutput(lsofOutput)
        XCTAssertNil(url)
    }

    // MARK: - Git Parser Tests

    func testGitHEADParserBranchRef() {
        let headContent = "ref: refs/heads/main\n"
        XCTAssertEqual(GitHEADParser.parseBranch(headContent: headContent), "main")

        let featureHead = "ref: refs/heads/feature/loom-v0\n"
        XCTAssertEqual(GitHEADParser.parseBranch(headContent: featureHead), "feature/loom-v0")
    }

    func testGitHEADParserDetachedHead() {
        let headContent = "3869efb5020d70ee9eb2a4305816e682b6ec6040\n"
        XCTAssertEqual(GitHEADParser.parseBranch(headContent: headContent), "3869efb")
    }

    func testGitHEADParserEmpty() {
        XCTAssertNil(GitHEADParser.parseBranch(headContent: ""))
        XCTAssertNil(GitHEADParser.parseBranch(headContent: "   \n"))
    }

    func testGitHEADParserWorktreeGitDir() {
        let gitFileContent = "gitdir: /Users/deepak/Desktop/Projects/oss/Loom/.git/worktrees/feat1\n"
        let base = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom-feat1")
        let resolved = GitHEADParser.parseWorktreeGitDir(gitFileContent: gitFileContent, relativeTo: base)
        XCTAssertEqual(resolved?.path, "/Users/deepak/Desktop/Projects/oss/Loom/.git/worktrees/feat1")
    }

    // MARK: - Git Repository Resolver Tests

    private final class MockFileSystem: FileSystemInspecting, Sendable {
        let files: [String: String]
        let directories: Set<String>

        init(files: [String: String], directories: Set<String>) {
            self.files = files
            self.directories = directories
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

    func testGitRepositoryResolverStandardGitRepo() async {
        let repoRoot = "/Users/deepak/Desktop/Projects/oss/Loom"
        let subDir = "/Users/deepak/Desktop/Projects/oss/Loom/Sources/LoomCore"

        let mockFS = MockFileSystem(
            files: [
                "\(repoRoot)/.git/HEAD": "ref: refs/heads/main\n"
            ],
            directories: [
                repoRoot,
                "\(repoRoot)/.git",
                subDir
            ]
        )

        let resolver = DefaultGitRepositoryResolver(fileSystem: mockFS)
        let info = await resolver.resolveRepository(for: URL(fileURLWithPath: subDir))

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.rootURL.path, repoRoot)
        XCTAssertEqual(info?.projectName, "Loom")
        XCTAssertEqual(info?.branch, "main")
    }

    func testGitRepositoryResolverNonGitDirectory() async {
        let mockFS = MockFileSystem(files: [:], directories: ["/Users/deepak/Desktop/Notes"])
        let resolver = DefaultGitRepositoryResolver(fileSystem: mockFS)
        let info = await resolver.resolveRepository(for: URL(fileURLWithPath: "/Users/deepak/Desktop/Notes"))

        XCTAssertNil(info)
    }

    // MARK: - CodexProvider Integration Tests

    private struct MockCodexProcessDiscoverer: CodexProcessDiscovering, Sendable {
        let processes: [CodexProcessInfo]
        let errorToThrow: (any Error)?

        init(processes: [CodexProcessInfo] = [], errorToThrow: (any Error)? = nil) {
            self.processes = processes
            self.errorToThrow = errorToThrow
        }

        func findRunningProcesses() async throws -> [CodexProcessInfo] {
            if let errorToThrow {
                throw errorToThrow
            }
            return processes
        }
    }

    private struct MockGitResolver: GitRepositoryResolving, Sendable {
        let repoMap: [URL: GitRepositoryInfo]

        init(repoMap: [URL: GitRepositoryInfo] = [:]) {
            self.repoMap = repoMap
        }

        func resolveRepository(for directoryURL: URL) async -> GitRepositoryInfo? {
            repoMap[directoryURL]
        }
    }

    func testCodexProviderNoProcesses() async throws {
        let discoverer = MockCodexProcessDiscoverer(processes: [])
        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: MockGitResolver())

        let avail = await provider.availability()
        XCTAssertTrue(avail.isAvailable)

        let sessions = try await provider.discoverSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testCodexProviderSingleSessionInGitRepo() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom")
        let process = CodexProcessInfo(
            pid: 1234,
            command: "/opt/homebrew/bin/codex",
            workingDirectory: repoURL,
            startedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let gitInfo = GitRepositoryInfo(
            rootURL: repoURL,
            projectName: "Loom",
            branch: "main"
        )

        let discoverer = MockCodexProcessDiscoverer(processes: [process])
        let gitResolver = MockGitResolver(repoMap: [repoURL: gitInfo])
        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: gitResolver)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.id, "codex-1234")
        XCTAssertEqual(session.provider, .codex)
        XCTAssertEqual(session.projectName, "Loom")
        XCTAssertEqual(session.projectPath, repoURL)
        XCTAssertEqual(session.branch, "main")
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.startedAt, Date(timeIntervalSince1970: 1700000000))
    }

    func testCodexProviderMultipleSessionsInDifferentRepos() async throws {
        let repo1 = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom")
        let repo2 = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/XKit")

        let process1 = CodexProcessInfo(
            pid: 1001,
            command: "codex",
            workingDirectory: repo1,
            startedAt: Date(timeIntervalSince1970: 1700000000)
        )
        let process2 = CodexProcessInfo(
            pid: 1002,
            command: "codex",
            workingDirectory: repo2,
            startedAt: Date(timeIntervalSince1970: 1700001000)
        )

        let gitInfo1 = GitRepositoryInfo(rootURL: repo1, projectName: "Loom", branch: "main")
        let gitInfo2 = GitRepositoryInfo(rootURL: repo2, projectName: "XKit", branch: "develop")

        let discoverer = MockCodexProcessDiscoverer(processes: [process1, process2])
        let gitResolver = MockGitResolver(repoMap: [repo1: gitInfo1, repo2: gitInfo2])
        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: gitResolver)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 2)

        XCTAssertEqual(sessions[0].projectName, "Loom")
        XCTAssertEqual(sessions[0].branch, "main")

        XCTAssertEqual(sessions[1].projectName, "XKit")
        XCTAssertEqual(sessions[1].branch, "develop")
    }

    func testCodexProviderSessionInNonGitDir() async throws {
        let nonGitURL = URL(fileURLWithPath: "/Users/deepak/Desktop/ScratchPad")
        let process = CodexProcessInfo(
            pid: 2001,
            command: "codex",
            workingDirectory: nonGitURL
        )

        let discoverer = MockCodexProcessDiscoverer(processes: [process])
        let gitResolver = MockGitResolver(repoMap: [:]) // resolves to nil
        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: gitResolver)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.projectName, "ScratchPad")
        XCTAssertEqual(session.projectPath, nonGitURL)
        XCTAssertNil(session.branch)
        XCTAssertEqual(session.state, .working)
    }

    func testCodexProviderSessionWithNilCwd() async throws {
        let process = CodexProcessInfo(
            pid: 3001,
            command: "codex",
            workingDirectory: nil
        )

        let discoverer = MockCodexProcessDiscoverer(processes: [process])
        let gitResolver = MockGitResolver(repoMap: [:])
        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: gitResolver)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.projectName, "Codex Session")
        XCTAssertNil(session.projectPath)
        XCTAssertNil(session.branch)
    }
}
