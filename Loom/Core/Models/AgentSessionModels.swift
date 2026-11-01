//
//  AgentSessionModels.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation

public enum AgentProviderKind: String, Codable, Sendable, CaseIterable {
    case t3Code = "t3code"
    case codex = "codex"
    case claudeCode = "claude_code"
    case antigravity = "antigravity"
}

public enum AgentSurface: String, Codable, Sendable {
    case cli = "CLI"
    case gui = "GUI"
    case t3Orchestrated = "T3Code"
}

public enum AgentRunState: String, Codable, Sendable {
    case working           // Actively streaming or running a tool
    case awaitingApproval  // Blocked on user permission / question
    case idle              // Process alive, waiting for next user prompt
    case inactive          // Process exited, recent historical session
}

public struct TokenUsageSnapshot: Sendable, Equatable, Codable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningTokens: Int

    public var totalTokens: Int {
        inputTokens + cachedInputTokens + outputTokens + reasoningTokens
    }

    public init(
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
    }
}

public struct AgentSessionStatus: Identifiable, Sendable, Equatable {
    public let id: String                  // Session UUID or "pid-<pid>"
    public let provider: AgentProviderKind
    public let surface: AgentSurface
    public let pid: pid_t?
    public let parentT3PID: pid_t?         // Non-nil if spawned by T3Code
    public let projectName: String         // Last path component of cwd
    public let workspacePath: String?      // Full cwd
    public let gitBranch: String?
    public let modelName: String?
    public let state: AgentRunState
    public let tokenUsage: TokenUsageSnapshot?
    public let lastUpdated: Date

    public init(
        id: String,
        provider: AgentProviderKind,
        surface: AgentSurface,
        pid: pid_t? = nil,
        parentT3PID: pid_t? = nil,
        projectName: String,
        workspacePath: String? = nil,
        gitBranch: String? = nil,
        modelName: String? = nil,
        state: AgentRunState,
        tokenUsage: TokenUsageSnapshot? = nil,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.surface = surface
        self.pid = pid
        self.parentT3PID = parentT3PID
        self.projectName = projectName
        self.workspacePath = workspacePath
        self.gitBranch = gitBranch
        self.modelName = modelName
        self.state = state
        self.tokenUsage = tokenUsage
        self.lastUpdated = lastUpdated
    }
}
