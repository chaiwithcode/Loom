//
//  SessionLifecycleReconciler.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

/// Reusable session lifecycle reconciler that tracks sessions across discovery cycles,
/// handles state transitions (departed -> finished), enforces retention windows for
/// completed sessions, detects stale working sessions, and preserves stable logical session IDs.
public actor SessionLifecycleReconciler: Sendable {
    private var trackedSessions: [String: AgentSession] = [:]
    public let retentionWindow: TimeInterval
    public let staleThreshold: TimeInterval

    public init(
        retentionWindow: TimeInterval = 900, // 15 minutes
        staleThreshold: TimeInterval = 1800  // 30 minutes
    ) {
        self.retentionWindow = retentionWindow
        self.staleThreshold = staleThreshold
    }

    /// Reconciles newly discovered sessions against previously tracked sessions.
    ///
    /// - Parameters:
    ///   - newSessions: The newly discovered sessions from the current cycle.
    ///   - now: The current timestamp.
    ///   - providerTerminationReason: Optional context if the provider daemon/host terminated.
    ///   - isCancelled: If true, discovery was cancelled; prior sessions are preserved without assuming termination.
    ///   - providerError: If non-nil, discovery encountered an error; prior sessions are not assumed to have finished.
    /// - Returns: Reconciled, sorted list of sessions including retained finished sessions.
    public func reconcile(
        newSessions: [AgentSession],
        now: Date = Date(),
        providerTerminationReason: String? = nil,
        isCancelled: Bool = false,
        providerError: String? = nil
    ) -> [AgentSession] {
        // If discovery was cancelled, preserve current tracked sessions without altering states
        if isCancelled {
            return sortedSessions(Array(trackedSessions.values))
        }

        var updated: [String: AgentSession] = [:]

        // 1. Process newly discovered sessions
        for session in newSessions {
            var reconciledSession = session

            // Maintain stable logical session identity across process restarts:
            // If a previous session matches provider and providerSessionID, preserve stable ID and original startedAt
            if let provSessionID = session.providerSessionID, !provSessionID.isEmpty {
                if let match = trackedSessions.values.first(where: {
                    $0.provider == session.provider &&
                    $0.providerSessionID == provSessionID &&
                    $0.id != session.id
                }) {
                    reconciledSession = AgentSession(
                        id: match.id,
                        provider: session.provider,
                        projectName: session.projectName,
                        projectPath: session.projectPath,
                        state: session.state,
                        startedAt: match.startedAt ?? session.startedAt,
                        lastActivityAt: session.lastActivityAt,
                        branch: session.branch,
                        summary: session.summary,
                        pid: session.pid,
                        providerSessionID: session.providerSessionID,
                        associatedProcesses: session.associatedProcesses,
                        hostApp: session.hostApp,
                        diagnostics: session.diagnostics,
                        discoveryEvidence: session.discoveryEvidence + ["Correlated to prior session \(match.id) across restart"]
                    )
                }
            }

            // Check for stale working state
            if reconciledSession.state == .working {
                let activityTimestamp = reconciledSession.lastActivityAt ?? reconciledSession.startedAt
                if let activityTimestamp, now.timeIntervalSince(activityTimestamp) > staleThreshold {
                    var updatedEvidence = reconciledSession.discoveryEvidence
                    let diffMinutes = max(1, Int(now.timeIntervalSince(activityTimestamp) / 60))
                    let workerNote = reconciledSession.associatedProcesses.count > 1 ? " despite \(reconciledSession.associatedProcesses.count) surviving worker processes" : ""

                    // Positive waiting evidence check: only transition to .waiting if positive evidence exists;
                    // otherwise downgrade working to .idle
                    let hasPositiveWaitingEvidence = hasPositiveEvidenceOfWaiting(session: reconciledSession)

                    if hasPositiveWaitingEvidence {
                        updatedEvidence.append("Awaiting activity: no recorded activity for \(diffMinutes)m\(workerNote); confirmed Waiting state")
                        let waitingReconciled = AgentSession(
                            id: reconciledSession.id,
                            provider: reconciledSession.provider,
                            projectName: reconciledSession.projectName,
                            projectPath: reconciledSession.projectPath,
                            state: .waiting,
                            startedAt: reconciledSession.startedAt,
                            lastActivityAt: reconciledSession.lastActivityAt,
                            branch: reconciledSession.branch,
                            summary: reconciledSession.summary ?? "Awaiting user input",
                            pid: reconciledSession.pid,
                            providerSessionID: reconciledSession.providerSessionID,
                            associatedProcesses: reconciledSession.associatedProcesses,
                            hostApp: reconciledSession.hostApp,
                            diagnostics: reconciledSession.diagnostics,
                            discoveryEvidence: updatedEvidence
                        )
                        updated[waitingReconciled.id] = waitingReconciled
                        continue
                    } else {
                        updatedEvidence.append("Inactivity timeout: no recorded activity for \(diffMinutes)m\(workerNote); transitioned to Idle")
                        let idleReconciled = AgentSession(
                            id: reconciledSession.id,
                            provider: reconciledSession.provider,
                            projectName: reconciledSession.projectName,
                            projectPath: reconciledSession.projectPath,
                            state: .idle,
                            startedAt: reconciledSession.startedAt,
                            lastActivityAt: reconciledSession.lastActivityAt,
                            branch: reconciledSession.branch,
                            summary: reconciledSession.summary ?? "Idle (no activity)",
                            pid: reconciledSession.pid,
                            providerSessionID: reconciledSession.providerSessionID,
                            associatedProcesses: reconciledSession.associatedProcesses,
                            hostApp: reconciledSession.hostApp,
                            diagnostics: reconciledSession.diagnostics,
                            discoveryEvidence: updatedEvidence
                        )
                        updated[idleReconciled.id] = idleReconciled
                        continue
                    }
                }
            }

            updated[reconciledSession.id] = reconciledSession
        }

        // 2. Check previously tracked sessions that are missing in newSessions
        for (id, prev) in trackedSessions {
            if updated[id] == nil {
                // If there's an active provider error, do NOT manufacture a .finished state
                if let error = providerError {
                    if prev.state != .finished && prev.state != .failed {
                        let preservedSession = AgentSession(
                            id: prev.id,
                            provider: prev.provider,
                            projectName: prev.projectName,
                            projectPath: prev.projectPath,
                            state: prev.state,
                            startedAt: prev.startedAt,
                            lastActivityAt: prev.lastActivityAt,
                            branch: prev.branch,
                            summary: prev.summary,
                            pid: prev.pid,
                            providerSessionID: prev.providerSessionID,
                            associatedProcesses: prev.associatedProcesses,
                            hostApp: prev.hostApp,
                            diagnostics: prev.diagnostics,
                            discoveryEvidence: prev.discoveryEvidence + ["Provider error during discovery (\(error)): state preserved"]
                        )
                        updated[id] = preservedSession
                        continue
                    }
                }

                if prev.state != .finished && prev.state != .failed {
                    let reason = providerTerminationReason ?? "process exited"
                    let finishedSession = AgentSession(
                        id: prev.id,
                        provider: prev.provider,
                        projectName: prev.projectName,
                        projectPath: prev.projectPath,
                        state: .finished,
                        startedAt: prev.startedAt,
                        lastActivityAt: now,
                        branch: prev.branch,
                        summary: "Session finished (\(reason))",
                        pid: prev.pid,
                        providerSessionID: prev.providerSessionID,
                        associatedProcesses: [],
                        hostApp: prev.hostApp,
                        diagnostics: prev.diagnostics,
                        discoveryEvidence: prev.discoveryEvidence + ["Session departed (\(reason)): transitioned to Finished"]
                    )
                    updated[id] = finishedSession
                } else if prev.state == .failed {
                    // Retain failed sessions up to retentionWindow, preserving termination timestamp, failure state, and diagnostics
                    let terminationTime = prev.lastActivityAt ?? now
                    if now.timeIntervalSince(terminationTime) < retentionWindow {
                        if prev.lastActivityAt == nil {
                            let retainedFailed = AgentSession(
                                id: prev.id,
                                provider: prev.provider,
                                projectName: prev.projectName,
                                projectPath: prev.projectPath,
                                state: .failed,
                                startedAt: prev.startedAt,
                                lastActivityAt: terminationTime,
                                branch: prev.branch,
                                summary: prev.summary ?? "Session failed",
                                pid: prev.pid,
                                providerSessionID: prev.providerSessionID,
                                associatedProcesses: [],
                                hostApp: prev.hostApp,
                                diagnostics: prev.diagnostics,
                                discoveryEvidence: prev.discoveryEvidence + ["Process exited: retained failure state"]
                            )
                            updated[id] = retainedFailed
                        } else {
                            updated[id] = prev
                        }
                    }
                } else if prev.state == .finished {
                    // Retain finished sessions up to retentionWindow
                    let lastAct = prev.lastActivityAt ?? prev.startedAt ?? now
                    if now.timeIntervalSince(lastAct) < retentionWindow {
                        updated[id] = prev
                    }
                }
            }
        }

        trackedSessions = updated
        return sortedSessions(Array(updated.values))
    }

    public func currentSessions() -> [AgentSession] {
        sortedSessions(Array(trackedSessions.values))
    }

    public func reset() {
        trackedSessions.removeAll()
    }

    // MARK: - Private Helpers

    private func hasPositiveEvidenceOfWaiting(session: AgentSession) -> Bool {
        let evidenceText = session.discoveryEvidence.joined(separator: " ").lowercased()
        let summaryText = (session.summary ?? "").lowercased()

        let waitingKeywords = [
            "awaiting user",
            "needs input",
            "waiting for user",
            "turn complete",
            "prompt input",
            "waiting for input"
        ]

        for keyword in waitingKeywords {
            if evidenceText.contains(keyword) || summaryText.contains(keyword) {
                return true
            }
        }

        return false
    }

    private func sortedSessions(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.sorted { s1, s2 in
            let d1 = s1.startedAt
            let d2 = s2.startedAt
            if let d1 = d1, let d2 = d2, d1 != d2 {
                return d1 < d2
            }
            return s1.id < s2.id
        }
    }
}
