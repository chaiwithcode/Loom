//
//  ClaudeProviderTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import LoomCore

final class ClaudeProviderTests: XCTestCase {

    // MARK: - Parser & Command Matching Tests

    func testClaudeCommandMatching() {
        XCTAssertTrue(ClaudeParser.isClaudeCommand("claude"))
        XCTAssertTrue(ClaudeParser.isClaudeCommand("/opt/homebrew/bin/claude"))
        XCTAssertTrue(ClaudeParser.isClaudeCommand("/usr/local/bin/claude --session-id 123"))
        XCTAssertTrue(ClaudeParser.isClaudeCommand("/usr/local/bin/node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"))
        XCTAssertTrue(ClaudeParser.isClaudeCommand("node /Users/user/.npm-global/bin/claude.js"))
        XCTAssertTrue(ClaudeParser.isClaudeCommand("deno run /path/to/claude.ts"))
        XCTAssertTrue(ClaudeParser.isClaudeCommand("bun /path/to/claude.js"))

        // False positives
        XCTAssertFalse(ClaudeParser.isClaudeCommand("grep claude"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("vim claude.md"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("cat /path/to/claude-prompt.txt"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer) --type=renderer"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("/usr/bin/git diff"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("node build.js --target claude"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("node test.js \"claude\""))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("node server.js --model claude-3-opus"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("bun run test-claude.ts"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("deno run test-claude.ts"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("node cli.js --author claude"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("echo claude"))
        XCTAssertFalse(ClaudeParser.isClaudeCommand(""))
        XCTAssertFalse(ClaudeParser.isClaudeCommand("   "))
    }

    func testExtractSessionIDToken() {
        XCTAssertEqual(
            ClaudeParser.extractSessionIDToken(from: "claude --session-id session-123-abc"),
            "session-123-abc"
        )
        XCTAssertEqual(
            ClaudeParser.extractSessionIDToken(from: "claude --session-id=\"quoted-id-456\""),
            "quoted-id-456"
        )
        XCTAssertEqual(
            ClaudeParser.extractSessionIDToken(from: "claude --resume resume-token-789"),
            "resume-token-789"
        )
        XCTAssertEqual(
            ClaudeParser.extractSessionIDToken(from: "claude --resume='quoted-resume'"),
            "quoted-resume"
        )
        XCTAssertNil(ClaudeParser.extractSessionIDToken(from: "claude"))
        XCTAssertNil(ClaudeParser.extractSessionIDToken(from: "claude --other-flag foo"))
    }

    func testCwdEscaping() {
        XCTAssertEqual(
            ClaudeParser.escapedCWD("/Users/developer/Desktop/Projects/oss/Loom"),
            "-Users-developer-Desktop-Projects-oss-Loom"
        )
        XCTAssertEqual(
            ClaudeParser.escapedCWD("/Users/foo.bar/my project_1/"),
            "-Users-foo-bar-my-project-1-"
        )
        XCTAssertEqual(
            ClaudeParser.escapedCWD("/tmp"),
            "-tmp"
        )
    }

    func testProjectDirectories() {
        let home = URL(fileURLWithPath: "/Users/testuser")
        let dirs = ClaudeParser.projectDirectories(cwd: "/Users/testuser/project", homeDirectory: home)
        XCTAssertEqual(dirs.count, 3)
        XCTAssertTrue(dirs[0].path.contains(".claude/projects/-Users-testuser-project"))
        XCTAssertTrue(dirs[1].path.contains("Library/Application Support/Claude/claude-code-sessions"))
        XCTAssertTrue(dirs[2].path.contains("Library/Application Support/Claude/local-agent-mode-sessions"))
    }

    // MARK: - Transcript Tail Parsing Tests

    func testTranscriptTailParsingBashToolUse() {
        let jsonl = """
        {"type":"user","message":{"content":"Run tests"}}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test"}}]}}
        """
        let tail = ClaudeParser.parseTranscriptTail(from: jsonl)
        XCTAssertNotNil(tail)
        XCTAssertEqual(tail?.toolName, "Bash")
        XCTAssertEqual(tail?.toolCommand, "swift test")
        XCTAssertFalse(tail?.isTurnComplete ?? true)
        XCTAssertEqual(tail?.lastUserPrompt, "Run tests")
    }

    func testTranscriptTailParsingFileEditToolUse() {
        let jsonl = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"FileEdit","input":{"file_path":"/Users/user/app/Foo.swift"}}]}}
        """
        let tail = ClaudeParser.parseTranscriptTail(from: jsonl)
        XCTAssertNotNil(tail)
        XCTAssertEqual(tail?.toolName, "FileEdit")
        XCTAssertEqual(tail?.toolTarget, "/Users/user/app/Foo.swift")
        XCTAssertFalse(tail?.isTurnComplete ?? true)
    }

    func testTranscriptTailParsingFileViewToolUse() {
        let jsonl = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"FileView","input":{"path":"/Users/user/app/Bar.swift"}}]}}
        """
        let tail = ClaudeParser.parseTranscriptTail(from: jsonl)
        XCTAssertNotNil(tail)
        XCTAssertEqual(tail?.toolName, "FileView")
        XCTAssertEqual(tail?.toolTarget, "/Users/user/app/Bar.swift")
        XCTAssertFalse(tail?.isTurnComplete ?? true)
    }

