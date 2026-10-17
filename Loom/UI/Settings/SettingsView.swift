//
//  SettingsView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import LoomCore

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case providers = "Providers"
    case sessions = "Sessions"
    case storage = "Storage"
    case privacy = "Privacy"
    case about = "About"

    public var id: String { rawValue }
}

public struct SettingsView: View {
    @Bindable var settings: LoomSettings
    var store: SessionStore?
    @State private var selectedTab: SettingsTab

    public init(
        settings: LoomSettings,
        store: SessionStore? = nil,
        initialTab: SettingsTab = .general,
        initialProviderID: ProviderID? = nil
    ) {
        self.settings = settings
        self.store = store
        self._selectedTab = State(initialValue: initialProviderID == nil ? initialTab : .providers)
        self.initialProviderID = initialProviderID
    }

    private let initialProviderID: ProviderID?

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Settings Section", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityIdentifier("picker-settings-tabs")

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab(settings: settings)
                case .providers:
                    ProvidersSettingsTab(settings: settings, store: store, focusedProviderID: initialProviderID)
                case .sessions:
                    SessionsSettingsTab(settings: settings)
                case .storage:
                    StorageSettingsTab(hidePaths: settings.hideProjectPaths)
                case .privacy:
                    PrivacySettingsTab(settings: settings)
                case .about:
                    AboutSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            SettingsFooterView()
        }
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 640, minHeight: 360, idealHeight: 460, maxHeight: 600)
    }
}

