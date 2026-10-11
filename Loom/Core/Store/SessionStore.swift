//
//  SessionStore.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

public struct ProviderSnapshot: Identifiable, Hashable, Equatable, Sendable {
    public var id: ProviderID { providerID }
    public let providerID: ProviderID
    public let displayName: String
    public var availability: ProviderAvailability
    public var sessions: [AgentSession]
    public var usage: ProviderUsageSnapshot?
    public var usageErrorMessage: String?
    public var errorMessage: String?
    public var isRefreshing: Bool
    public var diagnostics: ProviderDiscoveryDiagnostics?

    public init(
        providerID: ProviderID,
        displayName: String,
        availability: ProviderAvailability = .unknown,
        sessions: [AgentSession] = [],
        usage: ProviderUsageSnapshot? = nil,
        usageErrorMessage: String? = nil,
        errorMessage: String? = nil,
        isRefreshing: Bool = false,
        diagnostics: ProviderDiscoveryDiagnostics? = nil
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.availability = availability
        self.sessions = sessions
        self.usage = usage
        self.usageErrorMessage = usageErrorMessage
        self.errorMessage = errorMessage
        self.isRefreshing = isRefreshing
        self.diagnostics = diagnostics
    }

    public var hasWarning: Bool {
        errorMessage != nil ||
        !availability.isAvailable ||
        usageErrorMessage != nil ||
        (usage?.isStale ?? false) ||
        usage?.errorMessage != nil
    }
}

public struct ProjectGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let projectName: String
    public let projectPath: URL?
    public let sessions: [AgentSession]

    public init(
        id: String,
        projectName: String,
        projectPath: URL?,
        sessions: [AgentSession]
    ) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.sessions = sessions
    }

    public static func groupSessions(_ sessions: [AgentSession]) -> [ProjectGroup] {
        var groupsByPath: [String: (name: String, path: URL, sessions: [AgentSession])] = [:]
        var pathGroupOrder: [String] = []
        var nilPathGroups: [ProjectGroup] = []

        for session in sessions {
            if let path = session.projectPath {
                let normalizedPath = path.standardizedFileURL.path
                let key = "path:\(normalizedPath)"
                if var existing = groupsByPath[key] {
                    existing.sessions.append(session)
                    if (existing.name.isEmpty || existing.name == "Untitled Project"),
                       let sName = session.projectName, !sName.isEmpty {
                        existing.name = sName
                    }
                    groupsByPath[key] = existing
                } else {
                    let rawName = session.projectName ?? path.lastPathComponent
                    let finalName = rawName.isEmpty ? "Untitled Project" : rawName
                    groupsByPath[key] = (name: finalName, path: path.standardizedFileURL, sessions: [session])
                    pathGroupOrder.append(key)
                }
            } else {
                let name = session.projectName ?? "Untitled Project"
                let group = ProjectGroup(
                    id: "session:\(session.provider.rawValue):\(session.id)",
                    projectName: name,
                    projectPath: nil,
                    sessions: [session]
                )
                nilPathGroups.append(group)
            }
        }

        var result: [ProjectGroup] = []

        for key in pathGroupOrder {
            guard let entry = groupsByPath[key] else { continue }
            let sortedSessions = sortSessions(entry.sessions)
            result.append(ProjectGroup(
                id: key,
                projectName: entry.name,
                projectPath: entry.path,
                sessions: sortedSessions
            ))
        }

        for group in nilPathGroups {
            result.append(group)
        }

        // Deterministically sort project groups:
        // 1. Groups with active/recent activity first (max of session dates)
        // 2. Case-insensitive alphabetical project name
        // 3. Stable group id
        result.sort { g1, g2 in
            let d1 = g1.sessions.compactMap { $0.lastActivityAt ?? $0.startedAt }.max()
            let d2 = g2.sessions.compactMap { $0.lastActivityAt ?? $0.startedAt }.max()

            if let d1 = d1, let d2 = d2 {
                if d1 != d2 {
                    return d1 > d2
                }
            } else if d1 != nil && d2 == nil {
                return true
            } else if d1 == nil && d2 != nil {
                return false
            }

            let nameCompare = g1.projectName.localizedCaseInsensitiveCompare(g2.projectName)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }

            return g1.id < g2.id
        }

        return result
    }

    private static func sortSessions(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.sorted { s1, s2 in
            let d1 = s1.lastActivityAt ?? s1.startedAt
            let d2 = s2.lastActivityAt ?? s2.startedAt

            if let d1 = d1, let d2 = d2 {
                if d1 != d2 {
                    return d1 > d2
                }
            } else if d1 != nil && d2 == nil {
                return true
            } else if d1 == nil && d2 != nil {
                return false
            }

            if s1.provider.rawValue != s2.provider.rawValue {
                return s1.provider.rawValue < s2.provider.rawValue
            }

            return s1.id < s2.id
        }
    }
}

