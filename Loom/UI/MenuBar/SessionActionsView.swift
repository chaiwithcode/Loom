//
//  SessionActionsView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
import LoomCore

// MARK: - Host Application Resolver

public enum HostAppResolver {
    /// Resolves any running macOS application corresponding to the agent's host app or process tree.
    public static func resolveRunningApplication(for session: AgentSession) -> NSRunningApplication? {
        let runningApps = NSWorkspace.shared.runningApplications

        // 1. Direct PID lookup if we have session.pid
        if let pid = session.pid,
           let app = runningApps.first(where: { $0.processIdentifier == pid_t(pid) && !$0.isTerminated }) {
            return app
        }

        // 2. Associated processes PID or parentPID lookup
        for proc in session.associatedProcesses {
            if let app = runningApps.first(where: { $0.processIdentifier == proc.pid && !$0.isTerminated }) {
                return app
            }
            if let ppid = proc.parentPID,
               let app = runningApps.first(where: { $0.processIdentifier == ppid && !$0.isTerminated }) {
                return app
            }
        }

        // 3. Resolve by HostApp enum mapping
        guard let hostApp = session.hostApp else { return nil }
        let candidateBundleIDs: [String]
        let candidateNames: [String]

        switch hostApp {
        case .vsCode:
            candidateBundleIDs = [
                "com.microsoft.VSCode",
                "com.visualstudio.code.oss",
                "com.microsoft.VSCodeInsiders"
            ]
            candidateNames = ["Code", "Visual Studio Code"]
        case .cursor:
            candidateBundleIDs = [
                "com.todesktop.230313mzl4w4u92",
                "com.cursor.Cursor"
            ]
            candidateNames = ["Cursor"]
        case .xcode:
            candidateBundleIDs = ["com.apple.dt.Xcode"]
            candidateNames = ["Xcode"]
        case .terminal:
            candidateBundleIDs = [
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.mitchellh.ghostty",
                "net.kovidgoyal.kitty",
                "com.github.wez.wezterm",
                "co.zeit.hyper"
            ]
            candidateNames = ["Terminal", "iTerm2", "Ghostty", "kitty", "WezTerm", "Hyper"]
        case .chatGPT:
            candidateBundleIDs = ["com.openai.chat"]
            candidateNames = ["ChatGPT"]
        case .antigravity:
            candidateBundleIDs = [
                "com.google.antigravity",
                "com.google.gemini.antigravity"
            ]
            candidateNames = ["Antigravity"]
        case .custom(let name):
            candidateBundleIDs = []
            candidateNames = [name]
        }

        // Match by bundle identifier first
        for bundleID in candidateBundleIDs {
            if let app = runningApps.first(where: {
                $0.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame && !$0.isTerminated
            }) {
                return app
            }
        }

        // Match by localized name
        for name in candidateNames {
            if let app = runningApps.first(where: {
                !$0.isTerminated && (
                    $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame ||
                    $0.bundleURL?.lastPathComponent.lowercased().contains(name.lowercased()) == true
                )
            }) {
                return app
            }
        }

        return nil
    }

    /// Activates the resolved host application if alive.
    @discardableResult
    public static func focusHostApp(for session: AgentSession) -> Bool {
        guard let app = resolveRunningApplication(for: session) else {
            return false
        }
        return app.activate(options: [.activateAllWindows])
    }
}

// MARK: - Compact Native Actions

private struct MicroGlassSurfaceModifier: ViewModifier {
    let isHovered: Bool
    let isEnabled: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.loomGlassEnabled) private var glassEnabled

    init(isHovered: Bool, isEnabled: Bool = true) {
        self.isHovered = isHovered
        self.isEnabled = isEnabled
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if !glassEnabled {
                base(content: content)
            } else if reduceTransparency {
                base(content: content)
                    .background(Color(nsColor: .controlBackgroundColor), in: shape)
            } else {
                systemSurface(content: content, shape: shape)
            }
        }
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func base(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func systemSurface(content: Content, shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            base(content: content).glassEffect(.regular.interactive(), in: shape)
        } else {
            base(content: content).background(.ultraThinMaterial, in: shape)
        }
        #else
        base(content: content).background(.ultraThinMaterial, in: shape)
        #endif
    }
}

private struct MicroGlassActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let helpText: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .modifier(MicroGlassSurfaceModifier(isHovered: isHovered, isEnabled: isEnabled))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Session Actions View

public struct SessionActionsView: View {
    public let session: AgentSession
    public let hideProjectPaths: Bool

