//
//  CodexProvider.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public final class CodexProvider: AgentProvider, Sendable {
    public let id: ProviderID = .codex
    public let displayName: String = "Codex"

    private let processDiscoverer: any CodexProcessDiscovering
    private let gitResolver: any GitRepositoryResolving
    private let workspaceResolver: any WorkspaceResolving
    private let correlationEngine: any SessionCorrelating
    private let usageFetcher: any CodexUsageFetching
    private let stateInspector: any CodexStateStoreInspecting

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
            await reconciler.reconcile(newSessions: newSessions, now: now, providerTerminationReason: "process exited")
        }
    }
    private let storage = DiagnosticsStorage()

    public init(
        processDiscoverer: any CodexProcessDiscovering = DefaultCodexProcessDiscoverer(),
        gitResolver: any GitRepositoryResolving = DefaultGitRepositoryResolver(),
        workspaceResolver: (any WorkspaceResolving)? = nil,
        correlationEngine: (any SessionCorrelating)? = nil,
        usageFetcher: any CodexUsageFetching = DefaultCodexUsageFetcher(),
        stateInspector: any CodexStateStoreInspecting = DefaultCodexStateStoreInspector()
    ) {
        self.processDiscoverer = processDiscoverer
        self.gitResolver = gitResolver
        self.stateInspector = stateInspector
        self.workspaceResolver = workspaceResolver ?? DefaultWorkspaceResolver(
            gitResolver: gitResolver,
            evidenceProviders: [CodexWorkspaceEvidenceProvider(stateInspector: stateInspector)]
        )
        self.correlationEngine = correlationEngine ?? DefaultSessionCorrelationEngine(stateInspector: stateInspector)
        self.usageFetcher = usageFetcher
    }

    public func availability() async -> ProviderAvailability {
        // As long as the provider can run process discovery, it is available.
        return .available
    }

    public func fetchUsage() async throws -> ProviderUsageSnapshot? {
        return try await usageFetcher.fetchUsage()
    }

    public func lastDiagnostics() async -> ProviderDiscoveryDiagnostics? {
        await storage.getDiagnostics()
    }

    public func discoverSessions() async throws -> [AgentSession] {
        let startTime = Date()
        let processes: [AgentProcess]
        let processTree: ProcessTree
        var discoveryError: String? = nil

        do {
            (processes, processTree) = try await processDiscoverer.discoverProcesses()
        } catch {
            discoveryError = error.localizedDescription
            processes = []
            processTree = ProcessTree(nodes: [])
        }

        let correlatedSessions: [AgentSession]
        if !processes.isEmpty {
            correlatedSessions = await correlationEngine.correlate(
                processes: processes,
                processTree: processTree,
                workspaceResolver: workspaceResolver
            )
        } else {
            correlatedSessions = []
        }

        let duration = Date().timeIntervalSince(startTime)
        let diagnostics = ProviderDiscoveryDiagnostics(
            processesDetected: processes.count,
            logicalSessions: correlatedSessions.count,
            workspacesResolved: correlatedSessions.filter { $0.projectPath != nil }.count,
            metadataStatus: discoveryError != nil ? .unavailable : .available,
            metadataError: discoveryError,
            discoveryDuration: duration
        )

        await storage.updateDiagnostics(diagnostics)

        let sessionsWithDiagnostics = correlatedSessions.map { session in
            AgentSession(
                id: session.id,
                provider: session.provider,
                projectName: session.projectName,
                projectPath: session.projectPath,
                state: session.state,
                startedAt: session.startedAt,
                lastActivityAt: session.lastActivityAt,
                branch: session.branch,
                summary: session.summary,
                pid: session.pid,
                providerSessionID: session.providerSessionID,
                associatedProcesses: session.associatedProcesses,
                hostApp: session.hostApp,
                diagnostics: diagnostics,
                discoveryEvidence: session.discoveryEvidence
            )
        }

        return await storage.reconcileSessions(newSessions: sessionsWithDiagnostics, now: Date())
    }
}
