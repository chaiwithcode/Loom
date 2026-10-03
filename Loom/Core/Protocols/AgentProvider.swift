import Foundation

public protocol AgentProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    func availability() async -> ProviderAvailability
    func discoverSessions() async throws -> [AgentSession]
}
