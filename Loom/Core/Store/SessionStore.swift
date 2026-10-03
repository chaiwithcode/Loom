import Foundation
import Observation

public struct ProviderSnapshot: Identifiable, Hashable, Equatable, Sendable {
    public var id: ProviderID { providerID }
    public let providerID: ProviderID
    public let displayName: String
    public var availability: ProviderAvailability
    public var sessions: [AgentSession]
    public var errorMessage: String?
    public var isRefreshing: Bool

    public init(
        providerID: ProviderID,
        displayName: String,
        availability: ProviderAvailability = .unknown,
        sessions: [AgentSession] = [],
        errorMessage: String? = nil,
        isRefreshing: Bool = false
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.availability = availability
        self.sessions = sessions
        self.errorMessage = errorMessage
        self.isRefreshing = isRefreshing
    }
}

private struct ProviderRefreshResult: Sendable {
    let providerID: ProviderID
    let availability: ProviderAvailability
    let sessions: [AgentSession]
    let errorMessage: String?
}

@Observable
@MainActor
public final class SessionStore {
    public private(set) var providerSnapshots: [ProviderSnapshot] = []
    public private(set) var isRefreshing: Bool = false
    public private(set) var lastRefreshedAt: Date? = nil

    private let registeredProviders: [any AgentProvider]
    private var activeRefreshTask: Task<Void, Never>?

    public init(providers: [any AgentProvider]) {
        self.registeredProviders = providers
        self.providerSnapshots = providers.map { provider in
            ProviderSnapshot(
                providerID: provider.id,
                displayName: provider.displayName,
                availability: .unknown,
                sessions: [],
                errorMessage: nil,
                isRefreshing: false
            )
        }
    }

    public var allSessions: [AgentSession] {
        providerSnapshots.flatMap(\.sessions)
    }

    public func snapshot(for providerID: ProviderID) -> ProviderSnapshot? {
        providerSnapshots.first(where: { $0.providerID == providerID })
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
        await task.value
        activeRefreshTask = nil
    }

    private func performRefresh() async {
        isRefreshing = true

        // Mark all snapshots as refreshing
        for i in providerSnapshots.indices {
            providerSnapshots[i].isRefreshing = true
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
                            errorMessage: nil
                        )
                    }

                    do {
                        let discovered = try await provider.discoverSessions()
                        return ProviderRefreshResult(
                            providerID: provider.id,
                            availability: avail,
                            sessions: discovered,
                            errorMessage: nil
                        )
                    } catch {
                        return ProviderRefreshResult(
                            providerID: provider.id,
                            availability: avail,
                            sessions: [],
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }

            // Per-provider results become visible as each provider finishes
            for await result in group {
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
        snapshot.sessions = result.sessions
        snapshot.errorMessage = result.errorMessage
        snapshot.isRefreshing = false
        providerSnapshots[index] = snapshot
    }
}
