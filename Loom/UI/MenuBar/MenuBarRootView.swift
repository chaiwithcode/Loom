//
//  MenuBarRootView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
@preconcurrency import ObjectiveC
import LoomCore

public struct MenuBarRootView: View {
    @Bindable var store: SessionStore
    var settings: LoomSettings?
    @State private var contentHeights: [MenuTab: CGFloat] = [.agents: 180, .usage: 180, .storage: 180]
    @State private var selectedTab: MenuTab
    @State private var selectedProviderID: ProviderID?
    @State private var chromeHeight: CGFloat = 162
    @State private var selectorHeight: CGFloat = 36
    @State private var availableHeight: CGFloat = 720
    private let defaultExpandedSessionIds: Set<String>

    public init(
        store: SessionStore,
        settings: LoomSettings? = nil,
        isUsageExpanded: Bool = false,
        expandedSessionIds: Set<String> = [],
        selectedProviderID: ProviderID? = nil
    ) {
        self.store = store
        self.settings = settings
        self._selectedTab = State(initialValue: isUsageExpanded ? .usage : .agents)
        self.defaultExpandedSessionIds = expandedSessionIds
        self._selectedProviderID = State(initialValue: selectedProviderID)
    }

    private var resolvedSelectedProviderID: ProviderID? {
        let enabled = store.enabledSnapshots
        guard !enabled.isEmpty else { return nil }

        if let selected = selectedProviderID,
           enabled.contains(where: { $0.id == selected }) {
            return selected
        }

        if let defaultID = settings?.defaultProviderID,
           enabled.contains(where: { $0.id == defaultID }) {
            return defaultID
        }

        return enabled.first?.id
    }

    private func filteredSessions(for snapshot: ProviderSnapshot) -> [AgentSession] {
        if let settings {
            return snapshot.sessions.filter { settings.shouldInclude(session: $0) }
        }
        return snapshot.sessions
    }

    public var body: some View {
        LoomGlassContainer {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    MenuBarHeaderView(store: store, settings: settings, selectedTab: selectedTab)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 7)

                    // Native segmented navigation
                    FloatingGlassSegmentedControl(selectedTab: $selectedTab)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
                .background(MenuHeightReader(part: "header"))

                Divider().opacity(0.4)

                if selectedTab == .agents && !store.enabledSnapshots.isEmpty {
                    providerSelector
                        .background(MenuHeightReader(part: "selector"))
                }

                // Preserve separate scroll/disclosure state without letting the inactive
                // tab determine the menu height or participate in accessibility/input.
                ZStack(alignment: .top) {
                    ForEach(MenuTab.allCases, id: \.self) { tab in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                if tab == .storage {
                                    storageTabContent
                                } else if store.providerSnapshots.isEmpty {
                                    Text("No providers registered")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 24)
                                } else if store.enabledSnapshots.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "pause.circle")
                                            .font(.system(size: 28))
                                            .foregroundStyle(.secondary)
                                        Text("All Providers Disabled")
                                            .font(.headline)
                                        Text("Monitoring is disabled for all providers. Enable providers in Settings to monitor sessions and usage.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 24)
                                        Button("Open Settings…") {
                                            DockController.shared.showSettings(store: store)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.regular)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 32)
                                } else if tab == .agents {
                                    if let selectedSnapshot = store.enabledSnapshots.first(where: { $0.id == resolvedSelectedProviderID }) {
                                        ProviderSectionView(
                                            snapshot: selectedSnapshot,
                                            showsSessions: true,
                                            showsUsage: false,
                                            expandedSessionIds: defaultExpandedSessionIds,
                                            settings: settings
                                        )
                                    }
                                } else if tab == .usage {
                                    ForEach(store.enabledSnapshots) { snapshot in
                                        ProviderSectionView(
                                            snapshot: snapshot,
                                            showsSessions: false,
                                            showsUsage: true,
                                            expandedSessionIds: defaultExpandedSessionIds,
                                            settings: settings
                                        )
                                        if snapshot.id != store.enabledSnapshots.last?.id {
                                            Divider().padding(.vertical, 4)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .padding(.top, tab == .agents ? 8 : 16)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(MenuHeightReader(part: tab.rawValue))
                        }
                        .id(scrollId(for: tab))
                        .frame(height: viewportHeight(for: tab))
                        .opacity(selectedTab == tab ? 1 : 0)
                        .environment(\.loomGlassEnabled, selectedTab == tab)
                        .allowsHitTesting(selectedTab == tab)
                        .accessibilityHidden(selectedTab != tab)
                        .zIndex(selectedTab == tab ? 1 : 0)
                    }
                }
                .frame(height: viewportHeight(for: selectedTab), alignment: .top)
                .clipped()

