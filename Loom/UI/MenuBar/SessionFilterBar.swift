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
            guard session.state == .idle || session.state == .finished || session.state == .unknown else { return false }
        }

        // 2. Search query matching
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let q = trimmed.lowercased()

        // Match against project name
        if let name = session.projectName, name.lowercased().contains(q) {
            return true
        }

        // Match against repository directory name
        if let folderName = session.projectPath?.lastPathComponent, folderName.lowercased().contains(q) {
            return true
        }

        // Match against branch name
        if let branch = session.branch, branch.lowercased().contains(q) {
            return true
        }

        // Match against activity summary
        if let summary = session.summary, summary.lowercased().contains(q) {
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
        if let sid = session.providerSessionID, sid.lowercased().contains(q) {
            return true
        }
        if session.id.lowercased().contains(q) {
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
    var settings: LoomSettings?
    var counts: [SessionFilterCriterion: Int] = [:]

    public init(
        searchText: Binding<String>,
        selectedFilter: Binding<SessionFilterCriterion>,
        settings: LoomSettings? = nil,
        counts: [SessionFilterCriterion: Int] = [:]
    ) {
        self._searchText = searchText
        self._selectedFilter = selectedFilter
        self.settings = settings
        self.counts = counts
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Search field row + Privacy toggle
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search repo, branch, activity…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

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

                if let settings {
                    PrivacyQuickToggle(settings: settings)
                        .padding(.horizontal, 2)
                }
            }

            // Filter pills row
            HStack(spacing: 6) {
                ForEach(SessionFilterCriterion.allCases) { criterion in
                    filterPill(criterion)
                }
                Spacer(minLength: 0)
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
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            criterion == .needsAttention
                                ? Color.orange.opacity(0.25)
                                : (isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)),
                            in: Capsule()
                        )
                        .foregroundStyle(
                            criterion == .needsAttention
                                ? Color.orange
                                : (isSelected ? .white : .secondary)
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(criterion.displayName) filter\(count != nil ? ", \(count!) sessions" : "")")
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
            return "Finished or idle agent sessions will appear here."
        }
    }
}
