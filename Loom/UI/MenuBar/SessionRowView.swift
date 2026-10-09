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
        let title = showProvider ? "\(session.provider.displayName), \(projectTitle)" : projectTitle
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
                HStack(alignment: .center, spacing: 10) {
                    StateIndicatorView(state: session.state)
                        .frame(width: 13, height: 13)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(projectTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(projectTitle)

                        HStack(spacing: 5) {
                            if showProvider {
                                Text(session.provider.displayName)
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .foregroundStyle(.secondary)
                            }
                            Text(session.state.displayName)
                                .foregroundStyle(stateColor(for: session.state))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
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

    private var sessionDetails: some View {
        VStack(alignment: .leading, spacing: 9) {
            DetailRow(label: "Provider", value: session.provider.displayName)
            if let path = session.projectPath?.path {
                DetailRow(label: "Project", value: (path as NSString).abbreviatingWithTildeInPath)
            } else if let name = session.projectName, !name.isEmpty {
                DetailRow(label: "Project", value: name)
            }
            if let branch = session.branch, !branch.isEmpty {
                DetailRow(label: "Branch", value: branch)
            }
            if let startedAt = session.startedAt {
                DetailRow(label: "Started", value: timestamp(startedAt))
            }
            if let lastActivityAt = session.lastActivityAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    DetailRow(label: "Last activity", value: relativeActivity(lastActivityAt, now: context.date))
                }
            }
            if let summary = session.summary, !summary.isEmpty {
                DetailRow(label: "Summary", value: summary)
            }
            if let pid = session.pid {
                DetailRow(label: "Process ID", value: String(pid))
            }

            if let path = session.projectPath?.path {
                Divider()
                    .padding(.vertical, 3)
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

    private func timestamp(_ date: Date) -> String {
        date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }

    private func relativeActivity(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private func stateColor(for state: AgentState) -> Color {
        switch state {
        case .working: return .blue
        case .waiting: return .orange
        case .finished: return .green
        case .failed: return .red
        case .idle, .unknown: return .secondary
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
            case .working:
                Circle().fill(.blue).frame(width: 11, height: 11)
            case .waiting:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .finished:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .idle:
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: 11, height: 11)
            case .unknown:
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .accessibilityHidden(true)
    }
}