                Divider()

                // Footer
                MenuBarFooterView(store: store)
                    .background(MenuHeightReader(part: "footer"))
            }
        }
        .frame(minWidth: 320, idealWidth: 420, maxWidth: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background { LoomPanelMaterial() }
        .background(MenuScreenHeightReader { height in
            if abs(availableHeight - height) > 0.5 { availableHeight = height }
        })
        .onPreferenceChange(MenuHeightKey.self) { heights in
            for tab in MenuTab.allCases {
                if let height = heights[tab.rawValue], height > 0,
                   abs((contentHeights[tab] ?? 180) - height) > 0.5 {
                    contentHeights[tab] = height
                }
            }
            if let header = heights["header"], let footer = heights["footer"] {
                let height = header + footer + 2 // The two dividers.
                if abs(chromeHeight - height) > 0.5 { chromeHeight = height }
            }
            if let selector = heights["selector"], selector > 0,
               abs(selectorHeight - selector) > 0.5 {
                selectorHeight = selector
            }
        }
        .onChange(of: settings?.defaultProviderID) { _, _ in
            selectedProviderID = nil
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .storage {
                Task {
                    await store.refreshStorage()
                }
            }
        }
        .task {
            // Refresh on popover display
            await store.refresh()
            await store.refreshStorage()
        }
    }

    @ViewBuilder
    private var providerSelector: some View {
        let snapshots = store.enabledSnapshots
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(snapshots) { snapshot in
                    providerButton(for: snapshot)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    ForEach(Array(snapshots.prefix(2))) { snapshot in
                        providerButton(for: snapshot)
                    }
                }
                if snapshots.count > 2 {
                    HStack(spacing: 4) {
                        ForEach(Array(snapshots.dropFirst(2))) { snapshot in
                            providerButton(for: snapshot)
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Provider selector")
    }

    private func providerButton(for snapshot: ProviderSnapshot) -> some View {
        let isSelected = resolvedSelectedProviderID == snapshot.id
        let sessionCount = filteredSessions(for: snapshot).count
        let needsAttention = snapshot.sessions.contains { $0.state == .waiting || $0.state == .failed }

        return ProviderFilterPill(
            snapshot: snapshot,
            sessionCount: sessionCount,
            needsAttention: needsAttention,
            isSelected: isSelected
        ) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedProviderID = snapshot.id
            }
        }
    }

    private func viewportHeight(for tab: MenuTab) -> CGFloat {
        let extraChrome: CGFloat
        if tab == .agents && !store.enabledSnapshots.isEmpty {
            extraChrome = selectorHeight
        } else {
            extraChrome = 0
        }
        return min(contentHeights[tab] ?? 180, max(1, availableHeight - (chromeHeight + extraChrome)))
    }

    private func scrollId(for tab: MenuTab) -> String {
        switch tab {
        case .agents:
            return "scroll-agents-\(resolvedSelectedProviderID?.rawValue ?? "none")"
        case .usage:
            return "scroll-usage"
        case .storage:
            return "scroll-storage"
        }
    }

    @ViewBuilder
    private var storageTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Storage Summary Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent storage")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    if store.isStorageScanning {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Measuring…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if let scannedAt = store.storageOverview?.scannedAt {
                        Text(freshnessText(scannedAt, now: Date()))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if store.isStorageScanning && store.storageOverview == nil {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Measuring…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                } else if let overview = store.storageOverview {
                    Text(ByteCountFormatter.string(fromByteCount: overview.totalBytes, countStyle: .file))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                } else {
                    Text("Not measured")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)

            if let overview = store.storageOverview {
                if overview.summaries.isEmpty {
                    Text("No local providers found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(overview.summaries) { summary in
                            providerStorageRow(summary, overview: overview)
                        }
                    }

                    if !overview.isComplete {
                        Text("Some folders could not be fully measured. Totals reflect accessible files.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }

            Button {
                DockController.shared.showSettings(store: store, tab: .storage)
            } label: {
                HStack {
                    Text("Storage Details…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open detailed Storage settings in Loom (⌘,)")
            .accessibilityLabel("Open Storage Details")
        }
    }

    private func freshnessText(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes == 0 { return "Measured just now" }
        if minutes < 60 { return "Measured \(minutes)m ago" }
        return "Measured \(minutes / 60)h ago"
    }

    private func providerStorageRow(_ summary: ProviderStorageSummary, overview: StorageOverview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    ProviderIconView(providerID: summary.providerID, size: 14)
                    Text(summary.name)
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer()
                if summary.hasData {
                    Text(ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                } else {
                    Text("No data")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            StorageComparativeBar(proportion: overview.proportion(for: summary.providerID))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.name), \(summary.hasData ? ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file) : "No data")")
    }
}

private enum MenuTab: String, CaseIterable {
    case agents, usage, storage

    var title: String {
        switch self {
        case .agents: return "Sessions"
        case .usage: return "Usage"
        case .storage: return "Storage"
        }
    }

    var icon: String {
        switch self {
        case .agents: return "bolt.horizontal.circle"
        case .usage: return "gauge.with.dots.needle.33percent"
        case .storage: return "internaldrive"
        }
    }
}

private struct FloatingGlassSegmentedControl: View {
    @Binding var selectedTab: MenuTab

    var body: some View {
        Picker("Section", selection: $selectedTab) {
            ForEach(MenuTab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
        .accessibilityIdentifier("main-tab-picker")
    }
}

private struct ProviderFilterPill: View {
    let snapshot: ProviderSnapshot
    let sessionCount: Int
    let needsAttention: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                ProviderIconView(providerID: snapshot.id, size: 12)

                Text(snapshot.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if needsAttention {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .help("This provider has sessions requiring attention")
                }

                Text("\(sessionCount)")
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .loomFloatingLens(isSelected: isSelected, isHovered: isHovered, cornerRadius: 12)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.displayName), \(sessionCount) \(sessionCount == 1 ? "session" : "sessions")\(needsAttention ? ", needs attention" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("provider-tab-\(snapshot.id.rawValue)")
        .onHover { isHovered = $0 }
    }
}

private struct StorageComparativeBar: View {
    let proportion: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 3.5)

                let width = max(0, min(proxy.size.width, proxy.size.width * CGFloat(proportion)))
                if width > 0 {
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: max(3, width), height: 3.5)
                }
            }
        }
        .frame(height: 3.5)
        .accessibilityElement(children: .ignore)
    }
}

