//
//  T3CodeProvider.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation

public final class T3CodeProvider: AgentProvider, Sendable {
    public let id: ProviderID = .t3Code
    public let displayName: String = "T3 Code"

    private let detector: T3CodeDetector
    private let processScanner: ProcessTreeScanner

    public init(
        detector: T3CodeDetector = T3CodeDetector(),
        processScanner: ProcessTreeScanner = ProcessTreeScanner()
    ) {
        self.detector = detector
        self.processScanner = processScanner
    }

    public func availability() async -> ProviderAvailability {
        let table = processScanner.scanProcessTable()
        guard let runtime = detector.resolveServerRuntime(processTable: table) else {
            return .unavailable(reason: "T3 Code server not running")
        }

        if let origin = runtime.origin {
            let isReachable = await detector.probeEnvironment(origin: origin)
            if isReachable {
                return .available
            }
        }

        // If loopback probe timed out but PID is alive and state database exists
        return .available
    }

    public func discoverSessions() async throws -> [AgentSession] {
        let table = processScanner.scanProcessTable()
        guard let runtime = detector.resolveServerRuntime(processTable: table) else {
            return []
        }

        let records = detector.readActiveThreads()
        var sessions: [AgentSession] = []

        for record in records {
            let agentState: AgentState
            switch record.state {
            case .working:
                agentState = .working
            case .awaitingApproval:
                agentState = .waiting
            case .idle:
                agentState = .idle
            case .inactive:
                agentState = .finished
            }

            let projectURL = record.workspaceRoot.map { URL(fileURLWithPath: $0) }
            let projectName = record.projectTitle
                ?? projectURL?.lastPathComponent
                ?? "T3 Project"

            let session = AgentSession(
                id: record.threadID,
                provider: .t3Code,
                projectName: projectName,
                projectPath: projectURL,
                state: agentState,
                startedAt: record.updatedAt,
                lastActivityAt: record.updatedAt,
                branch: nil,
                summary: record.title,
                pid: Int(runtime.pid),
                providerSessionID: record.threadID,
                associatedProcesses: [],
                hostApp: .terminal,
                diagnostics: nil,
                discoveryEvidence: [
                    "T3Code runtime PID \(runtime.pid)",
                    "Provider: \(record.provider)",
                    "Run status: \(record.runStatus ?? "unknown")",
                    "Pending requests: \(record.pendingRequestsCount)"
                ]
            )
            sessions.append(session)
        }

        return sessions
    }

    public func fetchUsage() async throws -> ProviderUsageSnapshot? {
        return nil
    }

    public func lastDiagnostics() async -> ProviderDiscoveryDiagnostics? {
        return nil
    }
}
