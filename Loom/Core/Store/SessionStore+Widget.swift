//
//  SessionStore+Widget.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

extension LoomWidgetSnapshot {
    /// Constructs a privacy-safe widget snapshot from resolved SessionStore state.
    @MainActor
    public static func make(from store: SessionStore) -> LoomWidgetSnapshot {
        let active = store.allSessions.filter { $0.state == .working || $0.state == .starting }.count
        let attention = store.allSessions.filter { $0.state == .waiting || $0.state == .failed }.count
        let total = store.allSessions.count

        var summaries: [ProviderWidgetSummary] = []
        for snapshot in store.providerSnapshots {
            let isDegradedOrUnavailable: Bool
            let healthStr: String
            if !snapshot.isEnabled {
                healthStr = "disabled"
                isDegradedOrUnavailable = false
            } else {
                isDegradedOrUnavailable = !snapshot.availability.isAvailable || snapshot.errorMessage != nil
                switch snapshot.availability {
                case .available:
                    healthStr = snapshot.errorMessage != nil ? "error" : "available"
                case .degraded:
                    healthStr = "degraded"
                case .unavailable:
                    healthStr = "unavailable"
                case .error:
                    healthStr = "error"
                case .unknown:
                    healthStr = "unknown"
                }
            }

            // Lifecycle summary
            let lifecycleSummary: String?
            if snapshot.sessions.isEmpty {
                lifecycleSummary = nil
            } else {
                let workingCount = snapshot.sessions.filter { $0.state == .working }.count
                let startingCount = snapshot.sessions.filter { $0.state == .starting }.count
                let waitingCount = snapshot.sessions.filter { $0.state == .waiting }.count
                let failedCount = snapshot.sessions.filter { $0.state == .failed }.count
                let idleCount = snapshot.sessions.filter { $0.state == .idle }.count

                if failedCount > 0 {
                    lifecycleSummary = "\(failedCount) failed"
                } else if waitingCount > 0 {
                    lifecycleSummary = "\(waitingCount) waiting"
                } else if (workingCount + startingCount) > 0 {
                    lifecycleSummary = "\((workingCount + startingCount)) active"
                } else if idleCount > 0 {
                    lifecycleSummary = "\(idleCount) idle"
                } else {
                    lifecycleSummary = "\(snapshot.sessions.count) sessions"
                }
            }

            // Provider usage normalization
            let usageSummary: ProviderUsageWidgetSummary
            if !snapshot.isEnabled {
                usageSummary = ProviderUsageWidgetSummary(
                    status: .unavailable,
                    summary: "Monitoring disabled"
                )
            } else if snapshot.providerID == .claude {
                // Claude Code local integration currently does not provide quota/usage metrics
                usageSummary = ProviderUsageWidgetSummary(
                    status: .unsupported,
                    summary: "Usage unsupported"
                )
            } else if let usage = snapshot.usage {
                let windows = [usage.primaryBucket, usage.secondaryBucket].compactMap { $0 }.map {
                    WidgetQuotaWindow(id: $0.identifier, label: $0.label,
                        percentRemaining: $0.remainingPercent, resetsAt: $0.resetsAt, observedAt: usage.updatedAt,
                        windowDurationMins: $0.windowDurationMins)
                }
                let groups = usage.additionalGroups.isEmpty ? nil : usage.additionalGroups.map { group in
                    WidgetQuotaGroup(
                        id: group.identifier,
                        label: group.label,
                        windows: group.buckets.map { bucket in
                            WidgetQuotaWindow(
                                id: bucket.identifier,
                                label: bucket.label,
                                percentRemaining: bucket.remainingPercent,
                                resetsAt: bucket.resetsAt,
                                observedAt: usage.updatedAt,
                                windowDurationMins: bucket.windowDurationMins
                            )
                        }
                    )
                }
                let primary = usage.primaryBucket
                let pctRemaining = primary?.remainingPercent
                let pctUsed = primary?.usedPercent
                let formattedReset = primary?.formattedResetTime()

                if usage.isStale {
                    let label: String
                    if let pctRemaining {
                        label = "\(pctRemaining)% left (stale)"
                    } else if let pctUsed {
                        label = "\(pctUsed)% used (stale)"
                    } else {
                        label = "Stale usage"
                    }
                    usageSummary = ProviderUsageWidgetSummary(
                        status: .stale,
                        fractionUsed: primary?.usedFraction,
                        percentRemaining: pctRemaining,
                        percentUsed: pctUsed,
                        resetsAt: primary?.resetsAt,
                        formattedResetTime: formattedReset,
                        planType: usage.planType,
                        summary: label,
                        windows: windows,
                        groups: groups
                    )
                } else {
                    let label: String
                    if let pctRemaining {
                        label = "\(pctRemaining)% left"
                    } else if let pctUsed {
                        label = "\(pctUsed)% used"
                    } else if let primaryLabel = primary?.label, !primaryLabel.isEmpty {
                        label = primaryLabel
                    } else {
                        label = "Available"
                    }
                    usageSummary = ProviderUsageWidgetSummary(
                        status: .available,
                        fractionUsed: primary?.usedFraction,
                        percentRemaining: pctRemaining,
                        percentUsed: pctUsed,
                        resetsAt: primary?.resetsAt,
                        formattedResetTime: formattedReset,
                        planType: usage.planType,
                        summary: label,
                        windows: windows,
                        groups: groups
                    )
                }
            } else if snapshot.usageErrorMessage != nil {
                usageSummary = ProviderUsageWidgetSummary(
                    status: .unavailable,
                    summary: "Usage unavailable"
                )
            } else if !snapshot.availability.isAvailable {
                usageSummary = ProviderUsageWidgetSummary(
                    status: .unavailable,
                    summary: "Usage unavailable"
                )
            } else {
                usageSummary = ProviderUsageWidgetSummary(
                    status: .unknown,
                    summary: "Usage unknown"
                )
            }

            summaries.append(ProviderWidgetSummary(
                id: snapshot.providerID.rawValue,
                displayName: snapshot.displayName,
                sessionCount: snapshot.sessions.count,
                healthStatus: healthStr,
                isDegradedOrUnavailable: isDegradedOrUnavailable,
                lifecycleSummary: lifecycleSummary,
                usage: usageSummary
            ))
        }

        let status: String?
        if let reason = store.emptySessionReason {
            switch reason {
            case .noActiveSessions:
                status = "Idle"
            case .allProvidersDisabled:
                status = "All providers disabled"
            case .unavailable:
                status = "Providers unavailable"
            case .discoveryFailed:
                // Provider errors may contain paths, command lines, or credentials.
                // Keep detailed diagnostics in the app, outside the shared snapshot.
                status = "Session discovery failed"
            case .refreshing:
                status = "Refreshing..."
            }
        } else if active > 0 {
            status = "\(active) active \(active == 1 ? "session" : "sessions")"
        } else {
            status = nil
        }

        return LoomWidgetSnapshot(
            schemaVersion: currentSchemaVersion,
            timestamp: Date(),
            activeSessionCount: active,
            attentionSessionCount: attention,
            totalSessionCount: total,
            providerSummaries: summaries,
            statusMessage: status
        )
    }
}

extension SessionStore {
    /// Publishes the current session and provider state to the shared App Group snapshot for widgets.
    @MainActor
    @discardableResult
    public func publishWidgetSnapshot(to appGroup: SharedAppGroup = .shared) -> Bool {
        let snapshot = LoomWidgetSnapshot.make(from: self)
        let success = appGroup.writeSnapshot(snapshot)
        #if canImport(WidgetKit)
        if Bundle.main.bundleIdentifier == "com.chaiwithcode.loom" {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        return success
    }
}
