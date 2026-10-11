//
//  ProviderAvailability.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public enum ProviderAvailability: Hashable, Equatable, Sendable {
    case unknown
    case available
    case degraded(reason: String)
    case unavailable(reason: String)
    case error(reason: String)

    public var isAvailable: Bool {
        switch self {
        case .available, .degraded:
            return true
        case .unknown, .unavailable, .error:
            return false
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    public var isDegraded: Bool {
        if case .degraded = self { return true }
        return false
    }

    public var unavailabilityReason: String? {
        switch self {
        case .unavailable(let reason), .degraded(let reason), .error(let reason):
            return reason
        case .unknown, .available:
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .unknown: return "Checking"
        case .available: return "Available"
        case .degraded: return "Degraded"
        case .unavailable: return "Unavailable"
        case .error: return "Error"
        }
    }
}
