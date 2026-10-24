//
//  CheckForUpdatesView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI

/// Reusable SwiftUI button that triggers a software update check.
public struct CheckForUpdatesView: View {
    @ObservedObject private var updateController = UpdateController.shared

    public init() {}

    public var body: some View {
        Button("Check for Updates…") {
            updateController.checkForUpdates()
        }
        .disabled(!updateController.canCheckForUpdates)
        .help(updateController.canCheckForUpdates ? "Check for Loom updates" : "Updates are not available in development builds")
    }
}

/// Software update settings group for Settings -> General.
public struct SoftwareUpdatesSettingsSection: View {
    @ObservedObject private var updateController = UpdateController.shared

    public init() {}

    public var body: some View {
        SettingsSection("Software Updates") {
            Toggle(isOn: Binding(
                get: { updateController.automaticallyChecksForUpdates },
                set: { updateController.automaticallyChecksForUpdates = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatically check for updates")
                        .font(.body)
                    Text("Receive prompt when a new signed and notarized version of Loom is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("toggle-auto-updates")
            .accessibilityLabel("Automatically check for updates")
            .padding(.vertical, 4)

            HStack {
                Text("Updates are verified cryptographically before installation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates…") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
                .help(updateController.canCheckForUpdates ? "Check for Loom updates" : "Updates are not available in development builds")
                .accessibilityIdentifier("button-check-updates")
            }
            .padding(.vertical, 4)
        }
    }
}
