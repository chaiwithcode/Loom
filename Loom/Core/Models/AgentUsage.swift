//
//  AgentUsage.swift
//  Loom
//
//  Created by Deepak Sharma on 03/10/2026.
//  Copyright © 2026 ChaiWithCode. All rights reserved.
//

import Foundation

/// A single usage / quota window (e.g. 5-hour window, weekly window, or custom bucket).
public struct UsageBucket: Identifiable, Hashable, Equatable, Sendable {
    public var id: String { identifier }
    public let identifier: String
    public let label: String

    /// Value between 0.0 and 1.0 representing fraction used, or nil if unknown.
    /// (e.g. 0.15 = 15% used, 1.0 = exhausted, 0.0 = completely unused).
    public let usedFraction: Double?

    /// Optional date when this quota window resets.
    public let resetsAt: Date?

    /// Window duration in minutes, if known (e.g. 300 for 5 hours, 10080 for 7 days).
    public let windowDurationMins: Int?

    public init(
        identifier: String,
        label: String,
        usedFraction: Double?,
        resetsAt: Date? = nil,
        windowDurationMins: Int? = nil
    ) {
        self.identifier = identifier
        self.label = label
        if let frac = usedFraction {
            if frac.isNaN || frac.isInfinite {
                self.usedFraction = nil
            } else {
                self.usedFraction = min(max(frac, 0.0), 1.0)
            }
        } else {
            self.usedFraction = nil
        }
        self.resetsAt = resetsAt
        self.windowDurationMins = windowDurationMins
    }

    /// Remaining fraction (1.0 - usedFraction), or nil if usedFraction is unknown.
    public var remainingFraction: Double? {
        guard let used = usedFraction else { return nil }
        return max(0.0, min(1.0, 1.0 - used))
    }

    /// Remaining percentage as integer 0...100, or nil if unknown.
    public var remainingPercent: Int? {
        guard let remaining = remainingFraction else { return nil }
        return Int((remaining * 100.0).rounded())
    }

    /// Used percentage as integer 0...100, or nil if unknown.
    public var usedPercent: Int? {
        guard let used = usedFraction else { return nil }
        return Int((used * 100.0).rounded())
    }

    /// Formatted relative reset string (e.g., "resets in 2h 10m", "resets in 4d", or "resetting now").
    public func formattedResetTime(relativeTo reference: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(reference)
        if interval <= 0 {
            return "resetting now"
        }

        let totalMinutes = Int((interval / 60.0).rounded(.down))
        let totalHours = totalMinutes / 60
        let days = totalHours / 24

        if days > 0 {
            let remHours = totalHours % 24
            if remHours > 0 {
                return "resets in \(days)d \(remHours)h"
            } else {
                return "resets in \(days)d"
            }
        } else if totalHours > 0 {
            let remMins = totalMinutes % 60
            if remMins > 0 {
                return "resets in \(totalHours)h \(remMins)m"
            } else {
                return "resets in \(totalHours)h"
            }
        } else {
            return "resets in \(max(1, totalMinutes))m"
        }
    }
}

/// A logical group of usage buckets (e.g., "Gemini Models", "Claude and GPT models").
public struct UsageGroup: Identifiable, Hashable, Equatable, Sendable {
    public var id: String { identifier }
    public let identifier: String
    public let label: String
    public let buckets: [UsageBucket]

    public init(identifier: String, label: String, buckets: [UsageBucket]) {
        self.identifier = identifier
        self.label = label
        self.buckets = buckets
    }
}

/// Overall provider quota / usage snapshot.
public struct ProviderUsageSnapshot: Hashable, Equatable, Sendable {
    public let providerID: ProviderID
    public let updatedAt: Date
    public let planType: String?
    public let primaryBucket: UsageBucket?
    public let secondaryBucket: UsageBucket?
    public let additionalGroups: [UsageGroup]
    public let isStale: Bool
    public let errorMessage: String?

    public init(
        providerID: ProviderID,
        updatedAt: Date = Date(),
        planType: String? = nil,
        primaryBucket: UsageBucket? = nil,
        secondaryBucket: UsageBucket? = nil,
        additionalGroups: [UsageGroup] = [],
        isStale: Bool = false,
        errorMessage: String? = nil
    ) {
        self.providerID = providerID
        self.updatedAt = updatedAt
        self.planType = planType
        self.primaryBucket = primaryBucket
        self.secondaryBucket = secondaryBucket
        self.additionalGroups = additionalGroups
        self.isStale = isStale
        self.errorMessage = errorMessage
    }

    /// Returns a copy of this snapshot marked as stale, optionally appending an error message.
    public func markedStale(error: String? = nil) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: self.providerID,
            updatedAt: self.updatedAt,
            planType: self.planType,
            primaryBucket: self.primaryBucket,
            secondaryBucket: self.secondaryBucket,
            additionalGroups: self.additionalGroups,
            isStale: true,
            errorMessage: error ?? self.errorMessage
        )
    }

    /// Returns all primary and secondary buckets plus buckets in groups.
    public var allBuckets: [UsageBucket] {
        var result: [UsageBucket] = []
        if let primaryBucket { result.append(primaryBucket) }
        if let secondaryBucket { result.append(secondaryBucket) }
        for group in additionalGroups {
            result.append(contentsOf: group.buckets)
        }
        return result
    }
}
