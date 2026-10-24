//
//  DiagnosticsDisclosureView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import LoomCore

public struct DiagnosticsDisclosureView: View {
    public let snapshot: ProviderSnapshot
    public let hideProjectPaths: Bool
    @State private var isExpanded: Bool

    public init(
        snapshot: ProviderSnapshot,
        hideProjectPaths: Bool = false,
        isExpanded: Bool = false
    ) {
        self.snapshot = snapshot
        self.hideProjectPaths = hideProjectPaths
        self._isExpanded = State(initialValue: isExpanded)
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                // Availability & Degraded Status
                availabilitySection

                Divider().opacity(0.5)

                // Process & Session Metrics
                metricsSection

                // Latency & Timestamps
                Divider().opacity(0.5)
                timestampsSection

                // Safe Diagnostics Errors (Discovery vs Quota)
                if hasAnyErrors {
                    Divider().opacity(0.5)
                    errorsSection
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11))
                Text("Discovery Diagnostics")
                    .font(.system(size: 12, weight: .medium))

                if snapshot.hasWarning || snapshot.errorMessage != nil || snapshot.usageErrorMessage != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }

                Spacer(minLength: 0)

                if let dur = snapshot.diagnostics?.discoveryDurationMsFormatted {
                    Text(dur)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    // MARK: - Sections

    @ViewBuilder
    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Provider status")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge(for: snapshot.availability)
            }

            if let reason = snapshot.availability.unavailabilityReason {
                Text(Self.sanitizeErrorMessage(reason, hidePaths: hideProjectPaths))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var metricsSection: some View {
        let diag = snapshot.diagnostics
        let procCount = diag?.processesDetected ?? snapshot.sessions.reduce(0) { $0 + $1.processCount }
        let sessionCount = diag?.logicalSessions ?? snapshot.sessions.count
        let resolved = diag?.workspacesResolved ?? snapshot.sessions.filter({ $0.projectPath != nil }).count

        VStack(alignment: .leading, spacing: 4) {
            metricRow("Processes detected", value: "\(procCount)")
            metricRow("Logical sessions", value: "\(sessionCount)")
            metricRow("Workspace resolution", value: "\(resolved)/\(max(sessionCount, 1)) resolved")

            if let status = diag?.metadataStatus {
                metricRow("Metadata status", value: status.rawValue.capitalized)
            }
        }
    }

    @ViewBuilder
    private var timestampsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let dur = snapshot.diagnostics?.discoveryDurationMsFormatted {
                metricRow("Discovery latency", value: dur)
            }

            if let usage = snapshot.usage {
                metricRow("Quota observation", value: formatTimestamp(usage.updatedAt))
            } else {
                metricRow("Quota observation", value: snapshot.usageErrorMessage != nil ? "Failed" : "Unavailable")
            }
        }
    }

    @ViewBuilder
    private var errorsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Discovery Failure
            if let discErr = snapshot.errorMessage {
                errorRow(
                    label: "Discovery Error",
                    message: discErr,
                    icon: "exclamationmark.triangle.fill"
                )
            }

            // Metadata Diagnostics Error
            if let metaErr = snapshot.diagnostics?.metadataError {
                errorRow(
                    label: "Metadata Warning",
                    message: metaErr,
                    icon: "info.circle.fill"
                )
            }

            // Quota Observation Failure
            if let quotaErr = snapshot.usageErrorMessage ?? snapshot.usage?.errorMessage {
                errorRow(
                    label: "Quota Error",
                    message: quotaErr,
                    icon: "gauge.with.dots.needle.bottom.50percent"
                )
            }
        }
    }

    // MARK: - Helpers

    private var hasAnyErrors: Bool {
        snapshot.errorMessage != nil ||
        snapshot.diagnostics?.metadataError != nil ||
        snapshot.usageErrorMessage != nil ||
        snapshot.usage?.errorMessage != nil
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func errorRow(label: String, message: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(Self.sanitizeErrorMessage(message, hidePaths: hideProjectPaths))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func statusBadge(for availability: ProviderAvailability) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(for: availability))
                .frame(width: 6, height: 6)
            Text(availability.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor(for: availability))
        }
    }

    private func statusColor(for availability: ProviderAvailability) -> Color {
        switch availability {
        case .available: return .green
        case .degraded: return .orange
        case .unavailable, .error: return .red
        case .unknown: return .secondary
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 15 {
            return "Just now"
        } else if diff < 60 {
            return "\(Int(diff))s ago"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Sanitization

    public static func sanitizeErrorMessage(_ text: String, hidePaths: Bool) -> String {
        var sanitized = text

        // Redact potential access tokens or bearer credentials
        let patterns = [
            #"sk-[A-Za-z0-9_-]{8,}"#,
            #"Bearer\s+[A-Za-z0-9._-]+"#,
            #"token=[A-Za-z0-9._-]+"#,
            #"key=[A-Za-z0-9._-]+"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: NSRange(sanitized.startIndex..., in: sanitized),
                    withTemplate: "[redacted]"
                )
            }
        }

        if hidePaths {
            if sanitized.contains("/") || sanitized.contains("~") {
                return "Error details sanitized by privacy setting"
            }
        } else {
            let home = NSHomeDirectory()
            if sanitized.contains(home) {
                sanitized = sanitized.replacingOccurrences(of: home, with: "~")
            }
        }
        return sanitized
    }
}
