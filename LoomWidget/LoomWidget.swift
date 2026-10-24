//
//  LoomWidget.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import WidgetKit
import SwiftUI
import AppKit
import AppIntents

struct LoomWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: LoomWidgetSnapshot?
    let readResult: SnapshotReadResult
    var providerID: String = "all"
}

struct LoomWidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LoomWidgetEntry {
        LoomWidgetEntry(date: Date(), snapshot: .preview, readResult: .success(.preview))
    }

    func getSnapshot(in context: Context, completion: @escaping (LoomWidgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let result = SharedAppGroup.shared.readSnapshot()
        let snapshot: LoomWidgetSnapshot?
        switch result {
        case .success(let s):
            snapshot = s
        case .notFound, .corrupted, .unsupportedVersion:
            snapshot = nil
        }
        completion(LoomWidgetEntry(date: Date(), snapshot: snapshot, readResult: result))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LoomWidgetEntry>) -> Void) {
        let result = SharedAppGroup.shared.readSnapshot()
        let snapshot: LoomWidgetSnapshot?
        switch result {
        case .success(let s):
            snapshot = s
        case .notFound, .corrupted, .unsupportedVersion:
            snapshot = nil
        }
        let entry = LoomWidgetEntry(date: Date(), snapshot: snapshot, readResult: result)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Provider Row View

private struct WidgetHeader: View {
    var title = "Sessions"
    var font: Font = .system(size: 13, weight: .semibold)
    var body: some View {
        HStack(spacing: 6) {
            LoomIconView(size: 18).accessibilityHidden(true)
            Text(title).font(font).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct RemainingBar: View {
    let percent: Int
    var cached = false
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.18))
                Capsule().fill(WidgetQuotaPresentation.color(percent: percent, cached: cached))
                    .frame(width: proxy.size.width * CGFloat(min(100, max(0, percent))) / 100)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// Matches the menu's quota thresholds. macOS may adapt these in tinted widgets.
private enum WidgetQuotaPresentation {
    static func color(percent: Int?, cached: Bool) -> Color {
        guard !cached, let percent else { return .secondary }
        return percent >= 30 ? .green : (percent >= 10 ? .orange : .red)
    }

    // Spend the six-row Large budget on real windows, reclaiming unused provider rows.
    static func rowLimit(for provider: ProviderWidgetSummary, in providers: [ProviderWidgetSummary]) -> Int {
        let share = max(1, 6 / max(1, providers.count))
        let reserved = providers.filter { $0.id != provider.id }.reduce(0) {
            $0 + min(share, max(1, $1.allQuotaWindows.count))
        }
        return max(1, 6 - reserved)
    }
}

private struct WidgetLargeQuotaRow: View {
    let window: WidgetQuotaWindow
    let provider: ProviderWidgetSummary
    let entry: LoomWidgetEntry

    private var cached: Bool {
        provider.usageStatus == .stale || entry.snapshot?.isStale(at: entry.date) == true
            || entry.date.timeIntervalSince(window.observedAt) > 900
    }

    private var resetText: String {
        if cached { return "Saved data" }
        guard let reset = window.resetsAt else { return "Reset time unavailable" }
        guard reset > entry.date else { return "Awaiting reset update" }
        let minutes = max(1, Int(reset.timeIntervalSince(entry.date) / 60))
        let interval: String
        if minutes >= 1440 { interval = "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        else if minutes >= 60 { interval = "\(minutes / 60)h \(minutes % 60)m" }
        else { interval = "\(minutes)m" }
        return "Resets in \(interval)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text(window.percentRemaining.map { "\($0)% left" } ?? "Unavailable")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetQuotaPresentation.color(percent: window.percentRemaining, cached: cached))
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
            if let percent = window.percentRemaining {
                RemainingBar(percent: percent, cached: cached, height: 3)
            } else {
                Capsule().fill(.secondary.opacity(0.18)).frame(height: 3)
            }
            Text(resetText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetDataNotice: View {
    let result: SnapshotReadResult
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text("Open Loom to update.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private var title: String {
        switch result {
        case .notFound: return "Launch Loom"
        case .corrupted: return "Couldn’t read session data"
        case .unsupportedVersion: return "Update Loom"
        case .success: return "No session data"
        }
    }
}

struct LoomSmallWidgetView: View {
    let entry: LoomWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader()
            if let snapshot = entry.snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(snapshot.activeSessionCount)").font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("active").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text("\(snapshot.totalSessionCount) sessions tracked")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    ForEach(snapshot.providers.prefix(3)) { provider in
                        HStack(spacing: 4) {
                            Text(provider.displayName).lineLimit(1).layoutPriority(1)
                            Spacer(minLength: 2)
                            Text(provider.isEnabled ? "\(provider.sessionCount)" : "Off")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }.font(.system(size: 11))
                    }
                }
                if snapshot.isStale(at: entry.date) {
                    Label("Open Loom to update", systemImage: "clock").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if snapshot.attentionSessionCount > 0 {
                    Text("\(snapshot.attentionSessionCount) need attention").font(.system(size: 10)).foregroundStyle(.orange)
                }
            } else {
                Spacer(minLength: 0)
                WidgetDataNotice(result: entry.readResult)
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "loom://open"))
    }
}

struct LoomMediumWidgetView: View {
    let entry: LoomWidgetEntry
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader()
                Spacer(minLength: 0)
                if let snapshot = entry.snapshot {
                    Text("\(snapshot.activeSessionCount)")
                        .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("Active sessions").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(snapshot.totalSessionCount) tracked").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if snapshot.isStale(at: entry.date) {
                        Label("Needs update", systemImage: "clock").foregroundStyle(.secondary)
                    } else if snapshot.attentionSessionCount > 0 {
                        Text("\(snapshot.attentionSessionCount) need attention").foregroundStyle(.orange)
                    }
                    (Text("Updated ") + Text(snapshot.timestamp, style: .time)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                } else { WidgetDataNotice(result: entry.readResult); Spacer(minLength: 0) }
            }
            .font(.system(size: 10))
            .frame(width: 105, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = entry.snapshot {
                    ForEach(snapshot.providers.prefix(3)) { provider in
                        Link(destination: URL(string: "loom://provider/\(provider.id)")!) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 3) {
                                    Text(provider.displayName).fontWeight(.medium).layoutPriority(1)
                                    Spacer(minLength: 0)
                                    Text(provider.isEnabled ? "\(provider.sessionCount) \(provider.sessionCount == 1 ? "session" : "sessions")" : "Off")
                                        .foregroundStyle(.secondary).monospacedDigit()
                                }.font(.system(size: 12))
                                if let window = provider.usage?.windows?.first,
                                   let percent = window.percentRemaining, provider.isEnabled {
                                    let cached = snapshot.isStale(at: entry.date) || provider.usageStatus == .stale
                                        || entry.date.timeIntervalSince(window.observedAt) > 900
                                    HStack(spacing: 6) {
                                        RemainingBar(percent: percent, cached: cached)
                                        Text("\(window.compactLabel) · \(percent)% left").font(.system(size: 10)).monospacedDigit()
                                            .foregroundStyle(WidgetQuotaPresentation.color(percent: percent, cached: cached)).lineLimit(1).layoutPriority(1)
                                    }
                                    if cached { Text("Saved data").font(.system(size: 9)).foregroundStyle(.secondary) }
                                } else {
                                    Text(!provider.isEnabled ? "Monitoring off" :
                                        provider.usageStatus == .unsupported ? "Quota not supported" : "Quota unavailable")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                } else { Text("No provider data").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(URL(string: "loom://open"))
    }
}

enum QuotaProvider: String, AppEnum {
    case all = "all"
    case codex = "codex"
    case claude = "claude"
    case antigravity = "antigravity"

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Provider" }
    static var caseDisplayRepresentations: [QuotaProvider: DisplayRepresentation] {
        [
            .all: "All Enabled Providers",
            .codex: "Codex",
            .claude: "Claude Code",
            .antigravity: "Antigravity"
        ]
    }
}

struct QuotaConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Loom Quotas" }
    static var description: IntentDescription { "Remaining quota and reset times for your local AI providers." }
    @Parameter(title: "Provider", default: .all) var provider: QuotaProvider
}

struct QuotaTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LoomWidgetEntry {
        LoomWidgetEntry(date: .now, snapshot: .preview, readResult: .success(.preview), providerID: QuotaProvider.all.rawValue)
    }
    func snapshot(for configuration: QuotaConfiguration, in context: Context) async -> LoomWidgetEntry {
        if context.isPreview {
            var entry = placeholder(in: context)
            entry.providerID = configuration.provider.rawValue
            return entry
        }
        return read(configuration)
    }
    func timeline(for configuration: QuotaConfiguration, in context: Context) async -> Timeline<LoomWidgetEntry> {
        let entry = read(configuration)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(300)))
    }
    private func read(_ configuration: QuotaConfiguration) -> LoomWidgetEntry {
        let result = SharedAppGroup.shared.readSnapshot()
        let snapshot: LoomWidgetSnapshot?
        if case .success(let value) = result { snapshot = value } else { snapshot = nil }
        return LoomWidgetEntry(date: .now, snapshot: snapshot, readResult: result, providerID: configuration.provider.rawValue)
    }
}

