//
//  AntigravityProvider.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public final class AntigravityProvider: AgentProvider, Sendable {
    public let id: ProviderID = .antigravity
    public let displayName: String = "Antigravity"

    private let processDiscoverer: any AntigravityProcessDiscovering
    private let storeInspector: any AntigravityStoreInspecting
    private let gitResolver: any GitRepositoryResolving
    private let workspaceResolver: any WorkspaceResolving
    private let usageFetcher: any AntigravityUsageFetching

    private actor DiagnosticsStorage {
        var diagnostics: ProviderDiscoveryDiagnostics?
        var availabilityOverride: ProviderAvailability?
        private let reconciler = SessionLifecycleReconciler()

        func update(_ diag: ProviderDiscoveryDiagnostics?, availability: ProviderAvailability? = nil) {
            diagnostics = diag
            if let availability {
                availabilityOverride = availability
            }
        }

        func get() -> ProviderDiscoveryDiagnostics? {
            diagnostics
        }

        func getAvailability() -> ProviderAvailability {
            availabilityOverride ?? .available
        }

        func reconcile(newSessions: [AgentSession], now: Date = Date(), reason: String? = nil) async -> [AgentSession] {
            await reconciler.reconcile(newSessions: newSessions, now: now, providerTerminationReason: reason)
        }
    }
    private let storage = DiagnosticsStorage()

    public init(
        processDiscoverer: any AntigravityProcessDiscovering = DefaultAntigravityProcessDiscoverer(),
        storeInspector: any AntigravityStoreInspecting = DefaultAntigravityStoreInspector(),
        gitResolver: any GitRepositoryResolving = DefaultGitRepositoryResolver(),
        workspaceResolver: (any WorkspaceResolving)? = nil,
        usageFetcher: any AntigravityUsageFetching = DefaultAntigravityUsageFetcher()
    ) {
        self.processDiscoverer = processDiscoverer
        self.storeInspector = storeInspector
        self.gitResolver = gitResolver
        self.workspaceResolver = workspaceResolver ?? DefaultWorkspaceResolver(gitResolver: gitResolver)
        self.usageFetcher = usageFetcher
    }

    public func availability() async -> ProviderAvailability {
        await storage.getAvailability()
    }

    public func fetchUsage() async throws -> ProviderUsageSnapshot? {
        guard await processDiscoverer.isAntigravityRunning() else {
            throw AntigravityUsageError.processNotFound
        }
        return try await usageFetcher.fetchUsage()
    }

    public func lastDiagnostics() async -> ProviderDiscoveryDiagnostics? {
        await storage.get()
    }

    public func discoverSessions() async throws -> [AgentSession] {
        let startTime = Date()

        // 1. Process liveness gate: if Antigravity is not running, reconcile empty sessions with termination reason
        guard await processDiscoverer.isAntigravityRunning() else {
            let duration = Date().timeIntervalSince(startTime)
            let diag = ProviderDiscoveryDiagnostics(
                processesDetected: 0,
                logicalSessions: 0,
                workspacesResolved: 0,
                metadataStatus: .skipped,
                metadataError: nil,
                discoveryDuration: duration
            )
            await storage.update(diag)
            return await storage.reconcile(newSessions: [], now: Date(), reason: "Antigravity process terminated")
        }

        let runningProcesses = await processDiscoverer.discoverProcesses()
        let processCount = runningProcesses.isEmpty ? 1 : runningProcesses.count

        // 2. Fetch active sessions from the local store with non-fatal error handling
        var records: [AntigravitySessionRecord] = []
        var metadataStatus: ProviderDiscoveryDiagnostics.MetadataStatus = .available
        var metadataError: String? = nil

        do {
            records = try await storeInspector.fetchActiveSessions()
        } catch {
            metadataStatus = .unavailable
            metadataError = error.localizedDescription
        }

        var activeRecords: [AntigravitySessionRecord] = []
        var seenConversationIds: Set<String> = []

        for record in records {
            guard !seenConversationIds.contains(record.conversationId) else {
                continue
            }
            seenConversationIds.insert(record.conversationId)

            if AntigravityParser.isActiveSession(
                status: record.status,
                notFullyIdle: record.notFullyIdle,
                killed: record.killed
            ) {
                activeRecords.append(record)
            }
        }

        // 3. If database metadata yielded active records, build sessions from metadata
        if !activeRecords.isEmpty {
            var sessions: [AgentSession] = []
            let duration = Date().timeIntervalSince(startTime)

            let diagnostics = ProviderDiscoveryDiagnostics(
                processesDetected: processCount,
                logicalSessions: activeRecords.count,
                workspacesResolved: activeRecords.filter { !AntigravityParser.parseWorkspaceURLs(from: $0.workspaceURIsJSON).isEmpty }.count,
                metadataStatus: metadataStatus,
                metadataError: metadataError,
                discoveryDuration: duration
            )
            await storage.update(diagnostics)

            for record in activeRecords {
                var projectName: String = "Antigravity Session"
                var projectPath: URL? = nil
                var branch: String? = nil

                var evidence: [String] = ["SQLite store record (\(record.status))"]

                let workspaceURLs = AntigravityParser.parseWorkspaceURLs(from: record.workspaceURIsJSON)
                if let primaryURL = workspaceURLs.first {
                    evidence.append("Workspace URI resolved from database")
                    let resolved = await workspaceResolver.resolveWorkspace(
                        for: AgentProcess(pid: 0, executable: "", commandLine: "", provider: .antigravity),
                        parent: nil,
                        explicitMetadataURL: primaryURL
                    )
                    projectName = resolved.projectName
                    projectPath = resolved.projectPath
                    branch = resolved.branch
                }

                if let host = runningProcesses.first?.hostApp {
                    evidence.append("Host application: \(host.displayName)")
                }

                let startedAt: Date? = nil
                let lastActivityAt = AntigravityParser.parseDate(from: record.lastModifiedTime)
                let cleanTitle = record.title.trimmingCharacters(in: .whitespacesAndNewlines)

                let sessionState = AntigravityParser.mapState(
                    status: record.status,
                    notFullyIdle: record.notFullyIdle
                )
                let stateEvidence = AntigravityParser.stateEvidence(
                    status: record.status,
                    notFullyIdle: record.notFullyIdle
                )
                evidence.append(stateEvidence)

                let activity = AntigravityParser.activitySummary(
                    conversationId: record.conversationId,
                    status: record.status,
                    title: cleanTitle
                )
                evidence.append(activity.evidence)

                let session = AgentSession(
                    id: "antigravity-\(record.conversationId)",
                    provider: .antigravity,
                    projectName: projectName,
                    projectPath: projectPath,
                    state: sessionState,
                    startedAt: startedAt,
                    lastActivityAt: lastActivityAt,
                    branch: branch,
                    summary: activity.summary,
                    pid: runningProcesses.first.map { Int($0.pid) },
                    providerSessionID: record.conversationId,
                    associatedProcesses: runningProcesses,
                    hostApp: runningProcesses.first?.hostApp ?? .antigravity,
                    diagnostics: diagnostics,
                    discoveryEvidence: evidence
                )
                sessions.append(session)
            }

            await storage.update(diagnostics, availability: .available)
            return await storage.reconcile(newSessions: sessions, now: Date())
        }

        // 4. Graceful degradation: if metadata failed or was empty, fall back to running processes
        if metadataStatus == .unavailable {
            let duration = Date().timeIntervalSince(startTime)
            let effectiveProcesses = runningProcesses.isEmpty ? [
                AgentProcess(pid: 0, executable: "agy", commandLine: "agy", provider: .antigravity)
            ] : runningProcesses

            // Group running processes into distinct logical CLI sessions
            let pids = Set(effectiveProcesses.map(\.pid))
            var rootProcesses = effectiveProcesses.filter { p in
                guard let ppid = p.parentPID else { return true }
                return !pids.contains(ppid)
            }
            if rootProcesses.isEmpty {
                rootProcesses = effectiveProcesses
            }

            var sessions: [AgentSession] = []
            var workspacesResolvedCount = 0

            for root in rootProcesses {
                let children = effectiveProcesses.filter { $0.parentPID == root.pid }
                let cluster = [root] + children

                let resolved = await workspaceResolver.resolveWorkspace(
                    for: root,
                    parent: nil,
                    explicitMetadataURL: nil
                )
                if resolved.projectPath != nil {
                    workspacesResolvedCount += 1
                }

                let isDaemon = root.commandLine.lowercased().contains("language_server") || root.commandLine.lowercased().contains("--hub")
                let isStarting = root.startedAt.map { Date().timeIntervalSince($0) < 8 } ?? false
                let hasWorkers = !children.isEmpty

                let sessionState: AgentState
                if hasWorkers {
                    sessionState = .working
                } else if isStarting {
                    sessionState = .starting
                } else if isDaemon {
                    sessionState = .idle
                } else {
                    sessionState = .waiting
                }

                var evidence: [String] = ["Process fallback: \(root.executable.isEmpty ? "agy" : URL(fileURLWithPath: root.executable).lastPathComponent)"]
                if let err = metadataError {
                    evidence.append("Database metadata unavailable: \(err)")
                }
                if let host = root.hostApp {
                    evidence.append("Host application: \(host.displayName)")
                }
                if hasWorkers {
                    evidence.append("Active worker: \(children.count) worker processes in tree")
                } else if isStarting {
                    evidence.append("State: Starting (process started recently)")
                } else if isDaemon {
                    evidence.append("State: Idle (language server daemon idling)")
                } else {
                    evidence.append("State: Waiting (interactive session awaiting input)")
                }

                let stableID: String
                if let token = root.sessionIDToken, !token.isEmpty {
                    stableID = "antigravity-\(token)"
                } else if root.pid == 0 {
                    stableID = "antigravity-fallback"
                } else {
                    stableID = "antigravity-\(root.pid)"
                }

                let lastActivity = children.compactMap(\.startedAt).max()

                let session = AgentSession(
                    id: stableID,
                    provider: .antigravity,
                    projectName: resolved.projectName,
                    projectPath: resolved.projectPath,
                    state: sessionState,
                    startedAt: root.startedAt,
                    lastActivityAt: lastActivity,
                    branch: resolved.branch,
                    summary: resolved.projectName,
                    pid: root.pid == 0 ? nil : Int(root.pid),
                    providerSessionID: root.sessionIDToken,
                    associatedProcesses: cluster,
                    hostApp: root.hostApp ?? .antigravity,
                    diagnostics: nil,
                    discoveryEvidence: evidence
                )
                sessions.append(session)
            }

            let diagnostics = ProviderDiscoveryDiagnostics(
                processesDetected: runningProcesses.count > 0 ? runningProcesses.count : 1,
                logicalSessions: sessions.count,
                workspacesResolved: workspacesResolvedCount,
                metadataStatus: metadataStatus,
                metadataError: metadataError,
                discoveryDuration: duration
            )
            let degradedAvail: ProviderAvailability = .degraded(reason: "Session metadata unavailable: \(metadataError ?? "database unavailable")")
            await storage.update(diagnostics, availability: degradedAvail)

            let sessionsWithDiagnostics = sessions.map { s in
                AgentSession(
                    id: s.id,
                    provider: s.provider,
                    projectName: s.projectName,
                    projectPath: s.projectPath,
                    state: s.state,
                    startedAt: s.startedAt,
                    lastActivityAt: s.lastActivityAt,
                    branch: s.branch,
                    summary: s.summary,
                    pid: s.pid,
                    providerSessionID: s.providerSessionID,
                    associatedProcesses: s.associatedProcesses,
                    hostApp: s.hostApp,
                    diagnostics: diagnostics,
                    discoveryEvidence: s.discoveryEvidence
                )
            }

            return await storage.reconcile(newSessions: sessionsWithDiagnostics, now: Date())
        }

        // Clean idle when metadata is available and reports no active sessions
        let duration = Date().timeIntervalSince(startTime)
        let diagnostics = ProviderDiscoveryDiagnostics(
            processesDetected: processCount,
            logicalSessions: 0,
            workspacesResolved: 0,
            metadataStatus: metadataStatus,
            metadataError: metadataError,
            discoveryDuration: duration
        )
        await storage.update(diagnostics, availability: .available)

        return await storage.reconcile(newSessions: [], now: Date())
    }
}
