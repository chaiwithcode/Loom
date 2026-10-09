//
//  CodexUsageFetcher.swift
//  Loom
//
//  Created by Deepak Sharma on 03/10/2026.
//  Copyright © 2026 ChaiWithCode. All rights reserved.
//

import Darwin
import Foundation
import os

public protocol CodexUsageFetching: Sendable {
    func fetchUsage() async throws -> ProviderUsageSnapshot?
}

public protocol CodexAppServerTransporting: Sendable {
    func execute(executableURL: URL, timeoutSeconds: TimeInterval) async throws -> ProviderUsageSnapshot?
}

public enum CodexUsageError: LocalizedError, Sendable {
    case executableNotFound
    case timeout
    case responseTooLarge
    case processFailed(String)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Codex CLI executable not found"
        case .timeout:
            return "Codex app-server request timed out"
        case .responseTooLarge:
            return "Codex app-server response exceeded maximum allowed buffer size"
        case .processFailed(let msg):
            return "Codex app-server failed: \(msg)"
        case .malformedResponse:
            return "Malformed Codex rate-limits response"
        }
    }
}

public final class SubprocessController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false
    private var isTerminated = false

    public init() {}

    public var isTerminatedOrCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled || isTerminated
    }

    public func launch(process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled || isTerminated {
            throw CancellationError()
        }
        self.process = process
        try process.run()
    }

    public func terminateAndReap() {
        lock.lock()
        isCancelled = true
        guard !isTerminated else {
            lock.unlock()
            return
        }
        isTerminated = true
        guard let p = process, p.isRunning else {
            lock.unlock()
            return
        }
        let pid = p.processIdentifier
        lock.unlock()

        guard pid > 0 else {
            if p.isRunning { p.terminate() }
            return
        }

        // Graceful SIGTERM to process and process group
        kill(pid, SIGTERM)
        kill(-pid, SIGTERM)

        // Poll for up to 200ms
        for _ in 0..<10 {
            if !p.isRunning || kill(pid, 0) != 0 {
                p.waitUntilExit()
                return
            }
            usleep(20_000)
        }

        // Escalate to SIGKILL if child is resistant to SIGTERM
        if p.isRunning || kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
            kill(-pid, SIGKILL)
        }

        p.waitUntilExit()
    }
}

public final class DefaultCodexAppServerTransport: CodexAppServerTransporting, Sendable {
    private let maxBufferSize: Int = 1024 * 1024 // 1 MB buffer limit

    public init() {}

