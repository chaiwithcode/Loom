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
    public var isEnabled: Bool

    public init(
        providerID: ProviderID,
        displayName: String,
        availability: ProviderAvailability = .unknown,
        sessions: [AgentSession] = [],
        usage: ProviderUsageSnapshot? = nil,
        usageErrorMessage: String? = nil,
        errorMessage: String? = nil,
        isRefreshing: Bool = false,
        diagnostics: ProviderDiscoveryDiagnostics? = nil,
        isEnabled: Bool = true
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
        self.isEnabled = isEnabled
    }

    public var hasWarning: Bool {
        guard isEnabled else { return false }
        return errorMessage != nil ||
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
    case allProvidersDisabled

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
        case .allProvidersDisabled:
            return "All providers disabled in Settings"
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
    var sessionsCancelled: Bool = false
    var usageCancelled: Bool = false
}

@Observable
@MainActor
public final class SessionStore {
    public let fixture: DemoFixture
    public private(set) var providerSnapshots: [ProviderSnapshot] = []
    public private(set) var isRefreshing: Bool = false
    public private(set) var lastRefreshedAt: Date? = nil
    public private(set) var enabledProviderIDs: Set<ProviderID>
    public private(set) var storageOverview: StorageOverview?
    public private(set) var isStorageScanning: Bool = false

    public var enabledSnapshots: [ProviderSnapshot] {
        providerSnapshots.filter(\.isEnabled)
    }

    private let registeredProviders: [any AgentProvider]
    private var activeRefreshTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?
    private var activeStorageTask: Task<StorageOverview?, Never>?
    private var providerGenerations: [ProviderID: Int] = [:]
    private var activeProviderTasks: [ProviderID: Task<ProviderRefreshResult, Never>] = [:]
    private var needsSubsequentRefresh: Bool = false

    @ObservationIgnored
    nonisolated(unsafe) private var wakeObserver: (any NSObjectProtocol)?

