//
//  AgentState.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public enum AgentState: String, Hashable, Equatable, Sendable, CaseIterable {
    case starting
    case working
    case waiting
    case idle
    case finished
    case failed
    case unknown

    public var displayName: String {
        switch self {
        case .starting: return "Starting"
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .idle: return "Idle"
        case .finished: return "Finished"
        case .failed: return "Failed"
        case .unknown: return "Unknown"
        }
    }
}
