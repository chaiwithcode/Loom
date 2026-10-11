//
//  AgentSession.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

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
    public let providerSessionID: String?
    public let associatedProcesses: [AgentProcess]
    public let hostApp: HostApp?
    public let diagnostics: ProviderDiscoveryDiagnostics?
    public let discoveryEvidence: [String]

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
        pid: Int? = nil,
        providerSessionID: String? = nil,
        associatedProcesses: [AgentProcess] = [],
        hostApp: HostApp? = nil,
        diagnostics: ProviderDiscoveryDiagnostics? = nil,
        discoveryEvidence: [String] = []
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
        self.providerSessionID = providerSessionID
        self.associatedProcesses = associatedProcesses
        self.hostApp = hostApp
        self.diagnostics = diagnostics
        self.discoveryEvidence = discoveryEvidence
    }

    public var providerQualifiedId: String {
        "\(provider.rawValue):\(id)"
    }

    public var formattedProjectPath: String? {
        guard let path = projectPath?.path else { return nil }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    public var processCount: Int {
        if !associatedProcesses.isEmpty {
            return associatedProcesses.count
        }
        return pid != nil ? 1 : 0
    }
}