    func testTranscriptTailParsingGrepAndGlob() {
        let grepJsonl = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Grep","input":{"pattern":"ClaudeParser"}}]}}
        """
        let grepTail = ClaudeParser.parseTranscriptTail(from: grepJsonl)
        XCTAssertEqual(grepTail?.toolName, "Grep")
        XCTAssertEqual(grepTail?.toolTarget, "ClaudeParser")

        let globJsonl = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Glob","input":{"pattern":"*.swift"}}]}}
        """
        let globTail = ClaudeParser.parseTranscriptTail(from: globJsonl)
        XCTAssertEqual(globTail?.toolName, "Glob")
        XCTAssertEqual(globTail?.toolTarget, "*.swift")
    }

    func testTranscriptTailParsingTurnComplete() {
        let jsonl = """
        {"type":"user","message":{"content":"Hello"}}
        {"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"How can I help you?"}]}}
        """
        let tail = ClaudeParser.parseTranscriptTail(from: jsonl)
        XCTAssertNotNil(tail)
        XCTAssertTrue(tail?.isTurnComplete ?? false)
        XCTAssertNil(tail?.toolName)
        XCTAssertEqual(tail?.lastUserPrompt, "Hello")
    }

    func testTranscriptTailParsingProgress() {
        let jsonl = """
        {"type":"progress","status":"thinking"}
        """
        let tail = ClaudeParser.parseTranscriptTail(from: jsonl)
        XCTAssertNotNil(tail)
        XCTAssertEqual(tail?.toolTarget, "thinking")
        XCTAssertFalse(tail?.isTurnComplete ?? true)
    }

    func testTranscriptTailFileInspectionWithRealFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session-abc.jsonl")
        let content = """
        {"type":"user","message":{"content":"Do something"}}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status"}}]}}
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let tail = ClaudeParser.inspectTranscriptTail(at: fileURL)
        XCTAssertNotNil(tail)
        XCTAssertEqual(tail?.toolName, "Bash")
        XCTAssertEqual(tail?.toolCommand, "git status")
    }

    // MARK: - Activity Summary & State Mapping Tests

    func testActivitySummaryFormatting() {
        // Child worker
        let childWorker = AgentProcess(
            pid: 999,
            parentPID: 100,
            executable: "swift",
            commandLine: "swift test --filter FooTests",
            provider: ProviderID.claude
        )
        let (childSummary, childEvidence) = ClaudeParser.activitySummary(tail: nil, childWorker: childWorker, projectName: "MyProj")
        XCTAssertEqual(childSummary, "Running swift test")
        XCTAssertTrue(childEvidence.contains("PID 999"))

        // Transcript Bash tool
        let bashTail = ClaudeTranscriptTail(toolName: "Bash", toolCommand: "git commit -m 'feat'")
        let (bashSummary, _) = ClaudeParser.activitySummary(tail: bashTail, childWorker: nil, projectName: "MyProj")
        XCTAssertEqual(bashSummary, "Committing git changes")

        // Transcript FileEdit tool
        let editTail = ClaudeTranscriptTail(toolName: "FileEdit", toolTarget: "/path/to/MyFile.swift")
        let (editSummary, _) = ClaudeParser.activitySummary(tail: editTail, childWorker: nil, projectName: "MyProj")
        XCTAssertEqual(editSummary, "Editing MyFile.swift")

        // Transcript FileView tool
        let viewTail = ClaudeTranscriptTail(toolName: "FileView", toolTarget: "/path/to/AnotherFile.swift")
        let (viewSummary, _) = ClaudeParser.activitySummary(tail: viewTail, childWorker: nil, projectName: "MyProj")
        XCTAssertEqual(viewSummary, "Reading AnotherFile.swift")

        // Transcript Grep tool
        let grepTail = ClaudeTranscriptTail(toolName: "Grep", toolTarget: "SessionStore")
        let (grepSummary, _) = ClaudeParser.activitySummary(tail: grepTail, childWorker: nil, projectName: "MyProj")
        XCTAssertEqual(grepSummary, "Searching 'SessionStore'")

        // Turn complete
        let completeTail = ClaudeTranscriptTail(isTurnComplete: true)
        let (completeSummary, _) = ClaudeParser.activitySummary(tail: completeTail, childWorker: nil, projectName: "MyProj")
        XCTAssertEqual(completeSummary, "Awaiting user input")

        // User prompt
        let promptTail = ClaudeTranscriptTail(lastUserPrompt: "Fix issue with crashing app")
        let (promptSummary, _) = ClaudeParser.activitySummary(tail: promptTail, childWorker: nil, projectName: "MyProj")
        XCTAssertEqual(promptSummary, "Awaiting turn: Fix issue with crashing app")

        // Fallback
        let (fallbackSummary, _) = ClaudeParser.activitySummary(tail: nil, childWorker: nil, projectName: "MyProject")
        XCTAssertEqual(fallbackSummary, "MyProject")
    }

    func testStateMapping() {
        let toolTail = ClaudeTranscriptTail(toolName: "Bash")
        let completeTail = ClaudeTranscriptTail(isTurnComplete: true)

        XCTAssertEqual(ClaudeParser.mapState(hasChildWorkers: true, isStarting: false, isInteractive: false, tail: nil, hasTranscript: true), AgentState.working)
        XCTAssertEqual(ClaudeParser.mapState(hasChildWorkers: false, isStarting: false, isInteractive: false, tail: toolTail, hasTranscript: true), AgentState.working)
        XCTAssertEqual(ClaudeParser.mapState(hasChildWorkers: false, isStarting: true, isInteractive: false, tail: nil, hasTranscript: false), AgentState.starting)
        XCTAssertEqual(ClaudeParser.mapState(hasChildWorkers: false, isStarting: false, isInteractive: true, tail: completeTail, hasTranscript: true), AgentState.waiting)
        XCTAssertEqual(ClaudeParser.mapState(hasChildWorkers: false, isStarting: false, isInteractive: false, tail: completeTail, hasTranscript: true), AgentState.waiting)
        XCTAssertEqual(ClaudeParser.mapState(hasChildWorkers: false, isStarting: false, isInteractive: false, tail: nil, hasTranscript: true), AgentState.waiting)
        XCTAssertEqual(ClaudeParser.mapState(hasChildWorkers: false, isStarting: false, isInteractive: false, tail: nil, hasTranscript: false), AgentState.unknown)
    }

    func testLsofCwdParsing() {
        let normal = """
        p12345
        fcwd
        n/Users/developer/Desktop/Projects/oss/Loom
        """
        XCTAssertEqual(ClaudeParser.parseLsofCwdOutput(normal)?.path, "/Users/developer/Desktop/Projects/oss/Loom")

        let rootOnly = "p12345\nfcwd\nn/\n"
        XCTAssertNil(ClaudeParser.parseLsofCwdOutput(rootOnly))

        let empty = "p12345\nfcwd\n"
        XCTAssertNil(ClaudeParser.parseLsofCwdOutput(empty))
    }

    // MARK: - ClaudeProvider Integration Tests

    func testClaudeProviderAvailability() async {
        let provider = ClaudeProvider()
        let availability = await provider.availability()
        XCTAssertEqual(availability, .available)
    }

    func testClaudeProviderSingleSessionInGitRepo() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let now = Date()
        let process = AgentProcess(
            pid: 1001,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: repoURL,
            startedAt: now.addingTimeInterval(-60),
            provider: ProviderID.claude
        )
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 1001, parentPID: 1, command: "claude", executable: "claude", startedAt: now.addingTimeInterval(-60))
        ])

        let transcriptURL = URL(fileURLWithPath: "/Users/developer/.claude/projects/-Users-developer-Desktop-Projects-oss-Loom/session-uuid-1.jsonl")
        let transcript = ClaudeTranscriptInfo(
            url: transcriptURL,
            sessionID: "session-uuid-1",
            modifiedAt: now.addingTimeInterval(-10)
        )
        let tail = ClaudeTranscriptTail(toolName: "Bash", toolCommand: "swift test")

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(
            transcripts: [repoURL: [transcript]],
            tails: [transcriptURL: tail]
        )
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.id, "session-uuid-1")
        XCTAssertEqual(session.provider, ProviderID.claude)
        XCTAssertEqual(session.projectName, "Loom")
        XCTAssertEqual(session.projectPath, repoURL)
        XCTAssertEqual(session.branch, "main")
        XCTAssertEqual(session.state, AgentState.working)
        XCTAssertEqual(session.summary, "Running swift test")
        XCTAssertEqual(session.pid, 1001)

        let diagnostics = await provider.lastDiagnostics()
        XCTAssertEqual(diagnostics?.processesDetected, 1)
        XCTAssertEqual(diagnostics?.logicalSessions, 1)
        XCTAssertEqual(diagnostics?.workspacesResolved, 1)
    }

    func testClaudeProviderSingleSessionInNonGitWorkspace() async throws {
        let dirURL = URL(fileURLWithPath: "/Users/developer/Desktop/Scratchpad")
        let process = AgentProcess(
            pid: 1002,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: dirURL,
            startedAt: Date(timeIntervalSince1970: 1700000000),
            provider: ProviderID.claude
        )
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 1002, parentPID: 1, command: "claude", executable: "claude", startedAt: Date(timeIntervalSince1970: 1700000000))
        ])

        let transcriptURL = URL(fileURLWithPath: "/Users/developer/.claude/projects/-Users-developer-Desktop-Scratchpad/session-uuid-2.jsonl")
        let transcript = ClaudeTranscriptInfo(
            url: transcriptURL,
            sessionID: "session-uuid-2",
            modifiedAt: Date(timeIntervalSince1970: 1700000050)
        )
        let tail = ClaudeTranscriptTail(isTurnComplete: true)

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(
            transcripts: [dirURL: [transcript]],
            tails: [transcriptURL: tail]
        )
        let mockGitResolver = MockClaudeGitResolver(repoMap: [:])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.id, "session-uuid-2")
        XCTAssertEqual(session.projectName, "Scratchpad")
        XCTAssertEqual(session.projectPath, dirURL)
        XCTAssertNil(session.branch)
        XCTAssertEqual(session.state, AgentState.waiting)
        XCTAssertEqual(session.summary, "Awaiting user input")
    }

    func testMultipleClaudeSessionsInSameRepoRemainDistinct() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")

        let process1 = AgentProcess(
            pid: 2001,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: repoURL,
            startedAt: Date(timeIntervalSince1970: 1700000000),
            provider: ProviderID.claude
        )
        let process2 = AgentProcess(
            pid: 2002,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: repoURL,
            startedAt: Date(timeIntervalSince1970: 1700002000),
            provider: ProviderID.claude
        )

        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 2001, parentPID: 1, command: "claude", executable: "claude", startedAt: Date(timeIntervalSince1970: 1700000000)),
            ProcessNode(pid: 2002, parentPID: 1, command: "claude", executable: "claude", startedAt: Date(timeIntervalSince1970: 1700002000))
        ])

        let t1URL = URL(fileURLWithPath: "/tmp/session-1.jsonl")
        let t2URL = URL(fileURLWithPath: "/tmp/session-2.jsonl")

        let transcript1 = ClaudeTranscriptInfo(
            url: t1URL,
            sessionID: "session-1",
            modifiedAt: Date(timeIntervalSince1970: 1700000500)
        )
        let transcript2 = ClaudeTranscriptInfo(
            url: t2URL,
            sessionID: "session-2",
            modifiedAt: Date(timeIntervalSince1970: 1700002500)
        )

        let tail1 = ClaudeTranscriptTail(toolName: "FileEdit", toolTarget: "App.swift")
        let tail2 = ClaudeTranscriptTail(isTurnComplete: true)

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process1, process2], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(
            transcripts: [repoURL: [transcript2, transcript1]], // newest first
            tails: [t1URL: tail1, t2URL: tail2]
        )
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 2)

        let s1 = sessions.first(where: { $0.pid == 2001 })
        let s2 = sessions.first(where: { $0.pid == 2002 })

        XCTAssertNotNil(s1)
        XCTAssertNotNil(s2)
        XCTAssertNotEqual(s1?.id, s2?.id)
        XCTAssertEqual(s1?.projectPath, repoURL)
        XCTAssertEqual(s2?.projectPath, repoURL)
        XCTAssertEqual(s1?.projectName, "Loom")
        XCTAssertEqual(s2?.projectName, "Loom")
    }

    func testChildWorkerProcessesCollapseIntoParentSession() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")

        // Parent Claude process
        let now = Date()
        let parentProcess = AgentProcess(
            pid: 3000,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: repoURL,
            startedAt: now.addingTimeInterval(-60),
            provider: ProviderID.claude
        )

        // Process tree includes parent, child shell, and grandchild test runner
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 3000, parentPID: 1, command: "claude", executable: "claude", startedAt: now.addingTimeInterval(-60)),
            ProcessNode(pid: 3001, parentPID: 3000, command: "/bin/sh -c swift test", executable: "sh", startedAt: now.addingTimeInterval(-30)),
            ProcessNode(pid: 3002, parentPID: 3001, command: "swift test", executable: "swift", startedAt: now.addingTimeInterval(-10))
        ])

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [parentProcess], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(transcripts: [:], tails: [:])
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.pid, 3000)
        XCTAssertEqual(session.state, AgentState.working)
        XCTAssertEqual(session.associatedProcesses.count, 3)
        XCTAssertTrue(session.summary?.contains("Testing") == true || session.summary?.contains("swift") == true)
    }

    func testSessionLifecycleReconcilerExitedProcessRetention() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")

        let process = AgentProcess(
            pid: 4000,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: repoURL,
            startedAt: Date(),
            provider: ProviderID.claude
        )
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 4000, parentPID: 1, command: "claude", executable: "claude", startedAt: Date())
        ])

        let transcriptURL = URL(fileURLWithPath: "/tmp/session-4000.jsonl")
        let transcript = ClaudeTranscriptInfo(url: transcriptURL, sessionID: "session-4000", modifiedAt: Date())
        let tail = ClaudeTranscriptTail(isTurnComplete: true)

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(
            transcripts: [repoURL: [transcript]],
            tails: [transcriptURL: tail]
        )
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        // Cycle 1: Session is active (.waiting)
        let activeSessions = try await provider.discoverSessions()
        XCTAssertEqual(activeSessions.count, 1)
        XCTAssertEqual(activeSessions[0].state, AgentState.waiting)

        // Cycle 2: Process exited
        mockProcessDiscoverer.processes = []
        mockProcessDiscoverer.tree = ProcessTree(nodes: [])

        let reconciledSessions = try await provider.discoverSessions()
        XCTAssertEqual(reconciledSessions.count, 1)
        XCTAssertEqual(reconciledSessions[0].state, AgentState.finished)
        XCTAssertTrue(reconciledSessions[0].summary?.contains("finished") == true)
    }

    func testGracefulDegradationWithoutTranscript() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let process = AgentProcess(
            pid: 5000,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: repoURL,
            startedAt: Date(timeIntervalSince1970: 1700000000), // older than starting threshold
            provider: ProviderID.claude
        )
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 5000, parentPID: 1, command: "claude", executable: "claude", startedAt: Date(timeIntervalSince1970: 1700000000))
        ])

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(transcripts: [:], tails: [:])
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.id, "claude-5000")
        XCTAssertEqual(session.state, AgentState.unknown)
        XCTAssertTrue(session.discoveryEvidence.contains { $0.contains("Unknown") })
    }

    func testLiveSystemDiscoveryRejectsFalsePositives() async throws {
        let discoverer = DefaultClaudeProcessDiscoverer()
        let (processes, _) = try await discoverer.discoverProcesses()

        // Ensure Python or agy running user prompts containing 'claude' are never matched
        for p in processes {
            XCTAssertFalse(p.executable.lowercased().contains("python"))
            XCTAssertFalse(p.executable.lowercased().contains("agy"))
            XCTAssertFalse(p.commandLine.lowercased().hasPrefix("grep"))
        }
    }

    // MARK: - Regression Tests for Stale Transcript Binding & Authoritative Session Flags

    func testTranscriptFrom24HoursAgoDoesNotBindToNewProcess() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let now = Date()
        let process = AgentProcess(
            pid: 6001,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: repoURL,
            startedAt: now.addingTimeInterval(-60), // started 1 minute ago
            provider: ProviderID.claude
        )
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 6001, parentPID: 1, command: "claude", executable: "claude", startedAt: now.addingTimeInterval(-60))
        ])

        // Transcript from yesterday (24h ago)
        let staleTranscriptURL = URL(fileURLWithPath: "/Users/developer/.claude/projects/-Users-developer-Desktop-Projects-oss-Loom/yesterday-session.jsonl")
        let staleTranscript = ClaudeTranscriptInfo(
            url: staleTranscriptURL,
            sessionID: "yesterday-session",
            modifiedAt: now.addingTimeInterval(-86400)
        )
        let staleTail = ClaudeTranscriptTail(toolName: "Bash", toolCommand: "old command from yesterday")

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(
            transcripts: [repoURL: [staleTranscript]],
            tails: [staleTranscriptURL: staleTail]
        )
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        // Truthful: must NOT bind to yesterday's transcript
        XCTAssertNotEqual(session.id, "yesterday-session")
        XCTAssertEqual(session.id, "claude-6001")
        XCTAssertEqual(session.state, AgentState.unknown)
        XCTAssertFalse(session.summary?.contains("old command from yesterday") == true)
    }

    func testNoValidTranscriptReturnsTruthfulUnknown() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let now = Date()
        let process = AgentProcess(
            pid: 6002,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: repoURL,
            startedAt: now.addingTimeInterval(-100), // > 10s old
            provider: ProviderID.claude
        )
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 6002, parentPID: 1, command: "claude", executable: "claude", startedAt: now.addingTimeInterval(-100))
        ])

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(transcripts: [repoURL: []], tails: [:])
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].state, AgentState.unknown)
        XCTAssertEqual(sessions[0].id, "claude-6002")
    }

    func testStaleTranscriptIgnoredAlongsideFreshUnrelatedTranscript() {
        let now = Date()
        let staleTranscriptURL = URL(fileURLWithPath: "/tmp/stale.jsonl")
        let stale = ClaudeTranscriptInfo(url: staleTranscriptURL, sessionID: "stale", modifiedAt: now.addingTimeInterval(-86400))

        var used: Set<String> = []
        let correlated = ClaudeParser.correlateTranscript(
            for: now.addingTimeInterval(-30),
            in: [stale],
            usedPaths: &used
        )

        XCTAssertNil(correlated, "CorrelateTranscript must never return a stale transcript from yesterday")
        XCTAssertTrue(used.isEmpty)
    }

    func testExplicitResumeChoosesExactTranscriptOverNewerTranscript() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let now = Date()
        let process = AgentProcess(
            pid: 6003,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude --resume resume-exact-uuid",
            workingDirectory: repoURL,
            startedAt: now.addingTimeInterval(-10),
            provider: ProviderID.claude,
            sessionIDToken: "resume-exact-uuid"
        )
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 6003, parentPID: 1, command: "claude --resume resume-exact-uuid", executable: "claude", startedAt: now.addingTimeInterval(-10))
        ])

        let exactURL = URL(fileURLWithPath: "/tmp/resume-exact-uuid.jsonl")
        let exactTranscript = ClaudeTranscriptInfo(url: exactURL, sessionID: "resume-exact-uuid", modifiedAt: now.addingTimeInterval(-3600)) // 1h ago
        let exactTail = ClaudeTranscriptTail(isTurnComplete: true)

        let newerURL = URL(fileURLWithPath: "/tmp/newer-unrelated.jsonl")
        let newerTranscript = ClaudeTranscriptInfo(url: newerURL, sessionID: "newer-unrelated", modifiedAt: now.addingTimeInterval(-5)) // 5s ago
        let newerTail = ClaudeTranscriptTail(toolName: "Bash", toolCommand: "newer action")

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(
            transcripts: [repoURL: [newerTranscript, exactTranscript]],
            tails: [exactURL: exactTail, newerURL: newerTail]
        )
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "resume-exact-uuid", "--resume must authoritatively bind its exact transcript even when another is newer")
        XCTAssertEqual(sessions[0].state, AgentState.waiting)
    }

    func testExplicitSessionIDChoosesExactTranscript() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let now = Date()
        let process = AgentProcess(
            pid: 6004,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude --session-id session-exact-uuid",
            workingDirectory: repoURL,
            startedAt: now.addingTimeInterval(-10),
            provider: ProviderID.claude,
            sessionIDToken: "session-exact-uuid"
        )
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 6004, parentPID: 1, command: "claude --session-id session-exact-uuid", executable: "claude", startedAt: now.addingTimeInterval(-10))
        ])

        let exactURL = URL(fileURLWithPath: "/tmp/session-exact-uuid.jsonl")
        let exactTranscript = ClaudeTranscriptInfo(url: exactURL, sessionID: "session-exact-uuid", modifiedAt: now.addingTimeInterval(-3600))
        let exactTail = ClaudeTranscriptTail(isTurnComplete: true)

        let newerURL = URL(fileURLWithPath: "/tmp/other-newer.jsonl")
        let newerTranscript = ClaudeTranscriptInfo(url: newerURL, sessionID: "other-newer", modifiedAt: now.addingTimeInterval(-2))

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(
            transcripts: [repoURL: [newerTranscript, exactTranscript]],
            tails: [exactURL: exactTail]
        )
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "session-exact-uuid")
    }

    func testOpenFDTranscriptMatchesProcessAuthoritatively() async throws {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let now = Date()
        let process = AgentProcess(
            pid: 6005,
            parentPID: 1,
            executable: "claude",
            commandLine: "claude",
            workingDirectory: repoURL,
            startedAt: now.addingTimeInterval(-20),
            provider: ProviderID.claude
        )
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 6005, parentPID: 1, command: "claude", executable: "claude", startedAt: now.addingTimeInterval(-20))
        ])

        let candidateURL = URL(fileURLWithPath: "/tmp/candidate-time.jsonl")
        let candidateTranscript = ClaudeTranscriptInfo(url: candidateURL, sessionID: "candidate-time", modifiedAt: now.addingTimeInterval(-5))

        let openFDURL = URL(fileURLWithPath: "/tmp/open-fd-uuid.jsonl")
        let openFDTranscript = ClaudeTranscriptInfo(url: openFDURL, sessionID: "open-fd-uuid", modifiedAt: now.addingTimeInterval(-15))
        let openFDTail = ClaudeTranscriptTail(toolName: "FileEdit", toolTarget: "README.md")

        let mockProcessDiscoverer = MockClaudeProcessDiscoverer(processes: [process], tree: tree)
        let mockTranscriptInspector = MockClaudeTranscriptInspector(
            transcripts: [repoURL: [candidateTranscript]],
            tails: [openFDURL: openFDTail],
            openTranscripts: [6005: openFDTranscript]
        )
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let mockGitResolver = MockClaudeGitResolver(repoMap: [repoURL: gitInfo])

        let provider = ClaudeProvider(
            processDiscoverer: mockProcessDiscoverer,
            transcriptInspector: mockTranscriptInspector,
            gitResolver: mockGitResolver
        )

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "open-fd-uuid", "Authoritative open-FD transcript must take precedence over time-correlated transcripts")
        XCTAssertEqual(sessions[0].state, AgentState.working)
        XCTAssertEqual(sessions[0].summary, "Editing README.md")
    }
}

// MARK: - Test Mocks

private struct MockClaudeGitResolver: GitRepositoryResolving, Sendable {
    var repoMap: [URL: GitRepositoryInfo] = [:]

    func resolveRepository(for directoryURL: URL) async -> GitRepositoryInfo? {
        repoMap[directoryURL]
    }
}

final class MockClaudeProcessDiscoverer: ClaudeProcessDiscovering, @unchecked Sendable {
    var installed: Bool = true
    var processes: [AgentProcess]
    var tree: ProcessTree

    init(processes: [AgentProcess] = [], tree: ProcessTree = ProcessTree(nodes: [])) {
        self.processes = processes
        self.tree = tree
    }

    func isClaudeInstalled() async -> Bool {
        installed
    }

    func discoverProcesses() async throws -> (processes: [AgentProcess], processTree: ProcessTree) {
        (processes: processes, processTree: tree)
    }
}

final class MockClaudeTranscriptInspector: ClaudeTranscriptInspecting, @unchecked Sendable {
    var transcripts: [URL: [ClaudeTranscriptInfo]]
    var tails: [URL: ClaudeTranscriptTail]
    var openTranscripts: [pid_t: ClaudeTranscriptInfo]

    init(
        transcripts: [URL: [ClaudeTranscriptInfo]] = [:],
        tails: [URL: ClaudeTranscriptTail] = [:],
        openTranscripts: [pid_t: ClaudeTranscriptInfo] = [:]
    ) {
        self.transcripts = transcripts
        self.tails = tails
        self.openTranscripts = openTranscripts
    }

    func findTranscripts(for cwd: URL) async -> [ClaudeTranscriptInfo] {
        transcripts[cwd] ?? []
    }

    func inspectTranscriptTail(at url: URL) async -> ClaudeTranscriptTail? {
        tails[url]
    }

    func findOpenTranscript(for pid: pid_t) async -> ClaudeTranscriptInfo? {
        openTranscripts[pid]
    }
}
