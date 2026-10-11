//
//  AgentProcess.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public enum HostApp: Hashable, Equatable, Sendable {
    case vsCode
    case cursor
    case xcode
    case terminal
    case chatGPT
    case antigravity
    case custom(String)

    public var displayName: String {
        switch self {
        case .vsCode: return "VS Code"
        case .cursor: return "Cursor"
        case .xcode: return "Xcode"
        case .terminal: return "Terminal"
        case .chatGPT: return "ChatGPT"
        case .antigravity: return "Antigravity"
        case .custom(let name): return name
        }
    }
}

public struct AgentProcess: Identifiable, Hashable, Equatable, Sendable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let parentPID: pid_t?
    public let executable: String
    public let commandLine: String
    public let workingDirectory: URL?
    public let startedAt: Date?
    public let provider: ProviderID
    public let hostApp: HostApp?
    public let sessionIDToken: String?

    public init(
        pid: pid_t,
        parentPID: pid_t? = nil,
        executable: String = "",
        commandLine: String,
        workingDirectory: URL? = nil,
        startedAt: Date? = nil,
        provider: ProviderID,
        hostApp: HostApp? = nil,
        sessionIDToken: String? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.executable = executable
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
        self.provider = provider
        self.hostApp = hostApp
        self.sessionIDToken = sessionIDToken
    }
}
