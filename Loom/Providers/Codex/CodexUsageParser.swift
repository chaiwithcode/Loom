//
//  CodexUsageParser.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public enum CodexUsageParser {
    /// Parses the JSON result object or payload from a Codex `account/rateLimits/read` response.
    public static func parseRateLimits(from jsonObject: [String: Any]) -> ProviderUsageSnapshot? {
        // If the object has a "result" key, unwrap it; otherwise assume it is the result itself.
        let result = (jsonObject["result"] as? [String: Any]) ?? jsonObject

        guard let rateLimits = result["rateLimits"] as? [String: Any] else {
            return nil
        }

        let planType = rateLimits["planType"] as? String

        let primaryBucket: UsageBucket?
        if let primaryDict = rateLimits["primary"] as? [String: Any] {
            primaryBucket = parseWindow(primaryDict, defaultIdentifier: "codex-primary", defaultLabel: "5h Window")
        } else {
            primaryBucket = nil
        }

        let secondaryBucket: UsageBucket?
        if let secondaryDict = rateLimits["secondary"] as? [String: Any] {
            secondaryBucket = parseWindow(secondaryDict, defaultIdentifier: "codex-secondary", defaultLabel: "Weekly Window")
        } else {
            secondaryBucket = nil
        }

        var additionalBuckets: [UsageBucket] = []
        if let byLimitId = result["rateLimitsByLimitId"] as? [String: [String: Any]] {
            for (limitId, limitDict) in byLimitId.sorted(by: { $0.key < $1.key }) {
                // If limitId contains primary or secondary, parse its sub-windows
                if let limPrimary = limitDict["primary"] as? [String: Any] {
                    if let bucket = parseWindow(limPrimary, defaultIdentifier: "\(limitId)-primary", defaultLabel: "\(limitId) (5h)") {
                        // Check if identical to top-level primary bucket to avoid redundant duplication
                        if !isDuplicate(bucket, of: primaryBucket) {
                            additionalBuckets.append(bucket)
                        }
                    }
                }
                if let limSecondary = limitDict["secondary"] as? [String: Any] {
                    if let bucket = parseWindow(limSecondary, defaultIdentifier: "\(limitId)-secondary", defaultLabel: "\(limitId) (Weekly)") {
                        if !isDuplicate(bucket, of: secondaryBucket) {
                            additionalBuckets.append(bucket)
                        }
                    }
                }
            }
        }

        // If we found zero valid buckets, return nil
        if primaryBucket == nil && secondaryBucket == nil && additionalBuckets.isEmpty {
            return nil
        }

        let groups: [UsageGroup]
        if !additionalBuckets.isEmpty {
            groups = [UsageGroup(identifier: "additional-limits", label: "Other Models", buckets: additionalBuckets)]
        } else {
            groups = []
        }

        return ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date(),
            planType: planType,
            primaryBucket: primaryBucket,
            secondaryBucket: secondaryBucket,
            additionalGroups: groups,
            isStale: false,
            errorMessage: nil
        )
    }

    /// Parses NDJSON data or raw JSON Data from the app-server response.
    public static func parseRateLimits(from data: Data) -> ProviderUsageSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseRateLimits(from: json)
    }

    private static func parseWindow(_ dict: [String: Any], defaultIdentifier: String, defaultLabel: String) -> UsageBucket? {
        let rawUsedPercent = dict["usedPercent"] as? NSNumber
        let usedFraction: Double?
        if let rawNum = rawUsedPercent {
            let val = rawNum.doubleValue
            if val < 0.0 || val.isNaN || val.isInfinite {
                usedFraction = nil
            } else {
                usedFraction = min(max(val / 100.0, 0.0), 1.0)
            }
        } else {
            usedFraction = nil
        }

        let resetsAt: Date?
        if let epochSec = dict["resetsAt"] as? NSNumber, epochSec.doubleValue > 0 {
            resetsAt = Date(timeIntervalSince1970: epochSec.doubleValue)
        } else {
            resetsAt = nil
        }

        let windowDurationMins = (dict["windowDurationMins"] as? NSNumber)?.intValue

        // Return nil only if usedFraction, resetsAt, and windowDuration are all nil
        if usedFraction == nil && resetsAt == nil && windowDurationMins == nil {
            return nil
        }

        var label = defaultLabel
        if let duration = windowDurationMins {
            if duration == 300 {
                label = "5h Window"
            } else if duration == 10080 {
                label = "Weekly Window"
            } else if duration >= 60 && duration % 60 == 0 {
                label = "\(duration / 60)h Window"
            } else {
                label = "\(duration)m Window"
            }
        }

        return UsageBucket(
            identifier: defaultIdentifier,
            label: label,
            usedFraction: usedFraction,
            resetsAt: resetsAt,
            windowDurationMins: windowDurationMins
        )
    }

    private static func isDuplicate(_ candidate: UsageBucket, of reference: UsageBucket?) -> Bool {
        guard let reference else { return false }
        return candidate.windowDurationMins == reference.windowDurationMins &&
               candidate.usedFraction == reference.usedFraction &&
               candidate.resetsAt == reference.resetsAt
    }
}