    @State private var feedbackText: String? = nil
    @State private var isCopyHovered: Bool = false

    public init(session: AgentSession, hideProjectPaths: Bool = false) {
        self.session = session
        self.hideProjectPaths = hideProjectPaths
    }

    private var runningApp: NSRunningApplication? {
        HostAppResolver.resolveRunningApplication(for: session)
    }

    private var hostAppName: String {
        runningApp?.localizedName ?? session.hostApp?.displayName ?? "Host App"
    }

    private var hasResolvedHost: Bool {
        runningApp != nil
    }

    private var resolvedProjectPath: String? {
        session.projectPath?.path
    }

    private var pathExistsOnDisk: Bool {
        guard let path = resolvedProjectPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private var effectivePID: Int? {
        session.pid ?? session.associatedProcesses.first.map { Int($0.pid) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Action 1: Focus Host App (Micro-glass button with hover state)
                MicroGlassActionButton(
                    title: "Focus \(hostAppName)",
                    systemImage: "arrow.up.forward.app",
                    isEnabled: hasResolvedHost,
                    helpText: hasResolvedHost ? "Activate \(hostAppName) on this Mac" : "Host application is not currently running",
                    accessibilityLabel: "Focus host application \(hostAppName)"
                ) {
                    let success = HostAppResolver.focusHostApp(for: session)
                    if success {
                        flashFeedback("Focused \(hostAppName)")
                    } else {
                        flashFeedback("Could not focus \(hostAppName)")
                    }
                }

                // Action 2: Reveal in Finder (Micro-glass button with hover state)
                MicroGlassActionButton(
                    title: "Finder",
                    systemImage: "folder",
                    isEnabled: pathExistsOnDisk,
                    helpText: pathExistsOnDisk ? "Reveal repository folder in Finder" : (resolvedProjectPath == nil ? "No repository path available" : "Folder not found on disk"),
                    accessibilityLabel: "Reveal repository in Finder"
                ) {
                    if Self.revealInFinder(for: session) {
                        flashFeedback("Revealed in Finder")
                    } else {
                        flashFeedback("Path not found on disk")
                    }
                }

                // Action 3: Copy Menu (PID, Path, Session ID, All Metadata) with Micro-glass styling & chevron
                Menu {
                    if let pid = effectivePID {
                        Button {
                            if Self.copyPID(for: session) {
                                flashFeedback("Copied PID \(pid)")
                            }
                        } label: {
                            Label("Copy PID (\(pid))", systemImage: "number")
                        }
                    }

                    Button {
                        if Self.copyRepositoryPath(for: session, hideProjectPaths: hideProjectPaths) {
                            flashFeedback(hideProjectPaths ? "Copied Project Name" : "Copied Repository Path")
                        }
                    } label: {
                        Label(hideProjectPaths ? "Copy Project Name" : "Copy Repository Path", systemImage: "doc.on.doc")
                    }
                    .disabled(session.projectPath == nil && session.projectName == nil)

                    if let sid = session.providerSessionID, !sid.isEmpty {
                        Button {
                            if Self.copySessionID(for: session) {
                                flashFeedback("Copied Session ID")
                            }
                        } label: {
                            Label("Copy Session ID", systemImage: "tag")
                        }
                    }

                    Divider()

                    Button {
                        if Self.copySessionMetadata(for: session, hideProjectPaths: hideProjectPaths) {
                            flashFeedback("Copied Metadata")
                        }
                    } label: {
                        Label("Copy All Metadata", systemImage: "text.badge.plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("Copy")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.primary)
                    .modifier(MicroGlassSurfaceModifier(isHovered: isCopyHovered, isEnabled: true))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .onHover { isCopyHovered = $0 }
                .help("Copy session metadata to clipboard")
                .accessibilityLabel("Copy session metadata options")

                Spacer(minLength: 0)

                // Feedback indicator pill
                if let feedback = feedbackText {
                    let isError = feedback.contains("Could not") || feedback.contains("not found")
                    HStack(spacing: 3.5) {
                        Image(systemName: isError ? "exclamationmark.circle" : "checkmark")
                            .font(.system(size: 8, weight: .bold))
                        Text(feedback)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(isError ? Color.orange : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        isError ? Color.orange.opacity(0.08) : Color.primary.opacity(0.06),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isError ? Color.orange.opacity(0.20) : Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func flashFeedback(_ message: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            feedbackText = message
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                if feedbackText == message {
                    feedbackText = nil
                }
            }
        }
    }

    // MARK: - Clipboard & Finder Operations

    public static func copyPID(for session: AgentSession) -> Bool {
        guard let pid = session.pid ?? session.associatedProcesses.first.map({ Int($0.pid) }) else {
            return false
        }
        let text = String(pid)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    public static func copyRepositoryPath(for session: AgentSession, hideProjectPaths: Bool) -> Bool {
        let text: String
        if hideProjectPaths {
            text = LoomSettings.safeProjectName(for: session, hidePaths: true)
        } else if let path = session.projectPath?.path {
            text = path
        } else if let formatted = session.formattedProjectPath {
            text = formatted
        } else if let name = session.projectName, !name.isEmpty {
            text = name
        } else {
            return false
        }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    public static func copySessionID(for session: AgentSession) -> Bool {
        guard let sid = session.providerSessionID ?? (!session.id.isEmpty ? session.id : nil) else {
            return false
        }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(sid, forType: .string)
    }

    public static func copySessionMetadata(for session: AgentSession, hideProjectPaths: Bool = false) -> Bool {
        var lines: [String] = []
        lines.append("Provider: \(session.provider.displayName)")
        if hideProjectPaths {
            if let name = session.projectName, !name.isEmpty {
                lines.append("Project: \(name)")
            }
        } else {
            if let path = session.formattedProjectPath ?? session.projectPath?.path {
                lines.append("Repository: \(path)")
            } else if let name = session.projectName, !name.isEmpty {
                lines.append("Project: \(name)")
            }
        }
        if let branch = session.branch, !branch.isEmpty {
            lines.append("Branch: \(branch)")
        }
        lines.append("State: \(session.state.displayName)")
        if let pid = session.pid {
            lines.append("PID: \(pid)")
        }
        if let host = session.hostApp {
            lines.append("Host: \(host.displayName)")
        }
        if let sid = session.providerSessionID, !sid.isEmpty {
            lines.append("Session ID: \(sid)")
        }
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    public static func revealInFinder(for session: AgentSession) -> Bool {
        guard let path = session.projectPath?.path,
              FileManager.default.fileExists(atPath: path) else {
            return false
        }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        return true
    }
}

// MARK: - Native Context Menu Content

public struct SessionActionsContextMenu: View {
    public let session: AgentSession
    public let hideProjectPaths: Bool

    public init(session: AgentSession, hideProjectPaths: Bool = false) {
        self.session = session
        self.hideProjectPaths = hideProjectPaths
    }

    private var runningApp: NSRunningApplication? {
        HostAppResolver.resolveRunningApplication(for: session)
    }

    private var hostName: String {
        runningApp?.localizedName ?? session.hostApp?.displayName ?? "Host App"
    }

    private var hasHost: Bool {
        runningApp != nil
    }

    private var effectivePID: Int? {
        session.pid ?? session.associatedProcesses.first.map { Int($0.pid) }
    }

    private var fileExists: Bool {
        guard let path = session.projectPath?.path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    public var body: some View {
        Button {
            HostAppResolver.focusHostApp(for: session)
        } label: {
            Label("Focus \(hostName)", systemImage: "arrow.up.forward.app")
        }
        .disabled(!hasHost)

        Divider()

        if let pid = effectivePID {
            Button {
                _ = SessionActionsView.copyPID(for: session)
            } label: {
                Label("Copy PID (\(pid))", systemImage: "number")
            }
        }

        Button {
            _ = SessionActionsView.copyRepositoryPath(for: session, hideProjectPaths: hideProjectPaths)
        } label: {
            Label(hideProjectPaths ? "Copy Project Name" : "Copy Repository Path", systemImage: "doc.on.doc")
        }
        .disabled(session.projectPath == nil && session.projectName == nil)

        if let sid = session.providerSessionID, !sid.isEmpty {
            Button {
                _ = SessionActionsView.copySessionID(for: session)
            } label: {
                Label("Copy Session ID", systemImage: "tag")
            }
        }

        Button {
            _ = SessionActionsView.copySessionMetadata(for: session, hideProjectPaths: hideProjectPaths)
        } label: {
            Label("Copy Session Summary", systemImage: "text.badge.plus")
        }

        Divider()

        Button {
            _ = SessionActionsView.revealInFinder(for: session)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        .disabled(!fileExists)
    }
}

// MARK: - View Modifier Extension

public extension View {
    func sessionContextMenu(session: AgentSession, hideProjectPaths: Bool = false) -> some View {
        self.contextMenu {
            SessionActionsContextMenu(session: session, hideProjectPaths: hideProjectPaths)
        }
    }
}
