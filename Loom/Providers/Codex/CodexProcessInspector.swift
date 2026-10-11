//
//  CodexProcessInspector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

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
    func discoverProcesses() async throws -> (processes: [AgentProcess], processTree: ProcessTree)
}

extension CodexProcessDiscovering {
    public func discoverProcesses() async throws -> (processes: [AgentProcess], processTree: ProcessTree) {
        let legacy = try await findRunningProcesses()
        let nodes = legacy.map {
            ProcessNode(
                pid: $0.pid,
                parentPID: nil,
                command: $0.command,
                executable: $0.command,
                startedAt: $0.startedAt
            )
        }
        let tree = ProcessTree(nodes: nodes)
        let agentProcesses = legacy.map {
            AgentProcess(
                pid: $0.pid,
                parentPID: nil,
                executable: $0.command,
                commandLine: $0.command,
                workingDirectory: $0.workingDirectory,
                startedAt: $0.startedAt,
                provider: .codex,
                hostApp: nil,
                sessionIDToken: ProcessTree.extractSessionIDToken(from: $0.command)
            )
        }
        return (processes: agentProcesses, processTree: tree)
    }
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
