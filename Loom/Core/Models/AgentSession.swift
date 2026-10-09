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
    public let pid: Int?

    public init(
        id: String,
        provider: ProviderID,
        projectName: String? = nil,
        projectPath: URL? = nil,
        state: AgentState,
        startedAt: Date? = nil,
        lastActivityAt: Date? = nil,
        branch: String? = nil,
        summary: String? = nil,
        pid: Int? = nil
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
        self.pid = pid
    }

    public var providerQualifiedId: String {
        "\(provider.rawValue):\(id)"
    }
}
