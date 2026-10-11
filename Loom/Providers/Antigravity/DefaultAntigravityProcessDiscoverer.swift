//
//  DefaultAntigravityProcessDiscoverer.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public final class DefaultAntigravityProcessDiscoverer: AntigravityProcessDiscovering, Sendable {
    private let executor: any ProcessExecuting
    private let psPath: String
    private let lsofPath: String

    public init(
        executor: any ProcessExecuting = DefaultProcessExecutor(),
        psPath: String = "/bin/ps",
        lsofPath: String = "/usr/sbin/lsof"
    ) {
        self.executor = executor
        self.psPath = psPath
        self.lsofPath = lsofPath
    }

    public func isAntigravityRunning() async -> Bool {
        let psOutput: String
        do {
            psOutput = try await executor.execute(
                executablePath: psPath,
                arguments: ["-ax", "-o", "command="]
            )
        } catch {
            return false
        }

        let lines = psOutput.components(separatedBy: .newlines)
        for line in lines {
            if AntigravityParser.isAntigravityProcessCommand(line) {
                return true
            }
        }

        return false
    }

    public func discoverProcesses() async -> [AgentProcess] {
        let psOutput: String
        do {
            psOutput = try await executor.execute(
                executablePath: psPath,
                arguments: ["-ax", "-o", "pid=,ppid=,lstart=,command="]
            )
        } catch {
            return []
        }

        let nodes = ProcessTree.parsePsOutput(psOutput)
        let tree = ProcessTree(nodes: nodes)

        var antigravityProcesses: [AgentProcess] = []
        for node in nodes {
            if AntigravityParser.isAntigravityProcessCommand(node.command) {
                let hostApp = tree.resolveHostApp(for: node.pid) ?? .antigravity
                let sessionToken = ProcessTree.extractSessionIDToken(from: node.command)

                var cwd: URL? = nil
                if let lsofOutput = try? await executor.execute(
                    executablePath: lsofPath,
                    arguments: ["-a", "-p", "\(node.pid)", "-d", "cwd", "-Fn"]
                ) {
                    cwd = CodexParser.parseLsofCwdOutput(lsofOutput)
                }
                if cwd == nil {
                    cwd = CodexParser.extractWorkspaceDirectory(from: node.command)
                }

                antigravityProcesses.append(AgentProcess(
                    pid: node.pid,
                    parentPID: node.parentPID,
                    executable: node.executable,
                    commandLine: node.command,
                    workingDirectory: cwd,
                    startedAt: node.startedAt,
                    provider: .antigravity,
                    hostApp: hostApp,
                    sessionIDToken: sessionToken
                ))
            }
        }

        return antigravityProcesses
    }
}
