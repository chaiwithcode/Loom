import SwiftUI
import LoomCore

public struct SessionRowView: View {
    public let session: AgentSession

    public init(session: AgentSession) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                // State icon
                StateIndicatorView(state: session.state)

                // Project name
                Text(session.projectName ?? "Untitled Project")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // State badge text
                Text(session.state.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(stateColor(for: session.state))
            }

            HStack(spacing: 8) {
                // Git branch if present
                if let branch = session.branch, !branch.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(branch)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                // Relative last activity using native timeline
                if let lastActivity = session.lastActivityAt {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .accessibilityHidden(true)
                            Text(lastActivity, style: .relative)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Summary description if available
            if let summary = session.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts: [String] = [
            session.provider.rawValue,
            session.projectName ?? "Untitled project",
            session.state.displayName
        ]
        if let branch = session.branch {
            parts.append("branch \(branch)")
        }
        if let lastActivity = session.lastActivityAt {
            parts.append("active \(lastActivity.formatted(.relative(presentation: .named)))")
        }
        if let summary = session.summary {
            parts.append(summary)
        }
        return parts.joined(separator: ", ")
    }

    private func stateColor(for state: AgentState) -> Color {
        switch state {
        case .working: return .blue
        case .waiting: return .orange
        case .finished: return .green
        case .failed: return .red
        case .idle: return .secondary
        case .unknown: return .purple
        }
    }
}

private struct StateIndicatorView: View {
    let state: AgentState

    var body: some View {
        switch state {
        case .working:
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        case .waiting:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .accessibilityHidden(true)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .accessibilityHidden(true)
        case .idle:
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityHidden(true)
        }
    }
}
