//
//  ClaudeProvider.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public final class ClaudeProvider: AgentProvider, Sendable {
    public let id: ProviderID = .claude
    public let displayName: String = "Claude Code"

    private let processDiscoverer: any ClaudeProcessDiscovering
    private let transcriptInspector: any ClaudeTranscriptInspecting
    private let gitResolver: any GitRepositoryResolving
    private let workspaceResolver: any WorkspaceResolving

    private actor DiagnosticsStorage {
        var diagnostics: ProviderDiscoveryDiagnostics?
        private let reconciler = SessionLifecycleReconciler()

        func updateDiagnostics(_ diag: ProviderDiscoveryDiagnostics?) {
            diagnostics = diag
        }

        func getDiagnostics() -> ProviderDiscoveryDiagnostics? {
            diagnostics
        }

        func reconcileSessions(newSessions: [AgentSession], now: Date, reason: String? = nil) async -> [AgentSession] {
            await reconciler.reconcile(newSessions: newSessions, now: now, providerTerminationReason: reason)
        }
    }
    private let storage = DiagnosticsStorage()

    public init(
        processDiscoverer: any ClaudeProcessDiscovering = DefaultClaudeProcessDiscoverer(),
        transcriptInspector: any ClaudeTranscriptInspecting = DefaultClaudeTranscriptInspector(),
        gitResolver: any GitRepositoryResolving = DefaultGitRepositoryResolver(),
        workspaceResolver: (any WorkspaceResolving)? = nil
    ) {
        self.processDiscoverer = processDiscoverer
        self.transcriptInspector = transcriptInspector
        self.gitResolver = gitResolver
        self.workspaceResolver = workspaceResolver ?? DefaultWorkspaceResolver(gitResolver: gitResolver)
    }

    public func availability() async -> ProviderAvailability {
        return .available
    }

    public func lastDiagnostics() async -> ProviderDiscoveryDiagnostics? {
        await storage.getDiagnostics()
    }

    public func discoverSessions() async throws -> [AgentSession] {
        let startTime = Date()
        let (processes, processTree) = try await processDiscoverer.discoverProcesses()

        guard !processes.isEmpty else {
            let duration = Date().timeIntervalSince(startTime)
            let diagnostics = ProviderDiscoveryDiagnostics(
                processesDetected: 0,
                logicalSessions: 0,
                workspacesResolved: 0,
                metadataStatus: .available,
                metadataError: nil,
                discoveryDuration: duration
            )
            await storage.updateDiagnostics(diagnostics)
            return await storage.reconcileSessions(newSessions: [], now: Date(), reason: "process exited")
        }

        var usedTranscriptPaths: Set<String> = []
        var sessions: [AgentSession] = []
        var assignedSessionIDs: Set<String> = []
        var workspacesResolvedCount = 0

        for process in processes {
            let cwd = process.workingDirectory
            let resolvedWorkspace = await workspaceResolver.resolveWorkspace(
                for: process,
                parent: nil,
                explicitMetadataURL: nil
            )

            if resolvedWorkspace.projectPath != nil {
                workspacesResolvedCount += 1
            }

            let projectName: String
            if !resolvedWorkspace.projectName.isEmpty && resolvedWorkspace.projectName != "Untitled Project" {
                projectName = resolvedWorkspace.projectName
            } else if let cwdName = cwd?.lastPathComponent, !cwdName.isEmpty {
                projectName = cwdName
            } else {
                projectName = "Claude Session"
            }

            let branch = resolvedWorkspace.branch

            // 1. Transcript matching with strict priority:
            // (a) Explicit CLI session ID flag (--resume <id>, --session-id <id>)
            // (b) Authoritative open-FD transcript from lsof
            // (c) Bounded process-start-time correlation (modifiedAt >= startedAt - 5s)
            // (d) Otherwise: no transcript match (truthful .starting / .unknown)
            var matchedTranscript: ClaudeTranscriptInfo? = nil
            var tail: ClaudeTranscriptTail? = nil

            if let cwd = cwd {
                let candidateTranscripts = await transcriptInspector.findTranscripts(for: cwd)

                // (a) Authoritative CLI session token
                if let explicitToken = process.sessionIDToken, !explicitToken.isEmpty {
                    matchedTranscript = ClaudeParser.findTranscript(
                        matchingSessionID: explicitToken,
                        in: candidateTranscripts,
                        usedPaths: &usedTranscriptPaths
                    )
                }

                // (b) Authoritative open file descriptor via lsof
                if matchedTranscript == nil {
                    if let openTranscript = await transcriptInspector.findOpenTranscript(for: process.pid),
                       !usedTranscriptPaths.contains(openTranscript.url.path) {
                        usedTranscriptPaths.insert(openTranscript.url.path)
                        matchedTranscript = openTranscript
                    }
                }

                // (c) Bounded process-start-time correlation
                if matchedTranscript == nil {
                    matchedTranscript = ClaudeParser.correlateTranscript(
                        for: process.startedAt,
                        in: candidateTranscripts,
                        usedPaths: &usedTranscriptPaths
                    )
                }

                if let transcript = matchedTranscript {
                    tail = await transcriptInspector.inspectTranscriptTail(at: transcript.url)
                }
            }

            // 2. Process hierarchy and child workers
            let descendantNodes = processTree.descendants(of: process.pid)
            let descendants = descendantNodes.map { node in
                AgentProcess(
                    pid: node.pid,
                    parentPID: node.parentPID,
                    executable: node.executable,
                    commandLine: node.command,
                    workingDirectory: cwd,
                    startedAt: node.startedAt,
                    provider: .claude,
                    hostApp: process.hostApp,
                    sessionIDToken: process.sessionIDToken
                )
            }
            let associatedProcesses = [process] + descendants

            // Filter active workers (child commands running under Claude)
            let childWorkers = descendants.filter { p in
                let cmd = p.commandLine.lowercased()
                return !cmd.isEmpty
            }
            let activeWorker = childWorkers.max(by: { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }) ?? childWorkers.first

            // 3. State derivation
            let isStarting: Bool
            if let started = process.startedAt, Date().timeIntervalSince(started) < 10.0, tail == nil, childWorkers.isEmpty {
                isStarting = true
            } else {
                isStarting = false
            }

            let state = ClaudeParser.mapState(
                hasChildWorkers: !childWorkers.isEmpty,
                isStarting: isStarting,
                isInteractive: tail?.isTurnComplete == true,
                tail: tail,
                hasTranscript: matchedTranscript != nil
            )

            // 4. Activity summary and evidence
            let activityInfo = ClaudeParser.activitySummary(
                tail: tail,
                childWorker: activeWorker,
                projectName: projectName
            )

            let stateEvidenceText = ClaudeParser.stateEvidence(state: state)
            var evidence: [String] = [stateEvidenceText, activityInfo.evidence]

            if let hostApp = process.hostApp {
                evidence.append("Host application: \(hostApp.displayName)")
            }
            if let branch = branch, !branch.isEmpty {
                evidence.append("Branch: \(branch)")
            }
            if associatedProcesses.count > 1 {
                evidence.append("Associated processes: \(associatedProcesses.count) (PID \(process.pid))")
            }

            // 5. Logical session ID
            var logicalID = matchedTranscript?.sessionID
                ?? process.sessionIDToken
                ?? "claude-\(process.pid)"

            if assignedSessionIDs.contains(logicalID) {
                logicalID = "\(logicalID)-\(process.pid)"
            }
            assignedSessionIDs.insert(logicalID)

            let sessionStartedAt = process.startedAt ?? matchedTranscript?.modifiedAt
            let latestWorkerActivity = descendants.compactMap(\.startedAt).max()
            let sessionLastActivity = matchedTranscript?.modifiedAt ?? latestWorkerActivity ?? process.startedAt ?? Date()

            let session = AgentSession(
                id: logicalID,
                provider: .claude,
                projectName: projectName,
                projectPath: resolvedWorkspace.projectPath ?? cwd,
                state: state,
                startedAt: sessionStartedAt,
                lastActivityAt: sessionLastActivity,
                branch: branch,
                summary: activityInfo.summary,
                pid: Int(process.pid),
                providerSessionID: matchedTranscript?.sessionID ?? process.sessionIDToken,
                associatedProcesses: associatedProcesses,
                hostApp: process.hostApp,
                diagnostics: nil,
                discoveryEvidence: evidence
            )
            sessions.append(session)
        }

        let duration = Date().timeIntervalSince(startTime)
        let diagnostics = ProviderDiscoveryDiagnostics(
            processesDetected: processes.count,
            logicalSessions: sessions.count,
            workspacesResolved: workspacesResolvedCount,
            metadataStatus: .available,
            metadataError: nil,
            discoveryDuration: duration
        )
        await storage.updateDiagnostics(diagnostics)

        let sessionsWithDiagnostics = sessions.map { session in
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
