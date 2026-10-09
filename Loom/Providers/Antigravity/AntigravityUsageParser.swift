//
//  AntigravityUsageParser.swift
//  Loom
//
//  Created by Deepak Sharma on 03/10/2026.
//  Copyright © 2026 ChaiWithCode. All rights reserved.
//

import Foundation

public enum AntigravityUsageParser {

    /// Parses the JSON dictionary from Antigravity `RetrieveUserQuotaSummary` response.
    public static func parseQuotaSummary(from jsonObject: [String: Any]) -> ProviderUsageSnapshot? {
        // If wrapped in "response", unwrap it
        let root = (jsonObject["response"] as? [String: Any]) ?? jsonObject

        guard let groupsArray = root["groups"] as? [[String: Any]], !groupsArray.isEmpty else {
            return nil
        }

        var parsedGroups: [UsageGroup] = []
        var primaryCandidate: UsageBucket?
        var secondaryCandidate: UsageBucket?

        for groupDict in groupsArray {
            let groupDisplayName = (groupDict["displayName"] as? String) ?? "Quota"
            let bucketsArray = (groupDict["buckets"] as? [[String: Any]]) ?? []

            var groupBuckets: [UsageBucket] = []

            for bDict in bucketsArray {
                guard let bucketId = bDict["bucketId"] as? String else { continue }
                let bName = (bDict["displayName"] as? String) ?? bucketId

                let usedFraction: Double?
                if let remNum = bDict["remainingFraction"] as? NSNumber {
                    let rem = remNum.doubleValue
                    if rem < 0.0 || rem.isNaN || rem.isInfinite {
                        usedFraction = nil
                    } else {
                        // remainingFraction is 0.0...1.0, so usedFraction = 1.0 - remainingFraction
                        let clampedRem = min(max(rem, 0.0), 1.0)
                        usedFraction = 1.0 - clampedRem
                    }
                } else {
                    usedFraction = nil
                }

                let resetsAt: Date?
                if let resetStr = bDict["resetTime"] as? String {
                    resetsAt = parseDate(from: resetStr)
                } else {
                    resetsAt = nil
                }

                let durationMins: Int?
                if bucketId.contains("5h") || bName.localizedCaseInsensitiveContains("5 hour") || bName.localizedCaseInsensitiveContains("five hour") {
                    durationMins = 300
                } else if bucketId.contains("weekly") || bName.localizedCaseInsensitiveContains("weekly") {
                    durationMins = 10080
                } else {
                    durationMins = nil
                }

                // Short clean label
                let shortLabel: String
                if durationMins == 300 {
                    shortLabel = "\(groupDisplayName) 5h"
                } else if durationMins == 10080 {
                    shortLabel = "\(groupDisplayName) Weekly"
                } else {
                    shortLabel = bName
                }

                let bucket = UsageBucket(
                    identifier: bucketId,
                    label: shortLabel,
                    usedFraction: usedFraction,
                    resetsAt: resetsAt,
                    windowDurationMins: durationMins
                )

                groupBuckets.append(bucket)

                // Prioritize Gemini Models for primary and secondary summary buckets
                let isGemini = groupDisplayName.localizedCaseInsensitiveContains("gemini")
                if durationMins == 300 && (primaryCandidate == nil || isGemini) {
                    primaryCandidate = bucket
                } else if durationMins == 10080 && (secondaryCandidate == nil || isGemini) {
                    secondaryCandidate = bucket
                }
            }

            if !groupBuckets.isEmpty {
                parsedGroups.append(UsageGroup(identifier: groupDisplayName.lowercased().replacingOccurrences(of: " ", with: "-"), label: groupDisplayName, buckets: groupBuckets))
            }
        }

        // If no 5h/weekly candidate was found, fall back to first bucket
        if primaryCandidate == nil, let firstBucket = parsedGroups.first?.buckets.first {
            primaryCandidate = firstBucket
        }

        if primaryCandidate == nil && secondaryCandidate == nil && parsedGroups.isEmpty {
            return nil
        }

        return ProviderUsageSnapshot(
            providerID: .antigravity,
            updatedAt: Date(),
            planType: nil,
            primaryBucket: primaryCandidate,
            secondaryBucket: secondaryCandidate,
            additionalGroups: parsedGroups,
            isStale: false,
            errorMessage: nil
        )
    }

    /// Parses raw JSON Data from Antigravity `RetrieveUserQuotaSummary` response.
    public static func parseQuotaSummary(from data: Data) -> ProviderUsageSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseQuotaSummary(from: json)
    }

    public static func parseDate(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let d = isoFormatter.date(from: trimmed) {
            return d
        }
        let isoFractionalFormatter = ISO8601DateFormatter()
        isoFractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return isoFractionalFormatter.date(from: trimmed)
    }
}
