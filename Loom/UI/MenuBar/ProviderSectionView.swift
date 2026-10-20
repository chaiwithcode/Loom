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
    public let settings: LoomSettings?
    @State private var isShowingAdditionalQuotas = false
    @State private var isShowingDiagnostics = false
    @State private var isShowingRecentFinished = false

    public init(
        snapshot: ProviderSnapshot,
        showsSessions: Bool = true,
        showsUsage: Bool = true,
        expandedSessionIds: Set<String> = [],
        settings: LoomSettings? = nil
    ) {
        self.snapshot = snapshot
        self.showsSessions = showsSessions
        self.showsUsage = showsUsage
        self.expandedSessionIds = expandedSessionIds
        self.settings = settings
    }

    private var status: (label: String, color: Color) {
        if !snapshot.isEnabled { return ("Disabled", .secondary) }
        if snapshot.isRefreshing || snapshot.availability == .unknown { return ("Checking", .secondary) }
        if snapshot.errorMessage != nil { return ("Error", .red) }
        if snapshot.availability.isDegraded { return ("Degraded", .orange) }
        if snapshot.availability.isAvailable { return ("Available", .green) }
        return ("Unavailable", .orange)
    }

    private var visibleSessions: [AgentSession] {
        if let settings {
            return snapshot.sessions.filter { settings.shouldInclude(session: $0) }
        }
        return snapshot.sessions
    }

    private var attentionSessions: [AgentSession] {
        visibleSessions.filter { $0.state == .waiting || $0.state == .failed }
    }

    private var activeSessions: [AgentSession] {
        visibleSessions.filter { $0.state == .working || $0.state == .starting || $0.state == .idle || $0.state == .unknown }
    }

    private var finishedSessions: [AgentSession] {
        visibleSessions.filter { $0.state == .finished }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerHeader

            if showsUsage {
                if let usage = snapshot.usage {
                    primaryQuotas(usage)
                    if let error = usage.errorMessage ?? snapshot.usageErrorMessage, !error.isEmpty {
                        issueNotice(.usage(hasSavedData: true), details: error, color: .orange)
                    }
                } else if snapshot.id == .claude {
                    claudeQuotaNotice
                } else if let error = snapshot.usageErrorMessage, !error.isEmpty {
                    issueNotice(.usage(hasSavedData: false), details: error, color: .orange)
                } else if snapshot.availability.isAvailable && !snapshot.isRefreshing {
                    Text("No quota data available")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if let error = snapshot.errorMessage, !error.isEmpty {
                issueNotice(.discovery, details: error, color: .orange)
            } else if let reason = snapshot.availability.unavailabilityReason {
                notice(sanitizedNotice(reason), symbol: "exclamationmark.triangle", color: .orange)
            }

            // Render sessions with priority hierarchy
            if showsSessions {
                if !visibleSessions.isEmpty {
                    if showsUsage && snapshot.usage != nil { Divider() }

                    // 1. Attention Sessions (Waiting for input or Failed) appear first
                    if !attentionSessions.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.orange)
                            Text("Needs Attention (\(attentionSessions.count))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        .padding(.top, 2)

                        VStack(spacing: 8) {
                            ForEach(attentionSessions) { session in
                                SessionRowView(
                                    session: session,
                                    isExpanded: expandedSessionIds.contains(session.id),
                                    hideProjectPaths: settings?.hideProjectPaths ?? false
                                )
                            }
                        }
                    }

                    // 2. Active Sessions (Working / Starting / Idle / Unknown)
                    if !activeSessions.isEmpty {
                        if !attentionSessions.isEmpty {
                            Text("Active sessions")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            Text("Recent sessions")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 8) {
                            ForEach(activeSessions) { session in
                                SessionRowView(
                                    session: session,
                                    isExpanded: expandedSessionIds.contains(session.id),
                                    hideProjectPaths: settings?.hideProjectPaths ?? false
                                )
                            }
                        }
                    }

                    // 3. Completed Sessions (Finished)
                    if !finishedSessions.isEmpty {
                        if attentionSessions.isEmpty && activeSessions.isEmpty {
                            // If only completed sessions exist, display directly
                            Text("Recent sessions")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)

                            VStack(spacing: 8) {
                                ForEach(finishedSessions) { session in
                                    SessionRowView(
                                        session: session,
                                        isExpanded: expandedSessionIds.contains(session.id),
                                        hideProjectPaths: settings?.hideProjectPaths ?? false
                                    )
                                }
                            }
                        } else {
                            // Compact collapsible section so finished runs do not dominate popover
                            DisclosureGroup(isExpanded: $isShowingRecentFinished) {
                                VStack(spacing: 8) {
                                    ForEach(finishedSessions) { session in
                                        SessionRowView(
                                            session: session,
                                            isExpanded: expandedSessionIds.contains(session.id),
                                            hideProjectPaths: settings?.hideProjectPaths ?? false
                                        )
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 11))
                                    Text("Recent Completed Sessions (\(finishedSessions.count))")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .tint(.secondary)
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
                                let errVal = (settings?.hideProjectPaths ?? false) ? "Error details hidden by privacy setting" : err
                                diagRow("Metadata error", value: errVal)
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
                Divider().padding(.vertical, 4)
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

    private var claudeQuotaNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Quota monitoring not exposed by CLI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Text("Claude Code does not provide a local quota command or telemetry endpoint.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quota monitoring not exposed by CLI. Claude Code does not provide a local quota command or telemetry endpoint.")
    }

    private func issueNotice(_ issue: ProviderIssue, details: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(issue.title, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
            Text(issue.recovery).font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Technical details") {
                Text(sanitizedNotice(details))
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sanitizedNotice(_ text: String) -> String {
        if (settings?.hideProjectPaths ?? false) && (text.contains("/") || text.contains("~")) {
            return "Details hidden by privacy setting"
        }
        return text
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
            .font(.system(size: 17, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            if status.label == "Checking" {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(status.color).frame(width: 6, height: 6)
            }
            Text(status.label).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help("Local provider availability; this does not confirm account authentication")
    }

    @ViewBuilder
    private var planBadge: some View {
        if showsUsage, let plan = snapshot.usage?.planType, !plan.isEmpty {
            Text(plan)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        let reason: String?
        if usage.errorMessage != nil {
            reason = "Previously fetched quota; refresh to check current availability"
        } else {
            reason = nil
        }
        return UsageBarView(bucket: bucket, isStale: usage.isStale, updatedAt: usage.updatedAt, staleReason: reason)
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
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
