//
//  SessionRowView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
import LoomCore

public struct SessionRowView: View {
    public let session: AgentSession
    public let showProvider: Bool
    public let hideProjectPaths: Bool
    @State private var isExpanded: Bool

    public init(
        session: AgentSession,
        isExpanded: Bool = false,
        showProvider: Bool = false,
        hideProjectPaths: Bool = false
    ) {
        self.session = session
        self.showProvider = showProvider
        self.hideProjectPaths = hideProjectPaths
        self._isExpanded = State(initialValue: isExpanded)
    }

    private var projectTitle: String {
        LoomSettings.safeProjectName(for: session, hidePaths: hideProjectPaths)
    }

    private var sessionHeaderAccessibilityLabel: String {
        let title = "\(session.provider.displayName), \(projectTitle)"
        let status = isExpanded ? "expanded" : "collapsed"
        if let pid = session.pid {
            return "\(title), PID \(pid), \(session.state.displayName), \(status)"
        }
        return "\(title), \(session.state.displayName), \(status)"
    }

    private var accentBorderColor: Color? {
        switch session.state {
        case .waiting:
            return Color.orange.opacity(0.40)
        case .failed:
            return Color.red.opacity(0.40)
        default:
            return nil
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    StateIndicatorView(state: session.state)
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(projectTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(projectTitle)

                            if let hostApp = session.hostApp {
                                Text(hostApp.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                            }
                        }

                        HStack(spacing: 5) {
                            if let branch = session.branch, !branch.isEmpty {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 8))
                                    Text(branch)
                                        .font(.system(size: 10.5))
                                }
                                .foregroundStyle(.secondary)

                                Text("•")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                            }

                            if let summary = session.summary, !summary.isEmpty {
                                Text(hideProjectPaths ? "Active" : summary)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                activityLine
                            }
                        }
                    }

                    Spacer(minLength: 6)

                    HStack(spacing: 5) {
                        Text(session.state.displayName)
                            .font(.system(size: 10, weight: session.state == .waiting || session.state == .failed ? .semibold : .medium))
                            .foregroundStyle(stateColor(for: session.state))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(stateColor(for: session.state).opacity(0.12), in: Capsule())

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sessionHeaderAccessibilityLabel)
            .accessibilityHint(isExpanded ? "Collapse session details" : "Expand session details")

            // Expandable Process Inspector & Actions
            if isExpanded {
                Divider().opacity(0.4)
                sessionDetails
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .loomRow(
            isAttention: session.state == .waiting || session.state == .failed,
            isSelected: isExpanded
        )
    }

    @ViewBuilder
    private var activityLine: some View {
        if let lastActivity = session.lastActivityAt {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(relativeActivity(lastActivity, now: context.date))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
        } else if let started = session.startedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text("Started \(relativeActivity(started, now: context.date))")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 3) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                Text("Loom session")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
    }

    private var sessionDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Productivity Quick Actions (Focus Host App, Reveal in Finder, Copy metadata)
            SessionActionsView(session: session, hideProjectPaths: hideProjectPaths)

            Divider().opacity(0.4).padding(.vertical, 2)

            // Essential Metadata
            if !hideProjectPaths, let path = session.formattedProjectPath {
                DetailRow(label: "Repository", value: path)
            } else if let name = session.projectName, !name.isEmpty {
                DetailRow(label: "Project", value: hideProjectPaths ? projectTitle : name)
            }

            if let branch = session.branch, !branch.isEmpty {
                DetailRow(label: "Branch", value: branch)
            }
            if let hostApp = session.hostApp {
                DetailRow(label: "Host app", value: hostApp.displayName)
            }
            if let startedAt = session.startedAt {
                DetailRow(label: "Started", value: timestamp(startedAt))
            }
            if let lastActivityAt = session.lastActivityAt {
                DetailRow(label: "Last activity", value: timestamp(lastActivityAt))
            }
            if let summary = session.summary, !summary.isEmpty {
                DetailRow(label: "Current activity", value: hideProjectPaths ? "Details hidden by privacy setting" : summary)
            }

            // Associated processes breakdown & hierarchy
            if !session.associatedProcesses.isEmpty {
                Divider().opacity(0.4).padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Process Tree (\(session.associatedProcesses.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(session.associatedProcesses, id: \.pid) { proc in
                            processRow(proc)
                        }
                    }
                }
            } else if let pid = session.pid {
                DetailRow(label: "Process ID", value: String(pid))
            }

            // Discovery Evidence
            if !session.discoveryEvidence.isEmpty || session.providerSessionID != nil {
                Divider().opacity(0.4).padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discovery Evidence")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if let sid = session.providerSessionID, !sid.isEmpty {
                        DetailRow(label: "Session ID", value: sid)
                    }

                    if hideProjectPaths {
                        Text("• Evidence details hidden by privacy setting")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.discoveryEvidence, id: \.self) { ev in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(ev)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func processRow(_ proc: AgentProcess) -> some View {
        let execName = URL(fileURLWithPath: proc.executable).lastPathComponent
        let displayText = hideProjectPaths
            ? (execName.isEmpty ? "process" : execName)
            : (execName.isEmpty ? proc.commandLine : execName)

        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("PID \(proc.pid)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)

                if let ppid = proc.parentPID {
                    Text("PPID \(ppid)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
            }
        }
        .padding(.vertical, 1.5)
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }

    private func relativeActivity(_ date: Date, now: Date) -> String {
        let diff = now.timeIntervalSince(date)
        if diff < 60 && diff >= -10 {
            return "just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private func stateColor(for state: AgentState) -> Color {
        switch state {
        case .starting: return .teal
        case .working: return .blue
        case .waiting: return .orange
        case .finished: return .green
        case .failed: return .red
        case .idle, .unknown: return .secondary
        }
    }

    private func activityIcon(for state: AgentState) -> String {
        switch state {
        case .starting: return "bolt.fill"
        case .working: return "arrow.triangle.2.circlepath"
        case .waiting: return "hourglass"
        case .idle: return "moon.fill"
        case .finished: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .unknown: return "ellipsis.circle"
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
    }
}

private struct StateIndicatorView: View {
    let state: AgentState

    var body: some View {
        Group {
            switch state {
            case .starting:
                Circle().fill(.teal).frame(width: 8, height: 8)
            case .working:
                Circle().fill(.blue).frame(width: 8, height: 8)
            case .waiting:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .finished:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .idle:
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
            case .unknown:
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 9))
        .accessibilityHidden(true)
    }
}
