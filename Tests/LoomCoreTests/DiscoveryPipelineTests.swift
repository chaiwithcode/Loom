//
//  DiscoveryPipelineTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import LoomCore

final class DiscoveryPipelineTests: XCTestCase {

    // MARK: - 1. ProcessTree & Host App Resolution Tests

    func testProcessTreeBuildAndHostResolution() {
        let psOutput = """
          100     1 Sat Oct 10 10:00:00 2026 /Applications/Visual Studio Code.app/Contents/MacOS/Electron
          101   100 Sat Oct 10 10:00:05 2026 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper --type=utility
          102   101 Sat Oct 10 10:00:10 2026 /opt/homebrew/bin/codex sandbox --session-id=codex-session-vscode /Users/developer/Desktop/Projects/oss/Loom
          103   102 Sat Oct 10 10:00:12 2026 /usr/local/bin/node /path/to/kernel.js
          200     1 Sat Oct 10 10:05:00 2026 /Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
          201   200 Sat Oct 10 10:05:01 2026 /bin/zsh -l
          202   201 Sat Oct 10 10:05:10 2026 /opt/homebrew/bin/codex exec --working-dir /Users/developer/Desktop/Projects/oss/XKit
          300     1 Sat Oct 10 10:10:00 2026 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
          301   300 Sat Oct 10 10:10:05 2026 /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex sandbox --session-id 98c95ead7ccd476aae7aa8ba50350c54
          302   301 Sat Oct 10 10:10:07 2026 /usr/local/bin/node /path/to/trusted-worker.js
        """

        let nodes = ProcessTree.parsePsOutput(psOutput)
        XCTAssertEqual(nodes.count, 10)

        let tree = ProcessTree(nodes: nodes)

        // VS Code ancestry
        XCTAssertEqual(tree.resolveHostApp(for: 102), .vsCode)
        XCTAssertEqual(tree.resolveHostApp(for: 103), .vsCode)
        XCTAssertEqual(tree.descendants(of: 102).map(\.pid), [103])

        // Terminal ancestry
        XCTAssertEqual(tree.resolveHostApp(for: 202), .terminal)

        // ChatGPT ancestry
        XCTAssertEqual(tree.resolveHostApp(for: 301), .chatGPT)
        XCTAssertEqual(tree.resolveHostApp(for: 302), .chatGPT)
    }

    func testProcessTreeSessionIDTokenExtraction() {
        XCTAssertEqual(
            ProcessTree.extractSessionIDToken(from: "codex sandbox --session-id 98c95ead7ccd476aae7aa8ba50350c54 /path"),
            "98c95ead7ccd476aae7aa8ba50350c54"
        )
        XCTAssertEqual(
            ProcessTree.extractSessionIDToken(from: "codex sandbox --session-id=\"my-session-uuid\""),
            "my-session-uuid"
        )
        XCTAssertEqual(
            ProcessTree.extractSessionIDToken(from: "codex --conversation=chat-4242"),
            "chat-4242"
        )
        XCTAssertEqual(
            ProcessTree.extractSessionIDToken(from: "codex --conversation-id 'token-single-quote'"),
            "token-single-quote"
        )
        XCTAssertNil(
            ProcessTree.extractSessionIDToken(from: "codex exec echo hello")
        )
    }

    // MARK: - 2. Multi-tier Workspace Resolution Tests

    private final class MockFileSystemForDiscovery: FileSystemInspecting, Sendable {
        let files: [String: String]

        init(files: [String: String]) {
            self.files = files
        }

        func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
            if files.keys.contains(path) {
                isDirectory?.pointee = ObjCBool(false)
                return true
            }
            return false
        }

