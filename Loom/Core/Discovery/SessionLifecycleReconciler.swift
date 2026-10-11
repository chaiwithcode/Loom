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
/// completed sessions, and detects stale working sessions.
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
    /// - Returns: Reconciled, sorted list of sessions including retained finished sessions.
    public func reconcile(
        newSessions: [AgentSession],
        now: Date = Date(),
        providerTerminationReason: String? = nil
    ) -> [AgentSession] {
        var updated: [String: AgentSession] = [:]

        // 1. Process newly discovered sessions and check for stale working state
        for session in newSessions {
            if session.state == .working {
                let activityTimestamp = session.lastActivityAt ?? session.startedAt
                if let activityTimestamp, now.timeIntervalSince(activityTimestamp) > staleThreshold {
                    var updatedEvidence = session.discoveryEvidence
                    let diffMinutes = max(1, Int(now.timeIntervalSince(activityTimestamp) / 60))
                    let workerNote = session.associatedProcesses.count > 1 ? " despite \(session.associatedProcesses.count) surviving worker processes" : ""
                    updatedEvidence.append("Stale activity: no recorded activity for \(diffMinutes)m\(workerNote); transitioned to Waiting")

                    let staleReconciled = AgentSession(
                        id: session.id,
                        provider: session.provider,
                        projectName: session.projectName,
                        projectPath: session.projectPath,
                        state: .waiting,
                        startedAt: session.startedAt,
                        lastActivityAt: session.lastActivityAt,
                        branch: session.branch,
                        summary: session.summary ?? "Awaiting activity",
                        pid: session.pid,
                        providerSessionID: session.providerSessionID,
                        associatedProcesses: session.associatedProcesses,
                        hostApp: session.hostApp,
                        diagnostics: session.diagnostics,
                        discoveryEvidence: updatedEvidence
                    )
                    updated[session.id] = staleReconciled
                    continue
                }
            }
            updated[session.id] = session
        }

        // 2. Check if previously tracked active sessions have departed
        for (id, prev) in trackedSessions {
            if updated[id] == nil {
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

        return Array(updated.values).sorted { s1, s2 in
            let d1 = s1.startedAt
            let d2 = s2.startedAt
            if let d1 = d1, let d2 = d2, d1 != d2 {
                return d1 < d2
            }
            return s1.id < s2.id
        }
    }

    public func currentSessions() -> [AgentSession] {
        Array(trackedSessions.values)
    }

    public func reset() {
        trackedSessions.removeAll()
    }
}
