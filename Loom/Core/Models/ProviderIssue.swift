//
//  ProviderIssue.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

/// Presentation-safe guidance. Raw diagnostic text stays behind explicit disclosure.
public struct ProviderIssue: Sendable, Equatable {
    public let title: String
    public let recovery: String

    public static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    public static func usage(hasSavedData: Bool) -> ProviderIssue {
        ProviderIssue(
            title: "Couldn’t refresh usage",
            recovery: hasSavedData
                ? "Showing saved data. Try refreshing again."
                : "Open the provider app, then try refreshing again."
        )
    }

    public static let discovery = ProviderIssue(
        title: "Couldn’t check sessions",
        recovery: "Open the provider app, then refresh Loom."
    )
}
