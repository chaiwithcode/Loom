//
//  SharedCLIDiscoveryCache.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public actor SharedCLIDiscoveryCache {
    public static let shared = SharedCLIDiscoveryCache()

    public struct Snapshot: Sendable {
        public let timestamp: Date
        public let processTable: [pid_t: MonitoredProcess]
        public let t3Result: T3CodeDetector.DetectionResult
        public let codexStatuses: [AgentSessionStatus]
        public let claudeStatuses: [AgentSessionStatus]
        public let antigravityStatuses: [AgentSessionStatus]
    }

    private let scanner = ProcessTreeScanner()
    private let t3Detector = T3CodeDetector()
    private let codexDetector = CodexCLIDetector()
    private let claudeDetector = ClaudeCodeDetector()
    private let agyDetector = AntigravityCLIDetector()

    private var cachedSnapshot: Snapshot?
    private var inFlightTask: Task<Snapshot, Never>?
    private let cacheTTL: TimeInterval = 1.5

    public init() {}

    public func snapshot(forceRefresh: Bool = false) async -> Snapshot {
        if !forceRefresh,
           let cached = cachedSnapshot,
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached
        }

        if let existingTask = inFlightTask {
            return await existingTask.value
        }

        let task = Task<Snapshot, Never> { [scanner, t3Detector, codexDetector, claudeDetector, agyDetector] in
            let table = scanner.scanProcessTable()
            let t3Result = await t3Detector.detect(processTable: table)
            let rootT3PIDs = t3Result.rootT3PIDs

            let codex = codexDetector.detect(processTable: table, t3RootPIDs: rootT3PIDs)
            let claude = claudeDetector.detect(processTable: table, t3RootPIDs: rootT3PIDs)
            let agy = agyDetector.detect(processTable: table, t3RootPIDs: rootT3PIDs)

            return Snapshot(
                timestamp: Date(),
                processTable: table,
                t3Result: t3Result,
                codexStatuses: codex,
                claudeStatuses: claude,
                antigravityStatuses: agy
            )
        }

        inFlightTask = task
        let result = await task.value
        cachedSnapshot = result
        inFlightTask = nil
        return result
    }

    // MARK: - Native AgentSession Conversion

    public static func mapState(_ state: AgentRunState) -> AgentState {
        switch state {
        case .working: return .working
        case .awaitingApproval: return .waiting
        case .idle: return .idle
        case .inactive: return .finished
        }
    }

    public static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM tok", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK tok", Double(count) / 1_000)
        }
        return "\(count) tok"
    }

    public static func toAgentSession(
        _ status: AgentSessionStatus,
        providerID: ProviderID,
        orchestratedChildren: [AgentSessionStatus] = [],
        diagnostics: ProviderDiscoveryDiagnostics? = nil
    ) -> AgentSession {
        let mappedState = mapState(status.state)
        let projectURL = status.workspacePath.map { URL(fileURLWithPath: $0) }

        var summaryParts: [String] = []
        if status.state == .awaitingApproval {
            summaryParts.append("Waiting for approval")
        }
        if let model = status.modelName, !model.isEmpty {
            summaryParts.append(model)
        }
        if let usage = status.tokenUsage, usage.totalTokens > 0 {
            summaryParts.append(formatTokens(usage.totalTokens))
        }
        if !orchestratedChildren.isEmpty {
            let childLabels = orchestratedChildren.map { child in
                switch child.provider {
                case .codex: return "Codex CLI"
                case .claudeCode: return "Claude Code"
                case .antigravity: return "Antigravity CLI"
                case .t3Code: return "T3Code"
                }
            }
            summaryParts.insert("Driving \(childLabels.joined(separator: ", "))", at: 0)
        }

        let summaryText = summaryParts.isEmpty ? status.projectName : summaryParts.joined(separator: " • ")

        let host: HostApp = {
            switch status.surface {
            case .t3Orchestrated:
                return .custom("T3 Code")
            case .gui:
                return providerID == .t3Code ? .custom("T3 Code") : .antigravity
            case .cli:
                return .terminal
            }
        }()

        var processes: [AgentProcess] = []
        if let pid = status.pid {
            processes.append(
                AgentProcess(
                    pid: pid,
                    parentPID: status.parentT3PID,
                    executable: providerID.rawValue,
                    commandLine: providerID.rawValue,
                    workingDirectory: projectURL,
                    startedAt: status.lastUpdated,
                    provider: providerID,
                    hostApp: host,
                    sessionIDToken: status.id
                )
            )
        }

        for child in orchestratedChildren {
            if let cpid = child.pid {
                processes.append(
                    AgentProcess(
                        pid: cpid,
                        parentPID: child.parentT3PID ?? status.pid,
                        executable: child.provider.rawValue,
                        commandLine: child.provider.rawValue,
                        workingDirectory: child.workspacePath.map { URL(fileURLWithPath: $0) },
                        startedAt: child.lastUpdated,
                        provider: providerID,
                        hostApp: .custom("T3 Code"),
                        sessionIDToken: child.id
                    )
                )
            }
        }

        var evidence: [String] = [
            "Surface: \(status.surface.rawValue)",
            "State: \(mappedState.displayName)"
        ]
        if let model = status.modelName, !model.isEmpty {
            evidence.append("Model: \(model)")
        }
        if let usage = status.tokenUsage, usage.totalTokens > 0 {
            evidence.append("Tokens: \(formatTokens(usage.totalTokens)) (in: \(usage.inputTokens), cached: \(usage.cachedInputTokens), out: \(usage.outputTokens))")
        }
        if !orchestratedChildren.isEmpty {
            evidence.append("Orchestrated child CLIs: \(orchestratedChildren.count)")
        }

        return AgentSession(
            id: status.id,
            provider: providerID,
            projectName: status.projectName,
            projectPath: projectURL,
            state: mappedState,
            startedAt: status.lastUpdated,
            lastActivityAt: status.lastUpdated,
            branch: status.gitBranch,
            summary: summaryText,
            pid: status.pid.map { Int($0) },
            providerSessionID: status.id,
            associatedProcesses: processes,
            hostApp: host,
            diagnostics: diagnostics,
            discoveryEvidence: evidence
        )
    }
}