public struct SettingsFooterView: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Text("Made with")
            Image(systemName: "heart.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red.opacity(0.85))
                .accessibilityHidden(true)
            Text("by Deepak (ChaiWithCode)")
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Made with love by Deepak (ChaiWithCode)")
        .accessibilityIdentifier("footer-made-with-love")
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var settings: LoomSettings

    var body: some View {
        ScrollView {
            Form {
                Section {
                    Toggle(isOn: $settings.showInDock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Loom in Dock")
                                .font(.body)
                            Text("Keep Loom in the macOS Dock and Command-Tab application switcher.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("toggle-show-in-dock")
                    .accessibilityLabel("Show Loom in Dock")
                    .padding(.vertical, 4)

                    Picker("Refresh Interval", selection: $settings.refreshIntervalSeconds) {
                        Text("Every 30 seconds").tag(30)
                        Text("Every minute (default)").tag(60)
                        Text("Every 2 minutes").tag(120)
                        Text("Every 5 minutes").tag(300)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("picker-refresh-interval")
                    .accessibilityLabel("Refresh Interval")
                    .padding(.vertical, 4)
                }

                SoftwareUpdatesSettingsSection()

                Section {
                    HStack {
                        Spacer()
                        Button("Restore Defaults") {
                            settings.resetToDefaults()
                        }
                        .accessibilityIdentifier("button-restore-defaults")
                        .accessibilityLabel("Restore Defaults")
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct ProviderRowItem: Identifiable {
    let id: ProviderID
    let displayName: String
    let snapshot: ProviderSnapshot?
}

private struct ProvidersSettingsTab: View {
    @Bindable var settings: LoomSettings
    let store: SessionStore?
    let focusedProviderID: ProviderID?

    private var supportedProviders: [ProviderRowItem] {
        let supported = LoomSettings.defaultProviderIDs.sorted(by: { $0.rawValue < $1.rawValue })
        return supported.map { id in
            let snapshot = store?.providerSnapshots.first(where: { $0.providerID == id })
            let displayName = snapshot?.displayName ?? id.displayName
            return ProviderRowItem(id: id, displayName: displayName, snapshot: snapshot)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Default Provider", selection: $settings.defaultProviderID) {
                    ForEach(LoomSettings.defaultProviderIDs.sorted(by: { $0.rawValue < $1.rawValue })) { id in
                        Text(id.displayName).tag(id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("picker-default-provider")
                .accessibilityLabel("Default Provider")
            }

            Section("Monitoring") {
                ForEach(supportedProviders) { item in
                    providerRow(item)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func providerRow(_ item: ProviderRowItem) -> some View {
        let isEnabled = settings.isProviderEnabled(item.id)
        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { settings.setProvider(item.id, enabled: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Monitor \(item.displayName)")
            .accessibilityIdentifier("toggle-monitor-\(item.id.rawValue)")
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: item.snapshot, isEnabled: isEnabled))
                        .frame(width: 8, height: 8)

                    Text(item.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                }

                Text(statusLabel(for: item.snapshot, isEnabled: isEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("label-status-\(item.id.rawValue)")
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            if focusedProviderID == item.id {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .accessibilityIdentifier("provider-row-\(item.id.rawValue)")
    }

    private func statusColor(for snapshot: ProviderSnapshot?, isEnabled: Bool) -> Color {
        guard isEnabled else { return .secondary }
        guard let snapshot else { return .secondary }
        if snapshot.isRefreshing { return .secondary }
        if snapshot.errorMessage != nil { return .red }
        switch snapshot.availability {
        case .available:
            return .green
        case .degraded:
            return .orange
        case .error:
            return .red
        case .unavailable:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    private func statusLabel(for snapshot: ProviderSnapshot?, isEnabled: Bool) -> String {
        guard isEnabled else { return "Monitoring disabled" }
        guard let snapshot else {
            return store == nil ? "Not checked yet" : "Not registered"
        }
        if snapshot.isRefreshing { return "Checking…" }
        if let err = snapshot.errorMessage {
            if settings.hideProjectPaths && (err.contains("/") || err.contains("~")) {
                return "Error (details hidden by privacy setting)"
            }
            return err.hasPrefix("Error") ? err : "Error: \(err)"
        }
        switch snapshot.availability {
        case .available:
            let count = snapshot.sessions.count
            return "\(count) \(count == 1 ? "session" : "sessions")"
        case .degraded(let reason):
            if settings.hideProjectPaths && (reason.contains("/") || reason.contains("~")) {
                return "Degraded (details hidden by privacy setting)"
            }
            return reason.hasPrefix("Degraded") ? reason : "Degraded: \(reason)"
        case .error(let reason):
            if settings.hideProjectPaths && (reason.contains("/") || reason.contains("~")) {
                return "Error (details hidden by privacy setting)"
            }
            return reason.hasPrefix("Error") ? reason : "Error: \(reason)"
        case .unavailable(let reason):
            if settings.hideProjectPaths && (reason.contains("/") || reason.contains("~")) {
                return "Unavailable"
            }
            return reason
        case .unknown:
            return "Not checked yet"
        }
    }
}

private struct SessionsSettingsTab: View {
    @Bindable var settings: LoomSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.includeRecentSessions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include recent sessions")
                            .font(.body)
                        Text("Show recently completed or inactive sessions alongside active work. Sessions with unknown activity remain visible.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("toggle-include-recent-sessions")
                .accessibilityLabel("Include recent sessions")
                .padding(.vertical, 4)

                Picker("Hide finished after", selection: $settings.hideFinishedAfter) {
                    ForEach(HideFinishedInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("picker-hide-finished-after")
                .accessibilityLabel("Hide finished after")
                .padding(.vertical, 4)
                .disabled(!settings.includeRecentSessions)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettingsTab: View {
    @Bindable var settings: LoomSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.hideProjectPaths) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide project paths")
                            .font(.body)
                        Text("Omit filesystem paths and free-form evidence from the menu bar interface.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("toggle-hide-project-paths")
                .accessibilityLabel("Hide project paths")
                .padding(.vertical, 4)

                Text("When enabled, project names containing full directory paths are trimmed to their folder name, repository path rows and process command lines are hidden, and error details containing path structures are omitted. Reveal in Finder actions continue to open the actual folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettingsTab: View {
    private var versionString: String {
        AppVersion.current.aboutString
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                Text("Loom")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(versionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("text-about-version")

                CheckForUpdatesView()
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityIdentifier("button-about-check-updates")

                Text("Lightweight macOS menu bar monitor for local AI coding agents.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 24)

                Text("© 2026 Deepak Sharma (ChaiWithCode). MIT License.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}