private struct HeaderGlassButton: View {
    let icon: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    let helpText: String
    let accessibilityLabel: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : (isDisabled ? Color.secondary.opacity(0.4) : (isHovered ? Color.primary : Color.secondary)))
                .frame(width: 24, height: 24)
        }
        .loomToolbarButtonStyle()
        .controlSize(.small)
        .disabled(isDisabled)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .onHover { isHovered = $0 }
    }
}

private struct MenuBarHeaderView: View {
    let store: SessionStore
    var settings: LoomSettings?
    var selectedTab: MenuTab = .agents

    private var activitySubtitle: String {
        let enabled = store.enabledSnapshots
        let activeCount = enabled.reduce(0) { count, snap in
            count + snap.sessions.filter { $0.state == .working || $0.state == .starting }.count
        }
        let attentionCount = enabled.reduce(0) { count, snap in
            count + snap.sessions.filter { $0.state == .waiting || $0.state == .failed }.count
        }

        if attentionCount > 0 && activeCount > 0 {
            return "\(activeCount) active • \(attentionCount) need attention"
        } else if attentionCount > 0 {
            return "\(attentionCount) need attention"
        } else if activeCount > 0 {
            return "\(activeCount) active"
        } else {
            return "Ready"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            LoomIconView(size: 15)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            Text("Loom")
                .font(.system(size: 13, weight: .semibold))

            if let badge = store.fixture.badgeLabel {
                Text(badge)
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.secondary)
            }

            Text("•")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            Text(activitySubtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            // Native header actions
            HStack(spacing: 6) {
                // Quick Privacy Toggle
                HeaderGlassButton(
                    icon: (settings?.hideProjectPaths ?? false) ? "eye.slash.fill" : "eye",
                    isActive: settings?.hideProjectPaths ?? false,
                    helpText: (settings?.hideProjectPaths ?? false) ? "Project paths hidden (click to show)" : "Hide project paths",
                    accessibilityLabel: "Toggle project path privacy"
                ) {
                    if let settings {
                        settings.hideProjectPaths.toggle()
                    }
                }

                // Manual Refresh
                HeaderGlassButton(
                    icon: "arrow.clockwise",
                    isDisabled: store.isRefreshing,
                    helpText: "Refresh (⌘R)",
                    accessibilityLabel: "Refresh sessions"
                ) {
                    Task {
                        await store.refresh()
                        if selectedTab == .storage {
                            await store.refreshStorage(force: true)
                        }
                    }
                }

                // Settings
                HeaderGlassButton(
                    icon: "gearshape",
                    helpText: "Open Settings (⌘,)",
                    accessibilityLabel: "Settings"
                ) {
                    DockController.shared.showSettings(store: store)
                }
            }
        }
    }
}

