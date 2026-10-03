import Foundation

public struct CodexProcessInfo: Identifiable, Hashable, Equatable, Sendable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let command: String
    public let workingDirectory: URL?
    public let startedAt: Date?

    public init(
        pid: pid_t,
        command: String,
        workingDirectory: URL? = nil,
        startedAt: Date? = nil
    ) {
        self.pid = pid
        self.command = command
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
    }
}

public protocol CodexProcessDiscovering: Sendable {
    func findRunningProcesses() async throws -> [CodexProcessInfo]
}

public struct GitRepositoryInfo: Hashable, Equatable, Sendable {
    public let rootURL: URL
    public let projectName: String
    public let branch: String?

    public init(
        rootURL: URL,
        projectName: String,
        branch: String? = nil
    ) {
        self.rootURL = rootURL
        self.projectName = projectName
        self.branch = branch
    }
}

public protocol GitRepositoryResolving: Sendable {
    func resolveRepository(for directoryURL: URL) async -> GitRepositoryInfo?
}
