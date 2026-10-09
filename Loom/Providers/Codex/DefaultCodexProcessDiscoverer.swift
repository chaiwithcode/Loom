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

    public func findRunningProcesses() async throws -> [CodexProcessInfo] {
        // 1. Query running processes via /bin/ps; propagate actionable discovery errors
        let psOutput = try await executor.execute(
            executablePath: psPath,
            arguments: ["-ax", "-o", "pid=,lstart=,command="]
        )

        let parsedProcesses = CodexParser.parsePsOutput(psOutput)
        guard !parsedProcesses.isEmpty else {
            return []
        }

        // 2. For each identified Codex process, resolve its working directory via lsof
        var results: [CodexProcessInfo] = []
        for item in parsedProcesses {
            var cwd: URL? = nil
            if let lsofOutput = try? await executor.execute(
                executablePath: lsofPath,
                arguments: ["-a", "-p", "\(item.pid)", "-d", "cwd", "-Fn"]
            ) {
                cwd = CodexParser.parseLsofCwdOutput(lsofOutput)
            }

            results.append(CodexProcessInfo(
                pid: item.pid,
                command: item.command,
                workingDirectory: cwd,
                startedAt: item.startedAt
            ))
        }

        return results
    }
}
