//
//  ProviderDiscoveryDiagnostics.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct ProviderDiscoveryDiagnostics: Hashable, Equatable, Sendable {
    public let processesDetected: Int
    public let logicalSessions: Int
    public let workspacesResolved: Int
    public let metadataStatus: MetadataStatus
    public let metadataError: String?
    public let discoveryDuration: TimeInterval?

    public enum MetadataStatus: String, Hashable, Equatable, Sendable {
        case available
        case unavailable
        case partial
        case skipped
    }

    public init(
        processesDetected: Int = 0,
        logicalSessions: Int = 0,
        workspacesResolved: Int = 0,
        metadataStatus: MetadataStatus = .available,
        metadataError: String? = nil,
        discoveryDuration: TimeInterval? = nil
    ) {
        self.processesDetected = processesDetected
        self.logicalSessions = logicalSessions
        self.workspacesResolved = workspacesResolved
        self.metadataStatus = metadataStatus
        self.metadataError = metadataError
        self.discoveryDuration = discoveryDuration
    }

    public var discoveryDurationMsFormatted: String? {
        guard let duration = discoveryDuration else { return nil }
        let ms = Int(round(duration * 1000.0))
        return "\(ms) ms"
    }
}
