//
//  DefaultCodexProcessDiscoverer.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public protocol ProcessExecuting: Sendable {
    func execute(executablePath: String, arguments: [String]) async throws -> String
}

public final class DefaultProcessExecutor: ProcessExecuting, Sendable {
    public init() {}

    public func execute(executablePath: String, arguments: [String]) async throws -> String {
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else {
                return ""
            }
            return output
        }.value
    }
}

public final class DefaultCodexProcessDiscoverer: CodexProcessDiscovering, Sendable {
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

    public func discoverProcesses() async throws -> (processes: [AgentProcess], processTree: ProcessTree) {
        // 1. Query running processes via /bin/ps with resilient error handling (e.g. sandbox EPERM)
        let psOutput: String
        do {
            psOutput = try await executor.execute(
                executablePath: psPath,
                arguments: ["-ax", "-o", "pid=,ppid=,lstart=,command="]
            )
        } catch let posixError as POSIXError where posixError.code == .EPERM {
            return (processes: [], processTree: ProcessTree(nodes: []))
        } catch let nsError as NSError where nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EPERM) {
            return (processes: [], processTree: ProcessTree(nodes: []))
        }

        let nodes = ProcessTree.parsePsOutput(psOutput)
        let tree = ProcessTree(nodes: nodes)

        var matchedProcesses: [AgentProcess] = []

        for node in nodes {
            guard CodexParser.isCodexCommand(node.command) else {
                continue
            }

            var cwd: URL? = nil
            if let lsofOutput = try? await executor.execute(
                executablePath: lsofPath,
                arguments: ["-a", "-p", "\(node.pid)", "-d", "cwd", "-Fn"]
            ) {
                cwd = CodexParser.parseLsofCwdOutput(lsofOutput)
            }

            let hostApp = tree.resolveHostApp(for: node.pid)
            let sessionToken = ProcessTree.extractSessionIDToken(from: node.command)

            matchedProcesses.append(AgentProcess(
                pid: node.pid,
                parentPID: node.parentPID,
                executable: node.executable,
                commandLine: node.command,
                workingDirectory: cwd,
                startedAt: node.startedAt,
                provider: .codex,
                hostApp: hostApp,
                sessionIDToken: sessionToken
            ))
        }

        return (processes: matchedProcesses, processTree: tree)
    }

    public func findRunningProcesses() async throws -> [CodexProcessInfo] {
        let (processes, _) = try await discoverProcesses()
        return processes.map {
            CodexProcessInfo(
                pid: $0.pid,
                command: $0.commandLine,
                workingDirectory: $0.workingDirectory,
                startedAt: $0.startedAt
            )
        }
    }
}
