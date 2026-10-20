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
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    // Line 1: Repository / Project name (prominent) + State badge & Chevron
                    HStack(alignment: .center, spacing: 8) {
                        Text(projectTitle)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(projectTitle)

                        Spacer(minLength: 4)

                        // Semantic state badge
                        HStack(spacing: 4) {
                            StateIndicatorView(state: session.state)
                                .frame(width: 8, height: 8)
                            Text(session.state.displayName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(stateColor(for: session.state))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(stateColor(for: session.state).opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    // Line 2: Branch pill, Host App badge, Process count & Relative Activity
                    HStack(spacing: 6) {
                        if let branch = session.branch, !branch.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 9))
                                Text(branch)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }

                        if let hostApp = session.hostApp {
                            Text(hostApp.displayName)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }

                        let pCount = session.processCount
                        Text(pCount == 1 ? "1 proc" : "\(pCount) procs")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 4)

                        activityLine
                    }

                    // Line 3: Current activity summary (if present)
                    if let summary = session.summary, !summary.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: activityIcon(for: session.state))
                                .font(.system(size: 9.5))
                                .foregroundStyle(stateColor(for: session.state))
                            Text(hideProjectPaths ? "Activity details hidden" : summary)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sessionHeaderAccessibilityLabel)
            .accessibilityHint(isExpanded ? "Collapse session details" : "Expand session details")

            // Expandable Process Inspector & Actions
            if isExpanded {
                Divider()
                sessionDetails
                    .padding(12)
            }
        }
        .loomCard(cornerRadius: 10, accentBorderColor: accentBorderColor)
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
        VStack(alignment: .leading, spacing: 8) {
            DetailRow(label: "Provider", value: session.provider.displayName)
            DetailRow(label: "State", value: session.state.displayName)

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
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Process Tree (\(session.associatedProcesses.count))")
                        .font(.system(size: 11.5, weight: .semibold))
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
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Discovery Evidence")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if let sid = session.providerSessionID, !sid.isEmpty {
                        DetailRow(label: "Session ID", value: sid)
                    }

                    if hideProjectPaths {
                        Text("• Evidence details hidden by privacy setting")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.discoveryEvidence, id: \.self) { ev in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(ev)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }

            // Productivity Quick Actions (Focus Host App, Reveal in Finder, Copy metadata)
            Divider().padding(.vertical, 2)
            SessionActionsView(session: session, hideProjectPaths: hideProjectPaths)
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
