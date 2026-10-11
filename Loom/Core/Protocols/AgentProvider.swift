//
//  AgentProvider.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public protocol AgentProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    func availability() async -> ProviderAvailability
    func discoverSessions() async throws -> [AgentSession]
    func fetchUsage() async throws -> ProviderUsageSnapshot?
    func lastDiagnostics() async -> ProviderDiscoveryDiagnostics?
}

extension AgentProvider {
    public func fetchUsage() async throws -> ProviderUsageSnapshot? {
        return nil
    }

    public func lastDiagnostics() async -> ProviderDiscoveryDiagnostics? {
        return nil
    }
}
