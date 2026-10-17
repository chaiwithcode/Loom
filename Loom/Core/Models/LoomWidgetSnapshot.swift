//
//  LoomWidgetSnapshot.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

/// Status of usage availability for a provider in the widget snapshot.
public enum ProviderUsageStatus: String, Codable, Sendable, Equatable {
    case available
    case unavailable
    case unsupported
    case stale
    case unknown
}

/// Individual quota window with its own observation time, independent of snapshot publication.
public struct WidgetQuotaWindow: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let percentRemaining: Int?
    public let resetsAt: Date?
    public let observedAt: Date
    public let windowDurationMins: Int?
    public var compactLabel: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return label }
        if minutes == 10080 { return "Weekly" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
    public init(id: String, label: String, percentRemaining: Int?, resetsAt: Date?, observedAt: Date,
                windowDurationMins: Int? = nil) {
        self.id = id; self.label = label
        self.percentRemaining = percentRemaining.map { min(100, max(0, $0)) }
        self.resetsAt = resetsAt; self.observedAt = observedAt
        self.windowDurationMins = windowDurationMins
    }
}

/// A logical group of related quota windows (e.g., standard windows, model limits).
public struct WidgetQuotaGroup: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let windows: [WidgetQuotaWindow]

    public init(id: String, label: String, windows: [WidgetQuotaWindow]) {
        self.id = id
        self.label = label
        self.windows = windows
    }
}

/// Generic, normalized representation of provider quota/usage suitable for widgets.
/// Provider-specific scraping, polling, and parsing remain strictly inside provider layers.
public struct ProviderUsageWidgetSummary: Codable, Sendable, Equatable {
    /// Normalized usage status
    public let status: ProviderUsageStatus

    /// Fraction of quota used (0.0 to 1.0), if known
    public let fractionUsed: Double?

    /// Percentage remaining (0 to 100), if known
    public let percentRemaining: Int?

    /// Percentage used (0 to 100), if known
    public let percentUsed: Int?

    /// Quota reset date, if known
    public let resetsAt: Date?

    /// Formatted reset description (e.g. "resets in 2h 10m"), if known
    public let formattedResetTime: String?

    /// Plan or tier label (e.g. "Pro", "Pay-as-you-go"), if known
    public let planType: String?

    /// Concise human-readable summary string (e.g., "73% left", "Usage unavailable", "Usage unsupported", "Stale usage")
    public let summary: String
    public let windows: [WidgetQuotaWindow]?
    public let groups: [WidgetQuotaGroup]?

    public init(
        status: ProviderUsageStatus,
        fractionUsed: Double? = nil,
        percentRemaining: Int? = nil,
        percentUsed: Int? = nil,
        resetsAt: Date? = nil,
        formattedResetTime: String? = nil,
        planType: String? = nil,
        summary: String,
        windows: [WidgetQuotaWindow]? = nil,
        groups: [WidgetQuotaGroup]? = nil
    ) {
        self.status = status
        self.fractionUsed = fractionUsed
        self.percentRemaining = percentRemaining
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
        self.formattedResetTime = formattedResetTime
        self.planType = planType
        self.summary = summary
        self.windows = windows
        self.groups = groups
    }
}

/// Summary of a single provider for widget display.
/// Excludes all command lines, project paths, and credentials.
public struct ProviderWidgetSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let sessionCount: Int
    public let healthStatus: String
    public let isDegradedOrUnavailable: Bool
    public let lifecycleSummary: String?
    public let usage: ProviderUsageWidgetSummary?

    public init(
        id: String,
        displayName: String,
        sessionCount: Int,
        healthStatus: String,
        isDegradedOrUnavailable: Bool,
        lifecycleSummary: String? = nil,
        usage: ProviderUsageWidgetSummary? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.sessionCount = sessionCount
        self.healthStatus = healthStatus
        self.isDegradedOrUnavailable = isDegradedOrUnavailable
        self.lifecycleSummary = lifecycleSummary
        self.usage = usage
    }

    public var isEnabled: Bool {
        healthStatus.lowercased() != "disabled"
    }

    public var usageStatus: ProviderUsageStatus {
        usage?.status ?? .unknown
    }

    public var usageSummaryText: String {
        usage?.summary ?? "Usage unknown"
    }

    /// All available quota windows for this provider, combining primary/secondary windows and additional groups without duplication.
    public var allQuotaWindows: [WidgetQuotaWindow] {
        guard let usage else { return [] }
        var result: [WidgetQuotaWindow] = []
        var seenIDs = Set<String>()
        if let windows = usage.windows {
            for window in windows {
                if !seenIDs.contains(window.id) {
                    seenIDs.insert(window.id)
                    result.append(window)
                }
            }
        }
        if let groups = usage.groups {
            for group in groups {
                for window in group.windows {
                    if !seenIDs.contains(window.id) {
                        seenIDs.insert(window.id)
                        result.append(window)
                    }
                }
            }
        }
        return result
    }
}

/// High-level presentation state of the widget snapshot.
public enum WidgetSnapshotState: String, Codable, Sendable, Equatable {
    case normal
    case empty
    case attentionNeeded
    case degraded
    case allDisabled
    case stale
}

