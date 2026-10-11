//
//  ClaudeProcessInspector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct ClaudeProcessInfo: Identifiable, Hashable, Equatable, Sendable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let parentPID: pid_t?
    public let command: String
    public let workingDirectory: URL?
    public let startedAt: Date?

    public init(
        pid: pid_t,
        parentPID: pid_t? = nil,
        command: String,
        workingDirectory: URL? = nil,
        startedAt: Date? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
    }
}

public protocol ClaudeProcessDiscovering: Sendable {
    func isClaudeInstalled() async -> Bool
    func discoverProcesses() async throws -> (processes: [AgentProcess], processTree: ProcessTree)
}

public final class DefaultClaudeProcessDiscoverer: ClaudeProcessDiscovering, Sendable {
    private let executor: any ProcessExecuting
    private let psPath: String
    private let lsofPath: String
    private let fileSystem: any FileSystemInspecting

    public init(
        executor: any ProcessExecuting = DefaultProcessExecutor(),
        fileSystem: any FileSystemInspecting = DefaultFileSystemInspector(),
        psPath: String = "/bin/ps",
        lsofPath: String = "/usr/sbin/lsof"
    ) {
        self.executor = executor
        self.fileSystem = fileSystem
        self.psPath = psPath
        self.lsofPath = lsofPath
    }

    public func isClaudeInstalled() async -> Bool {
        let commonPaths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        ]
        for path in commonPaths {
            if fileSystem.fileExists(atPath: path, isDirectory: nil) {
                return true
            }
        }
        if let which = try? await executor.execute(executablePath: "/usr/bin/which", arguments: ["claude"]),
           !which.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    public func discoverProcesses() async throws -> (processes: [AgentProcess], processTree: ProcessTree) {
        let psOutput: String
        do {
            psOutput = try await executor.execute(
                executablePath: psPath,
                arguments: ["-ax", "-o", "pid=,ppid=,lstart=,command="]
            )
        } catch {
            return (processes: [], processTree: ProcessTree(nodes: []))
        }

        let nodes = ProcessTree.parsePsOutput(psOutput)
        let tree = ProcessTree(nodes: nodes)

        var matchedProcesses: [AgentProcess] = []

        for node in nodes {
            guard ClaudeParser.isClaudeCommand(node.command) else {
                continue
            }

            var cwd: URL? = nil
            if let lsofOutput = try? await executor.execute(
                executablePath: lsofPath,
                arguments: ["-a", "-p", "\(node.pid)", "-d", "cwd", "-Fn"]
            ) {
                cwd = ClaudeParser.parseLsofCwdOutput(lsofOutput)
            }

            let hostApp = tree.resolveHostApp(for: node.pid)
            let sessionToken = ClaudeParser.extractSessionIDToken(from: node.command)
                ?? ProcessTree.extractSessionIDToken(from: node.command)

            matchedProcesses.append(AgentProcess(
                pid: node.pid,
                parentPID: node.parentPID,
                executable: node.executable,
                commandLine: node.command,
                workingDirectory: cwd,
                startedAt: node.startedAt,
                provider: .claude,
                hostApp: hostApp,
                sessionIDToken: sessionToken
            ))
        }

        return (processes: matchedProcesses, processTree: tree)
    }
}