public enum EmptySessionReason: Equatable, Sendable {
    case refreshing
    case discoveryFailed(message: String)
    case unavailable(message: String)
    case noActiveSessions

    public var message: String {
        switch self {
        case .refreshing:
            return "Checking for sessions…"
        case .discoveryFailed(let msg):
            return msg
        case .unavailable(let msg):
            return msg
        case .noActiveSessions:
            return "No active sessions"
        }
    }
}

private struct ProviderRefreshResult: Sendable {
    let providerID: ProviderID
    let availability: ProviderAvailability
    let sessions: [AgentSession]
    let usage: ProviderUsageSnapshot?
    let usageError: String?
    let sessionError: String?
    let diagnostics: ProviderDiscoveryDiagnostics?
}

@Observable
@MainActor
public final class SessionStore {
    public let fixture: DemoFixture
    public private(set) var providerSnapshots: [ProviderSnapshot] = []
    public private(set) var isRefreshing: Bool = false
    public private(set) var lastRefreshedAt: Date? = nil

    private let registeredProviders: [any AgentProvider]
    private var activeRefreshTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var wakeObserver: (any NSObjectProtocol)?

    public init(providers: [any AgentProvider], fixture: DemoFixture = .standard) {
        self.fixture = fixture
        self.registeredProviders = providers
        self.providerSnapshots = providers.map { provider in
            ProviderSnapshot(
                providerID: provider.id,
                displayName: provider.displayName,
                availability: .unknown,
                sessions: [],
                usage: nil,
                errorMessage: nil,
                isRefreshing: false,
                diagnostics: nil
            )
        }

        #if canImport(AppKit)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        #endif
    }

    deinit {
        #if canImport(AppKit)
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        #endif
    }

    public var allSessions: [AgentSession] {
        providerSnapshots.flatMap(\.sessions)
    }

    public var groupedSessions: [ProjectGroup] {
        ProjectGroup.groupSessions(allSessions)
    }

    public func snapshot(for providerID: ProviderID) -> ProviderSnapshot? {
        providerSnapshots.first(where: { $0.providerID == providerID })
    }

    public var hasUsageOrProviderWarning: Bool {
        providerSnapshots.contains(where: \.hasWarning)
    }

    public var emptySessionReason: EmptySessionReason? {
        guard allSessions.isEmpty else { return nil }

        if isRefreshing {
            return .refreshing
        }

        let failedSnapshots = providerSnapshots.filter { $0.errorMessage != nil }
        if !failedSnapshots.isEmpty {
            if failedSnapshots.count == 1, let error = failedSnapshots.first?.errorMessage {
                return .discoveryFailed(message: "Discovery failed: \(error)")
            } else {
                return .discoveryFailed(message: "Session discovery failed")
            }
        }

        let unavailableSnapshots = providerSnapshots.filter { !$0.availability.isAvailable }
        if !providerSnapshots.isEmpty && unavailableSnapshots.count == providerSnapshots.count {
            let reasons = unavailableSnapshots.compactMap { $0.availability.unavailabilityReason }
            if reasons.count == 1, let reason = reasons.first {
                return .unavailable(message: reason)
            }
            return .unavailable(message: "Providers unavailable")
        }

        return .noActiveSessions
    }

