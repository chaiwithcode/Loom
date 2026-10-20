//
//  UsageBarView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import LoomCore

/// A remaining-quota card designed with Liquid Glass principles.
/// Unknown data is never rendered as exhausted quota.
public struct UsageBarView: View {
    public let bucket: UsageBucket
    public let isStale: Bool
    public let updatedAt: Date?
    public let staleReason: String?
    public let errorMessage: String?

    public init(
        bucket: UsageBucket,
        isStale: Bool = false,
        updatedAt: Date? = nil,
        staleReason: String? = nil,
        errorMessage: String? = nil
    ) {
        self.bucket = bucket
        self.isStale = isStale
        self.updatedAt = updatedAt
        self.staleReason = staleReason
        self.errorMessage = errorMessage
    }

    private var barColor: Color {
        guard let percent = bucket.remainingPercent else { return .secondary }
        return percent >= 30 ? .green : (percent >= 10 ? .orange : .red)
    }

    private func staleLabel(relativeTo now: Date) -> String {
        guard let updatedAt else { return "Cached data" }
        let minutes = max(0, Int(now.timeIntervalSince(updatedAt) / 60))
        if minutes < 1 { return "Cached just now" }
        if minutes < 60 { return "Cached \(minutes)m ago" }
        return "Cached \(minutes / 60)h ago"
    }

    private enum PacingStatus {
        case onPace
        case accelerated
        case lightUsage

        var label: String {
            switch self {
            case .onPace: return "On pace"
            case .accelerated: return "Accelerated"
            case .lightUsage: return "Light"
            }
        }

        var color: Color {
            switch self {
            case .onPace: return .green
            case .accelerated: return .orange
            case .lightUsage: return .teal
            }
        }

        var icon: String {
            switch self {
            case .onPace: return "checkmark.circle"
            case .accelerated: return "bolt.fill"
            case .lightUsage: return "leaf"
            }
        }
    }

    /// Evaluates quota consumption pacing based only on reliable observed data and known window duration.
    private func pacingStatus(at now: Date) -> PacingStatus? {
        guard let used = bucket.usedFraction,
              let resetsAt = bucket.resetsAt,
              resetsAt > now else {
            return nil
        }

        let windowDurationSeconds: Double
        if let durationMins = bucket.windowDurationMins, durationMins > 0 {
            windowDurationSeconds = Double(durationMins * 60)
        } else if bucket.identifier.contains("5h") {
            windowDurationSeconds = 5 * 3600
        } else if bucket.identifier.contains("week") || bucket.identifier.contains("7d") {
            windowDurationSeconds = 7 * 86400
        } else {
            return nil
        }

        let remainingSeconds = resetsAt.timeIntervalSince(now)
        guard remainingSeconds > 0 && remainingSeconds <= windowDurationSeconds else {
            return nil
        }

        let elapsedFraction = (windowDurationSeconds - remainingSeconds) / windowDurationSeconds
        let diff = used - elapsedFraction

        if diff > 0.15 {
            return .accelerated
        } else if diff < -0.15 {
            return .lightUsage
        } else {
            return .onPace
        }
    }

    /// Formats exact reset date and time.
    private func resetDescription(at now: Date) -> String {
        guard let resetsAt = bucket.resetsAt else {
            return "Reset time unavailable"
        }

        let calendar = Calendar.current
        let timeStr = resetsAt.formatted(date: .omitted, time: .shortened)
        let relative = bucket.formattedResetTime(relativeTo: now)

        if calendar.isDateInToday(resetsAt) {
            return "Resets today at \(timeStr)"
        } else if calendar.isDateInTomorrow(resetsAt) {
            return "Resets tomorrow at \(timeStr)"
        } else if let relative {
            return relative.capitalizedFirst
        } else {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "EEE"
            let dayName = weekdayFormatter.string(from: resetsAt)
            return "Resets \(dayName) at \(timeStr)"
        }
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                // Header line: Label and optional Pacing badge
                HStack(alignment: .firstTextBaseline) {
                    Text(bucket.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(bucket.label)

                    Spacer(minLength: 4)

                    if let pacing = pacingStatus(at: context.date) {
                        HStack(spacing: 2.5) {
                            Image(systemName: pacing.icon)
                                .font(.system(size: 7.5, weight: .semibold))
                            Text(pacing.label)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(pacing.color)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(pacing.color.opacity(0.12), in: Capsule())
                        .help("Quota consumption pacing within current window")
                    }
                }

                // Main Quota Readout
                if let percent = bucket.remainingPercent {
                    (Text("\(percent)%").font(.system(size: 23, weight: .semibold))
                        + Text(" left").font(.system(size: 14)))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Text("Unavailable")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        if let fraction = bucket.remainingFraction {
                            Capsule()
                                .fill(barColor)
                                .frame(width: max(0, min(geometry.size.width, geometry.size.width * CGFloat(fraction))))
                        }
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)

                // Exact reset timing
                Text(resetDescription(at: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(bucket.formattedResetTime(relativeTo: context.date)?.capitalizedFirst ?? "")

                // Stale warning badge
                if isStale {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9.5, weight: .medium))
                        Text(staleLabel(relativeTo: context.date))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                    .help(staleReason ?? "Previously fetched quota; current data could not be confirmed")
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
            .loomCard(cornerRadius: 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(bucket.label), \(bucket.remainingPercent.map { "\($0) percent remaining" } ?? "remaining quota unavailable")\(isStale ? ", cached data" : "")")
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
