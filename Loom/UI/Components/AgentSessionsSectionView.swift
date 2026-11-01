//
//  AgentSessionsSectionView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
#if !SWIFT_PACKAGE
import LoomCore
#endif

public struct AgentSessionsSectionView: View {
    @ObservedObject var coordinator: AgentMonitoringCoordinator

    public init(coordinator: AgentMonitoringCoordinator) {
        self.coordinator = coordinator
    }

    /// Top-level sessions (excludes CLI processes spawned as children of T3Code)
    private var topLevelSessions: [AgentSessionStatus] {
        coordinator.sessions.filter { $0.surface != .t3Orchestrated }
    }

    /// Child CLI sessions spawned by a given T3Code daemon/app PID
    private func childSessions(for t3Session: AgentSessionStatus) -> [AgentSessionStatus] {
        guard t3Session.provider == .t3Code else { return [] }
        return coordinator.sessions.filter { child in
            guard child.surface == .t3Orchestrated else { return false }
            if let t3PID = t3Session.pid, let parentPID = child.parentT3PID, t3PID == parentPID {
                return true
            }
            if let ws1 = t3Session.workspacePath, let ws2 = child.workspacePath, ws1 == ws2 {
                return true
            }
            return false
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACTIVE AGENTS & CLIs")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if coordinator.sessions.contains(where: { $0.state == .awaitingApproval }) {
                    Label("Needs Approval", systemImage: "exclamationmark.bubble.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)

            if topLevelSessions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .foregroundStyle(.tertiary)
                    Text("No active CLI or T3Code sessions")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(topLevelSessions) { session in
                    AgentSessionCardView(
                        session: session,
                        orchestratedChildren: childSessions(for: session)
                    )
                }
            }
        }
    }

    public static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

private struct AgentSessionCardView: View {
    let session: AgentSessionStatus
    let orchestratedChildren: [AgentSessionStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(for: session.state))
                    .frame(width: 7, height: 7)

                Text(session.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let branch = session.gitBranch, !branch.isEmpty {
                    Text(branch)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                }

                Spacer()

                ProviderBadge(provider: session.provider, surface: session.surface)
            }

            HStack(spacing: 8) {
                Text(statusLabel(for: session.state))
                    .font(.system(size: 11, weight: session.state == .awaitingApproval ? .semibold : .regular))
                    .foregroundStyle(session.state == .awaitingApproval ? .orange : .secondary)

                if let model = session.modelName, !model.isEmpty {
                    Text("• \(model)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                if let usage = session.tokenUsage, usage.totalTokens > 0 {
                    Text("\(Self.formatTokens(usage.totalTokens)) tok")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Nested child CLI rows when T3Code is driving Codex / Claude / agy
            if !orchestratedChildren.isEmpty {
                Divider()
                    .opacity(0.4)
                    .padding(.vertical, 2)

                ForEach(orchestratedChildren) { child in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        Text(providerDisplayName(child.provider))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        if let model = child.modelName {
                            Text(model)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        if let usage = child.tokenUsage, usage.totalTokens > 0 {
                            Text("\(Self.formatTokens(usage.totalTokens)) tok")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Circle()
                            .fill(statusColor(for: child.state))
                            .frame(width: 6, height: 6)
                    }
                    .padding(.leading, 6)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.quaternary.opacity(session.state == .inactive ? 0.25 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    session.state == .awaitingApproval ? Color.orange.opacity(0.6) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
        .opacity(session.state == .inactive ? 0.65 : 1.0)
    }

    private func statusColor(for state: AgentRunState) -> Color {
        switch state {
        case .working: return .green
        case .awaitingApproval: return .orange
        case .idle: return .blue
        case .inactive: return .gray.opacity(0.5)
        }
    }

    private func statusLabel(for state: AgentRunState) -> String {
        switch state {
        case .working: return "Working"
        case .awaitingApproval: return "Waiting for Approval"
        case .idle: return "Idle"
        case .inactive: return "Recent"
        }
    }

    private func providerDisplayName(_ provider: AgentProviderKind) -> String {
        switch provider {
        case .t3Code: return "T3Code"
        case .codex: return "Codex CLI"
        case .claudeCode: return "Claude Code"
        case .antigravity: return "Antigravity CLI"
        }
    }

    private static func formatTokens(_ count: Int) -> String {
        AgentSessionsSectionView.formatTokens(count)
    }
}

private struct ProviderBadge: View {
    let provider: AgentProviderKind
    let surface: AgentSurface

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var label: String {
        switch provider {
        case .t3Code: return "T3Code"
        case .codex: return "codex"
        case .claudeCode: return "claude"
        case .antigravity: return surface == .cli ? "agy" : "Antigravity"
        }
    }
}
