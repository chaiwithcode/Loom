//
//  SettingsView.swift
//  Loom
//
//  Created by Deepak Sharma on 03/10/2026.
//  Copyright © 2026 ChaiWithCode. All rights reserved.
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

            ProvidersSettingsTab(store: store)
                .tabItem {
                    Label("Providers", systemImage: "cpu")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 440, height: 280)
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
        }
        .padding(16)
    }
}

private struct ProvidersSettingsTab: View {
    let store: SessionStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registered Agent Providers")
                .font(.headline)

            if let store, !store.providerSnapshots.isEmpty {
                List(store.providerSnapshots) { snapshot in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(snapshot.availability.isAvailable ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(snapshot.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        if snapshot.availability.isAvailable {
                            Text("\(snapshot.sessions.count) active session(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.bordered)
            } else {
                Text("No live providers connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
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

            Text("© 2026 ChaiWithCode. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }
}
