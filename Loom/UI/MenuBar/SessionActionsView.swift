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

// MARK: - Session Actions View

public struct SessionActionsView: View {
    public let session: AgentSession
    public let hideProjectPaths: Bool

    @State private var feedbackText: String? = nil

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
                // Action 1: Focus Host App
                Button {
                    let success = HostAppResolver.focusHostApp(for: session)
                    if success {
                        flashFeedback("Focused \(hostAppName)")
                    } else {
                        flashFeedback("Could not focus \(hostAppName)")
                    }
                } label: {
                    Label("Focus \(hostAppName)", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasResolvedHost)
                .help(hasResolvedHost ? "Activate \(hostAppName) on this Mac" : "Host application is not currently running")
                .accessibilityLabel("Focus host application \(hostAppName)")

                // Action 2: Reveal in Finder
                Button {
                    if Self.revealInFinder(for: session) {
                        flashFeedback("Revealed in Finder")
                    } else {
                        flashFeedback("Path not found on disk")
                    }
                } label: {
                    Label("Finder", systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!pathExistsOnDisk)
                .help(pathExistsOnDisk ? "Reveal repository folder in Finder" : (resolvedProjectPath == nil ? "No repository path available" : "Folder not found on disk"))
                .accessibilityLabel("Reveal repository in Finder")

                // Action 3: Copy Menu (PID, Path, Session ID)
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
                } label: {
                    Label("Copy…", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Copy session metadata to clipboard")

                Spacer(minLength: 0)

                // Feedback indicator
                if let feedback = feedbackText {
                    Text(feedback)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
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
