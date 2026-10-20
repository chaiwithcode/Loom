//
//  NotificationsSettingsTab.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
import LoomCore

public struct NotificationsSettingsTab: View {
    @Bindable var settings: LoomSettings
    @State private var authorizationStatus: NotificationAuthorizationStatus = .notDetermined
    @State private var isSendingTest = false
    @State private var statusFeedbackMessage: String?

    public init(settings: LoomSettings) {
        self.settings = settings
    }

    public var body: some View {
        ScrollView {
            Form {
                Section {
                    Toggle(isOn: $settings.notificationsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Notifications")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Receive native macOS alerts for quota thresholds and agent session states.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("toggle-enable-notifications")
                    .accessibilityLabel("Enable Notifications")
                    .padding(.vertical, 4)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled {
                            Task {
                                _ = await NotificationCoordinator.shared.requestAuthorization()
                                await refreshStatus()
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusIndicatorColor)
                            .frame(width: 8, height: 8)
                        Text(statusIndicatorLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("label-permission-status")

                        Spacer()

                        if authorizationStatus == .denied {
                            Button("Open System Settings") {
                                openSystemSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("button-open-system-settings")
                            .accessibilityLabel("Open System Settings")
                        }
                    }
                    .padding(.vertical, 2)

                    if authorizationStatus == .denied {
                        Text("Notifications are disabled for Loom in macOS System Settings. Allow notifications in System Settings to receive alerts.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    HStack {
                        Button("Send Test Notification") {
                            sendTestNotification()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(!settings.notificationsEnabled || authorizationStatus == .denied || isSendingTest)
                        .accessibilityIdentifier("button-send-test-notification")
                        .accessibilityLabel("Send Test Notification")

                        if let statusFeedbackMessage {
                            Text(statusFeedbackMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section("Quota Alerts") {
                    Toggle(isOn: $settings.notifyQuota15Percent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("15% quota remaining")
                                .font(.body)
                            Text("Notify when 5-hour or weekly quota drops below 15%.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("toggle-notify-quota-15")
                    .accessibilityLabel("15% quota remaining")
                    .disabled(!settings.notificationsEnabled)
                    .padding(.vertical, 2)

                    Toggle(isOn: $settings.notifyQuota5Percent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("5% quota remaining")
                                .font(.body)
                            Text("Urgent warning when 5-hour or weekly quota drops below 5%.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("toggle-notify-quota-5")
                    .accessibilityLabel("5% quota remaining")
                    .disabled(!settings.notificationsEnabled)
                    .padding(.vertical, 2)

                    Toggle(isOn: $settings.notifyQuotaReset) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quota reset / replenished")
                                .font(.body)
                            Text("Notify when a rate-limit window rolls over and fresh quota is observed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("toggle-notify-quota-reset")
                    .accessibilityLabel("Quota reset or replenished")
                    .disabled(!settings.notificationsEnabled)
                    .padding(.vertical, 2)
                }

                Section("Session Alerts") {
                    Toggle(isOn: $settings.notifySessionWaiting) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Needs human input")
                                .font(.body)
                            Text("Notify when an agent pauses and is waiting for user confirmation or input.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("toggle-notify-session-waiting")
                    .accessibilityLabel("Needs human input")
                    .disabled(!settings.notificationsEnabled)
                    .padding(.vertical, 2)

                    Toggle(isOn: $settings.notifySessionFinished) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Session finished")
                                .font(.body)
                            Text("Notify when an agent completes its run successfully.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("toggle-notify-session-finished")
                    .accessibilityLabel("Session finished")
                    .disabled(!settings.notificationsEnabled)
                    .padding(.vertical, 2)

                    Toggle(isOn: $settings.notifySessionFailed) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Session failed")
                                .font(.body)
                            Text("Notify when an agent process exits unexpectedly with an error.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("toggle-notify-session-failed")
                    .accessibilityLabel("Session failed")
                    .disabled(!settings.notificationsEnabled)
                    .padding(.vertical, 2)
                }
            }
            .formStyle(.grouped)
        }
        .task {
            await refreshStatus()
        }
    }

    private var statusIndicatorColor: Color {
        switch authorizationStatus {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .provisional:
            return .orange
        case .notDetermined:
            return .secondary
        }
    }

    private var statusIndicatorLabel: String {
        switch authorizationStatus {
        case .authorized:
            return "Permission: Authorized"
        case .denied:
            return "Permission: Denied in System Settings"
        case .provisional:
            return "Permission: Provisional"
        case .notDetermined:
            return "Permission: Not Determined"
        }
    }

    private func refreshStatus() async {
        authorizationStatus = await NotificationCoordinator.shared.checkAuthorizationStatus()
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func sendTestNotification() {
        isSendingTest = true
        statusFeedbackMessage = "Sending test alert…"
        Task {
            do {
                try await NotificationCoordinator.shared.sendTestNotification()
                statusFeedbackMessage = "Test alert sent"
            } catch {
                statusFeedbackMessage = "Failed: \(error.localizedDescription)"
            }
            isSendingTest = false
        }
    }
}