// MARK: - Quota Widget Typography Hierarchy

private enum WidgetQuotaTypography {
    // Small Multi-Provider
    static let smallMultiProviderName = Font.system(size: 11, weight: .semibold)
    static let smallMultiWindowLabel = Font.system(size: 10, weight: .medium)
    static let smallMultiPercentage = Font.system(size: 13, weight: .bold)

    // Small Single-Provider
    static let smallSingleProviderName = Font.system(size: 13, weight: .semibold)
    static let smallSingleWindowLabel = Font.system(size: 11, weight: .medium)
    static let smallSinglePercentage = Font.system(size: 15, weight: .bold)
    static let smallSingleReset = Font.system(size: 10, weight: .regular)

    // Medium Multi-Column
    static let mediumProviderName = Font.system(size: 13, weight: .semibold)
    static let mediumWindowLabel = Font.system(size: 11, weight: .medium)
    static let mediumPercentage = Font.system(size: 15, weight: .bold)
    static let mediumReset = Font.system(size: 10, weight: .regular)

    // Large Multi-Section
    static let largeProviderName = Font.system(size: 13, weight: .semibold)
    static let largeWindowLabel = Font.system(size: 13, weight: .medium)
    static let largePercentage = Font.system(size: 17, weight: .bold)
    static let largeReset = Font.system(size: 10, weight: .regular)
}

