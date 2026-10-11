//
//  AntigravityUsageFetcher.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
import os
import Security

public protocol AntigravityUsageFetching: Sendable {
    func fetchUsage() async throws -> ProviderUsageSnapshot?
}

public protocol AntigravityQuotaTransporting: Sendable {
    func requestQuota(url: URL, csrfToken: String, timeoutSeconds: TimeInterval) async throws -> Data
}

public enum AntigravityUsageError: LocalizedError, Sendable {
    case processNotFound
    case portsNotFound
    case timeout
    case responseTooLarge
    case requestFailed(String)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .processNotFound:
            return "Antigravity language_server not running"
        case .portsNotFound:
            return "No listening ports found for Antigravity"
        case .timeout:
            return "Antigravity quota request timed out"
        case .responseTooLarge:
            return "Antigravity quota response exceeded maximum allowed buffer size"
        case .requestFailed(let msg):
            return "Antigravity quota request failed: \(msg)"
        case .malformedResponse:
            return "Malformed Antigravity quota response"
        }
    }
}

/// A restricted URLSession delegate that ONLY permits self-signed TLS certificates
/// on the explicit loopback IP (127.0.0.1 / localhost) and discovered port,
/// and strictly rejects HTTP redirects to protect the ephemeral CSRF token.
public final class ScopedLoopbackSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    public let allowedPort: Int

    public init(allowedPort: Int) {
        self.allowedPort = allowedPort
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleAuthenticationChallenge(challenge, completionHandler: completionHandler)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleAuthenticationChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        let port = challenge.protectionSpace.port

        let isLoopback = (host == "127.0.0.1" || host == "localhost")
        let isExpectedPort = (port == allowedPort)

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           isLoopback && isExpectedPort,
           let serverTrust = challenge.protectionSpace.serverTrust {
            // Strictly accept TLS only for this exact discovered loopback endpoint
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Strictly reject any HTTP redirect to prevent CSRF token forwarding
        completionHandler(nil)
    }
}

public final class DefaultAntigravityQuotaTransport: AntigravityQuotaTransporting, Sendable {
    private let maxResponseSize: Int = 1024 * 1024 // 1 MB

    public init() {}

