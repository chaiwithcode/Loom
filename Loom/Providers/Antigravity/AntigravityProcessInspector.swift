//
//  AntigravityProcessInspector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct AntigravitySessionRecord: Hashable, Equatable, Sendable {
    public let conversationId: String
    public let title: String
    public let workspaceURIsJSON: String
    public let status: String
    public let notFullyIdle: Bool
    public let killed: Bool
    public let lastUserInputTime: String
    public let lastModifiedTime: String

    public init(
        conversationId: String,
        title: String,
        workspaceURIsJSON: String,
        status: String,
        notFullyIdle: Bool,
        killed: Bool,
        lastUserInputTime: String = "",
        lastModifiedTime: String = ""
    ) {
        self.conversationId = conversationId
        self.title = title
        self.workspaceURIsJSON = workspaceURIsJSON
        self.status = status
        self.notFullyIdle = notFullyIdle
        self.killed = killed
        self.lastUserInputTime = lastUserInputTime
        self.lastModifiedTime = lastModifiedTime
    }
}

public protocol AntigravityStoreInspecting: Sendable {
    func fetchActiveSessions() async throws -> [AntigravitySessionRecord]
}

public protocol AntigravityProcessDiscovering: Sendable {
    func isAntigravityRunning() async -> Bool
    func discoverProcesses() async -> [AgentProcess]
}

extension AntigravityProcessDiscovering {
    public func discoverProcesses() async -> [AgentProcess] {
        return []
    }
}