struct LoomQuotaWidgetView: View {
    let entry: LoomWidgetEntry
    @Environment(\.widgetFamily) var family
    var aggregateTitle = "Quotas"

    private var canonicalOrder: [String] { ["codex", "claude", "antigravity"] }

    private var visibleProviders: [ProviderWidgetSummary] {
        guard let snapshot = entry.snapshot else { return [] }
        let sorted = snapshot.providers.sorted { p1, p2 in
            let idx1 = canonicalOrder.firstIndex(of: p1.id) ?? 99
            let idx2 = canonicalOrder.firstIndex(of: p2.id) ?? 99
            return idx1 < idx2
        }
        if entry.providerID == "all" || entry.providerID.isEmpty {
            return sorted.filter { $0.isEnabled && $0.usageStatus != .unsupported }
        } else {
            return sorted.filter { $0.id == entry.providerID }
        }
    }

    private var headerTitle: String {
        if entry.providerID == "all" || entry.providerID.isEmpty {
            return aggregateTitle
        }
        return visibleProviders.first?.displayName ?? aggregateTitle
    }

    private var widgetDestinationURL: URL {
        if entry.providerID == "all" || entry.providerID.isEmpty {
            if visibleProviders.count == 1, let single = visibleProviders.first {
                return URL(string: "loom://provider/\(single.id)") ?? URL(string: "loom://quotas")!
            }
            return URL(string: "loom://quotas")!
        }
        return URL(string: "loom://provider/\(entry.providerID)") ?? URL(string: "loom://quotas")!
    }

