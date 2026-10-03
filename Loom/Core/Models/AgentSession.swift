import Foundation

public struct AgentSession: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let provider: ProviderID
    public let projectName: String?
    public let projectPath: URL?
    public let state: AgentState
    public let startedAt: Date?
    public let lastActivityAt: Date?
    public let branch: String?
    public let summary: String?

    public init(
        id: String,
        provider: ProviderID,
        projectName: String? = nil,
        projectPath: URL? = nil,
        state: AgentState,
        startedAt: Date? = nil,
        lastActivityAt: Date? = nil,
        branch: String? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.projectName = projectName
        self.projectPath = projectPath
        self.state = state
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.branch = branch
        self.summary = summary
    }
}