private struct MenuBarFooterView: View {
    let store: SessionStore

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 5) {
                if store.isRefreshing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Refreshing…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else if let lastRefreshed = store.lastRefreshedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(updatedLabel(lastRefreshed, now: context.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Ready")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text("•")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                Text("v\(AppVersion.current.shortString)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .layoutPriority(1)
            .accessibilityLabel("Quit")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func updatedLabel(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes == 0 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes)m ago" }
        return "Updated \(minutes / 60)h ago"
    }
}

public enum PathDisambiguationHelper {
    public static func disambiguationCue(
        for group: ProjectGroup,
        in allGroups: [ProjectGroup]
    ) -> String? {
        guard let myURL = group.projectPath else { return nil }

        let sameNamedGroups = allGroups.filter {
            $0.projectName.caseInsensitiveCompare(group.projectName) == .orderedSame
        }
        guard sameNamedGroups.count > 1 else { return nil }

        let myParentURL = myURL.standardizedFileURL.deletingLastPathComponent()
        let myComponents = myParentURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard !myComponents.isEmpty else { return "/" }

        let otherParentComponents = sameNamedGroups
            .filter { $0.id != group.id }
            .compactMap { other -> [String]? in
                guard let otherURL = other.projectPath else { return nil }
                return otherURL.standardizedFileURL.deletingLastPathComponent().pathComponents.filter { $0 != "/" && !$0.isEmpty }
            }

        for k in 1...myComponents.count {
            let candidate = myComponents.suffix(k).joined(separator: "/")
            let hasCollision = otherParentComponents.contains { otherComp in
                let otherCandidate = otherComp.suffix(k).joined(separator: "/")
                return candidate == otherCandidate
            }
            if !hasCollision {
                return candidate
            }
        }

        return myParentURL.path
    }
}

private struct MenuHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct MenuHeightReader: View {
    let part: String
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: MenuHeightKey.self, value: [part: geometry.size.height])
        }
    }
}

// SwiftUI has no screen environment for MenuBarExtra. Observe only the containing
// window's display; SwiftUI continues to own the content and viewport dimensions.
private struct MenuScreenHeightReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScreenView {
        let view = ScreenView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ScreenView, context: Context) {
        view.onChange = onChange
    }

    final class ScreenView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var notificationTokens: ScreenNotificationTokens?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            notificationTokens = nil
            guard let window else { return }
            var tokens: [NSObjectProtocol] = []
            for (name, object) in [
                (NSWindow.didChangeScreenNotification, window as AnyObject?),
                (NSApplication.didChangeScreenParametersNotification, nil)
            ] {
                tokens.append(NotificationCenter.default.addObserver(
                    forName: name, object: object, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportHeight() }
                })
            }
            notificationTokens = ScreenNotificationTokens(tokens: tokens)
            reportHeight()
        }

        private func reportHeight() {
            guard let screen = window?.screen else { return }
            // Leave room for the popover edge/arrow inside the screen's usable area.
            let height = max(1, screen.visibleFrame.height - 16)
            DispatchQueue.main.async { [weak self] in self?.onChange?(height) }
        }
    }
}

private final class ScreenNotificationTokens {
    private let center: NotificationCenter
    private let tokens: [NSObjectProtocol]

    init(center: NotificationCenter = .default, tokens: [NSObjectProtocol]) {
        self.center = center
        self.tokens = tokens
    }

    deinit {
        for token in tokens {
            center.removeObserver(token)
        }
    }
}
