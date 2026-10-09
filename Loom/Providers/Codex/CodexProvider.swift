import Foundation

public final class CodexProvider: AgentProvider, Sendable {
    public let id: ProviderID = .codex
    public let displayName: String = "Codex"

    private let processDiscoverer: any CodexProcessDiscovering
    private let gitResolver: any GitRepositoryResolving
    private let usageFetcher: any CodexUsageFetching

    public init(
        processDiscoverer: any CodexProcessDiscovering = DefaultCodexProcessDiscoverer(),
        gitResolver: any GitRepositoryResolving = DefaultGitRepositoryResolver(),
        usageFetcher: any CodexUsageFetching = DefaultCodexUsageFetcher()
    ) {
        self.processDiscoverer = processDiscoverer
        self.gitResolver = gitResolver
        self.usageFetcher = usageFetcher
    }

    public func availability() async -> ProviderAvailability {
        // As long as the provider can run process discovery, it is available.
        return .available
    }

    public func fetchUsage() async throws -> ProviderUsageSnapshot? {
        return try await usageFetcher.fetchUsage()
    }

    public func discoverSessions() async throws -> [AgentSession] {
        let processes = try await processDiscoverer.findRunningProcesses()
        guard !processes.isEmpty else {
            return []
        }

        var sessions: [AgentSession] = []

        for process in processes {
            // Determine effective working directory: fallback to extracted workspace if cwd is nil or root '/'
            var effectiveDir = process.workingDirectory
            if effectiveDir == nil || effectiveDir?.path == "/" {
                if let detected = CodexParser.extractWorkspaceDirectory(from: process.command) {
                    effectiveDir = detected
                }
            }

            var projectName: String? = nil
            var projectPath: URL? = nil
            var branch: String? = nil

            if let cwd = effectiveDir, cwd.path != "/" {
                if let gitInfo = await gitResolver.resolveRepository(for: cwd) {
                    projectName = gitInfo.projectName
                    projectPath = gitInfo.rootURL
                    branch = gitInfo.branch
                } else {
                    let name = cwd.lastPathComponent
                    projectName = name.isEmpty ? "Codex Session" : name
                    projectPath = cwd
                    branch = nil
                }
            } else {
                projectName = "Codex Session"
                projectPath = nil
                branch = nil
            }

            let session = AgentSession(
                id: "codex-\(process.pid)",
                provider: .codex,
                projectName: projectName,
                projectPath: projectPath,
                state: .unknown,
                startedAt: process.startedAt,
                lastActivityAt: nil,
                branch: branch,
                summary: nil,
                pid: Int(process.pid)
            )
            sessions.append(session)
        }

        return sessions
    }
}
