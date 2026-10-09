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
        XCTAssertEqual(session.state, .unknown)
        XCTAssertEqual(session.startedAt, Date(timeIntervalSince1970: 1700000000))
        XCTAssertNil(session.lastActivityAt)
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
        XCTAssertEqual(session.state, .unknown)
        XCTAssertNil(session.lastActivityAt)
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
        XCTAssertEqual(session.pid, 3001)
        XCTAssertNil(session.summary)
    }

    // MARK: - Helper Rejection and Path Edge Cases

    func testCodexParserRejectsHelperProcesses() {
        let rendererHelper = "/Applications/Codex.app/Contents/Frameworks/Codex Helper (Renderer).app/Contents/MacOS/Codex Helper (Renderer) --type=renderer --user-data-dir=/Users/deepak/Library"
        XCTAssertFalse(CodexParser.isCodexCommand(rendererHelper))

        let chatgptService = "/Applications/ChatGPT.app/Contents/Frameworks/Codex Framework.framework/Versions/154.0/Helpers/Codex (Service).app/Contents/MacOS/Codex (Service) --type=utility"
        XCTAssertFalse(CodexParser.isCodexCommand(chatgptService))

        let gpuHelper = "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper --type=gpu-process"
        XCTAssertFalse(CodexParser.isCodexCommand(gpuHelper))

        let sparkleAutoUpdate = "/Applications/ChatGPT.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate com.openai.codex /Users/deepak deepak"
        XCTAssertFalse(CodexParser.isCodexCommand(sparkleAutoUpdate))

        let computerUse = "/Users/deepak/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService"
        XCTAssertFalse(CodexParser.isCodexCommand(computerUse))

        let modifierMonitor = "/Applications/ChatGPT.app/Contents/Resources/native/bare-modifier-monitor --key DoubleCommand --immediate"
        XCTAssertFalse(CodexParser.isCodexCommand(modifierMonitor))
    }

    func testCodexParserRejectsAppServerInfrastructure() {
        let appServerDaemon = "/Users/deepak/.codex/packages/app-server-daemon/releases/0.160.0-aarch64-apple-darwin/bin/codex app-server --listen unix:// --managed-daemon"
        XCTAssertFalse(CodexParser.isCodexCommand(appServerDaemon))

        let bundledAppServer = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex -c features.code_mode_host=true app-server --analytics-default-enabled"
        XCTAssertFalse(CodexParser.isCodexCommand(bundledAppServer))

        let execServer = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex exec-server --remote https://codex-cloud-environments.chatgpt.com/api"
        XCTAssertFalse(CodexParser.isCodexCommand(execServer))

        let codeModeHost = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex-code-mode-host"
        XCTAssertFalse(CodexParser.isCodexCommand(codeModeHost))
    }

    func testCodexParserKeepsInfrastructureNamesInUserPrompts() {
        let commands = [
            "codex exec Explain app-server",
            "codex exec Explain --managed-daemon",
            "codex exec Explain codex-code-mode-host and --code-mode-host",
            "codex resume --last Explain exec-server",
            "codex \"Explain app-server and --managed-daemon\"",
            "codex -- Explain --code-mode-host",
            "codex -C /tmp/app-server exec Explain --managed-daemon",
            "codex -c note=codex-code-mode-host exec Explain app-server"
        ]
        for command in commands {
            XCTAssertTrue(CodexParser.isCodexCommand(command), command)
        }
    }

    func testCodexParserStillRejectsInfrastructureAfterGlobalOptions() {
        let commands = [
            "codex app-server",
            "codex exec-server --remote http://localhost",
            "codex --managed-daemon",
            "codex --code-mode-host",
            "codex -c features.code_mode_host=true app-server",
            "codex --config 'note=two words' --model test exec-server",
            "codex -C /tmp/project --managed-daemon app-server"
        ]
        for command in commands {
            XCTAssertFalse(CodexParser.isCodexCommand(command), command)
        }
    }

    func testCodexParserDistinguishesHelperFlagsFromPromptText() {
        for flag in ["--type=renderer", "--type=utility", "--type=gpu-process",
                     "--type=crashpad-handler", "--type=zygote"] {
            XCTAssertFalse(CodexParser.isCodexCommand("codex \(flag)"), flag)
            XCTAssertFalse(CodexParser.isCodexCommand("codex -c mode=test \(flag)"), flag)
            XCTAssertTrue(CodexParser.isCodexCommand("codex exec Explain \(flag)"), flag)
            XCTAssertTrue(CodexParser.isCodexCommand("codex \"\(flag)\""), flag)
            XCTAssertTrue(CodexParser.isCodexCommand("codex --prompt \"\(flag)\""), flag)
            XCTAssertTrue(CodexParser.isCodexCommand("codex -- Explain \(flag)"), flag)
        }
    }

    func testCodexParserMatchesPathsWithSpaces() {
        let directWithSpaces = "/Applications/Codex Tools/bin/codex resume --session 123"
        XCTAssertTrue(CodexParser.isCodexCommand(directWithSpaces))

        let quotedWithSpaces = "\"/Applications/Codex Tools/bin/codex\" resume"
        XCTAssertTrue(CodexParser.isCodexCommand(quotedWithSpaces))

        let cliWithSpaces = "/Users/deepak/My Developer Tools/codex-cli exec \"echo hi\""
        XCTAssertTrue(CodexParser.isCodexCommand(cliWithSpaces))

        let nodeScriptWithSpaces = "/usr/local/bin/node \"/Users/deepak/My Tools/codex.js\""
        XCTAssertTrue(CodexParser.isCodexCommand(nodeScriptWithSpaces))

        let nodeUnquotedWithSpaces = "/opt/homebrew/bin/node /Users/deepak/My Tools/node_modules/@openai/codex/bin/codex.js"
        XCTAssertTrue(CodexParser.isCodexCommand(nodeUnquotedWithSpaces))
    }

    func testCodexParserWorkspaceExtraction() {
        let cmdWorkingDir = "codex sandbox -c shell=none --working-dir /Users/deepak/Desktop/Projects/oss/Loom"
        let url1 = CodexParser.extractWorkspaceDirectory(from: cmdWorkingDir)
        XCTAssertEqual(url1?.path, "/Users/deepak/Desktop/Projects/oss/Loom")

        let cmdQuoted = "codex -C \"/Users/deepak/My Projects/Loom\""
        let url2 = CodexParser.extractWorkspaceDirectory(from: cmdQuoted)
        XCTAssertEqual(url2?.path, "/Users/deepak/My Projects/Loom")

        let cmdRoot = "codex --working-dir /"
        let url3 = CodexParser.extractWorkspaceDirectory(from: cmdRoot)
        XCTAssertNil(url3, "Root path '/' must not be treated as a valid project workspace")

        let cmdNone = "codex resume --session 123"
        let url4 = CodexParser.extractWorkspaceDirectory(from: cmdNone)
        XCTAssertNil(url4)
    }

    func testCodexProviderPopulatesPIDAndPreventsRootCwd() async throws {
        // When cwd is root '/', provider must not present project name or path as '/'
        let rootURL = URL(fileURLWithPath: "/")
        let process = CodexProcessInfo(
            pid: 4567,
            command: "/opt/homebrew/bin/codex",
            workingDirectory: rootURL,
            startedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let discoverer = MockCodexProcessDiscoverer(processes: [process])
        let gitResolver = MockGitResolver(repoMap: [:])
        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: gitResolver)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.pid, 4567)
        XCTAssertEqual(session.projectName, "Codex Session")
        XCTAssertNil(session.projectPath, "Project path must be nil rather than root '/'")
        XCTAssertNil(session.summary, "Raw PID summary filler should be omitted")
    }

    func testCodexProviderUsesExtractedWorkspaceWhenCwdIsRoot() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom")
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")

        let process = CodexProcessInfo(
            pid: 8888,
            command: "codex sandbox --working-dir /Users/deepak/Desktop/Projects/oss/Loom",
            workingDirectory: URL(fileURLWithPath: "/"),
            startedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let discoverer = MockCodexProcessDiscoverer(processes: [process])
        let gitResolver = MockGitResolver(repoMap: [repoURL: gitInfo])
        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: gitResolver)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.pid, 8888)
        XCTAssertEqual(session.projectName, "Loom")
        XCTAssertEqual(session.projectPath, repoURL)
        XCTAssertEqual(session.branch, "main")
    }

    private final class MockProcessExecutor: ProcessExecuting, Sendable {
        let handler: @Sendable (String, [String]) async throws -> String

        init(handler: @escaping @Sendable (String, [String]) async throws -> String) {
            self.handler = handler
        }

        func execute(executablePath: String, arguments: [String]) async throws -> String {
            try await handler(executablePath, arguments)
        }
    }

    func testDefaultCodexProcessDiscovererPropagatesPsFailure() async {
        let executor = MockProcessExecutor { execPath, args in
            if execPath == "/bin/ps" {
                throw POSIXError(.EACCES)
            }
            return ""
        }

        let discoverer = DefaultCodexProcessDiscoverer(executor: executor)
        do {
            _ = try await discoverer.findRunningProcesses()
            XCTFail("Expected discoverer to propagate ps failure")
        } catch {
            // Success: actionable error was propagated rather than disguised as []
            XCTAssertTrue(error is POSIXError)
        }
    }

    func testDefaultCodexProcessDiscovererToleratesLsofFailure() async throws {
        let executor = MockProcessExecutor { execPath, args in
            if execPath == "/bin/ps" {
                return "12345 Sat Oct 3 10:00:00 2026 /opt/homebrew/bin/codex\n"
            }
            if execPath == "/usr/sbin/lsof" {
                throw POSIXError(.EACCES)
            }
            return ""
        }

        let discoverer = DefaultCodexProcessDiscoverer(executor: executor)
        let processes = try await discoverer.findRunningProcesses()
        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes[0].pid, 12345)
        XCTAssertNil(processes[0].workingDirectory)
    }

    // MARK: - Regression Tests for Acceptance Review Gaps

    func testCodexCommandPermitsLoomAndCommonKeywordsInArguments() {
        // Gap 1: broad substring filtering on command line previously rejected valid Codex commands
        // when arguments or prompts contained "loom", "grep", "agy", "swiftc", "helper", or "renderer".
        XCTAssertTrue(CodexParser.isCodexCommand("codex -C /Users/deepak/Desktop/Projects/oss/Loom"))
        XCTAssertTrue(CodexParser.isCodexCommand("/opt/homebrew/bin/codex -C /Users/deepak/Desktop/Projects/oss/Loom"))
        XCTAssertTrue(CodexParser.isCodexCommand("codex \"how do I use grep to find symbols?\""))
        XCTAssertTrue(CodexParser.isCodexCommand("codex --prompt \"test agy CLI options\""))
        XCTAssertTrue(CodexParser.isCodexCommand("codex \"explain swiftc warning\""))
        XCTAssertTrue(CodexParser.isCodexCommand("codex \"fix the auth helper and React renderer component\""))
        XCTAssertTrue(CodexParser.isCodexCommand("/usr/local/bin/node /usr/local/lib/node_modules/@openai/codex/bin/codex.js -C /Users/deepak/Desktop/Projects/oss/Loom"))
    }

    func testCodexCommandRejectsEchoAndNonExecutableArgumentsMentioningCodex() {
        // Gap 2: searching anywhere for /codex previously misidentified trailing path arguments as the executable.
        XCTAssertFalse(CodexParser.isCodexCommand("/bin/echo /tmp/codex"))
        XCTAssertFalse(CodexParser.isCodexCommand("/bin/echo \"/tmp/codex\""))
        XCTAssertFalse(CodexParser.isCodexCommand("echo \"check /tmp/codex\""))
        XCTAssertFalse(CodexParser.isCodexCommand("/usr/bin/cat '/tmp/codex'"))
        XCTAssertFalse(CodexParser.isCodexCommand("grep /tmp/codex"))
        XCTAssertFalse(CodexParser.isCodexCommand("python3 test.py \"/tmp/codex\""))
        XCTAssertFalse(CodexParser.isCodexCommand("node test.js \"/tmp/codex\""))
    }

    func testWorkspaceExtractionTokenBoundariesAndNoLoomCwdResolution() {
        // Token boundary flag matching
        let url1 = CodexParser.extractWorkspaceDirectory(from: "codex -C /Users/deepak/Desktop/Projects/oss/Loom")
        XCTAssertEqual(url1?.path, "/Users/deepak/Desktop/Projects/oss/Loom")

        let url2 = CodexParser.extractWorkspaceDirectory(from: "codex -c shell=none -C /Users/deepak/Desktop/Projects/oss/Loom")
        XCTAssertEqual(url2?.path, "/Users/deepak/Desktop/Projects/oss/Loom")

        let urlFlagEq = CodexParser.extractWorkspaceDirectory(from: "codex --working-dir=/Users/deepak/Desktop/Projects/oss/Loom")
        XCTAssertEqual(urlFlagEq?.path, "/Users/deepak/Desktop/Projects/oss/Loom")

        // Non-boundary flag matching should be rejected
        let urlColor = CodexParser.extractWorkspaceDirectory(from: "codex -Color /Users/deepak/Desktop/Projects/oss/Loom")
        XCTAssertNil(urlColor)

        let urlEmbedded = CodexParser.extractWorkspaceDirectory(from: "codex --my--working-dir=/Users/deepak/Desktop/Projects/oss/Loom")
        XCTAssertNil(urlEmbedded)

        // Relative path must not resolve against Loom's process cwd
        let urlRelative = CodexParser.extractWorkspaceDirectory(from: "codex -C relative/path")
        XCTAssertNil(urlRelative, "Relative paths without a known root base must return nil, not resolve against Loom cwd")

        let urlDot = CodexParser.extractWorkspaceDirectory(from: "codex -C .")
        XCTAssertNil(urlDot, "'.' relative path must return nil, not resolve against Loom cwd")
    }

    func testCodexProviderStateIsUnknownAndLastActivityIsNilWithoutDateFallback() async throws {
        let startTime = Date(timeIntervalSince1970: 1700000000)
        let process = CodexProcessInfo(
            pid: 4242,
            command: "codex --working-dir=/tmp/test-project",
            workingDirectory: URL(fileURLWithPath: "/tmp/test-project"),
            startedAt: startTime
        )

        let discoverer = MockCodexProcessDiscoverer(processes: [process])
        let gitResolver = MockGitResolver(repoMap: [:])
        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: gitResolver)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.id, "codex-4242")
        XCTAssertEqual(session.provider, .codex)
        XCTAssertEqual(session.state, .unknown, "Process-only Codex discovery must map truthfully to .unknown")
        XCTAssertEqual(session.startedAt, startTime, "startedAt preserves true process start time")
        XCTAssertNil(session.lastActivityAt, "lastActivityAt must be nil without actual recorded evidence and no Date() fallback")
        XCTAssertEqual(session.pid, 4242)
    }
}