    /// Starts a background periodic refresh loop (default 60 seconds).
    public func startPeriodicRefresh(interval: TimeInterval = 60) {
        guard interval > 0 else { return }
        stopPeriodicRefresh()
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }
                guard !Task.isCancelled, let self else { break }
                await self.refresh()
            }
        }
    }

    /// Stops the background periodic refresh loop and optionally cancels an in-flight refresh.
    public func stopPeriodicRefresh(cancelInFlight: Bool = false) {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        if cancelInFlight {
            activeRefreshTask?.cancel()
            // Do NOT nil activeRefreshTask here: retain handle until the in-flight task
            // finishes unwinding/exiting to prevent overlapping execution with any subsequent refresh.
        }
    }

    public func refresh() async {
        // Overlapping-refresh protection: if a refresh is already in-flight,
        // await the existing active task instead of spawning a duplicate concurrent refresh.
        if let currentTask = activeRefreshTask {
            await currentTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }

        activeRefreshTask = task
        defer {
            if activeRefreshTask == task {
                activeRefreshTask = nil
            }
        }
        await task.value
    }

    private func performRefresh() async {
        isRefreshing = true

        // Mark all snapshots as refreshing
        for i in providerSnapshots.indices {
            providerSnapshots[i].isRefreshing = true
        }

        defer {
            isRefreshing = false
            for i in providerSnapshots.indices {
                providerSnapshots[i].isRefreshing = false
            }
        }

        let providers = registeredProviders

        // Concurrently query providers; isolate errors and stream results
        await withTaskGroup(of: ProviderRefreshResult.self) { group in
            for provider in providers {
                group.addTask {
                    let avail = await provider.availability()
                    guard avail.isAvailable else {
                        return ProviderRefreshResult(
                            providerID: provider.id,
                            availability: avail,
                            sessions: [],
                            usage: nil,
                            usageError: "Provider is unavailable",
                            sessionError: nil,
                            diagnostics: nil
                        )
                    }

                    // Concurrent query for sessions and usage within provider
                    async let sessionsTask: ([AgentSession], String?) = {
                        do {
                            let s = try await provider.discoverSessions()
                            return (s, nil)
                        } catch {
                            return ([], error.localizedDescription)
                        }
                    }()

                    async let usageTask: (ProviderUsageSnapshot?, String?) = {
                        do {
                            let u = try await provider.fetchUsage()
                            return (u, nil)
                        } catch {
                            return (nil, error.localizedDescription)
                        }
                    }()

                    let (discoveredSessions, sErr) = await sessionsTask
                    let (fetchedUsage, uErr) = await usageTask
                    let diag = await provider.lastDiagnostics() ?? discoveredSessions.first?.diagnostics

                    return ProviderRefreshResult(
                        providerID: provider.id,
                        availability: avail,
                        sessions: discoveredSessions,
                        usage: fetchedUsage,
                        usageError: uErr,
                        sessionError: sErr,
                        diagnostics: diag
                    )
                }
            }

            // Per-provider results become visible as each provider finishes
            for await result in group {
                guard !Task.isCancelled else { break }
                self.applyProviderResult(result)
            }
        }

        isRefreshing = false
        lastRefreshedAt = Date()
    }

    private func applyProviderResult(_ result: ProviderRefreshResult) {
        guard let index = providerSnapshots.firstIndex(where: { $0.providerID == result.providerID }) else {
            return
        }

        var snapshot = providerSnapshots[index]
        snapshot.availability = result.availability
        snapshot.errorMessage = result.sessionError
        snapshot.diagnostics = result.diagnostics ?? result.sessions.first?.diagnostics
        snapshot.isRefreshing = false

        // Stale lifecycle protection: if provider encountered a fatal error or is unavailable,
        // ensure any previously active sessions do not remain stuck in .working!
        if result.sessionError != nil || !result.availability.isAvailable {
            if result.sessions.isEmpty && !snapshot.sessions.isEmpty {
                snapshot.sessions = snapshot.sessions.map { s in
                    if s.state == .working || s.state == .starting || s.state == .waiting {
                        let reason = result.sessionError != nil ? "Provider error: \(result.sessionError!)" : "Provider unavailable"
                        return AgentSession(
                            id: s.id,
                            provider: s.provider,
                            projectName: s.projectName,
                            projectPath: s.projectPath,
                            state: result.sessionError != nil ? .failed : .idle,
                            startedAt: s.startedAt,
                            lastActivityAt: Date(),
                            branch: s.branch,
                            summary: reason,
                            pid: s.pid,
                            providerSessionID: s.providerSessionID,
                            associatedProcesses: [],
                            hostApp: s.hostApp,
                            diagnostics: s.diagnostics,
                            discoveryEvidence: s.discoveryEvidence + [reason]
                        )
                    }
                    return s
                }
            } else {
                snapshot.sessions = result.sessions
            }
        } else {
            snapshot.sessions = result.sessions
        }

        // Retain previous successful usage marked as stale if current fetch failed or returned nil or provider unavailable
        if let newUsage = result.usage {
            snapshot.usage = newUsage
            snapshot.usageErrorMessage = nil
        } else if let prevUsage = snapshot.usage {
            let reason = result.usageError ?? "Usage data unavailable"
            snapshot.usage = prevUsage.markedStale(error: reason)
            snapshot.usageErrorMessage = result.usageError
        } else if let err = result.usageError {
            snapshot.usage = nil
            snapshot.usageErrorMessage = err
        }

        providerSnapshots[index] = snapshot
    }
}