    public func requestQuota(url: URL, csrfToken: String, timeoutSeconds: TimeInterval) async throws -> Data {
        try Task.checkCancellation()

        guard let port = url.port else {
            throw AntigravityUsageError.requestFailed("Missing port in URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = timeoutSeconds

        let delegate = ScopedLoopbackSessionDelegate(allowedPort: port)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        defer {
            session.invalidateAndCancel()
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AntigravityUsageError.requestFailed("Invalid response type")
            }

            guard httpResponse.statusCode == 200 else {
                throw AntigravityUsageError.requestFailed("HTTP \(httpResponse.statusCode)")
            }

            var buffer = Data()
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count > maxResponseSize {
                    session.invalidateAndCancel()
                    throw AntigravityUsageError.responseTooLarge
                }
            }

            return buffer
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

public final class DefaultAntigravityUsageFetcher: AntigravityUsageFetching, Sendable {
    private let processExecutor: any ProcessExecuting
    private let timeoutSeconds: TimeInterval
    private let transport: any AntigravityQuotaTransporting

    public init(
        processExecutor: any ProcessExecuting = DefaultProcessExecutor(),
        timeoutSeconds: TimeInterval = 5.0,
        transport: any AntigravityQuotaTransporting = DefaultAntigravityQuotaTransport()
    ) {
        self.processExecutor = processExecutor
        self.timeoutSeconds = timeoutSeconds
        self.transport = transport
    }

    public func fetchUsage() async throws -> ProviderUsageSnapshot? {
        try Task.checkCancellation()

        // Step 1: Discover language_server or agy hub process and its ephemeral CSRF token
        guard let (pid, csrfToken) = try await discoverProcessAndCsrf() else {
            throw AntigravityUsageError.processNotFound
        }

        // Step 2: Discover listening ports for this PID
        let ports = try await discoverListeningPorts(for: pid)
        guard !ports.isEmpty else {
            throw AntigravityUsageError.portsNotFound
        }

        // Step 3: Query discovered ports until success within overall timeout
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastError: (any Error)? = nil
        for port in ports {
            try Task.checkCancellation()
            let remainingTimeout = deadline.timeIntervalSinceNow
            guard remainingTimeout > 0 else {
                throw AntigravityUsageError.timeout
            }

            guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
                continue
            }

            do {
                let data = try await transport.requestQuota(
                    url: url,
                    csrfToken: csrfToken,
                    timeoutSeconds: min(remainingTimeout, 3.0)
                )
                if let snapshot = AntigravityUsageParser.parseQuotaSummary(from: data) {
                    return snapshot
                } else {
                    throw AntigravityUsageError.malformedResponse
                }
            } catch {
                if error is CancellationError {
                    throw error
                }
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        throw AntigravityUsageError.requestFailed("No responsive loopback quota endpoint")
    }

    private func discoverProcessAndCsrf() async throws -> (pid: Int32, csrfToken: String)? {
        let output = try await executeWithTimeout(executablePath: "/bin/ps", arguments: ["aux"], timeout: 3.0)

        let lines = output.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            guard line.contains("--csrf_token") else {
                continue
            }

            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard tokens.count >= 2, let pid = Int32(tokens[1]) else {
                continue
            }

            // Verify that the command path has the target executable basename (language_server or agy)
            let commandToken = tokens.count > 10 ? tokens[10] : tokens.first(where: {
                let base = URL(fileURLWithPath: $0).lastPathComponent
                return base == "language_server" || base.hasPrefix("language_server") || base == "agy"
            })
            guard let cmd = commandToken else { continue }
            let basename = URL(fileURLWithPath: cmd).lastPathComponent
            let isTargetExecutable = (basename == "language_server" || basename.hasPrefix("language_server") || basename == "agy")
            guard isTargetExecutable else {
                continue
            }

            // Find --csrf_token argument safely without storing or logging
            for i in 0..<tokens.count {
                let token = tokens[i]
                if token == "--csrf_token" {
                    if i + 1 < tokens.count {
                        let csrfValue = tokens[i + 1]
                        return (pid, csrfValue)
                    }
                } else if token.hasPrefix("--csrf_token=") {
                    let csrfValue = String(token.dropFirst("--csrf_token=".count))
                    return (pid, csrfValue)
                }
            }
        }

        return nil
    }

    private func discoverListeningPorts(for pid: Int32) async throws -> [Int] {
        let output = try await executeWithTimeout(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-Pan", "-p", String(pid), "-iTCP", "-sTCP:LISTEN"],
            timeout: 3.0
        )

        var ports: [Int] = []
        let lines = output.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            guard line.contains("LISTEN") && line.contains("127.0.0.1:") else {
                continue
            }

            let parts = line.components(separatedBy: "127.0.0.1:")
            if parts.count >= 2 {
                let portStr = parts[1].prefix(while: { $0.isNumber })
                if let port = Int(portStr), !ports.contains(port) {
                    ports.append(port)
                }
            }
        }

        return ports
    }

    private func executeWithTimeout(executablePath: String, arguments: [String], timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()

        if !(processExecutor is DefaultProcessExecutor) {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try Task.checkCancellation()
                    return try await self.processExecutor.execute(executablePath: executablePath, arguments: arguments)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw AntigravityUsageError.timeout
                }

                let output = try await group.next()!
                group.cancelAll()
                return output
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        let controller = SubprocessController()
        let timedOut = OSAllocatedUnfairLock(initialState: false)

        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    return try await withTaskCancellationHandler {
                        try Task.checkCancellation()

                        let stderrFd = stderrHandle.fileDescriptor
                        let stderrQueue = DispatchQueue(label: "com.loom.antigravity.stderr", qos: .utility)
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
                            try? stdoutHandle.close()
                        }

                        var accumulated = Data()
                        while true {
                            try Task.checkCancellation()
                            guard let chunk = try stdoutHandle.read(upToCount: 4096), !chunk.isEmpty else {
                                try Task.checkCancellation()
                                if controller.isTerminatedOrCancelled {
                                    throw CancellationError()
                                }
                                break
                            }
                            accumulated.append(chunk)
                            if accumulated.count > 1024 * 1024 {
                                throw AntigravityUsageError.responseTooLarge
                            }
                        }

                        guard let string = String(data: accumulated, encoding: .utf8) else {
                            return ""
                        }
                        return string
                    } onCancel: {
                        controller.terminateAndReap()
                    }
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    timedOut.withLock { $0 = true }
                    controller.terminateAndReap()
                    throw AntigravityUsageError.timeout
                }

                let output = try await group.next()!
                group.cancelAll()
                return output
            }
        } catch is CancellationError {
            if timedOut.withLock({ $0 }) {
                throw AntigravityUsageError.timeout
            }
            throw CancellationError()
        }
    }
}
