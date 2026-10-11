//
//  CodexUsageFetcher.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
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
    private var pid: pid_t = 0
    private var isCancelled = false
    private var isTerminated = false
    private var cleanupStarted = false
    private var cleanupError: (any Error)?
    private let exitSemaphore = DispatchSemaphore(value: 0)
    private let cleanupGroup = DispatchGroup()
    private let cleanupQueue = DispatchQueue(label: "com.loom.codex.subprocess-cleanup", qos: .userInitiated)

    public init() {}

    public var isTerminatedOrCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled || isTerminated
    }

    public var isCancelledOnly: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    public var retainedCleanupError: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return cleanupError
    }

    public func launch(process: Process) throws {
        lock.lock()
        if isCancelled || isTerminated || cleanupStarted {
            lock.unlock()
            throw CancellationError()
        }

        // Register terminationHandler BEFORE process.run so no exit event can ever be lost.
        // Foundation remains the sole child-reaper; when terminationHandler fires,
        // Foundation has reaped the process and its exit state is captured.
        process.terminationHandler = { [weak self] _ in
            guard let self = self else { return }
            self.lock.lock()
            self.isTerminated = true
            self.lock.unlock()
            self.exitSemaphore.signal()
        }

        self.process = process
        do {
            try process.run()
            self.pid = process.processIdentifier
            lock.unlock()
        } catch {
            self.process = nil
            self.isTerminated = true
            lock.unlock()
            throw error
        }
    }

    public func cancel() {
        lock.lock()
        isCancelled = true
        guard !cleanupStarted else {
            lock.unlock()
            return
        }
        cleanupStarted = true
        guard let p = process else {
            isTerminated = true
            lock.unlock()
            return
        }
        let capturedPid = self.pid
        let alreadyTerminated = self.isTerminated
        cleanupGroup.enter()
        lock.unlock()

        cleanupQueue.async { [self] in
            defer { self.cleanupGroup.leave() }
            self.performReap(process: p, pid: capturedPid, alreadyTerminated: alreadyTerminated)
        }
    }

    public func terminateAndReap() {
        lock.lock()
        isCancelled = true
        if cleanupStarted {
            lock.unlock()
            cleanupGroup.wait()
            return
        }
        cleanupStarted = true
        guard let p = process else {
            isTerminated = true
            lock.unlock()
            return
        }
        let capturedPid = self.pid
        let alreadyTerminated = self.isTerminated
        cleanupGroup.enter()
        lock.unlock()

        cleanupQueue.async { [self] in
            defer { self.cleanupGroup.leave() }
            self.performReap(process: p, pid: capturedPid, alreadyTerminated: alreadyTerminated)
        }
        cleanupGroup.wait()
    }

    private func performReap(process: Process, pid: pid_t, alreadyTerminated: Bool) {
        if alreadyTerminated {
            lock.lock()
            isTerminated = true
            lock.unlock()
            return
        }

        if !process.isRunning {
            // Recheck if process has exited
            let waitRes = exitSemaphore.wait(timeout: .now() + .milliseconds(100))
            if waitRes == .success {
                exitSemaphore.signal()
            }
            lock.lock()
            isTerminated = true
            lock.unlock()
            return
        }

        if pid > 0 {
            // Graceful SIGTERM to process and process group
            kill(pid, SIGTERM)
            kill(-pid, SIGTERM)

            // Wait up to 200ms for terminationHandler signal
            let gracefulResult = exitSemaphore.wait(timeout: .now() + .milliseconds(200))
            if gracefulResult == .success {
                exitSemaphore.signal()
                lock.lock()
                isTerminated = true
                lock.unlock()
                return
            }

            // Recheck process state before SIGKILL to avoid signalling known exited child
            if !process.isRunning {
                let waitRes = exitSemaphore.wait(timeout: .now() + .milliseconds(100))
                if waitRes == .success {
                    exitSemaphore.signal()
                }
                lock.lock()
                isTerminated = true
                lock.unlock()
                return
            }

            // Escalate to SIGKILL if child did not exit within 200ms
            kill(pid, SIGKILL)
            kill(-pid, SIGKILL)

            // Await terminationHandler signal after SIGKILL (bounded up to 2 seconds to prevent infinite hang)
            let killResult = exitSemaphore.wait(timeout: .now() + .seconds(2))
            if killResult == .success {
                exitSemaphore.signal()
                lock.lock()
                isTerminated = true
                lock.unlock()
                return
            }

            // If we timed out after SIGKILL and handler/process exit was not confirmed,
            // do not claim successful reap or mark process terminated.
            if !process.isRunning {
                lock.lock()
                isTerminated = true
                lock.unlock()
                return
            }

            lock.lock()
            cleanupError = CodexUsageError.processFailed("Failed to terminate subprocess PID \(pid)")
            lock.unlock()
        } else {
            process.terminate()
            let res = exitSemaphore.wait(timeout: .now() + .milliseconds(200))
            if res == .success {
                exitSemaphore.signal()
                lock.lock()
                isTerminated = true
                lock.unlock()
                return
            }
            if !process.isRunning {
                lock.lock()
                isTerminated = true
                lock.unlock()
                return
            }
            lock.lock()
            cleanupError = CodexUsageError.processFailed("Failed to terminate subprocess")
            lock.unlock()
        }
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
            let snapshot = try await withThrowingTaskGroup(of: ProviderUsageSnapshot?.self) { group in
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

            if let cleanupErr = controller.retainedCleanupError {
                throw cleanupErr
            }
            return snapshot
        } catch is CancellationError {
            if timedOut.withLock({ $0 }) {
                if let cleanupErr = controller.retainedCleanupError {
                    throw cleanupErr
                }
                throw CodexUsageError.timeout
            }
            if let cleanupErr = controller.retainedCleanupError {
                throw cleanupErr
            }
            throw CancellationError()
        } catch {
            if let cleanupErr = controller.retainedCleanupError {
                throw cleanupErr
            }
            throw error
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
            do {
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
                        if controller.isCancelledOnly {
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
                        if controller.isCancelledOnly {
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
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw error
            }
        } onCancel: {
            controller.cancel()
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

            if controller.isCancelledOnly {
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