    var body: some View {
        Group {
            if entry.snapshot == nil {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: aggregateTitle)
                    Spacer(minLength: 0)
                    WidgetDataNotice(result: entry.readResult)
                    Spacer(minLength: 0)
                }
            } else if visibleProviders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: aggregateTitle)
                    Spacer(minLength: 0)
                    Text("No supported quota providers enabled")
                        .font(.system(size: 13, weight: .medium))
                    Text("Enable providers in Loom Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                switch family {
                case .systemMedium:
                    mediumQuotaView(visibleProviders)
                case .systemLarge:
                    largeQuotaView(visibleProviders)
                default:
                    if visibleProviders.count == 1 {
                        singleProviderSmallView(visibleProviders[0])
                    } else {
                        multiProviderSmallView(visibleProviders)
                    }
                }
            }
        }
        .widgetURL(widgetDestinationURL)
    }

    private func singleProviderSmallView(_ provider: ProviderWidgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: provider.displayName, font: WidgetQuotaTypography.smallSingleProviderName)
            if !provider.isEnabled {
                Spacer(minLength: 0)
                Text("Monitoring off")
                    .font(.system(size: 13, weight: .medium))
                Text("Enable this provider in Loom.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if provider.usageStatus == .unsupported {
                Spacer(minLength: 0)
                Text("Quota not supported")
                    .font(.system(size: 13, weight: .medium))
                Text("Open Loom for details.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if provider.usageStatus == .unavailable || provider.allQuotaWindows.isEmpty {
                Spacer(minLength: 0)
                Text("Quota unavailable")
                    .font(.system(size: 13, weight: .medium))
                Text("Open Loom for details.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                let windows = provider.allQuotaWindows
                ForEach(windows.prefix(2)) { window in
                    quotaWindow(window, provider: provider)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func multiProviderSmallView(_ providers: [ProviderWidgetSummary]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: aggregateTitle)
            Spacer(minLength: 0)
            ForEach(providers.prefix(3)) { provider in
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(WidgetQuotaTypography.smallMultiProviderName)
                        .lineLimit(1)

                    if !provider.isEnabled {
                        Text("Monitoring off")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if provider.usageStatus == .unsupported {
                        Text("Quota not supported")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if provider.usageStatus == .unavailable || provider.allQuotaWindows.isEmpty {
                        Text("Quota unavailable")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        let windows = Array(provider.allQuotaWindows.prefix(2))
                        HStack(spacing: 6) {
                            ForEach(windows) { window in
                                smallQuotaWindowPill(window, provider: provider)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func smallQuotaWindowPill(_ window: WidgetQuotaWindow, provider: ProviderWidgetSummary) -> some View {
        let cached = provider.usageStatus == .stale || entry.snapshot?.isStale(at: entry.date) == true
            || entry.date.timeIntervalSince(window.observedAt) > 900
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(window.compactLabel)
                    .font(WidgetQuotaTypography.smallMultiWindowLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let percent = window.percentRemaining {
                    Text("\(percent)%")
                        .font(WidgetQuotaTypography.smallMultiPercentage)
                        .foregroundStyle(WidgetQuotaPresentation.color(percent: percent, cached: cached))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(WidgetQuotaTypography.smallMultiPercentage)
                        .foregroundStyle(.secondary)
                }
            }
            if let percent = window.percentRemaining {
                RemainingBar(percent: percent, cached: cached, height: 3)
            } else {
                Capsule()
                    .fill(.secondary.opacity(0.18))
                    .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func mediumQuotaView(_ providers: [ProviderWidgetSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: headerTitle)
            HStack(alignment: .top, spacing: 10) {
                ForEach(providers.prefix(3)) { provider in
                    LoomUsageOverviewMediumColumn(provider: provider, entry: entry)
                }
            }
        }
    }

    private func largeQuotaView(_ providers: [ProviderWidgetSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                WidgetHeader(title: headerTitle)
                Spacer(minLength: 0)
                if let snapshot = entry.snapshot {
                    if snapshot.isStale(at: entry.date) {
                        Label("Saved data", systemImage: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        (Text("Updated ") + Text(snapshot.timestamp, style: .time))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            let displayProviders = Array(providers.prefix(3))
            ForEach(Array(displayProviders.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    Divider()
                }
                largeProviderSection(provider, maxRows: WidgetQuotaPresentation.rowLimit(for: provider, in: displayProviders))
            }
            Spacer(minLength: 0)
        }
    }

    private func largeProviderSection(_ provider: ProviderWidgetSummary, maxRows: Int = 3) -> some View {
        Link(destination: URL(string: "loom://provider/\(provider.id)")!) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(provider.displayName)
                        .font(WidgetQuotaTypography.largeProviderName)
                    Spacer(minLength: 0)
                    if !provider.isEnabled {
                        Text("Monitoring off")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if provider.usageStatus == .unsupported {
                        Text("Quota not supported")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if provider.usageStatus == .unavailable {
                        Text("Quota unavailable")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if provider.usageStatus == .stale || (entry.snapshot?.isStale(at: entry.date) == true) {
                        Text("Saved data")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                if !provider.isEnabled {
                    Text("Enable this provider in Loom.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if provider.usageStatus == .unsupported {
                    Text("Quota not supported for this provider.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if provider.usageStatus == .unavailable {
                    Text("Quota unavailable. Open Loom to update.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    let windows = provider.allQuotaWindows
                    if windows.isEmpty {
                        Text("Quota unavailable")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        let displayed = Array(windows.prefix(maxRows))
                        let overflow = windows.count - displayed.count

                        VStack(spacing: 4) {
                            ForEach(displayed) { window in
                                largeQuotaRow(window, provider: provider)
                            }
                            if overflow > 0 {
                                HStack {
                                    Spacer()
                                    Text("+\(overflow) more \(overflow == 1 ? "limit" : "limits")")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func largeQuotaRow(_ window: WidgetQuotaWindow, provider: ProviderWidgetSummary) -> some View {
        WidgetLargeQuotaRow(window: window, provider: provider, entry: entry)
    }

    private func quotaWindow(_ window: WidgetQuotaWindow, provider: ProviderWidgetSummary) -> some View {
        let cached = provider.usageStatus == .stale || entry.snapshot?.isStale(at: entry.date) == true
            || entry.date.timeIntervalSince(window.observedAt) > 900
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.label)
                    .font(WidgetQuotaTypography.smallSingleWindowLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text(window.percentRemaining.map { "\($0)% left" } ?? "Unavailable")
                    .font(WidgetQuotaTypography.smallSinglePercentage)
                    .foregroundStyle(WidgetQuotaPresentation.color(percent: window.percentRemaining, cached: cached))
                    .monospacedDigit()
                    .fixedSize()
            }
            if let percent = window.percentRemaining {
                RemainingBar(percent: percent, cached: cached, height: 4)
            }
            if cached {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                    Text("Saved ") + Text(window.observedAt, style: .relative) + Text(" ago")
                }
                .font(WidgetQuotaTypography.smallSingleReset)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else if let reset = window.resetsAt {
                Text(reset > entry.date ? "Resets in \(resetInterval(reset))" : "Awaiting reset update")
                    .font(WidgetQuotaTypography.smallSingleReset)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Reset time unavailable")
                    .font(WidgetQuotaTypography.smallSingleReset)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func resetInterval(_ date: Date) -> String {
        let minutes = max(1, Int(date.timeIntervalSince(entry.date) / 60))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

struct LoomWidgetEntryView: View {
    var entry: LoomWidgetEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        Group {
            if family == .systemMedium { LoomMediumWidgetView(entry: entry) }
            else { LoomSmallWidgetView(entry: entry) }
        }
        .padding(14)
        .containerBackground(.background, for: .widget)
    }
}

struct LoomSessionsWidget: Widget {
    let kind = "com.chaiwithcode.loom.widget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LoomWidgetTimelineProvider()) { LoomWidgetEntryView(entry: $0) }
            .configurationDisplayName("Loom Sessions")
            .description("See active sessions and local provider activity.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

struct LoomQuotasWidget: Widget {
    let kind = "com.chaiwithcode.loom.quotas"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: QuotaConfiguration.self, provider: QuotaTimelineProvider()) {
            LoomQuotaWidgetView(entry: $0).padding(14).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Loom Quotas")
        .description("Remaining quota and reset times for your local AI providers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct LoomUsageOverviewMediumColumn: View {
    let provider: ProviderWidgetSummary
    let entry: LoomWidgetEntry

    var body: some View {
        Link(destination: URL(string: "loom://provider/\(provider.id)")!) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 3) {
                    Text(provider.displayName)
                        .font(WidgetQuotaTypography.mediumProviderName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                if !provider.isEnabled {
                    Spacer(minLength: 0)
                    Text("Monitoring off")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else if provider.usageStatus == .unsupported {
                    Spacer(minLength: 0)
                    Text("Quota not supported")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else if provider.usageStatus == .unavailable || provider.allQuotaWindows.isEmpty {
                    Spacer(minLength: 0)
                    Text("Quota unavailable")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    let windows = provider.allQuotaWindows
                    let maxRows = 2
                    let displayed = Array(windows.prefix(maxRows))
                    let overflow = windows.count - displayed.count

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(displayed) { window in
                            compactRow(window)
                        }
                        if overflow > 0 {
                            Text("+\(overflow) more")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func compactRow(_ window: WidgetQuotaWindow) -> some View {
        let cached = provider.usageStatus == .stale || entry.snapshot?.isStale(at: entry.date) == true
            || entry.date.timeIntervalSince(window.observedAt) > 900
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(window.compactLabel)
                    .font(WidgetQuotaTypography.mediumWindowLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let percent = window.percentRemaining {
                    Text("\(percent)%")
                        .font(WidgetQuotaTypography.mediumPercentage)
                        .foregroundStyle(WidgetQuotaPresentation.color(percent: percent, cached: cached))
                        .monospacedDigit()
                } else {
                    Text("Unavailable")
                        .font(WidgetQuotaTypography.mediumReset)
                        .foregroundStyle(.secondary)
                }
            }
            if let percent = window.percentRemaining {
                RemainingBar(percent: percent, cached: cached, height: 4)
            }
            if cached {
                Text("Saved")
                    .font(WidgetQuotaTypography.mediumReset)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let reset = window.resetsAt {
                Text(reset > entry.date ? resetInterval(reset) : "Resetting")
                    .font(WidgetQuotaTypography.mediumReset)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func resetInterval(_ date: Date) -> String {
        let minutes = max(1, Int(date.timeIntervalSince(entry.date) / 60))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

struct LoomUsageOverviewMediumView: View {
    let entry: LoomWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Overview")
            if let snapshot = entry.snapshot {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(snapshot.activeSessionCount)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("active sessions").font(.system(size: 10))
                        Text("\(snapshot.totalSessionCount) tracked")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if snapshot.isStale(at: entry.date) {
                            Label("Saved data", systemImage: "clock")
                                .foregroundStyle(.secondary)
                        } else if snapshot.attentionSessionCount > 0 {
                            Text("\(snapshot.attentionSessionCount) need attention")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.system(size: 9))
                    .frame(width: 92, alignment: .leading)
                    Divider()
                    let providers = snapshot.providers.filter { $0.isEnabled && $0.usageStatus != .unsupported }
                    VStack(alignment: .leading, spacing: 9) {
                        if providers.isEmpty {
                            Text("No supported quota providers enabled")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(providers.prefix(3)) { provider in
                            quotaSummary(provider)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer(minLength: 0)
                WidgetDataNotice(result: entry.readResult)
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "loom://open"))
    }

    private func quotaSummary(_ provider: ProviderWidgetSummary) -> some View {
        // Overview highlights the tightest known quota; Quotas keeps separate windows.
        let window = provider.usageStatus == .unavailable ? nil : provider.allQuotaWindows
            .filter { $0.percentRemaining != nil }.min {
                ($0.percentRemaining ?? 100) < ($1.percentRemaining ?? 100)
            }
        let cached = provider.usageStatus == .stale || entry.snapshot?.isStale(at: entry.date) == true
            || window.map { entry.date.timeIntervalSince($0.observedAt) > 900 } == true
        return Link(destination: URL(string: "loom://provider/\(provider.id)")!) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(provider.displayName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(window?.percentRemaining.map { "\($0)% left" } ?? "Unavailable")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetQuotaPresentation.color(percent: window?.percentRemaining, cached: cached))
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
                if let window, let percent = window.percentRemaining {
                    RemainingBar(percent: percent, cached: cached, height: 3)
                    Text(cached ? "Saved data · \(window.label)" : window.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct LoomUsageOverviewLargeView: View {
    let entry: LoomWidgetEntry

    var body: some View {
        LoomQuotaWidgetView(entry: entry, aggregateTitle: "Overview")
    }
}

struct LoomUsageOverviewEntryView: View {
    var entry: LoomWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if family == .systemLarge {
                LoomUsageOverviewLargeView(entry: entry)
            } else {
                LoomUsageOverviewMediumView(entry: entry)
            }
        }
        .padding(14)
        .containerBackground(.background, for: .widget)
    }
}

struct LoomUsageOverviewWidget: Widget {
    let kind = "com.chaiwithcode.loom.usage-overview"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LoomWidgetTimelineProvider()) {
            LoomUsageOverviewEntryView(entry: $0)
        }
        .configurationDisplayName("Loom Usage Overview")
        .description("Session activity and quota headroom across your local providers.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct LoomWidgets: WidgetBundle {
    var body: some Widget {
        LoomSessionsWidget()
        LoomQuotasWidget()
        LoomUsageOverviewWidget()
    }
}

// MARK: - Exported Widget Symbols (Verified by scripts/verify-widget-package.sh)

@_cdecl("LoomSmallWidgetView")
public func _export_LoomSmallWidgetView() {}

@_cdecl("LoomMediumWidgetView")
public func _export_LoomMediumWidgetView() {}

@_cdecl("LoomQuotaWidgetView")
public func _export_LoomQuotaWidgetView() {}

@_cdecl("LoomUsageOverviewMediumView")
public func _export_LoomUsageOverviewMediumView() {}

@_cdecl("LoomUsageOverviewLargeView")
public func _export_LoomUsageOverviewLargeView() {}

#if DEBUG
#Preview("Large Quotas", as: .systemLarge) {
    LoomQuotasWidget()
} timeline: {
    LoomWidgetEntry(date: .now, snapshot: .preview, readResult: .success(.preview))
}

#Preview("Medium Overview", as: .systemMedium) {
    LoomUsageOverviewWidget()
} timeline: {
    LoomWidgetEntry(date: .now, snapshot: .preview, readResult: .success(.preview))
}
#endif
