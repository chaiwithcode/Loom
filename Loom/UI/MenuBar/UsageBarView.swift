//
//  UsageBarView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import LoomCore

/// A remaining-quota card. Unknown data is never rendered as exhausted quota.
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

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(bucket.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(bucket.label)

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

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        if let fraction = bucket.remainingFraction {
                            Capsule()
                                .fill(barColor)
                                .frame(width: geometry.size.width * CGFloat(fraction))
                        }
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)

                Text(bucket.formattedResetTime(relativeTo: context.date)?.capitalizedFirst ?? "Reset time unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if isStale {
                    Label(staleLabel(relativeTo: context.date), systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
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
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
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
