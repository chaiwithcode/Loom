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
    @State private var isExpanded: Bool

    public init(session: AgentSession, isExpanded: Bool = false, showProvider: Bool = false) {
        self.session = session
        self.showProvider = showProvider
        self._isExpanded = State(initialValue: isExpanded)
    }

    private var projectTitle: String {
        session.projectName.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Project"
    }

    private var sessionHeaderAccessibilityLabel: String {
        let title = "\(session.provider.displayName), \(projectTitle)"
        let status = isExpanded ? "expanded" : "collapsed"
        if let pid = session.pid {
            return "\(title), PID \(pid), \(session.state.displayName), \(status)"
        }
        return "\(title), \(session.state.displayName), \(status)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    // Line 1: Provider name (left) and State badge (right)
                    HStack(alignment: .center, spacing: 8) {
                        Text(session.provider.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 4)

                        HStack(spacing: 5) {
                            StateIndicatorView(state: session.state)
                                .frame(width: 8, height: 8)
                            Text(session.state.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(stateColor(for: session.state))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(stateColor(for: session.state).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    // Line 2: Project / Repository name (prominent)
                    Text(projectTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(projectTitle)

                    // Line 3: Host application · X processes
                    HStack(spacing: 5) {
                        if let hostApp = session.hostApp {
                            Text(hostApp.displayName)
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.secondary)
                        }
                        let pCount = session.processCount
                        Text(pCount == 1 ? "1 process" : "\(pCount) processes")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12, weight: .medium))

                    // Line 4: Current activity summary (if available)
                    if let summary = session.summary, !summary.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: activityIcon(for: session.state))
                                .font(.system(size: 10))
                                .foregroundStyle(stateColor(for: session.state))
                            Text(summary)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    // Line 5: Activity line
                    activityLine
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sessionHeaderAccessibilityLabel)
            .accessibilityHint(isExpanded ? "Collapse session details" : "Expand session details")

            if isExpanded {
                Divider()
                sessionDetails
                    .padding(14)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var activityLine: some View {
        if let lastActivity = session.lastActivityAt {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Active \(relativeActivity(lastActivity, now: context.date))")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        } else if let started = session.startedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Started \(relativeActivity(started, now: context.date))")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                Text("Loom session")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private var sessionDetails: some View {
        VStack(alignment: .leading, spacing: 9) {
            DetailRow(label: "Provider", value: session.provider.displayName)
            DetailRow(label: "State", value: session.state.displayName)

            if let path = session.formattedProjectPath {
                DetailRow(label: "Repository", value: path)
            } else if let name = session.projectName, !name.isEmpty {
                DetailRow(label: "Project", value: name)
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
                DetailRow(label: "Current activity", value: summary)
            }

            // Associated processes breakdown & hierarchy
            if !session.associatedProcesses.isEmpty {
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Process Tree (\(session.associatedProcesses.count))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Discovery Evidence")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if let sid = session.providerSessionID, !sid.isEmpty {
                        DetailRow(label: "Session ID", value: sid)
                    }

                    ForEach(session.discoveryEvidence, id: \.self) { ev in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(ev)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            // Action: Reveal in Finder
            if let path = session.projectPath?.path {
                Divider().padding(.vertical, 3)
                if FileManager.default.fileExists(atPath: path) {
                    Button {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else {
                    Label("Folder not found on disk", systemImage: "folder.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func processRow(_ proc: AgentProcess) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("PID \(proc.pid)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                let execName = URL(fileURLWithPath: proc.executable).lastPathComponent
                Text(execName.isEmpty ? proc.commandLine : execName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                if let ppid = proc.parentPID {
                    Text("PPID \(ppid)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
            }
        }
        .padding(.vertical, 2)
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
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
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
        .font(.system(size: 10))
        .accessibilityHidden(true)
    }
}