        func readFile(atPath path: String) throws -> String {
            if let content = files[path] {
                return content
            }
            throw CocoaError(.fileNoSuchFile)
        }
    }

    private final class MockGitResolverForDiscovery: GitRepositoryResolving, Sendable {
        let repoMap: [URL: GitRepositoryInfo]

        init(repoMap: [URL: GitRepositoryInfo]) {
            self.repoMap = repoMap
        }

        func resolveRepository(for directoryURL: URL) async -> GitRepositoryInfo? {
            repoMap[directoryURL]
        }
    }

    func testWorkspaceResolutionAllTiers() async {
        let repoURL = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let gitInfo = GitRepositoryInfo(rootURL: repoURL, projectName: "Loom", branch: "main")
        let gitResolver = MockGitResolverForDiscovery(repoMap: [repoURL: gitInfo])

        let sandboxedMirrorURL = URL(fileURLWithPath: "/Users/developer/.codex/.chatgpt-projects/g-p-6a1c1358a77c8191b1700dd481c5b2b1")
        let agentsDocContent = """
        # AGENTS.md
        This is a local mirror of the ChatGPT project “Naviik - SmartRemote”.
        """
        let globalStateJSON = """
        {
            "local-projects": {
                "g-p-6a1c1358a77c8191b1700dd481c5b2b1": {
                    "name": "Naviik - SmartRemote"
                }
            }
        }
        """

        let mockFS = MockFileSystemForDiscovery(files: [
            sandboxedMirrorURL.appendingPathComponent("AGENTS.md").path: agentsDocContent,
            "/Users/developer/.codex/.codex-global-state.json": globalStateJSON
        ])

        let resolver = DefaultWorkspaceResolver(
            gitResolver: gitResolver,
            fileSystem: mockFS,
            homeDirectory: URL(fileURLWithPath: "/Users/developer")
        )

        // Tier 1: Explicit metadata URL
        let p1 = AgentProcess(pid: 1, commandLine: "codex", provider: .codex)
        let res1 = await resolver.resolveWorkspace(for: p1, parent: nil, explicitMetadataURL: repoURL)
        XCTAssertEqual(res1.projectName, "Loom")
        XCTAssertEqual(res1.projectPath, repoURL)
        XCTAssertEqual(res1.branch, "main")
        XCTAssertEqual(res1.sourceDescription, "provider-metadata+git")

        // Tier 2: Command-line flag --working-dir
        let p2 = AgentProcess(
            pid: 2,
            commandLine: "codex exec --working-dir=/Users/developer/Desktop/Projects/oss/Loom",
            provider: .codex
        )
        let res2 = await resolver.resolveWorkspace(for: p2, parent: nil, explicitMetadataURL: nil)
        XCTAssertEqual(res2.projectName, "Loom")
        XCTAssertEqual(res2.projectPath, repoURL)

        // Tier 3: Process CWD
        let p3 = AgentProcess(
            pid: 3,
            commandLine: "codex",
            workingDirectory: repoURL,
            provider: .codex
        )
        let res3 = await resolver.resolveWorkspace(for: p3, parent: nil, explicitMetadataURL: nil)
        XCTAssertEqual(res3.projectName, "Loom")

        // Tier 4: Parent process CWD
        let parent = AgentProcess(
            pid: 10,
            commandLine: "zsh",
            workingDirectory: repoURL,
            provider: .codex
        )
        let p4 = AgentProcess(pid: 11, parentPID: 10, commandLine: "codex", provider: .codex)
        let res4 = await resolver.resolveWorkspace(for: p4, parent: parent, explicitMetadataURL: nil)
        XCTAssertEqual(res4.projectName, "Loom")

        // Tier 5: AGENTS.md mirror extraction
        let p5 = AgentProcess(
            pid: 5,
            commandLine: "codex sandbox \(sandboxedMirrorURL.path)",
            provider: .codex
        )
        let res5 = await resolver.resolveWorkspace(for: p5, parent: nil, explicitMetadataURL: nil)
        XCTAssertEqual(res5.projectName, "Naviik - SmartRemote")
        XCTAssertEqual(res5.projectPath, sandboxedMirrorURL)
    }

    // MARK: - 3. Session Correlation Engine & Collapse Tests

    func testCodexDuplicateProcessCollapseIntoLogicalSessions() async {
        let repoA = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let repoB = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/XKit")

        let date1 = Date(timeIntervalSince1970: 1700000000)
        let date2 = Date(timeIntervalSince1970: 1700000010)
        let date3 = Date(timeIntervalSince1970: 1700000020)

        // Session 1: 3 processes for Loom with session ID token "s-loom"
        let p10 = AgentProcess(
            pid: 100,
            commandLine: "codex sandbox --session-id=s-loom \(repoA.path)",
            workingDirectory: repoA,
            startedAt: date1,
            provider: .codex,
            hostApp: .chatGPT,
            sessionIDToken: "s-loom"
        )
        let p11 = AgentProcess(
            pid: 101,
            parentPID: 100,
            commandLine: "node kernel.js --session-id=s-loom",
            workingDirectory: repoA,
            startedAt: date2,
            provider: .codex,
            hostApp: .chatGPT,
            sessionIDToken: "s-loom"
        )
        let p12 = AgentProcess(
            pid: 102,
            parentPID: 100,
            commandLine: "node trusted-worker.js --session-id=s-loom",
            workingDirectory: repoA,
            startedAt: date3,
            provider: .codex,
            hostApp: .chatGPT,
            sessionIDToken: "s-loom"
        )

        // Session 2: 3 processes for XKit with session ID token "s-xkit"
        let p20 = AgentProcess(
            pid: 200,
            commandLine: "codex sandbox --session-id=s-xkit \(repoB.path)",
            workingDirectory: repoB,
            startedAt: date1,
            provider: .codex,
            hostApp: .vsCode,
            sessionIDToken: "s-xkit"
        )
        let p21 = AgentProcess(
            pid: 201,
            parentPID: 200,
            commandLine: "node kernel.js --session-id=s-xkit",
            workingDirectory: repoB,
            startedAt: date2,
            provider: .codex,
            hostApp: .vsCode,
            sessionIDToken: "s-xkit"
        )
        let p22 = AgentProcess(
            pid: 202,
            parentPID: 200,
            commandLine: "node trusted-worker.js --session-id=s-xkit",
            workingDirectory: repoB,
            startedAt: date3,
            provider: .codex,
            hostApp: .vsCode,
            sessionIDToken: "s-xkit"
        )

        // Standalone single process (no session token)
        let p30 = AgentProcess(
            pid: 300,
            commandLine: "codex",
            workingDirectory: nil,
            startedAt: date1,
            provider: .codex,
            hostApp: nil,
            sessionIDToken: nil
        )

        let allProcesses = [p10, p11, p12, p20, p21, p22, p30]
        let nodes = allProcesses.map {
            ProcessNode(pid: $0.pid, parentPID: $0.parentPID, command: $0.commandLine, executable: $0.executable, startedAt: $0.startedAt)
        }
        let tree = ProcessTree(nodes: nodes)

        let gitResolver = MockGitResolverForDiscovery(repoMap: [
            repoA: GitRepositoryInfo(rootURL: repoA, projectName: "Loom", branch: "main"),
            repoB: GitRepositoryInfo(rootURL: repoB, projectName: "XKit", branch: "develop")
        ])
        let workspaceResolver = DefaultWorkspaceResolver(gitResolver: gitResolver)
        let correlationEngine = DefaultSessionCorrelationEngine()

        let sessions = await correlationEngine.correlate(
            processes: allProcesses,
            processTree: tree,
            workspaceResolver: workspaceResolver
        )

        // 7 raw processes MUST collapse into exactly 3 logical sessions
        XCTAssertEqual(sessions.count, 3)

        // Session 1: Loom
        let loomSession = sessions.first(where: { $0.id == "codex-s-loom" })
        XCTAssertNotNil(loomSession)
        XCTAssertEqual(loomSession?.projectName, "Loom")
        XCTAssertEqual(loomSession?.hostApp, .chatGPT)
        XCTAssertEqual(loomSession?.state, .working)
        XCTAssertEqual(loomSession?.associatedProcesses.count, 3)
        XCTAssertEqual(loomSession?.lastActivityAt, date3)

        // Session 2: XKit
        let xkitSession = sessions.first(where: { $0.id == "codex-s-xkit" })
        XCTAssertNotNil(xkitSession)
        XCTAssertEqual(xkitSession?.projectName, "XKit")
        XCTAssertEqual(xkitSession?.hostApp, .vsCode)
        XCTAssertEqual(xkitSession?.state, .working)
        XCTAssertEqual(xkitSession?.associatedProcesses.count, 3)

        // Session 3: Standalone fallback
        let standaloneSession = sessions.first(where: { $0.id == "codex-300" })
        XCTAssertNotNil(standaloneSession)
        XCTAssertEqual(standaloneSession?.state, .unknown)
        XCTAssertEqual(standaloneSession?.associatedProcesses.count, 1)
    }

    // MARK: - 4. Diagnostics & Degraded Session Tests

    func testCodexProviderEmitsDiscoveryDiagnostics() async throws {
        struct MockDiscovererWithTree: CodexProcessDiscovering {
            let processes: [AgentProcess]
            let tree: ProcessTree

            func findRunningProcesses() async throws -> [CodexProcessInfo] { [] }
            func discoverProcesses() async throws -> (processes: [AgentProcess], processTree: ProcessTree) {
                return (processes: processes, processTree: tree)
            }
        }

        let repo = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let p1 = AgentProcess(pid: 501, commandLine: "codex sandbox --session-id=sess-123 \(repo.path)", workingDirectory: repo, provider: .codex, sessionIDToken: "sess-123")
        let p2 = AgentProcess(pid: 502, parentPID: 501, commandLine: "node worker.js", workingDirectory: repo, provider: .codex, sessionIDToken: "sess-123")

        let nodes = [
            ProcessNode(pid: 501, parentPID: nil, command: p1.commandLine, executable: "codex"),
            ProcessNode(pid: 502, parentPID: 501, command: p2.commandLine, executable: "node")
        ]
        let tree = ProcessTree(nodes: nodes)

        let discoverer = MockDiscovererWithTree(processes: [p1, p2], tree: tree)
        let gitResolver = MockGitResolverForDiscovery(repoMap: [repo: GitRepositoryInfo(rootURL: repo, projectName: "Loom", branch: "main")])

        let provider = CodexProvider(processDiscoverer: discoverer, gitResolver: gitResolver)
        let sessions = try await provider.discoverSessions()

        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.id, "codex-sess-123")
        XCTAssertEqual(session.diagnostics?.processesDetected, 2)
        XCTAssertEqual(session.diagnostics?.logicalSessions, 1)
        XCTAssertEqual(session.diagnostics?.workspacesResolved, 1)
        XCTAssertEqual(session.diagnostics?.metadataStatus, .available)
        XCTAssertNil(session.diagnostics?.metadataError)
    }

    // MARK: - 5. Codex State Store & Evidence Ranking Tests

    private final class MockCodexStateStoreInspectorForPipeline: CodexStateStoreInspecting, Sendable {
        let roots: [CodexProjectRootRecord]
        let metadataMap: [String: CodexSessionMetadata]

        init(roots: [CodexProjectRootRecord] = [], metadataMap: [String: CodexSessionMetadata] = [:]) {
            self.roots = roots
            self.metadataMap = metadataMap
        }

        func loadProjectRoots() async -> [CodexProjectRootRecord] {
            roots
        }

        func projectName(forPath url: URL) async -> String? {
            let normalized = url.standardizedFileURL.path
            let matches = roots.filter {
                normalized == $0.path || normalized.hasPrefix($0.path == "/" ? "/" : $0.path + "/")
            }
            guard let maxLen = matches.map(\.path.count).max() else { return nil }
            return matches.first(where: { $0.path.count == maxLen })?.projectName
        }

        func sessionMetadata(for sessionID: String) async -> CodexSessionMetadata? {
            metadataMap[sessionID]
        }
    }

    func testSessionCorrelationMergesChildWorkersWithoutTokenIntoParentTokenSession() async {
        // Reproduce real scenario:
        // PID 65723 has --session-id token
        // PID 65724 (trusted-worker.js) is a child process without --session-id
        let mirrorURL = URL(fileURLWithPath: "/Users/developer/.codex/.chatgpt-projects/g-p-6a1c1358a77c8191b1700dd481c5b2b1")
        let parent = AgentProcess(
            pid: 65723,
            commandLine: "/Applications/ChatGPT.app/.../codex sandbox --session-id 98c95ead7ccd476aae7aa8ba50350c54 --working-dir \(mirrorURL.path)",
            workingDirectory: mirrorURL,
            provider: .codex,
            sessionIDToken: "98c95ead7ccd476aae7aa8ba50350c54"
        )
        let child = AgentProcess(
            pid: 65724,
            parentPID: 65723,
            commandLine: "/Applications/ChatGPT.app/.../codex sandbox trusted-worker.js",
            workingDirectory: mirrorURL,
            provider: .codex,
            sessionIDToken: nil // child lacks session ID token on its command line!
        )

        let nodes = [
            ProcessNode(pid: 65723, parentPID: nil, command: parent.commandLine, executable: "codex"),
            ProcessNode(pid: 65724, parentPID: 65723, command: child.commandLine, executable: "codex")
        ]
        let tree = ProcessTree(nodes: nodes)

        let engine = DefaultSessionCorrelationEngine()
        let resolver = DefaultWorkspaceResolver()

        let sessions = await engine.correlate(
            processes: [parent, child],
            processTree: tree,
            workspaceResolver: resolver
        )

        // Must collapse into EXACTLY 1 logical session instead of 2!
        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.id, "codex-98c95ead7ccd476aae7aa8ba50350c54")
        XCTAssertEqual(session.providerSessionID, "98c95ead7ccd476aae7aa8ba50350c54")
        XCTAssertEqual(session.associatedProcesses.count, 2)
        XCTAssertTrue(session.associatedProcesses.contains(where: { $0.pid == 65723 }))
        XCTAssertTrue(session.associatedProcesses.contains(where: { $0.pid == 65724 }))
    }

    func testWorkspaceResolverUsesCodexDatabaseEvidence() async {
        let sandboxURL = URL(fileURLWithPath: "/Users/developer/.codex/.chatgpt-projects/g-p-6a1c1358a77c8191b1700dd481c5b2b1")
        let roots = [
            CodexProjectRootRecord(
                projectID: "01a0d57a-199c-7260-b5e5-781055502a6f",
                projectName: "Naviik - SmartRemote",
                path: sandboxURL.path
            )
        ]
        let meta = CodexSessionMetadata(
            sessionID: "98c95ead7ccd476aae7aa8ba50350c54",
            projectName: "Naviik - SmartRemote",
            workingDirectory: sandboxURL,
            gitBranch: "main",
            title: "Install skills and build app store"
        )

        let inspector = MockCodexStateStoreInspectorForPipeline(
            roots: roots,
            metadataMap: ["98c95ead7ccd476aae7aa8ba50350c54": meta]
        )
        let evidenceProvider = CodexWorkspaceEvidenceProvider(stateInspector: inspector)
        let resolver = DefaultWorkspaceResolver(evidenceProviders: [evidenceProvider])

        // Process running in VS Code with CWD "/" but with session token
        let vsCodeProcess = AgentProcess(
            pid: 70887,
            commandLine: "codex -c features.code_mode_host=true app-server --stdio",
            workingDirectory: URL(fileURLWithPath: "/"),
            provider: .codex,
            sessionIDToken: "98c95ead7ccd476aae7aa8ba50350c54"
        )

        let resolved = await resolver.resolveWorkspace(for: vsCodeProcess, parent: nil, explicitMetadataURL: nil)

        XCTAssertEqual(resolved.projectName, "Naviik - SmartRemote")
        XCTAssertEqual(resolved.branch, "main")
        XCTAssertTrue(resolved.sourceDescription.contains("codex-state-database"))
    }

    func testSessionCorrelationWithActiveChildWorkerProducesWorkingStateAndSummary() async {
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 1000, parentPID: 1, command: "codex", executable: "/usr/local/bin/codex"),
            ProcessNode(pid: 1001, parentPID: 1000, command: "swift test --filter CoreTests", executable: "/usr/bin/swift")
        ])

        let processes = [
            AgentProcess(pid: 1000, parentPID: 1, executable: "/usr/local/bin/codex", commandLine: "codex", startedAt: Date().addingTimeInterval(-60), provider: .codex),
            AgentProcess(pid: 1001, parentPID: 1000, executable: "/usr/bin/swift", commandLine: "swift test --filter CoreTests", startedAt: Date().addingTimeInterval(-5), provider: .codex)
        ]

        let engine = DefaultSessionCorrelationEngine()
        let resolver = DefaultWorkspaceResolver()
        let sessions = await engine.correlate(processes: processes, processTree: tree, workspaceResolver: resolver)

        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.summary, "Running swift test")
        XCTAssertTrue(session.discoveryEvidence.contains { $0.contains("State: Working") })
        XCTAssertTrue(session.discoveryEvidence.contains { $0.contains("Active worker: PID 1001") })
    }

    func testSessionCorrelationWithLoneProcessProducesWaitingStateAndSummary() async {
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 2000, parentPID: 1, command: "codex --session-id session-lone", executable: "/usr/local/bin/codex")
        ])

        let processes = [
            AgentProcess(pid: 2000, parentPID: 1, executable: "/usr/local/bin/codex", commandLine: "codex --session-id session-lone", startedAt: Date().addingTimeInterval(-120), provider: .codex, sessionIDToken: "session-lone")
        ]

        let engine = DefaultSessionCorrelationEngine()
        let resolver = DefaultWorkspaceResolver()
        let sessions = await engine.correlate(processes: processes, processTree: tree, workspaceResolver: resolver)

        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.summary, "Awaiting user input")
        XCTAssertTrue(session.discoveryEvidence.contains { $0.contains("State: Waiting") })
    }

    func testSessionCorrelationWithRecentLoneProcessProducesStartingState() async {
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 3000, parentPID: 1, command: "codex", executable: "/usr/local/bin/codex")
        ])

        let processes = [
            AgentProcess(pid: 3000, parentPID: 1, executable: "/usr/local/bin/codex", commandLine: "codex", startedAt: Date().addingTimeInterval(-2), provider: .codex)
        ]

        let engine = DefaultSessionCorrelationEngine()
        let resolver = DefaultWorkspaceResolver()
        let sessions = await engine.correlate(processes: processes, processTree: tree, workspaceResolver: resolver)

        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.state, .starting)
        XCTAssertEqual(session.summary, "Starting session")
        XCTAssertTrue(session.discoveryEvidence.contains { $0.contains("State: Starting") })
    }

    func testSessionCorrelationEnrichesSummaryWithThreadTitleFromMetadata() async {
        final class StubStateInspector: CodexStateStoreInspecting, @unchecked Sendable {
            func loadProjectRoots() async -> [CodexProjectRootRecord] { [] }
            func projectName(forPath url: URL) async -> String? { nil }
            func sessionMetadata(for sessionID: String) async -> CodexSessionMetadata? {
                if sessionID == "thread-123" {
                    return CodexSessionMetadata(sessionID: "thread-123", projectName: "Loom", title: "Build payment sheet")
                }
                return nil
            }
        }

        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 4000, parentPID: 1, command: "codex --session-id thread-123", executable: "/usr/local/bin/codex")
        ])

        let processes = [
            AgentProcess(pid: 4000, parentPID: 1, executable: "/usr/local/bin/codex", commandLine: "codex --session-id thread-123", startedAt: Date().addingTimeInterval(-100), provider: .codex, sessionIDToken: "thread-123")
        ]

        let engine = DefaultSessionCorrelationEngine(stateInspector: StubStateInspector())
        let resolver = DefaultWorkspaceResolver()
        let sessions = await engine.correlate(processes: processes, processTree: tree, workspaceResolver: resolver)

        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.summary, "Awaiting input: Build payment sheet")
        XCTAssertTrue(session.discoveryEvidence.contains { $0.contains("Thread topic: Build payment sheet") })
    }

    // MARK: - 6. Correctness Regression Tests (P0/P1)

    func testTwoIndependentProcessesInSameRepoAndHostHaveDistinctSessionIDs() async {
        let repo = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let date = Date().addingTimeInterval(-100)

        let p1 = AgentProcess(
            pid: 7001,
            parentPID: 1,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "codex -C \(repo.path)",
            workingDirectory: repo,
            startedAt: date,
            provider: .codex,
            hostApp: .terminal,
            sessionIDToken: nil
        )
        let p2 = AgentProcess(
            pid: 7002,
            parentPID: 1,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "codex -C \(repo.path)",
            workingDirectory: repo,
            startedAt: date.addingTimeInterval(5),
            provider: .codex,
            hostApp: .terminal,
            sessionIDToken: nil
        )

        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 7001, parentPID: 1, command: p1.commandLine, executable: p1.executable, startedAt: p1.startedAt),
            ProcessNode(pid: 7002, parentPID: 1, command: p2.commandLine, executable: p2.executable, startedAt: p2.startedAt)
        ])

        let gitResolver = MockGitResolverForDiscovery(repoMap: [
            repo: GitRepositoryInfo(rootURL: repo, projectName: "Loom", branch: "main")
        ])
        let resolver = DefaultWorkspaceResolver(gitResolver: gitResolver)
        let engine = DefaultSessionCorrelationEngine()

        let sessions = await engine.correlate(processes: [p1, p2], processTree: tree, workspaceResolver: resolver)

        XCTAssertEqual(sessions.count, 2, "Two independent processes in same repo and host must remain 2 distinct sessions")
        XCTAssertNotEqual(sessions[0].id, sessions[1].id, "Fallback session IDs must not collide")
        XCTAssertTrue(sessions.contains { $0.id.contains("7001") })
        XCTAssertTrue(sessions.contains { $0.id.contains("7002") })
    }

    func testTwoIndependentChildrenOfSameShellRemainSeparate() async {
        let shellPID: pid_t = 8000
        let repo = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")

        let p1 = AgentProcess(
            pid: 8001,
            parentPID: shellPID,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "codex -C \(repo.path)",
            workingDirectory: repo,
            provider: .codex,
            sessionIDToken: nil
        )
        let p2 = AgentProcess(
            pid: 8002,
            parentPID: shellPID,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "codex -C \(repo.path)",
            workingDirectory: repo,
            provider: .codex,
            sessionIDToken: nil
        )

        let tree = ProcessTree(nodes: [
            ProcessNode(pid: shellPID, parentPID: 1, command: "/bin/zsh", executable: "zsh"),
            ProcessNode(pid: 8001, parentPID: shellPID, command: p1.commandLine, executable: p1.executable),
            ProcessNode(pid: 8002, parentPID: shellPID, command: p2.commandLine, executable: p2.executable)
        ])

        let resolver = DefaultWorkspaceResolver()
        let engine = DefaultSessionCorrelationEngine()

        let sessions = await engine.correlate(processes: [p1, p2], processTree: tree, workspaceResolver: resolver)

        XCTAssertEqual(sessions.count, 2, "Sibling processes sharing a parent PID must NOT be merged")
    }

    func testActualParentChildWorkerRelationshipCollapses() async {
        let agentPID: pid_t = 8100
        let workerPID: pid_t = 8101
        let repo = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")

        let agent = AgentProcess(
            pid: agentPID,
            parentPID: 1,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "codex -C \(repo.path)",
            workingDirectory: repo,
            provider: .codex,
            sessionIDToken: nil
        )
        let worker = AgentProcess(
            pid: workerPID,
            parentPID: agentPID,
            executable: "/usr/bin/git",
            commandLine: "git status",
            workingDirectory: repo,
            provider: .codex,
            sessionIDToken: nil
        )

        let tree = ProcessTree(nodes: [
            ProcessNode(pid: agentPID, parentPID: 1, command: agent.commandLine, executable: agent.executable),
            ProcessNode(pid: workerPID, parentPID: agentPID, command: worker.commandLine, executable: worker.executable)
        ])

        let resolver = DefaultWorkspaceResolver()
        let engine = DefaultSessionCorrelationEngine()

        let sessions = await engine.correlate(processes: [agent, worker], processTree: tree, workspaceResolver: resolver)

        XCTAssertEqual(sessions.count, 1, "Child worker process must collapse into parent session")
        XCTAssertEqual(sessions[0].state, .working)
        XCTAssertEqual(sessions[0].associatedProcesses.count, 2)
    }

    func testSharedIDEExtensionHostDoesNotMergeIndependentSessions() async {
        let ideHostPID: pid_t = 9000
        let repoA = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom")
        let repoB = URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/XKit")

        let p1 = AgentProcess(
            pid: 9001,
            parentPID: ideHostPID,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "codex -C \(repoA.path)",
            workingDirectory: repoA,
            provider: .codex,
            hostApp: .vsCode,
            sessionIDToken: nil
        )
        let p2 = AgentProcess(
            pid: 9002,
            parentPID: ideHostPID,
            executable: "/opt/homebrew/bin/codex",
            commandLine: "codex -C \(repoB.path)",
            workingDirectory: repoB,
            provider: .codex,
            hostApp: .vsCode,
            sessionIDToken: nil
        )

        let tree = ProcessTree(nodes: [
            ProcessNode(pid: ideHostPID, parentPID: 1, command: "Code Helper --type=utility", executable: "Code Helper"),
            ProcessNode(pid: 9001, parentPID: ideHostPID, command: p1.commandLine, executable: p1.executable),
            ProcessNode(pid: 9002, parentPID: ideHostPID, command: p2.commandLine, executable: p2.executable)
        ])

        let resolver = DefaultWorkspaceResolver()
        let engine = DefaultSessionCorrelationEngine()

        let sessions = await engine.correlate(processes: [p1, p2], processTree: tree, workspaceResolver: resolver)

        XCTAssertEqual(sessions.count, 2, "Processes sharing an IDE host parent must remain independent")
    }

    func testPromptKeywordsDoNotLeakIntoState() async {
        let tree = ProcessTree(nodes: [
            ProcessNode(pid: 9101, parentPID: 1, command: "codex \"how do I use docker exec?\"", executable: "/usr/local/bin/codex", startedAt: Date().addingTimeInterval(-100)),
            ProcessNode(pid: 9102, parentPID: 1, command: "codex \"prompt user for confirm\"", executable: "/usr/local/bin/codex", startedAt: Date().addingTimeInterval(-100)),
            ProcessNode(pid: 9103, parentPID: 1, command: "codex \"what is sandboxing?\"", executable: "/usr/local/bin/codex", startedAt: Date().addingTimeInterval(-100))
        ])

        let processes = [
            AgentProcess(pid: 9101, parentPID: 1, executable: "/usr/local/bin/codex", commandLine: "codex \"how do I use docker exec?\"", startedAt: Date().addingTimeInterval(-100), provider: .codex),
            AgentProcess(pid: 9102, parentPID: 1, executable: "/usr/local/bin/codex", commandLine: "codex \"prompt user for confirm\"", startedAt: Date().addingTimeInterval(-100), provider: .codex),
            AgentProcess(pid: 9103, parentPID: 1, executable: "/usr/local/bin/codex", commandLine: "codex \"what is sandboxing?\"", startedAt: Date().addingTimeInterval(-100), provider: .codex)
        ]

        let engine = DefaultSessionCorrelationEngine()
        let resolver = DefaultWorkspaceResolver()
        let sessions = await engine.correlate(processes: processes, processTree: tree, workspaceResolver: resolver)

        XCTAssertEqual(sessions.count, 3)

        // All 3 sessions must be .unknown, NOT fake .working or .waiting!
        for session in sessions {
            XCTAssertEqual(session.state, .unknown, "Prompt keywords ('exec', 'confirm', 'sandbox') must not leak into session state: \(session.summary ?? "")")
        }
    }
}