/// A compact, privacy-safe snapshot of resolved Loom agent sessions and provider states.
/// Designed for atomic exchange with WidgetKit extensions.
public struct LoomWidgetSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let timestamp: Date
    public let activeSessionCount: Int
    public let attentionSessionCount: Int
    public let totalSessionCount: Int
    public let providerSummaries: [ProviderWidgetSummary]
    public let statusMessage: String?

    public var providers: [ProviderWidgetSummary] {
        providerSummaries
    }

    public init(
        schemaVersion: Int = currentSchemaVersion,
        timestamp: Date = Date(),
        activeSessionCount: Int,
        attentionSessionCount: Int,
        totalSessionCount: Int,
        providerSummaries: [ProviderWidgetSummary],
        statusMessage: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.activeSessionCount = activeSessionCount
        self.attentionSessionCount = attentionSessionCount
        self.totalSessionCount = totalSessionCount
        self.providerSummaries = providerSummaries
        self.statusMessage = statusMessage
    }

    /// Checks if the snapshot is older than the given threshold (default: 15 minutes).
    public func isStale(at date: Date = Date(), threshold: TimeInterval = 900) -> Bool {
        date.timeIntervalSince(timestamp) > threshold
    }

    /// Computes the overall presentation state for widget display.
    public func state(at date: Date = Date()) -> WidgetSnapshotState {
        if isStale(at: date) {
            return .stale
        }
        if !providerSummaries.isEmpty && providerSummaries.allSatisfy({ !$0.isEnabled }) {
            return .allDisabled
        }
        if attentionSessionCount > 0 {
            return .attentionNeeded
        }
        if providerSummaries.contains(where: { $0.isDegradedOrUnavailable && $0.isEnabled }) {
            return .degraded
        }
        if activeSessionCount == 0 {
            return .empty
        }
        return .normal
    }

    /// Creates a preview snapshot with placeholder values matching Milestone 3A intent.
    public static var preview: LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: currentSchemaVersion,
            timestamp: Date(),
            activeSessionCount: 3,
            attentionSessionCount: 0,
            totalSessionCount: 3,
            providerSummaries: [
                ProviderWidgetSummary(
                    id: "codex",
                    displayName: "Codex",
                    sessionCount: 2,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: "2 active",
                    usage: ProviderUsageWidgetSummary(
                        status: .available,
                        fractionUsed: 0.27,
                        percentRemaining: 73,
                        percentUsed: 27,
                        summary: "73% left",
                        windows: [
                            WidgetQuotaWindow(id: "5h", label: "5 hours", percentRemaining: 73,
                                resetsAt: Date().addingTimeInterval(7200), observedAt: Date()),
                            WidgetQuotaWindow(id: "weekly", label: "Weekly", percentRemaining: 38,
                                resetsAt: Date().addingTimeInterval(432000), observedAt: Date())
                        ],
                        groups: [
                            WidgetQuotaGroup(id: "models", label: "Other Models", windows: [
                                WidgetQuotaWindow(id: "gpt-4o", label: "GPT-4o", percentRemaining: 65,
                                    resetsAt: Date().addingTimeInterval(14400), observedAt: Date()),
                                WidgetQuotaWindow(id: "o1", label: "o1", percentRemaining: 20,
                                    resetsAt: Date().addingTimeInterval(28800), observedAt: Date())
                            ])
                        ]
                    )
                ),
                ProviderWidgetSummary(
                    id: "claude",
                    displayName: "Claude Code",
                    sessionCount: 1,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: "1 active",
                    usage: ProviderUsageWidgetSummary(
                        status: .unsupported,
                        summary: "Usage unsupported"
                    )
                ),
                ProviderWidgetSummary(
                    id: "antigravity",
                    displayName: "Antigravity",
                    sessionCount: 0,
                    healthStatus: "available",
                    isDegradedOrUnavailable: false,
                    lifecycleSummary: nil,
                    usage: ProviderUsageWidgetSummary(
                        status: .available,
                        fractionUsed: 0.40,
                        percentRemaining: 60,
                        percentUsed: 40,
                        summary: "60% left",
                        windows: [
                            WidgetQuotaWindow(id: "ag-5h", label: "5 hours", percentRemaining: 60,
                                resetsAt: Date().addingTimeInterval(10800), observedAt: Date(), windowDurationMins: 300)
                        ],
                        groups: [
                            WidgetQuotaGroup(id: "gemini", label: "Gemini Models", windows: [
                                WidgetQuotaWindow(id: "gemini-pro", label: "Gemini 1.5 Pro", percentRemaining: 82,
                                    resetsAt: Date().addingTimeInterval(10800), observedAt: Date()),
                                WidgetQuotaWindow(id: "gemini-flash", label: "Gemini 1.5 Flash", percentRemaining: 95,
                                    resetsAt: Date().addingTimeInterval(10800), observedAt: Date())
                            ])
                        ]
                    )
                )
            ],
            statusMessage: "3 active sessions"
        )
    }

    /// Creates an empty snapshot.
    public static var empty: LoomWidgetSnapshot {
        LoomWidgetSnapshot(
            schemaVersion: currentSchemaVersion,
            timestamp: Date(),
            activeSessionCount: 0,
            attentionSessionCount: 0,
            totalSessionCount: 0,
            providerSummaries: [],
            statusMessage: "No active sessions"
        )
    }
}
