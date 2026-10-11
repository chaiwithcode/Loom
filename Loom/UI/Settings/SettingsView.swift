//
//  SettingsView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import LoomCore

public struct SettingsView: View {
    @Bindable var settings: LoomSettings
    var store: SessionStore?

    public init(settings: LoomSettings, store: SessionStore? = nil) {
        self.settings = settings
        self.store = store
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ProvidersSettingsTab(settings: settings, store: store)
                .tabItem {
                    Label("Providers", systemImage: "cpu")
                }

            SessionsSettingsTab(settings: settings)
                .tabItem {
                    Label("Sessions", systemImage: "clock")
                }

            PrivacySettingsTab(settings: settings)
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 350)
        .padding()
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var settings: LoomSettings

    var body: some View {
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
                .padding(.vertical, 4)
            }

            Divider()
                .padding(.vertical, 8)

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
        .padding(16)
    }
}

private struct ProvidersSettingsTab: View {
    @Bindable var settings: LoomSettings
    let store: SessionStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Default Provider", selection: $settings.defaultProviderID) {
                ForEach(LoomSettings.defaultProviderIDs.sorted(by: { $0.rawValue < $1.rawValue })) { id in
                    Text(id.displayName).tag(id)
                }
            }
            .pickerStyle(.menu)

            Text("Monitoring")
                .font(.headline)

            let snapshots = store?.providerSnapshots ?? LoomSettings.defaultProviderIDs.sorted(by: { $0.rawValue < $1.rawValue }).map { id in
                ProviderSnapshot(providerID: id, displayName: id.displayName)
            }

            List(snapshots) { snapshot in
                let isEnabled = settings.isProviderEnabled(snapshot.providerID)
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { isEnabled },
                        set: { settings.setProvider(snapshot.providerID, enabled: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Monitor \(snapshot.displayName)")
                    .accessibilityIdentifier("toggle-monitor-\(snapshot.providerID.rawValue)")

                    Circle()
                        .fill(statusColor(for: snapshot, isEnabled: isEnabled))
                        .frame(width: 8, height: 8)

                    Text(snapshot.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    Spacer()

                    Text(statusLabel(for: snapshot, isEnabled: isEnabled))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.bordered)
        }
        .padding(16)
    }

    private func statusColor(for snapshot: ProviderSnapshot, isEnabled: Bool) -> Color {
        guard isEnabled else { return .secondary }
        if snapshot.isRefreshing { return .secondary }
        if snapshot.errorMessage != nil { return .red }
        if snapshot.availability.isAvailable { return .green }
        if snapshot.availability == .unknown { return .secondary }
        return .orange
    }

    private func statusLabel(for snapshot: ProviderSnapshot, isEnabled: Bool) -> String {
        guard isEnabled else { return "Monitoring disabled" }
        if snapshot.isRefreshing { return "Checking…" }
        if let err = snapshot.errorMessage {
            if settings.hideProjectPaths && (err.contains("/") || err.contains("~")) {
                return "Error (details hidden by privacy setting)"
            }
            return "Error: \(err)"
        }
        if snapshot.availability.isAvailable {
            let count = snapshot.sessions.count
            return "\(count) \(count == 1 ? "session" : "sessions")"
        }
        if snapshot.availability == .unknown {
            return "Not checked yet"
        }
        if let reason = snapshot.availability.unavailabilityReason {
            if settings.hideProjectPaths && (reason.contains("/") || reason.contains("~")) {
                return "Unavailable"
            }
            return reason
        }
        return "Unavailable"
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
                .padding(.vertical, 4)
                .disabled(!settings.includeRecentSessions)
            }
        }
        .padding(16)
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
        .padding(16)
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Loom")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version 0.1.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Native macOS control surface for local AI coding agents.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            Text("© 2026 Deepak Sharma (ChaiWithCode). MIT License.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }
}
