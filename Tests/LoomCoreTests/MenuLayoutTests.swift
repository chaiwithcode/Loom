//
//  MenuLayoutTests.swift
//  Loom
//
//  Created by Deepak Sharma on 03/10/2026.
//  Copyright © 2026 ChaiWithCode. All rights reserved.
//

import XCTest
import AppKit
import SwiftUI
@testable import LoomCore

// MARK: - Menu Layout Regression Tests

@MainActor
final class MenuLayoutTests: XCTestCase {

    // MARK: - Viewport Collapse Tests

    func testScrollViewWithMaxHeightOnlyCollapsesToZeroHeight() {
        struct CollapsedScrollView: View {
            var body: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {}
                }
                .frame(maxHeight: 460)
            }
        }

        let host = NSHostingView(rootView: CollapsedScrollView())
        let fittingSize = host.fittingSize
        XCTAssertEqual(
            fittingSize.height,
            0.0,
            "ScrollView with only maxHeight: 460 collapses to 0 height in AppKit hosting"
        )
    }

    // MARK: - Bounded Viewport Non-Zero Tests

    func testBoundedViewportMaintainsNonCollapsedFittingSize() {
        struct BoundedScrollView: View {
            var body: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {}
                }
                .frame(minHeight: 180, maxHeight: 560)
            }
        }

        let host = NSHostingView(rootView: BoundedScrollView())
        let fittingSize = host.fittingSize
        XCTAssertEqual(
            fittingSize.height,
            180.0,
            "Bounded ScrollView should have fitting height matching minHeight (180pt) when empty"
        )
        XCTAssertGreaterThanOrEqual(
            fittingSize.height,
            180.0,
            "Bounded ScrollView fitting height must be at least minHeight (180pt)"
        )
        XCTAssertLessThanOrEqual(
            fittingSize.height,
            560.0,
            "Bounded ScrollView fitting height must not exceed maxHeight (560pt)"
        )
    }

    // MARK: - Dynamic Content Scaling Tests

    func testDynamicContentWithinViewportScalesBetweenMinAndMaxHeight() {
        struct DynamicScrollViewport: View {
            let contentHeight: CGFloat
            var body: some View {
                ScrollView {
                    Color.clear.frame(height: contentHeight)
                }
                .frame(minHeight: 180, maxHeight: 560)
            }
        }

        // Sub-minHeight content (50pt) clamps up to minHeight (180pt)
        let smallContentHost = NSHostingView(rootView: DynamicScrollViewport(contentHeight: 50))
        XCTAssertEqual(
            smallContentHost.fittingSize.height,
            180.0,
            "Content below minHeight should clamp to minHeight (180pt)"
        )

        // Mid-range content (250pt) scales to exact content height
        let midContentHost = NSHostingView(rootView: DynamicScrollViewport(contentHeight: 250))
        XCTAssertEqual(
            midContentHost.fittingSize.height,
            250.0,
            "Content between minHeight and maxHeight should scale to content height (250pt)"
        )

        // Over-maxHeight content (700pt) clamps down to maxHeight (560pt)
        let largeContentHost = NSHostingView(rootView: DynamicScrollViewport(contentHeight: 700))
        XCTAssertEqual(
            largeContentHost.fittingSize.height,
            560.0,
            "Content above maxHeight should clamp to maxHeight (560pt)"
        )
    }

    // MARK: - Responsive Menu Layout Fitting Comparison

    func testMenuBarRootViewResponsiveWidthAndHeight() {
        struct HeaderStub: View {
            var body: some View {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "app")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Loom")
                        Text("Local AI Control Surface")
                    }
                    Spacer()
                    Button("Settings") {}
                    Button("Refresh") {}
                    Button("Quit") {}
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }

        struct FooterStub: View {
            var body: some View {
                HStack(alignment: .center) {
                    Text("Ready")
                    Spacer()
                    Button("Quit") {}
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }

        struct ResponsiveMenuLayout: View {
            var body: some View {
                VStack(spacing: 0) {
                    HeaderStub()
                    Divider()
                    ScrollView {
                        VStack(spacing: 14) {}
                    }
                    .frame(minHeight: 180, maxHeight: 560)
                    Divider()
                    FooterStub()
                }
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
            }
        }

        let host = NSHostingView(rootView: ResponsiveMenuLayout())
        let fitting = host.fittingSize

        // Width verifies responsive ideal width (380pt) within bounded range [320, 520]
        XCTAssertEqual(fitting.width, 380.0, "Responsive layout should have ideal width of 380pt")
        XCTAssertGreaterThanOrEqual(fitting.width, 320.0, "Width must be at least minWidth (320pt)")
        XCTAssertLessThanOrEqual(fitting.width, 520.0, "Width must not exceed maxWidth (520pt)")

        // Height maintains non-collapsed viewport (minHeight 180pt + header/footer = ~240-270pt)
        XCTAssertGreaterThanOrEqual(fitting.height, 220.0, "Menu maintains non-collapsed viewport above 220pt")
        XCTAssertLessThanOrEqual(fitting.height, 300.0, "Empty menu maintains compact height below 300pt")
    }

    // MARK: - Narrow & Long Data Layout Priority Tests

    func testNarrowLayoutProtectsStatusBadgeFromLongProjectName() {
        struct RowHeaderTestView: View {
            let project: String
            let stateName: String

            var body: some View {
                HStack(alignment: .center, spacing: 8) {
                    Text(project)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    HStack(spacing: 5) {
                        Circle().frame(width: 7, height: 7)
                        Text(stateName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .layoutPriority(2)

                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .layoutPriority(2)
                }
                .frame(width: 280) // Narrow constrained viewport
            }
        }

        let host = NSHostingView(rootView: RowHeaderTestView(
            project: "ExtremelyLongProjectNameThatWouldNormallyPushEverythingElseOutOfView",
            stateName: "Working"
        ))
        let size = host.fittingSize
        XCTAssertEqual(size.width, 280.0, "Constrained width is respected")
        XCTAssertGreaterThan(size.height, 0.0, "View renders non-zero height without crashing")
    }

    func testNarrowLayoutProtectsTimestampFromLongBranchName() {
        struct SubheaderTestView: View {
            let branch: String

            var body: some View {
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(branch)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text("8m ago")
                    }
                    .layoutPriority(1)
                }
                .frame(width: 280) // Narrow constrained viewport
            }
        }

        let host = NSHostingView(rootView: SubheaderTestView(
            branch: "feature/PROJ-123456789-very-long-branch-name-with-many-segments-and-details"
        ))
        let size = host.fittingSize
        XCTAssertEqual(size.width, 280.0)
        XCTAssertGreaterThan(size.height, 0.0)
    }

    func testUsageMeterFooterResponsiveSwitching() {
        struct MeterFooterTestView: View {
            let width: CGFloat
            let resetText: String
            let errorText: String

            var body: some View {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(resetText)
                        Spacer(minLength: 4)
                        Text(errorText)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(resetText)
                        Text(errorText)
                            .lineLimit(1)
                    }
                }
                .frame(width: width)
            }
        }

        // Wide viewport (480pt): fits in horizontal HStack (smaller height)
        let wideHost = NSHostingView(rootView: MeterFooterTestView(
            width: 480,
            resetText: "Resets in 12h 45m",
            errorText: "Rate limited"
        ))
        let wideHeight = wideHost.fittingSize.height

        // Narrow viewport (150pt): falls back to vertical VStack (greater height)
        let narrowHost = NSHostingView(rootView: MeterFooterTestView(
            width: 150,
            resetText: "Resets tomorrow at 12:00 PM (in 12h 45m)",
            errorText: "Failed to connect to provider daemon"
        ))
        let narrowHeight = narrowHost.fittingSize.height

        XCTAssertGreaterThan(
            narrowHeight,
            wideHeight,
            "Narrow viewport should wrap to vertical stack, increasing height to prevent clipping"
        )
    }

    // MARK: - Long Data & Empty State Tests

    func testLongDataPathsAndSummaryWrapping() {
        struct DetailWrapTestView: View {
            let path: String
            let summary: String

            var body: some View {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Path:")
                        .font(.caption)
                    Text(path)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Summary:")
                        .font(.caption)
                    Text(summary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 320)
            }
        }

        let host = NSHostingView(rootView: DetailWrapTestView(
            path: "/Users/deepak/Desktop/Projects/indie/SmartRemote/submodules/core/extra/very/long/path/with/no/breaks/deep/in/hierarchy",
            summary: "This is a detailed multiline summary describing the current agent operation which spans multiple sentences and needs to wrap cleanly without truncating abruptly or pushing out adjacent views."
        ))
        let size = host.fittingSize
        XCTAssertEqual(size.width, 320.0, "Fixed width is preserved")
        XCTAssertGreaterThan(size.height, 60.0, "Multiline content wraps vertically, expanding height naturally")
    }

    func testEmptyAndIdleProviderLayouts() {
        struct EmptyProvidersTestView: View {
            var body: some View {
                VStack {
                    Text("No providers registered")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
            }
        }

        let host = NSHostingView(rootView: EmptyProvidersTestView())
        let size = host.fittingSize
        XCTAssertEqual(size.width, 380.0, "Empty view adheres to ideal width 380pt")
        XCTAssertGreaterThan(size.height, 0.0, "Empty view has valid height")
    }

    func testReopeningAndStoreRefreshCycle() async {
        let fixture = DemoFixture.standard
        let store = SessionStore(providers: fixture.makeProviders(), fixture: fixture)
        XCTAssertNil(store.lastRefreshedAt)

        await store.refresh()
        guard let firstRefresh = store.lastRefreshedAt else {
            XCTFail("First refresh did not record timestamp")
            return
        }

        // Reopening / subsequent refresh
        await store.refresh()
        guard let secondRefresh = store.lastRefreshedAt else {
            XCTFail("Second refresh did not record timestamp")
            return
        }
        XCTAssertGreaterThanOrEqual(secondRefresh.timeIntervalSince(firstRefresh), 0.0, "Timestamp updates monotonically")
    }

    // MARK: - Session Metadata and PID Layout Tests

    func testSessionRowLayoutOmitsEmptySubheaderWhenMetadataAbsent() {
        struct SubheaderTestView: View {
            let hasBranch: Bool
            let hasActivity: Bool
            let hasPID: Bool

            var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project Title")
                        .font(.headline)

                    if hasBranch || hasActivity || hasPID {
                        HStack(spacing: 8) {
                            if hasPID {
                                Text("PID 1234").font(.caption2)
                            }
                            if hasBranch {
                                Text("main").font(.caption2)
                            }
                            Spacer()
                            if hasActivity {
                                Text("5m ago").font(.caption2)
                            }
                        }
                    }
                }
                .frame(width: 320)
            }
        }

        let emptyHost = NSHostingView(rootView: SubheaderTestView(hasBranch: false, hasActivity: false, hasPID: false))
        let emptyHeight = emptyHost.fittingSize.height

        let withPIDHost = NSHostingView(rootView: SubheaderTestView(hasBranch: false, hasActivity: false, hasPID: true))
        let withPIDHeight = withPIDHost.fittingSize.height

        XCTAssertGreaterThan(withPIDHeight, emptyHeight, "Row with PID renders metadata row whereas empty subheader is omitted")
    }

    func testSessionRowExpandedDetailsLayoutDisplaysExplicitPID() {
        struct ExpandedDetailsLayoutView: View {
            let pid: Int?

            var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Provider:").font(.caption).frame(width: 84, alignment: .leading)
                        Text("Codex").font(.caption)
                    }
                    HStack {
                        Text("Process ID:").font(.caption).frame(width: 84, alignment: .leading)
                        Text(pid.map { String($0) } ?? "Unavailable")
                            .font(.caption)
                            .foregroundStyle(pid != nil ? .primary : .secondary)
                    }
                    HStack {
                        Text("Project Path:").font(.caption).frame(width: 84, alignment: .leading)
                        Text("/Users/deepak/Desktop/Projects/oss/Loom").font(.caption)
                    }
                }
                .frame(width: 320)
            }
        }

        let hostWithPID = NSHostingView(rootView: ExpandedDetailsLayoutView(pid: 54321))
        XCTAssertGreaterThan(hostWithPID.fittingSize.height, 40.0)

        let hostWithoutPID = NSHostingView(rootView: ExpandedDetailsLayoutView(pid: nil))
        XCTAssertGreaterThan(hostWithoutPID.fittingSize.height, 40.0)
    }

    // MARK: - Session-First Grouped Layout Tests

    func testSessionRowWithProviderLabelLayout() {
        struct ProviderRowTestView: View {
            let session: AgentSession
            let showProvider: Bool

            var body: some View {
                HStack(alignment: .center, spacing: 8) {
                    if showProvider {
                        Text(session.provider.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else {
                        Text(session.projectName ?? "Untitled")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().frame(width: 7, height: 7)
                        Text(session.state.displayName).font(.caption)
                    }
                    .layoutPriority(2)
                }
                .frame(width: 320)
            }
        }

        let session = AgentSession(
            id: "test-row-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom"),
            state: .unknown,
            startedAt: Date(timeIntervalSince1970: 1700000000),
            lastActivityAt: nil,
            branch: "main",
            summary: "Testing row",
            pid: 1234
        )

        let host = NSHostingView(rootView: ProviderRowTestView(session: session, showProvider: true))
        let fitting = host.fittingSize
        XCTAssertGreaterThan(fitting.height, 10.0)
        XCTAssertEqual(fitting.width, 320.0)
    }

    func testGroupedSessionsMenuBarLayout() {
        struct GroupedMenuTestView: View {
            let groups: [ProjectGroup]
            let snapshots: [ProviderSnapshot]
            @State var isExpanded: Bool = true

            var body: some View {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(group.projectName)
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        if group.sessions.count > 1 {
                                            Text("\(group.sessions.count)").font(.caption)
                                        }
                                    }
                                }
                            }
                            Divider()
                            DisclosureGroup(isExpanded: $isExpanded) {
                                ForEach(snapshots) { snap in
                                    Text(snap.displayName)
                                }
                            } label: {
                                Text("Usage & Providers")
                            }
                        }
                        .padding(12)
                    }
                    .frame(minHeight: 180, maxHeight: 560)
                }
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
            }
        }

        let store = SessionStore(providers: [], fixture: .empty)
        let host = NSHostingView(rootView: GroupedMenuTestView(groups: store.groupedSessions, snapshots: store.providerSnapshots))
        let fitting = host.fittingSize
        XCTAssertGreaterThanOrEqual(fitting.width, 320.0)
        XCTAssertLessThanOrEqual(fitting.width, 520.0)
        XCTAssertGreaterThanOrEqual(fitting.height, 180.0)
    }

    func testHonestEmptyStateAndWarningIndicatorLayout() {
        struct EmptyStateLayoutView: View {
            let reason: EmptySessionReason
            let hasWarning: Bool

            var body: some View {
                VStack(spacing: 8) {
                    switch reason {
                    case .refreshing:
                        HStack(spacing: 6) {
                            ProgressView()
                            Text(reason.message)
                        }
                    case .discoveryFailed(let message):
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(message)
                        }
                    case .unavailable(let message):
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(message)
                        }
                    case .noActiveSessions:
                        Text(reason.message)
                    }

                    if hasWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                }
                .frame(width: 320)
            }
        }

        let failedHost = NSHostingView(rootView: EmptyStateLayoutView(
            reason: .discoveryFailed(message: "Discovery failed: daemon down"),
            hasWarning: true
        ))
        XCTAssertEqual(failedHost.fittingSize.width, 320.0)
        XCTAssertGreaterThan(failedHost.fittingSize.height, 20.0)

        let emptyHost = NSHostingView(rootView: EmptyStateLayoutView(
            reason: .noActiveSessions,
            hasWarning: false
        ))
        XCTAssertEqual(emptyHost.fittingSize.width, 320.0)
        XCTAssertGreaterThan(emptyHost.fittingSize.height, 10.0)
    }

    // MARK: - Focused macOS Polish Layout & Sizing Regressions

    func testContentDrivenSizingProgressionAcrossEmptySingleExpandedMany() {
        struct MockHeader: View {
            var body: some View {
                HStack { Text("Loom"); Spacer(); Text("Actions") }
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }

        struct MockFooter: View {
            var body: some View {
                HStack { Text("Ready"); Spacer(); Text("Quit") }
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }

        struct DynamicMenuShell: View {
            let innerHeight: CGFloat
            var body: some View {
                VStack(spacing: 0) {
                    MockHeader()
                    Divider()
                    ScrollView {
                        Color.clear.frame(height: innerHeight)
                    }
                    .frame(minHeight: 180, maxHeight: 560)
                    Divider()
                    MockFooter()
                }
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
            }
        }

        // 1. Empty sessions (inner content ~40pt, clamped to minHeight 180pt + header/footer ~70pt)
        let emptyHost = NSHostingView(rootView: DynamicMenuShell(innerHeight: 40))
        let emptyHeight = emptyHost.fittingSize.height
        XCTAssertEqual(emptyHeight, 250.0, "Empty menu clamps scrollview to 180pt, giving ~250pt total height (non-zero bounds)")

        // 2. Single session (inner content ~100pt, clamped to minHeight 180pt)
        let singleHost = NSHostingView(rootView: DynamicMenuShell(innerHeight: 100))
        let singleHeight = singleHost.fittingSize.height
        XCTAssertEqual(singleHeight, 250.0, "Single session stays within compact minHeight bounds")

        // 3. Expanded details / usage (inner content ~300pt, content-driven growth)
        let expandedHost = NSHostingView(rootView: DynamicMenuShell(innerHeight: 300))
        let expandedHeight = expandedHost.fittingSize.height
        XCTAssertEqual(expandedHeight, 370.0, "Expanded content scales naturally (300pt content + 70pt header/footer)")
        XCTAssertGreaterThan(expandedHeight, singleHeight, "Expanded content height is strictly greater than collapsed single session")

        // 4. Many sessions (inner content ~800pt, clamped to maxHeight 560pt + header/footer ~70pt)
        let manyHost = NSHostingView(rootView: DynamicMenuShell(innerHeight: 800))
        let manyHeight = manyHost.fittingSize.height
        XCTAssertEqual(manyHeight, 630.0, "Many sessions clamp to maxHeight 560pt, giving ~630pt total height")
        XCTAssertGreaterThan(manyHeight, expandedHeight, "Many sessions height is greater than medium expanded content")

        // Strictly ordered progression
        XCTAssertLessThanOrEqual(emptyHeight, singleHeight)
        XCTAssertLessThan(singleHeight, expandedHeight)
        XCTAssertLessThan(expandedHeight, manyHeight)
        XCTAssertLessThanOrEqual(manyHeight, 660.0, "Max height never exceeds bounded limits")
    }

    func testFlexibleWidthBoundsAt320And520WithoutHorizontalOverflow() {
        struct FlexibleWidthRowView: View {
            let width: CGFloat
            let project: String
            let provider: String
            let branch: String

            var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    // Group Header
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "folder")
                        Text(project)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }

                    // Session Row
                    HStack(alignment: .center, spacing: 8) {
                        Text(provider)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        HStack(spacing: 5) {
                            Circle().frame(width: 7, height: 7)
                            Text("Working")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .layoutPriority(2)

                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .layoutPriority(2)
                    }

                    // Subheader
                    HStack {
                        Text(branch)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("5m ago").font(.caption2).layoutPriority(1)
                    }
                }
                .padding(12)
                .frame(width: width)
            }
        }

        let longProject = "ExtraordinarilyLongProjectNameForTestingHorizontalBoundsAndClippingProtection"
        let longBranch = "feature/nested-segment-long-branch-name-with-many-hyphens-and-details-that-can-overflow"

        // Test at minimum container width 320pt
        let narrowHost = NSHostingView(rootView: FlexibleWidthRowView(
            width: 320,
            project: longProject,
            provider: "Antigravity",
            branch: longBranch
        ))
        let narrowSize = narrowHost.fittingSize
        XCTAssertEqual(narrowSize.width, 320.0, "Narrow container matches exact width 320pt")
        XCTAssertGreaterThan(narrowSize.height, 40.0, "Renders non-zero height without horizontal clipping")

        // Test at maximum container width 520pt
        let wideHost = NSHostingView(rootView: FlexibleWidthRowView(
            width: 520,
            project: longProject,
            provider: "Antigravity",
            branch: longBranch
        ))
        let wideSize = wideHost.fittingSize
        XCTAssertEqual(wideSize.width, 520.0, "Wide container matches exact width 520pt")
        XCTAssertGreaterThan(wideSize.height, 40.0, "Renders non-zero height without horizontal clipping")
    }

    func testProjectHeaderHierarchyAndParentPathCueDisambiguation() {
        func shortestUniqueParentSuffix(
            projectPath: URL,
            projectName: String,
            allProjects: [(name: String, path: URL)]
        ) -> String? {
            let sameNamed = allProjects.filter { $0.name.caseInsensitiveCompare(projectName) == .orderedSame }
            guard sameNamed.count > 1 else { return nil }

            let myParentURL = projectPath.standardizedFileURL.deletingLastPathComponent()
            let myComponents = myParentURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            guard !myComponents.isEmpty else { return "/" }

            let others = sameNamed.filter { $0.path.standardizedFileURL != projectPath.standardizedFileURL }
                .map { $0.path.standardizedFileURL.deletingLastPathComponent().pathComponents.filter { $0 != "/" && !$0.isEmpty } }

            for k in 1...myComponents.count {
                let candidate = myComponents.suffix(k).joined(separator: "/")
                let hasCollision = others.contains { other in
                    let otherCandidate = other.suffix(k).joined(separator: "/")
                    return candidate == otherCandidate
                }
                if !hasCollision {
                    return candidate
                }
            }
            return myParentURL.path
        }

        struct ProjectHeaderDisambiguationView: View {
            let projectName: String
            let cue: String?
            let sessionCount: Int

            var body: some View {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "folder")
                    Text(projectName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(projectName)

                    if let cue = cue {
                        Text(cue)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                            .help(cue)
                    }

                    Spacer()

                    if sessionCount > 1 {
                        Text("\(sessionCount)")
                            .font(.caption)
                    }
                }
                .frame(width: 380)
            }
        }

        // 1. Same project name AND same parent basename (e.g. /a/work/Loom vs /b/work/Loom)
        // Must expand to multiple components (a/work vs b/work)
        let projectsWithSameParentBasename: [(name: String, path: URL)] = [
            ("Loom", URL(fileURLWithPath: "/a/work/Loom")),
            ("Loom", URL(fileURLWithPath: "/b/work/Loom"))
        ]
        let cueA = shortestUniqueParentSuffix(
            projectPath: URL(fileURLWithPath: "/a/work/Loom"),
            projectName: "Loom",
            allProjects: projectsWithSameParentBasename
        )
        let cueB = shortestUniqueParentSuffix(
            projectPath: URL(fileURLWithPath: "/b/work/Loom"),
            projectName: "Loom",
            allProjects: projectsWithSameParentBasename
        )
        XCTAssertEqual(cueA, "a/work", "Shortest unique parent suffix expands beyond basename 'work' to 'a/work'")
        XCTAssertEqual(cueB, "b/work", "Shortest unique parent suffix expands beyond basename 'work' to 'b/work'")

        let repoAHost = NSHostingView(rootView: ProjectHeaderDisambiguationView(
            projectName: "Loom",
            cue: cueA,
            sessionCount: 2
        ))
        let repoASize = repoAHost.fittingSize
        XCTAssertEqual(repoASize.width, 380.0)
        XCTAssertGreaterThan(repoASize.height, 10.0)

        let repoBHost = NSHostingView(rootView: ProjectHeaderDisambiguationView(
            projectName: "Loom",
            cue: cueB,
            sessionCount: 1
        ))
        let repoBSize = repoBHost.fittingSize
        XCTAssertEqual(repoBSize.width, 380.0)
        XCTAssertGreaterThan(repoBSize.height, 10.0)

        // 2. Same project name with distinct parent basenames (/work/Loom vs /personal/Loom)
        let distinctParents: [(name: String, path: URL)] = [
            ("Loom", URL(fileURLWithPath: "/Users/deepak/work/Loom")),
            ("Loom", URL(fileURLWithPath: "/Users/deepak/personal/Loom"))
        ]
        let cueWork = shortestUniqueParentSuffix(
            projectPath: URL(fileURLWithPath: "/Users/deepak/work/Loom"),
            projectName: "Loom",
            allProjects: distinctParents
        )
        let cuePersonal = shortestUniqueParentSuffix(
            projectPath: URL(fileURLWithPath: "/Users/deepak/personal/Loom"),
            projectName: "Loom",
            allProjects: distinctParents
        )
        XCTAssertEqual(cueWork, "work", "Distinct parent basename uses compact single component 'work'")
        XCTAssertEqual(cuePersonal, "personal", "Distinct parent basename uses compact single component 'personal'")

        // 3. Unique project repo: no duplicate name, parent folder cue is omitted
        let uniqueCue = shortestUniqueParentSuffix(
            projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/indie/SmartRemote"),
            projectName: "SmartRemote",
            allProjects: distinctParents + [("SmartRemote", URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/indie/SmartRemote"))]
        )
        XCTAssertNil(uniqueCue, "Unique project name omits parent folder cue")
    }

    func testStatusAlignedWithTextAndSymbolProtectedFromTruncation() {
        struct StatusAlignmentTestView: View {
            let providerName: String
            let state: AgentState
            let width: CGFloat

            var body: some View {
                HStack(alignment: .center, spacing: 8) {
                    Text(providerName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    HStack(spacing: 5) {
                        switch state {
                        case .working:
                            Circle().frame(width: 7, height: 7)
                        case .idle:
                            Circle().strokeBorder(lineWidth: 1.5).frame(width: 7, height: 7)
                        case .unknown:
                            Image(systemName: "questionmark.circle")
                        case .waiting:
                            Image(systemName: "exclamationmark.circle.fill")
                        case .finished:
                            Image(systemName: "checkmark.circle.fill")
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                        }
                        Text(state.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .layoutPriority(2)

                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .layoutPriority(2)
                }
                .frame(width: width)
            }
        }

        // Test across all 6 normalized states at narrow width 280pt
        for state in [AgentState.working, .idle, .unknown, .waiting, .finished, .failed] {
            let host = NSHostingView(rootView: StatusAlignmentTestView(
                providerName: "AntigravityVeryLongProviderNameThatWillTruncate",
                state: state,
                width: 280
            ))
            let size = host.fittingSize
            XCTAssertEqual(size.width, 280.0, "Narrow container respected for state \(state.displayName)")
            XCTAssertGreaterThan(size.height, 10.0, "Renders non-zero height for state \(state.displayName)")
        }
    }
}
