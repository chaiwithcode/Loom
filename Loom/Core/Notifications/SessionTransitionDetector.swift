//
//  SessionTransitionDetector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

/// Detects confirmed session state transitions across monitoring discovery cycles,
/// enforcing seeding at startup, suppressing inactivity timeouts, and preventing false-finished
/// events on provider failures or cancellations.
public final class SessionTransitionDetector: @unchecked Sendable {
    private let lock = NSLock()
    private var knownSessions: [String: AgentSession] = [:]
    private var hasSeeded = false
    private var seededProviders: Set<ProviderID> = []

    private var lastObservations: [String: Date] = [:]
    private var workingDurations: [String: TimeInterval] = [:]

    public init() {}

    /// Conservative observed working time; never inferred from process/session age.
    public func observedWorkingDuration(for sessionID: String) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return workingDurations[sessionID] ?? 0
    }

    /// Explicitly pre-seeds known sessions (e.g. from prior cache or startup scan) without firing alerts.
    public func seed(sessions: [AgentSession], for provider: ProviderID? = nil) {
        lock.lock()
        defer { lock.unlock() }

        for session in sessions {
            knownSessions[session.id] = session
            lastObservations[session.id] = Date()
            seededProviders.insert(session.provider)
        }
        if let provider {
            seededProviders.insert(provider)
        }
        hasSeeded = true
    }

    /// Evaluates discovered sessions against previously observed states.
    ///
    /// - Parameters:
    ///   - currentSessions: Sessions observed in the current scan cycle.
    ///   - failedProviders: Set of providers whose discovery encountered fatal errors.
    ///   - cancelledProviders: Set of providers whose discovery was cancelled.
    /// - Returns: A list of confirmed session state transition events.
    public func detectTransitions(
        currentSessions: [AgentSession],
        failedProviders: Set<ProviderID> = [],
        cancelledProviders: Set<ProviderID> = [],
        observedAt: Date = Date()
    ) -> [MonitoringEvent] {
        lock.lock()
        defer { lock.unlock() }

        // Deduplicate incoming sessions by logical session ID to prevent child worker double-reporting
        var dedupedCurrent: [String: AgentSession] = [:]
        for session in currentSessions {
            if dedupedCurrent[session.id] == nil {
                dedupedCurrent[session.id] = session
            }
        }

        // Count only intervals bounded by two Working observations. Gaps caused by
        // failed/cancelled scans or long suspensions are not counted, nor is the final
        // unobserved interval. Ten minutes permits the longest supported refresh cadence.
        for (id, session) in dedupedCurrent {
            if !failedProviders.contains(session.provider), !cancelledProviders.contains(session.provider),
               session.state == .working, knownSessions[id]?.state == .working,
               let prior = lastObservations[id], observedAt > prior,
               observedAt.timeIntervalSince(prior) <= 600 {
                workingDurations[id, default: 0] += observedAt.timeIntervalSince(prior)
            }
            lastObservations[id] = failedProviders.contains(session.provider) || cancelledProviders.contains(session.provider)
                ? nil : observedAt
        }
        for id in lastObservations.keys where dedupedCurrent[id] == nil {
            lastObservations.removeValue(forKey: id)
        }

        // On very first global scan, seed initial sessions without firing any notifications
        if !hasSeeded {
            for (id, session) in dedupedCurrent {
                knownSessions[id] = session
                seededProviders.insert(session.provider)
            }
            hasSeeded = true
            return []
        }

        var events: [MonitoringEvent] = []

        // 1. Evaluate observed sessions against previously known states
        for (id, session) in dedupedCurrent {
            // If this provider was never seeded before, seed it now without firing
            if !seededProviders.contains(session.provider) {
                knownSessions[id] = session
                continue
            }

            guard let previous = knownSessions[id] else {
                // Newly appeared session. Record initial state; transition is not yet confirmed.
                knownSessions[id] = session
                continue
            }

            let fromState = previous.state
            let toState = session.state

            if fromState != toState {
                switch toState {
                case .waiting:
                    // Exclude generic inactivity timeouts; only fire on confirmed waiting state
                    if !isStaleInactivityTimeout(session: session) {
                        events.append(.sessionStateTransition(
                            session: session,
                            fromState: fromState,
                            toState: .waiting
                        ))
                    }
                case .finished:
                    // Exclude finished transitions caused by provider discovery failure or cancellation
                    let isProviderCompromised = failedProviders.contains(session.provider) ||
                        cancelledProviders.contains(session.provider) ||
                        isProviderFailureEvidence(session: session)
                    if !isProviderCompromised && fromState != .unknown {
                        events.append(.sessionStateTransition(
                            session: session,
                            fromState: fromState,
                            toState: .finished
                        ))
                    }
                case .failed:
                    events.append(.sessionStateTransition(
                        session: session,
                        fromState: fromState,
                        toState: .failed
                    ))
                default:
                    // Other states (.working, .starting, .idle, .unknown) do not generate transition alerts
                    break
                }
            }

            knownSessions[id] = session
        }

        // Mark all providers present in the scan as seeded
        for session in dedupedCurrent.values {
            seededProviders.insert(session.provider)
        }

        // 2. Check for departed sessions (previously tracked active sessions that are now missing)
        for (id, previous) in knownSessions {
            if dedupedCurrent[id] == nil {
                let provider = previous.provider
                let isProviderCompromised = failedProviders.contains(provider) || cancelledProviders.contains(provider)

                // If the provider failed or cancelled discovery, do NOT assume departed sessions finished!
                if isProviderCompromised {
                    continue
                }

                if previous.state == .working || previous.state == .waiting || previous.state == .starting {
                    let finishedSession = AgentSession(
                        id: previous.id,
                        provider: previous.provider,
                        projectName: previous.projectName,
                        projectPath: previous.projectPath,
                        state: .finished,
                        startedAt: previous.startedAt,
                        lastActivityAt: Date(),
                        branch: previous.branch,
                        summary: "Session departed: finished",
                        pid: previous.pid,
                        providerSessionID: previous.providerSessionID,
                        associatedProcesses: [],
                        hostApp: previous.hostApp,
                        diagnostics: previous.diagnostics,
                        discoveryEvidence: previous.discoveryEvidence + ["Session departed: transitioned to Finished"]
                    )

                    events.append(.sessionStateTransition(
                        session: finishedSession,
                        fromState: previous.state,
                        toState: .finished
                    ))
                    knownSessions[id] = finishedSession
                }
            }
        }

        return events
    }

    /// Resets all tracked sessions and returns to unseeded state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        knownSessions.removeAll()
        lastObservations.removeAll()
        workingDurations.removeAll()
        seededProviders.removeAll()
        hasSeeded = false
    }

    // MARK: - Private Evidence Checks

    private func isStaleInactivityTimeout(session: AgentSession) -> Bool {
        if session.discoveryEvidence.contains(where: {
            $0.localizedCaseInsensitiveContains("Stale activity") ||
            $0.localizedCaseInsensitiveContains("inactivity timeout")
        }) {
            return true
        }
        if let summary = session.summary,
           summary.localizedCaseInsensitiveContains("Awaiting activity") {
            return true
        }
        return false
    }

    private func isProviderFailureEvidence(session: AgentSession) -> Bool {
        if let summary = session.summary,
           summary.localizedCaseInsensitiveContains("Provider error") ||
           summary.localizedCaseInsensitiveContains("Provider unavailable") {
            return true
        }
        if session.discoveryEvidence.contains(where: {
            $0.localizedCaseInsensitiveContains("Provider error") ||
            $0.localizedCaseInsensitiveContains("Provider unavailable")
        }) {
            return true
        }
        return false
    }
}
