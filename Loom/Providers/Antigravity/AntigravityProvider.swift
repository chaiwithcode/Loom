import Foundation

public final class AntigravityProvider: AgentProvider, Sendable {
    public let id: ProviderID = .antigravity
    public let displayName: String = "Antigravity"

    private let processDiscoverer: any AntigravityProcessDiscovering
    private let storeInspector: any AntigravityStoreInspecting
    private let gitResolver: any GitRepositoryResolving

    public init(
        processDiscoverer: any AntigravityProcessDiscovering = DefaultAntigravityProcessDiscoverer(),
        storeInspector: any AntigravityStoreInspecting = DefaultAntigravityStoreInspector(),
        gitResolver: any GitRepositoryResolving = DefaultGitRepositoryResolver()
    ) {
        self.processDiscoverer = processDiscoverer
        self.storeInspector = storeInspector
        self.gitResolver = gitResolver
    }

    public func availability() async -> ProviderAvailability {
        return .available
    }

    public func discoverSessions() async throws -> [AgentSession] {
        // 1. Process liveness gate: if Antigravity is not running, return [] cleanly
        guard await processDiscoverer.isAntigravityRunning() else {
            return []
        }

        // 2. Fetch active sessions from the local store
        let records = try await storeInspector.fetchActiveSessions()
        guard !records.isEmpty else {
            return []
        }

        var sessions: [AgentSession] = []
        var seenConversationIds: Set<String> = []

        for record in records {
            guard !seenConversationIds.contains(record.conversationId) else {
                continue
            }
            seenConversationIds.insert(record.conversationId)

            guard AntigravityParser.isActiveSession(
                status: record.status,
                notFullyIdle: record.notFullyIdle,
                killed: record.killed
            ) else {
                continue
            }

            var projectName: String? = nil
            var projectPath: URL? = nil
            var branch: String? = nil

            let workspaceURLs = AntigravityParser.parseWorkspaceURLs(from: record.workspaceURIsJSON)
            if let primaryURL = workspaceURLs.first {
                if let gitInfo = await gitResolver.resolveRepository(for: primaryURL) {
                    projectName = gitInfo.projectName
                    projectPath = gitInfo.rootURL
                    branch = gitInfo.branch
                } else {
                    projectName = primaryURL.lastPathComponent.isEmpty ? primaryURL.path : primaryURL.lastPathComponent
                    projectPath = primaryURL
                    branch = nil
                }
            } else {
                projectName = "Antigravity Session"
                projectPath = nil
                branch = nil
            }

            let startedAt = AntigravityParser.parseDate(from: record.lastUserInputTime)
            let lastActivityAt = AntigravityParser.parseDate(from: record.lastModifiedTime) ?? startedAt ?? Date()
            let cleanTitle = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = cleanTitle.isEmpty ? "Active Antigravity session" : cleanTitle

            let session = AgentSession(
                id: "antigravity-\(record.conversationId)",
                provider: .antigravity,
                projectName: projectName,
                projectPath: projectPath,
                state: .working,
                startedAt: startedAt,
                lastActivityAt: lastActivityAt,
                branch: branch,
                summary: summary
            )
            sessions.append(session)
        }

        return sessions
    }
}
