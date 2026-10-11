//
//  ProviderSectionView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import LoomCore

public struct ProviderSectionView: View {
    public let snapshot: ProviderSnapshot
    public let showsSessions: Bool
    public let showsUsage: Bool
    public let expandedSessionIds: Set<String>
    @State private var isShowingAdditionalQuotas = false
    @State private var isShowingDiagnostics = false

    public init(snapshot: ProviderSnapshot, showsSessions: Bool = true, showsUsage: Bool = true, expandedSessionIds: Set<String> = []) {
        self.snapshot = snapshot
        self.showsSessions = showsSessions
        self.showsUsage = showsUsage
        self.expandedSessionIds = expandedSessionIds
    }

    private var status: (label: String, color: Color) {
        if snapshot.isRefreshing || snapshot.availability == .unknown { return ("Checking", .secondary) }
        if snapshot.errorMessage != nil { return ("Error", .red) }
        if snapshot.availability.isDegraded { return ("Degraded", .orange) }
        if snapshot.availability.isAvailable { return ("Available", .green) }
        return ("Unavailable", .orange)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerHeader

            if showsUsage {
                if let usage = snapshot.usage {
                    primaryQuotas(usage)
                    if let error = usage.errorMessage ?? snapshot.usageErrorMessage, !error.isEmpty {
                        notice(error, symbol: "exclamationmark.triangle", color: .orange)
                    }
                } else if let error = snapshot.usageErrorMessage, !error.isEmpty {
                    notice("Quota unavailable: \(error)", symbol: "gauge.with.dots.needle.bottom.50percent", color: .orange)
                } else if snapshot.availability.isAvailable && !snapshot.isRefreshing {
                    Text("No quota data available")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if let error = snapshot.errorMessage, !error.isEmpty {
                notice(error, symbol: "exclamationmark.triangle", color: .red)
            } else if let reason = snapshot.availability.unavailabilityReason {
                notice(reason, symbol: "exclamationmark.triangle", color: .orange)
            }

            // Render any sessions supplied by the snapshot alongside provider notices.
            if showsSessions {
                if !snapshot.sessions.isEmpty {
                    if showsUsage && snapshot.usage != nil { Divider() }
                    Text("Recent sessions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(snapshot.sessions) { session in
                            SessionRowView(session: session, isExpanded: expandedSessionIds.contains(session.id))
                        }
                    }
                } else if snapshot.availability.isAvailable && snapshot.errorMessage == nil && !snapshot.isRefreshing {
                    Text("No recent sessions")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }

                // Expose Developer Discovery Diagnostics
                if let diag = snapshot.diagnostics {
                    DisclosureGroup(isExpanded: $isShowingDiagnostics) {
                        VStack(alignment: .leading, spacing: 6) {
                            diagRow("Processes detected", value: "\(diag.processesDetected)")
                            diagRow("Logical sessions", value: "\(diag.logicalSessions)")
                            diagRow("Workspaces resolved", value: "\(diag.workspacesResolved)/\(max(diag.logicalSessions, 1))")
                            diagRow("Metadata status", value: diag.metadataStatus.rawValue.capitalized)
                            if let dur = diag.discoveryDurationMsFormatted {
                                diagRow("Discovery duration", value: dur)
                            }
                            if let err = diag.metadataError {
                                diagRow("Metadata error", value: err)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 11))
                            Text("Discovery Diagnostics")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                }
            }

            if showsUsage, let usage = snapshot.usage, !usage.additionalGroups.isEmpty {
                Divider()
                DisclosureGroup(isExpanded: $isShowingAdditionalQuotas) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(usage.additionalGroups) { group in
                            Text(group.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            ForEach(group.buckets) { bucket in
                                quotaCard(bucket, usage: usage)
                            }
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Text("More model limits")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
                .tint(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(snapshot.displayName) section")
    }

    private func diagRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
    }

    private var providerHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                providerTitle.fixedSize()
                statusBadge.fixedSize()
                Spacer(minLength: 4)
                planBadge
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    providerTitle
                    Spacer(minLength: 4)
                    planBadge
                }
                statusBadge
            }
        }
    }

    private var providerTitle: some View {
        Text(snapshot.displayName)
            .font(.system(size: 18, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            if status.label == "Checking" {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(status.color).frame(width: 7, height: 7)
            }
            Text(status.label).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        .help("Local provider availability; this does not confirm account authentication")
    }

    @ViewBuilder
    private var planBadge: some View {
        if showsUsage, let plan = snapshot.usage?.planType, !plan.isEmpty {
            Text(plan)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                .help(plan)
        }
    }

    @ViewBuilder
    private func primaryQuotas(_ usage: ProviderUsageSnapshot) -> some View {
        if let primary = usage.primaryBucket, let secondary = usage.secondaryBucket {
            HStack(alignment: .top, spacing: 8) {
                quotaCard(primary, usage: usage)
                quotaCard(secondary, usage: usage)
            }
        } else if let bucket = usage.primaryBucket ?? usage.secondaryBucket {
            quotaCard(bucket, usage: usage)
        } else if usage.additionalGroups.allSatisfy({ $0.buckets.isEmpty }),
                  usage.errorMessage == nil, snapshot.usageErrorMessage == nil,
                  snapshot.availability.isAvailable, !snapshot.isRefreshing {
            Text("No quota data available")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func quotaCard(_ bucket: UsageBucket, usage: ProviderUsageSnapshot) -> some View {
        UsageBarView(bucket: bucket, isStale: usage.isStale, updatedAt: usage.updatedAt, staleReason: usage.errorMessage)
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
