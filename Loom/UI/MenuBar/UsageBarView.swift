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

    private func pacingStatus(at now: Date) -> QuotaPacing? {
        guard !isStale, errorMessage == nil, let pacing = bucket.observedPacing,
              pacing.resetsAt > now,
              now.timeIntervalSince(pacing.observedAt) >= 0,
              now.timeIntervalSince(pacing.observedAt) <= 600 else { return nil }
        return pacing
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
            VStack(alignment: .leading, spacing: 6) {
                // Header line: Label and optional Pacing badge
                HStack(alignment: .center) {
                    Text(bucket.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .help(bucket.label)

                    Spacer(minLength: 4)

                    if let pacing = pacingStatus(at: context.date) {
                        HStack(spacing: 3) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 8, weight: .semibold))
                            Text("\((pacing.usedFractionPerHour * 100).formatted(.number.precision(.fractionLength(0...1))))%/h")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 0.5)
                        )
                        .help("Observed consumption rate over the last \(Int(pacing.sampleInterval)) seconds; this is not a forecast.")
                    }
                }

                // Quota is a data measure: a quiet semantic track and a solid remaining fill.
                GeometryReader { geometry in
                    let barWidth = geometry.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))

                        if let fraction = bucket.remainingFraction, fraction > 0, barWidth > 0 {
                            let activeWidth = min(barWidth, max(0, barWidth * CGFloat(fraction)))
                            Capsule()
                                .fill(barColor)
                                .frame(width: activeWidth, height: 5)
                        }
                    }
                }
                .frame(height: 5)
                .accessibilityHidden(true)

                // Bottom line: Percentage on leading, Exact reset time on trailing (with zero truncation)
                HStack(alignment: .firstTextBaseline) {
                    if let percent = bucket.remainingPercent {
                        Text("\(percent)% left")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(barColor)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    } else {
                        Text("Unavailable")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Spacer(minLength: 8)

                    Text(resetDescription(at: context.date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                        .help(bucket.formattedResetTime(relativeTo: context.date)?.capitalizedFirst ?? "")
                }

                // Stale warning badge
                if isStale {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9, weight: .medium))
                        Text(staleLabel(relativeTo: context.date))
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.20), lineWidth: 0.5)
                    )
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .loomCard(cornerRadius: 8)
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
