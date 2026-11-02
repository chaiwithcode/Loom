//
//  T3CodeProvider.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public final class T3CodeProvider: AgentProvider, Sendable {
    public let id: ProviderID = .t3Code
    public let displayName: String = "T3 Code"

    private actor DiagnosticsStorage {
        var diagnostics: ProviderDiscoveryDiagnostics?
        private let reconciler = SessionLifecycleReconciler()

        func updateDiagnostics(_ diag: ProviderDiscoveryDiagnostics?) {
            diagnostics = diag
        }

        func getDiagnostics() -> ProviderDiscoveryDiagnostics? {
            diagnostics
        }

        func reconcileSessions(newSessions: [AgentSession], now: Date) async -> [AgentSession] {
            await reconciler.reconcile(newSessions: newSessions, now: now, providerTerminationReason: "T3 Code stopped")
        }
    }

    private let storage = DiagnosticsStorage()
    private let customDetector: T3CodeDetector?

    public init(detector: T3CodeDetector? = nil) {
        self.customDetector = detector
    }

    public func availability() async -> ProviderAvailability {
        return .available
    }

    public func fetchUsage() async throws -> ProviderUsageSnapshot? {
        return nil
    }

    public func lastDiagnostics() async -> ProviderDiscoveryDiagnostics? {
        await storage.getDiagnostics()
    }

    public func discoverSessions() async throws -> [AgentSession] {
        let startTime = Date()
        let t3Result: T3CodeDetector.DetectionResult
        let allOrchestratedChildren: [AgentSessionStatus]

        if let customDetector {
            let scanner = ProcessTreeScanner()
            let table = scanner.scanProcessTable()
            t3Result = await customDetector.detect(processTable: table)
            allOrchestratedChildren = []
        } else {
            let cache = await SharedCLIDiscoveryCache.shared.snapshot()
            t3Result = cache.t3Result
            allOrchestratedChildren = (cache.codexStatuses + cache.claudeStatuses + cache.antigravityStatuses)
                .filter { $0.surface == .t3Orchestrated && $0.state != .inactive }
        }

        let activeT3Sessions = t3Result.sessions.filter { $0.state != .inactive }
        let duration = Date().timeIntervalSince(startTime)

        let diagnostics = ProviderDiscoveryDiagnostics(
            processesDetected: t3Result.rootT3PIDs.count + allOrchestratedChildren.count,
            logicalSessions: activeT3Sessions.count,
            workspacesResolved: activeT3Sessions.filter { $0.workspacePath != nil }.count,
            metadataStatus: .available,
            metadataError: nil,
            discoveryDuration: duration
        )
        await storage.updateDiagnostics(diagnostics)

        let mappedSessions: [AgentSession] = activeT3Sessions.map { t3Session in
            let matchingChildren = allOrchestratedChildren.filter { child in
                if let ws1 = t3Session.workspacePath, let ws2 = child.workspacePath,
                   URL(fileURLWithPath: ws1).standardizedFileURL.path == URL(fileURLWithPath: ws2).standardizedFileURL.path {
                    return true
                }
                if let t3PID = t3Session.pid, let parentPID = child.parentT3PID, t3PID == parentPID {
                    return true
                }
                return activeT3Sessions.count == 1
            }

            // Elevate T3Code session state if any orchestrated child CLI is awaiting approval or working
            let effectiveState: AgentRunState = {
                if t3Session.state == .awaitingApproval || matchingChildren.contains(where: { $0.state == .awaitingApproval }) {
                    return .awaitingApproval
                }
                if t3Session.state == .working || matchingChildren.contains(where: { $0.state == .working }) {
                    return .working
                }
                return t3Session.state
            }()

            let aggregatedTokens: TokenUsageSnapshot? = {
                let usages = matchingChildren.compactMap(\.tokenUsage)
                guard !usages.isEmpty else { return t3Session.tokenUsage }
                return TokenUsageSnapshot(
                    inputTokens: usages.reduce(0) { $0 + $1.inputTokens },
                    cachedInputTokens: usages.reduce(0) { $0 + $1.cachedInputTokens },
                    outputTokens: usages.reduce(0) { $0 + $1.outputTokens },
                    reasoningTokens: usages.reduce(0) { $0 + $1.reasoningTokens }
                )
            }()

            let effectiveStatus = AgentSessionStatus(
                id: t3Session.id,
                provider: .t3Code,
                surface: .gui,
                pid: t3Session.pid,
                parentT3PID: nil,
                projectName: t3Session.projectName,
                workspacePath: t3Session.workspacePath,
                gitBranch: t3Session.gitBranch ?? matchingChildren.compactMap(\.gitBranch).first,
                modelName: t3Session.modelName ?? matchingChildren.compactMap(\.modelName).first,
                state: effectiveState,
                tokenUsage: aggregatedTokens,
                lastUpdated: max(t3Session.lastUpdated, matchingChildren.map(\.lastUpdated).max() ?? t3Session.lastUpdated)
            )

            return SharedCLIDiscoveryCache.toAgentSession(
                effectiveStatus,
                providerID: .t3Code,
                orchestratedChildren: matchingChildren,
                diagnostics: diagnostics
            )
        }

        return await storage.reconcileSessions(newSessions: mappedSessions, now: Date())
    }
}
