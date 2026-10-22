//
//  SessionFilterBar.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
import LoomCore

// MARK: - Session Filter Criterion

public enum SessionFilterCriterion: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case needsAttention = "needsAttention"
    case working = "working"
    case recent = "recent"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "All"
        case .needsAttention: return "Needs Attention"
        case .working: return "Working"
        case .recent: return "Recent"
        }
    }
}

// MARK: - Session Filter Engine

public enum SessionFilterEngine {
    /// Determines whether a session matches the given filter criterion and search query.
    public static func matches(
        session: AgentSession,
        query: String,
        filter: SessionFilterCriterion,
        hideProjectPaths: Bool = false
    ) -> Bool {
        // 1. Criterion classification
        switch filter {
        case .all:
            break
        case .needsAttention:
            guard session.state == .waiting || session.state == .failed else { return false }
        case .working:
            guard session.state == .working || session.state == .starting else { return false }
        case .recent:
            guard session.state == .finished else { return false }
        }

        // 2. Search query matching
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let q = trimmed.lowercased()

        // Match against project name
        let displayedProjectName = LoomSettings.safeProjectName(for: session, hidePaths: hideProjectPaths)
        if displayedProjectName.lowercased().contains(q) {
            return true
        }

        // Match against repository directory name
        if !hideProjectPaths, let folderName = session.projectPath?.lastPathComponent, folderName.lowercased().contains(q) {
            return true
        }

        // Match against branch name
        if let branch = session.branch, branch.lowercased().contains(q) {
            return true
        }

        // Match against activity summary
        if !hideProjectPaths, let summary = session.summary, summary.lowercased().contains(q) {
            return true
        }

        // Match against provider display name
        if session.provider.displayName.lowercased().contains(q) {
            return true
        }

        // Match against PID
        if let pid = session.pid, String(pid).contains(q) {
            return true
        }
        for proc in session.associatedProcesses {
            if String(proc.pid).contains(q) {
                return true
            }
        }

        // Match against provider session ID or logical ID
        if let sid = session.providerSessionID,
           (!hideProjectPaths || !looksLikePath(sid)), sid.lowercased().contains(q) {
            return true
        }
        if (!hideProjectPaths || !looksLikePath(session.id)), session.id.lowercased().contains(q) {
            return true
        }

        // Match against full project path only if hideProjectPaths is FALSE
        if !hideProjectPaths, let fullPath = session.projectPath?.path, fullPath.lowercased().contains(q) {
            return true
        }

        // Match against host app name
        if let host = session.hostApp?.displayName, host.lowercased().contains(q) {
            return true
        }

        return false
    }

    private static func looksLikePath(_ value: String) -> Bool {
        value.contains("/") || value.contains("~")
    }

    /// Pure, deterministic filter that preserves snapshot order without modifying source snapshots.
    public static func filterSessions(
        _ sessions: [AgentSession],
        query: String,
        filter: SessionFilterCriterion,
        hideProjectPaths: Bool = false
    ) -> [AgentSession] {
        sessions.filter { matches(session: $0, query: query, filter: filter, hideProjectPaths: hideProjectPaths) }
    }
}

// MARK: - Privacy Quick Action Toggle

public struct PrivacyQuickToggle: View {
    @Bindable var settings: LoomSettings

    public init(settings: LoomSettings) {
        self.settings = settings
    }

    public var body: some View {
        Button {
            settings.hideProjectPaths.toggle()
        } label: {
            Image(systemName: settings.hideProjectPaths ? "lock.shield.fill" : "lock.shield")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(settings.hideProjectPaths ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(settings.hideProjectPaths ? "Privacy Mode Active: Project paths concealed" : "Privacy Mode: Click to conceal project paths")
        .accessibilityLabel(settings.hideProjectPaths ? "Privacy mode enabled, project paths concealed" : "Privacy mode disabled, project paths visible")
    }
}

// MARK: - Session Filter Bar

public struct SessionFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedFilter: SessionFilterCriterion
    var counts: [SessionFilterCriterion: Int] = [:]

    public init(
        searchText: Binding<String>,
        selectedFilter: Binding<SessionFilterCriterion>,
        counts: [SessionFilterCriterion: Int] = [:]
    ) {
        self._searchText = searchText
        self._selectedFilter = selectedFilter
        self.counts = counts
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Search field
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search project, branch, host, ID…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .accessibilityIdentifier("session-search-field")

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(SessionFilterCriterion.allCases) { criterion in
                        filterPill(criterion)
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        filterPill(.all)
                        filterPill(.needsAttention)
                    }
                    HStack(spacing: 6) {
                        filterPill(.working)
                        filterPill(.recent)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func filterPill(_ criterion: SessionFilterCriterion) -> some View {
        let isSelected = selectedFilter == criterion
        let count = counts[criterion]

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedFilter = criterion
            }
        } label: {
            HStack(spacing: 4) {
                Text(criterion.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(
                            criterion == .needsAttention
                                ? Color.orange
                                : (isSelected ? Color.primary : Color.secondary)
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                isSelected
                    ? Color.primary.opacity(0.10)
                    : Color.clear,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(criterion.displayName) filter, \(count ?? 0) sessions")
        .accessibilityIdentifier("session-filter-\(criterion.rawValue)")
    }
}

// MARK: - Clear Empty State Messaging View

public struct SessionFilterEmptyStateView: View {
    public let query: String
    public let filter: SessionFilterCriterion
    public var onClearFilters: (() -> Void)?

    public init(
        query: String,
        filter: SessionFilterCriterion,
        onClearFilters: (() -> Void)? = nil
    ) {
        self.query = query
        self.filter = filter
        self.onClearFilters = onClearFilters
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            if !query.isEmpty || filter != .all {
                Button("Show All Sessions") {
                    onClearFilters?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var iconName: String {
        if !query.isEmpty {
            return "magnifyingglass"
        }
        switch filter {
        case .all: return "tray"
        case .needsAttention: return "checkmark.shield"
        case .working: return "moon.stars"
        case .recent: return "clock.arrow.circlepath"
        }
    }

    private var title: String {
        if !query.isEmpty {
            return "No matching sessions"
        }
        switch filter {
        case .all: return "No sessions found"
        case .needsAttention: return "No sessions need attention"
        case .working: return "No agents currently working"
        case .recent: return "No recent finished sessions"
        }
    }

    private var subtitle: String {
        if !query.isEmpty {
            return "No sessions matched \"\(query)\". Check your spelling or try clearing the search."
        }
        switch filter {
        case .all:
            return "No active or recent agent sessions were discovered."
        case .needsAttention:
            return "All discovered agent sessions are running smoothly or completed normally."
        case .working:
            return "No local agent processes are currently executing tasks."
        case .recent:
            return "Finished agent sessions within your retention period will appear here."
        }
    }
}
