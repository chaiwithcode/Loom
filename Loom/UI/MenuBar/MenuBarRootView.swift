import SwiftUI
import AppKit
import LoomCore

public struct MenuBarRootView: View {
    @Bindable var store: SessionStore
    var settings: LoomSettings?
    @State private var contentHeights: [MenuTab: CGFloat] = [.agents: 180, .usage: 180]
    @State private var selectedTab: MenuTab
    @State private var chromeHeight: CGFloat = 81
    @State private var availableHeight: CGFloat = 720
    private let defaultExpandedSessionIds: Set<String>

    public init(
        store: SessionStore,
        settings: LoomSettings? = nil,
        isUsageExpanded: Bool = false,
        expandedSessionIds: Set<String> = []
    ) {
        self.store = store
        self.settings = settings
        self._selectedTab = State(initialValue: isUsageExpanded ? .usage : .agents)
        self.defaultExpandedSessionIds = expandedSessionIds
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                MenuBarHeaderView(store: store, settings: settings)
                HStack(spacing: 0) {
                    tabButton("Sessions", tab: .agents)
                    tabButton("Usage", tab: .usage)
                }
                .padding(.horizontal, 16)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Loom view")
            }
            .background(MenuHeightReader(part: "header"))

            Divider()

            // Preserve separate scroll/disclosure state without letting the inactive
            // tab determine the menu height or participate in accessibility/input.
            ZStack(alignment: .top) {
                ForEach(MenuTab.allCases, id: \.self) { tab in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if store.providerSnapshots.isEmpty {
                                Text("No providers registered")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 24)
                            } else {
                                ForEach(store.providerSnapshots) { snapshot in
                                    ProviderSectionView(
                                        snapshot: snapshot,
                                        showsSessions: tab == .agents,
                                        showsUsage: tab == .usage,
                                        expandedSessionIds: defaultExpandedSessionIds
                                    )
                                    if snapshot.id != store.providerSnapshots.last?.id {
                                        Divider().padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(MenuHeightReader(part: tab.rawValue))
                    }
                    .frame(height: viewportHeight(for: tab))
                    .opacity(selectedTab == tab ? 1 : 0)
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
        .frame(minWidth: 320, idealWidth: 420, maxWidth: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
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
        }
        .task {
            // Refresh on popover display
            await store.refresh()
        }
    }

    private func tabButton(_ title: String, tab: MenuTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(height: 2)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func viewportHeight(for tab: MenuTab) -> CGFloat {
        min(contentHeights[tab] ?? 180, max(1, availableHeight - chromeHeight))
    }
}

private enum MenuTab: String, CaseIterable {
    case agents, usage
}

private struct MenuBarHeaderView: View {
    let store: SessionStore
    var settings: LoomSettings?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
                .layoutPriority(1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Loom")
                        .font(.system(size: 20, weight: .bold))
                        .fontWeight(.bold)
                    if let badge = store.fixture.badgeLabel {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                }
                Text("Local AI agents")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 4)

            // Settings action
            Button {
                DockController.shared.showSettings(store: store)
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .frame(width: 26, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel("Settings")
            .help("Open Loom Settings (⌘,)")
            .layoutPriority(2)

            // Manual Refresh action
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .frame(width: 26, height: 28)
            .contentShape(Rectangle())
            .disabled(store.isRefreshing)
            .accessibilityLabel("Refresh sessions")
            .help("Refresh agent sessions")
            .layoutPriority(2)


        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

private struct MenuBarFooterView: View {
    let store: SessionStore

    var body: some View {
        HStack(alignment: .center) {
            if store.isRefreshing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Refreshing...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let lastRefreshed = store.lastRefreshedAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(updatedLabel(lastRefreshed, now: context.date))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Ready")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
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
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard let window else { return }
            for (name, object) in [
                (NSWindow.didChangeScreenNotification, window as AnyObject?),
                (NSApplication.didChangeScreenParametersNotification, nil)
            ] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: object, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportHeight() }
                })
            }
            reportHeight()
        }

        private func reportHeight() {
            guard let screen = window?.screen else { return }
            // Leave room for the popover edge/arrow inside the screen's usable area.
            let height = max(1, screen.visibleFrame.height - 16)
            DispatchQueue.main.async { [weak self] in self?.onChange?(height) }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
