//
//  StatusItemController.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
import Observation
import LoomCore

// MARK: - Menu Bar Status Result

public struct MenuBarStatusResult: Equatable, Sendable {
    public let text: String?
    public let hasAttention: Bool
    public let activeCount: Int
    public let attentionCount: Int
    public let lowestQuotaPercent: Int?

    public init(
        text: String? = nil,
        hasAttention: Bool = false,
        activeCount: Int = 0,
        attentionCount: Int = 0,
        lowestQuotaPercent: Int? = nil
    ) {
        self.text = text
        self.hasAttention = hasAttention
        self.activeCount = activeCount
        self.attentionCount = attentionCount
        self.lowestQuotaPercent = lowestQuotaPercent
    }
}

// MARK: - Menu Bar Status Evaluator

public enum MenuBarStatusEvaluator {
    /// Evaluates the status text, attention indicator, active count, and lowest quota percentage.
    /// Strictly ignores stale, missing, or errored usage snapshots rather than showing false zero.
    public static func evaluate(
        mode: MenuBarStatusMode,
        snapshots: [ProviderSnapshot]
    ) -> MenuBarStatusResult {
        let healthySnapshots = snapshots.filter { $0.isEnabled && $0.availability.isAvailable }
        let allSessions = healthySnapshots.flatMap(\.sessions)

        // 1. Active working or starting agents count
        let activeCount = allSessions.filter { session in
            session.state == .working || session.state == .starting
        }.count

        // 2. Restrained attention indicator for confirmed sessions needing input or failed
        let attentionCount = allSessions.filter { session in
            session.state == .waiting || session.state == .failed
        }.count

        // 3. Lowest quota percentage:
        // Must be non-stale, non-errored, and supported.
        var validRemainingPercentages: [Int] = []
        for snapshot in healthySnapshots {
            guard let usage = snapshot.usage,
                  !usage.isStale,
                  Date().timeIntervalSince(usage.updatedAt) < 600,
                  snapshot.usageErrorMessage == nil,
                  usage.errorMessage == nil else {
                continue
            }

            for bucket in usage.allBuckets {
                if let rem = bucket.remainingPercent {
                    validRemainingPercentages.append(rem)
                }
            }
        }

        let lowestQuotaPercent = validRemainingPercentages.min()

        // 4. Status text formatted according to mode
        let text: String?
        switch mode {
        case .iconOnly:
            text = nil
        case .activeSessionCount:
            text = activeCount > 0 ? "\(activeCount)" : nil
        case .needsAttentionCount:
            text = attentionCount > 0 ? "\(attentionCount)" : nil
        case .lowestQuota:
            text = lowestQuotaPercent.map { "\($0)%" }
        }

        return MenuBarStatusResult(
            text: text,
            hasAttention: attentionCount > 0,
            activeCount: activeCount,
            attentionCount: attentionCount,
            lowestQuotaPercent: lowestQuotaPercent
        )
    }
}

// MARK: - Status Item Controller

@Observable
@MainActor
public final class StatusItemController {
    public static let shared = StatusItemController()

    public private(set) var currentStatus: MenuBarStatusResult = MenuBarStatusResult()

    public init() {}

    /// Updates the observed state from the current store and settings.
    public func update(store: SessionStore, settings: LoomSettings) {
        let mode = settings.menuBarStatusMode
        currentStatus = MenuBarStatusEvaluator.evaluate(mode: mode, snapshots: store.providerSnapshots)
    }

    /// Configures an AppKit NSStatusItem's button title, image, and tooltips directly if needed.
    public func updateStatusItem(_ statusItem: NSStatusItem, store: SessionStore, settings: LoomSettings) {
        update(store: store, settings: settings)

        guard let button = statusItem.button else { return }

        button.image = LoomIcon.menuBarImage
        button.imagePosition = .imageLeading

        if let text = currentStatus.text {
            let title = currentStatus.hasAttention ? "\(text) •" : text
            button.title = " \(title)"
        } else if currentStatus.hasAttention {
            button.title = " \(currentStatus.attentionCount) •"
        } else {
            button.title = ""
        }

        button.toolTip = accessibilityDescription(for: currentStatus)
    }

    public func accessibilityDescription(for status: MenuBarStatusResult) -> String {
        var parts: [String] = ["Loom"]
        if let text = status.text {
            parts.append(text)
        } else if status.hasAttention {
            parts.append("\(status.attentionCount) waiting")
        }
        if status.hasAttention {
            parts.append("\(status.attentionCount) \(status.attentionCount == 1 ? "session needs" : "sessions need") attention")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Menu Bar Status Label (SwiftUI Component for MenuBarExtra)

public struct MenuBarStatusLabel: View {
    @Bindable var store: SessionStore
    var settings: LoomSettings?

    public init(store: SessionStore, settings: LoomSettings? = nil) {
        self.store = store
        self.settings = settings
    }

    private var result: MenuBarStatusResult {
        let mode = settings?.menuBarStatusMode ?? .iconOnly
        return MenuBarStatusEvaluator.evaluate(mode: mode, snapshots: store.providerSnapshots)
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: LoomIcon.menuBarImage)
                .renderingMode(.template)

            if let text = result.text {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            } else if result.hasAttention {
                Text("\(result.attentionCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            if result.hasAttention {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts: [String] = ["Loom"]
        if let text = result.text {
            parts.append(text)
        } else if result.hasAttention {
            parts.append("\(result.attentionCount) waiting")
        }
        if result.hasAttention {
            parts.append("\(result.attentionCount) \(result.attentionCount == 1 ? "session needs" : "sessions need") attention")
        }
        return parts.joined(separator: ", ")
    }
}
