import Foundation

public final class CodexProvider: AgentProvider, Sendable {
    public let id: ProviderID = .codex
    public let displayName: String = "Codex"

    private let processDiscoverer: any CodexProcessDiscovering
    private let gitResolver: any GitRepositoryResolving

    public init(
        processDiscoverer: any CodexProcessDiscovering = DefaultCodexProcessDiscoverer(),
        gitResolver: any GitRepositoryResolving = DefaultGitRepositoryResolver()
    ) {
        self.processDiscoverer = processDiscoverer
        self.gitResolver = gitResolver
    }

    public func availability() async -> ProviderAvailability {
        // As long as the provider can run process discovery, it is available.
        return .available
    }

    public func discoverSessions() async throws -> [AgentSession] {
        let processes = try await processDiscoverer.findRunningProcesses()
        guard !processes.isEmpty else {
            return []
        }

        var sessions: [AgentSession] = []

        for process in processes {
            var projectName: String? = nil
            var projectPath: URL? = nil
            var branch: String? = nil

            if let cwd = process.workingDirectory {
                if let gitInfo = await gitResolver.resolveRepository(for: cwd) {
                    projectName = gitInfo.projectName
                    projectPath = gitInfo.rootURL
                    branch = gitInfo.branch
                } else {
                    projectName = cwd.lastPathComponent.isEmpty ? cwd.path : cwd.lastPathComponent
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
                state: .working,
                startedAt: process.startedAt,
                lastActivityAt: process.startedAt ?? Date(),
                branch: branch,
                summary: "Active Codex session (PID \(process.pid))"
            )
            sessions.append(session)
        }

        return sessions
    }
}