    public func execute(executableURL: URL, timeoutSeconds: TimeInterval) async throws -> ProviderUsageSnapshot? {
        try Task.checkCancellation()

        let controller = SubprocessController()
        let timedOut = OSAllocatedUnfairLock(initialState: false)

        do {
            return try await withThrowingTaskGroup(of: ProviderUsageSnapshot?.self) { group in
                group.addTask {
                    return try await self.runSubprocess(executableURL: executableURL, controller: controller)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    timedOut.withLock { $0 = true }
                    controller.terminateAndReap()
                    throw CodexUsageError.timeout
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch is CancellationError {
            if timedOut.withLock({ $0 }) {
                throw CodexUsageError.timeout
            }
            throw CancellationError()
        }
    }

    private func runSubprocess(executableURL: URL, controller: SubprocessController) async throws -> ProviderUsageSnapshot? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdinHandle = stdinPipe.fileHandleForWriting

        // On Darwin, set F_SETNOSIGPIPE on stdin pipe write descriptor so writes after child exit
        // return -1 with errno == EPIPE rather than raising an unhandled terminating SIGPIPE signal.
        _ = fcntl(stdinHandle.fileDescriptor, F_SETNOSIGPIPE, 1)

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()

            // Asynchronously drain stderr in fixed chunks; stderrQueue is the single cleanup owner of stderrHandle
            let stderrFd = stderrHandle.fileDescriptor
            let stderrQueue = DispatchQueue(label: "com.loom.codex.stderr", qos: .utility)
            stderrQueue.async {
                var buf = [UInt8](repeating: 0, count: 4096)
                while true {
                    let bytesRead = Darwin.read(stderrFd, &buf, buf.count)
                    if bytesRead <= 0 {
                        break
                    }
                }
                try? stderrHandle.close()
            }

            try controller.launch(process: process)

            defer {
                controller.terminateAndReap()
                try? stdinHandle.close()
                try? stdoutHandle.close()
            }

            let stdoutFd = stdoutHandle.fileDescriptor
            var buffer = Data()

            // Step 1: Send initialize request
            let initRequest: [String: Any] = [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "Loom",
                        "version": "0.1.0"
                    ],
                    "capabilities": [
                        "experimentalApi": false
                    ]
                ]
            ]
            let initData = try JSONSerialization.data(withJSONObject: initRequest)
            try stdinHandle.write(contentsOf: initData)
            try stdinHandle.write(contentsOf: Data([0x0A])) // newline

            // Read lines until id 1 (initialize) response is received
            var initializedSuccessfully = false
            while !initializedSuccessfully {
                try Task.checkCancellation()
                guard let line = try readNextLine(fd: stdoutFd, buffer: &buffer, controller: controller) else {
                    try Task.checkCancellation()
                    if controller.isTerminatedOrCancelled {
                        throw CancellationError()
                    }
                    throw CodexUsageError.processFailed("Process terminated before initialize response")
                }

                if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let id = json["id"] as? Int, id == 1 {
                    if json["error"] != nil {
                        throw CodexUsageError.processFailed("Codex app-server rejected initialize")
                    }
                    initializedSuccessfully = true
                }
            }

            // Step 2: Send initialized notification
            let initializedNotif: [String: Any] = ["method": "initialized"]
            let notifData = try JSONSerialization.data(withJSONObject: initializedNotif)
            try stdinHandle.write(contentsOf: notifData)
            try stdinHandle.write(contentsOf: Data([0x0A]))

            // Step 3: Send rateLimits request
            let rateLimitsRequest: [String: Any] = [
                "id": 2,
                "method": "account/rateLimits/read"
            ]
            let rateData = try JSONSerialization.data(withJSONObject: rateLimitsRequest)
            try stdinHandle.write(contentsOf: rateData)
            try stdinHandle.write(contentsOf: Data([0x0A]))

            // Read lines until id 2 (rateLimits) response is received
            while true {
                try Task.checkCancellation()
                guard let line = try readNextLine(fd: stdoutFd, buffer: &buffer, controller: controller) else {
                    try Task.checkCancellation()
                    if controller.isTerminatedOrCancelled {
                        throw CancellationError()
                    }
                    throw CodexUsageError.malformedResponse
                }

                if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let id = json["id"] as? Int, id == 2 {
                    if let errorObj = json["error"] as? [String: Any], let msg = errorObj["message"] as? String {
                        throw CodexUsageError.processFailed(msg)
                    }
                    return CodexUsageParser.parseRateLimits(from: json)
                }
            }
        } onCancel: {
            controller.terminateAndReap()
        }
    }

    private func readNextLine(fd: Int32, buffer: inout Data, controller: SubprocessController) throws -> Data? {
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: 0..<newlineIndex)
                buffer.removeSubrange(0...newlineIndex)
                return lineData
            }

            if controller.isTerminatedOrCancelled {
                throw CancellationError()
            }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let pollResult = poll(&pfd, 1, 100) // 100ms poll timeout for responsive cancellation checks

            if pollResult < 0 {
                let err = errno
                if err == EINTR {
                    continue
                }
                throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
            } else if pollResult == 0 {
                // Poll timed out; loop to recheck cancellation
                continue
            }

            let bytesRead = Darwin.read(fd, &buf, buf.count)
            if bytesRead > 0 {
                if buffer.count + bytesRead > maxBufferSize {
                    throw CodexUsageError.responseTooLarge
                }
                buffer.append(buf, count: bytesRead)
            } else if bytesRead == 0 {
                // EOF on pipe
                if buffer.isEmpty {
                    return nil
                }
                let lineData = buffer
                buffer.removeAll()
                return lineData
            } else {
                let err = errno
                if err == EINTR || err == EAGAIN {
                    continue
                }
                throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
            }
        }
    }
}

public final class DefaultCodexUsageFetcher: CodexUsageFetching, Sendable {
    private let explicitExecutableURL: URL?
    private let timeoutSeconds: TimeInterval
    private let transport: any CodexAppServerTransporting

    public init(
        explicitExecutableURL: URL? = nil,
        timeoutSeconds: TimeInterval = 5.0,
        transport: any CodexAppServerTransporting = DefaultCodexAppServerTransport()
    ) {
        self.explicitExecutableURL = explicitExecutableURL
        self.timeoutSeconds = timeoutSeconds
        self.transport = transport
    }

    public func fetchUsage() async throws -> ProviderUsageSnapshot? {
        try Task.checkCancellation()

        guard let binaryURL = resolveCodexExecutable() else {
            throw CodexUsageError.executableNotFound
        }

        return try await transport.execute(executableURL: binaryURL, timeoutSeconds: timeoutSeconds)
    }

    private func resolveCodexExecutable() -> URL? {
        if let explicit = explicitExecutableURL, FileManager.default.isExecutableFile(atPath: explicit.path) {
            return explicit
        }

        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // Check PATH environment variable
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = String(dir) + "/codex"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }

        return nil
    }
}