    public init(
        providers: [any AgentProvider],
        fixture: DemoFixture = .standard,
        enabledProviderIDs: Set<ProviderID>? = nil
    ) {
        self.fixture = fixture
        self.registeredProviders = providers
        let initialEnabled = enabledProviderIDs ?? Set(providers.map(\.id))
        self.enabledProviderIDs = initialEnabled
        self.providerSnapshots = providers.map { provider in
            let isEnabled = initialEnabled.contains(provider.id)
            return ProviderSnapshot(
                providerID: provider.id,
                displayName: provider.displayName,
                availability: isEnabled ? .unknown : .unavailable(reason: "Monitoring disabled"),
                sessions: [],
                usage: nil,
                usageErrorMessage: nil,
                errorMessage: nil,
                isRefreshing: false,
                diagnostics: nil,
                isEnabled: isEnabled
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
        enabledSnapshots.flatMap(\.sessions)
    }

    public var groupedSessions: [ProjectGroup] {
        ProjectGroup.groupSessions(allSessions)
    }

    public func snapshot(for providerID: ProviderID) -> ProviderSnapshot? {
        providerSnapshots.first(where: { $0.providerID == providerID })
    }

    public var hasUsageOrProviderWarning: Bool {
        enabledSnapshots.contains(where: \.hasWarning)
    }

    public var emptySessionReason: EmptySessionReason? {
        // Empty registered provider store preserves noActiveSessions semantics
        guard !registeredProviders.isEmpty else {
            return isRefreshing ? .refreshing : .noActiveSessions
        }

        // When registered providers exist but all are disabled in Settings
        guard !enabledSnapshots.isEmpty else {
            return .allProvidersDisabled
        }

        guard allSessions.isEmpty else { return nil }

        if isRefreshing {
            return .refreshing
        }

        let failedSnapshots = enabledSnapshots.filter { $0.errorMessage != nil }
        if !failedSnapshots.isEmpty {
            if failedSnapshots.count == 1, let error = failedSnapshots.first?.errorMessage {
                return .discoveryFailed(message: "Discovery failed: \(error)")
            } else {
                return .discoveryFailed(message: "Session discovery failed")
            }
        }

        let unavailableSnapshots = enabledSnapshots.filter { !$0.availability.isAvailable }
        if !enabledSnapshots.isEmpty && unavailableSnapshots.count == enabledSnapshots.count {
            let reasons = unavailableSnapshots.compactMap { $0.availability.unavailabilityReason }
            if reasons.count == 1, let reason = reasons.first {
                return .unavailable(message: reason)
            }
            return .unavailable(message: "Providers unavailable")
        }

        return .noActiveSessions
    }

    public func updateEnabledProviders(_ newIDs: Set<ProviderID>) {
        let oldIDs = enabledProviderIDs
        enabledProviderIDs = newIDs
        var newlyEnabled: [ProviderID] = []

        for provider in registeredProviders {
            let id = provider.id
            guard let index = providerSnapshots.firstIndex(where: { $0.providerID == id }) else { continue }
            let isNowEnabled = newIDs.contains(id)
            let wasEnabled = oldIDs.contains(id)

            providerSnapshots[index].isEnabled = isNowEnabled

            if !isNowEnabled {
                // Disabled: increment generation, cancel in-flight task, clear data
                providerGenerations[id, default: 0] += 1
                activeProviderTasks[id]?.cancel()
                activeProviderTasks[id] = nil

                providerSnapshots[index].isRefreshing = false
                providerSnapshots[index].sessions = []
                providerSnapshots[index].usage = nil
                providerSnapshots[index].usageErrorMessage = nil
                providerSnapshots[index].errorMessage = nil
                providerSnapshots[index].availability = .unavailable(reason: "Monitoring disabled")
                providerSnapshots[index].diagnostics = nil
            } else if isNowEnabled && !wasEnabled {
                // Newly re-enabled: increment generation, mark unknown, queue refresh
                providerGenerations[id, default: 0] += 1
                providerSnapshots[index].availability = .unknown
                newlyEnabled.append(id)
            }
        }

        if !newlyEnabled.isEmpty {
            if activeRefreshTask != nil {
                // An active refresh is already running: signal that a fresh pass is needed
                // once the current pass unwinds so the newly enabled provider is polled without manual intervention
                needsSubsequentRefresh = true
            } else {
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
        } else {
            publishWidgetSnapshot()
        }
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
            for (_, task) in activeProviderTasks {
                task.cancel()
            }
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
            repeat {
                self.needsSubsequentRefresh = false
                await self.performRefresh()
            } while self.needsSubsequentRefresh && !Task.isCancelled
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

        let enabledProviders = registeredProviders.filter { enabledProviderIDs.contains($0.id) }

        // Mark only enabled snapshots as refreshing
        for i in providerSnapshots.indices {
            if enabledProviderIDs.contains(providerSnapshots[i].providerID) {
                providerSnapshots[i].isRefreshing = true
            } else {
                providerSnapshots[i].isRefreshing = false
            }
        }

        defer {
            isRefreshing = false
            for i in providerSnapshots.indices {
                providerSnapshots[i].isRefreshing = false
            }
        }

        guard !enabledProviders.isEmpty else {
            return
        }

        // Concurrently query enabled providers; isolate errors and stream results
        await withTaskGroup(of: (ProviderRefreshResult, Int).self) { group in
            for provider in enabledProviders {
                let id = provider.id
                let generation = providerGenerations[id, default: 0]

                let task = Task<ProviderRefreshResult, Never> {
                    // Cooperative check before starting
                    guard !Task.isCancelled else {
                        return ProviderRefreshResult(
                            providerID: id,
                            availability: .unavailable(reason: "Cancelled"),
                            sessions: [],
                            usage: nil,
                            usageError: nil,
                            sessionError: nil,
                            diagnostics: nil
                        )
                    }

                    let avail = await provider.availability()
                    guard !Task.isCancelled else {
                        return ProviderRefreshResult(
                            providerID: id,
                            availability: avail,
                            sessions: [],
                            usage: nil,
                            usageError: nil,
                            sessionError: nil,
                            diagnostics: nil
                        )
                    }

                    guard avail.isAvailable else {
                        return ProviderRefreshResult(
                            providerID: id,
                            availability: avail,
                            sessions: [],
                            usage: nil,
                            usageError: "Provider is unavailable",
                            sessionError: nil,
                            diagnostics: nil
                        )
                    }

                    // Concurrent query for sessions and usage within provider with early cancellation checks
                    async let sessionsTask: ([AgentSession], String?, Bool) = {
                        guard !Task.isCancelled else { return ([], nil, true) }
                        do {
                            let s = try await provider.discoverSessions()
                            return (s, nil, false)
                        } catch {
                            if ProviderIssue.isCancellation(error) { return ([], nil, true) }
                            return ([], error.localizedDescription, false)
                        }
                    }()

                    async let usageTask: (ProviderUsageSnapshot?, String?, Bool) = {
                        guard !Task.isCancelled else { return (nil, nil, true) }
                        do {
                            let u = try await provider.fetchUsage()
                            return (u, nil, false)
                        } catch {
                            if ProviderIssue.isCancellation(error) { return (nil, nil, true) }
                            return (nil, error.localizedDescription, false)
                        }
                    }()

                    let (discoveredSessions, sErr, sCancelled) = await sessionsTask
                    let (fetchedUsage, uErr, uCancelled) = await usageTask

                    guard !Task.isCancelled else {
                        return ProviderRefreshResult(
                            providerID: id,
                            availability: avail,
                            sessions: [],
                            usage: nil,
                            usageError: nil,
                            sessionError: nil,
                            diagnostics: nil
                        )
                    }

                    let diag: ProviderDiscoveryDiagnostics?
                    if !Task.isCancelled {
                        diag = await provider.lastDiagnostics() ?? discoveredSessions.first?.diagnostics
                    } else {
                        diag = nil
                    }

                    return ProviderRefreshResult(
                        providerID: id,
                        availability: avail,
                        sessions: discoveredSessions,
                        usage: fetchedUsage,
                        usageError: uErr,
                        sessionError: sErr,
                        diagnostics: diag,
                        sessionsCancelled: sCancelled,
                        usageCancelled: uCancelled
                    )
                }

                activeProviderTasks[id] = task

                group.addTask {
                    let result = await task.value
                    return (result, generation)
                }
            }

            // Per-provider results become visible as each provider finishes
            for await (result, generation) in group {
                activeProviderTasks[result.providerID] = nil
                // Reject late results if task was cancelled, generation changed, or provider was disabled
                guard !Task.isCancelled,
                      generation == self.providerGenerations[result.providerID, default: 0],
                      self.enabledProviderIDs.contains(result.providerID) else {
                    continue
                }
                self.applyProviderResult(result)
            }
        }

        lastRefreshedAt = Date()
        publishWidgetSnapshot()
    }

    /// Measures and updates local agent storage overview asynchronously on a utility task.
    public func refreshStorage(force: Bool = false) async {
        if isStorageScanning && !force { return }
        if !force, let lastScanned = storageOverview?.scannedAt, Date().timeIntervalSince(lastScanned) < 30 {
            return
        }

        activeStorageTask?.cancel()
        isStorageScanning = true

        let worker = Task.detached(priority: .utility) { () -> StorageOverview? in
            let providers = ProviderStorageLocations.local()
            do {
                return try StorageScanner().measureOverview(for: providers)
            } catch {
                return nil
            }
        }

        let task = Task { () -> StorageOverview? in
            await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
        }

        activeStorageTask = task
        let result = await task.value
        guard !Task.isCancelled else {
            isStorageScanning = false
            return
        }

        if let result {
            self.storageOverview = result
        }
        self.isStorageScanning = false
    }

    private func applyProviderResult(_ result: ProviderRefreshResult) {
        guard let index = providerSnapshots.firstIndex(where: { $0.providerID == result.providerID }) else {
            return
        }

        var snapshot = providerSnapshots[index]
        snapshot.availability = result.availability
        if !result.sessionsCancelled { snapshot.errorMessage = result.sessionError }
        snapshot.diagnostics = result.diagnostics ?? result.sessions.first?.diagnostics
        snapshot.isRefreshing = false

        // Stale lifecycle protection: if provider encountered a fatal error or is unavailable,
        // ensure any previously active sessions do not remain stuck in .working!
        if result.sessionsCancelled {
            // An interrupted observation is not lifecycle evidence. Preserve previous sessions.
        } else if result.sessionError != nil || !result.availability.isAvailable {
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
        if result.usageCancelled {
            snapshot.usage = snapshot.usage?.markedStale(error: nil)
            snapshot.usageErrorMessage = nil
        } else if let newUsage = result.usage {
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
