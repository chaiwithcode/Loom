//
//  ProviderID.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct ProviderID: Hashable, Equatable, Sendable, RawRepresentable, Identifiable, CustomStringConvertible {
    public let rawValue: String

    public var id: String { rawValue }
    public var description: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let codex = ProviderID("codex")
    public static let claude = ProviderID("claude")
    public static let antigravity = ProviderID("antigravity")
    public static let t3Code = ProviderID("t3code")
    public static let knownProviders: [ProviderID] = [.t3Code, .codex, .claude, .antigravity]

    public var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude Code"
        case .antigravity:
            return "Antigravity"
        case .t3Code:
            return "T3 Code"
        default:
            return rawValue.capitalized
        }
    }
}
