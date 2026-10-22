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
    @State private var historyRecords: [NotificationRecord] = []
    private let historyStore: NotificationHistoryStore

    @MainActor public init(settings: LoomSettings, historyStore: NotificationHistoryStore? = nil) {
        self.settings = settings
        self.historyStore = historyStore ?? NotificationCoordinator.shared.historyStore
    }

    public var body: some View {
        SettingsForm {
            SettingsSection {
                Toggle(isOn: $settings.notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Notifications")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Receive native macOS alerts for quota thresholds and agent session states.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
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

            SettingsSection("Quota Alerts") {
                Toggle(isOn: $settings.notifyQuota15Percent) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("15% quota remaining")
                            .font(.body)
                        Text("Notify when 5-hour or weekly quota drops below 15%.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("toggle-notify-quota-reset")
                .accessibilityLabel("Quota reset or replenished")
                .disabled(!settings.notificationsEnabled)
                .padding(.vertical, 2)
            }

            SettingsSection("Session Alerts") {
                Toggle(isOn: $settings.notifySessionWaiting) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Needs human input")
                            .font(.body)
                        Text("Notify when an agent pauses and is waiting for user confirmation or input.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("toggle-notify-session-failed")
                .accessibilityLabel("Session failed")
                .disabled(!settings.notificationsEnabled)
                .padding(.vertical, 2)
            }

            SettingsSection("Notification History") {
                if historyRecords.isEmpty {
                    Text("No notifications yet. Recent alerts will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("notification-history-empty")
                } else {
                    ForEach(historyRecords) { record in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.providerLabel(record.provider))
                                    .fontWeight(.medium)
                                Text(Self.eventLabel(record.eventType))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(record.timestamp, style: .date)
                                Text(record.timestamp, style: .time)
                                Text(Self.deliveryLabel(record.deliveredStatus))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("notification-history-row")
                    }
                }
            }
        }
        .task {
            historyRecords = historyStore.recentRecords
            await refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationHistoryStore.didChangeNotification)) { notification in
            guard let changedStore = notification.object as? NotificationHistoryStore,
                  changedStore === historyStore else { return }
            historyRecords = historyStore.recentRecords
        }
    }

    private static func eventLabel(_ rawValue: String) -> String {
        switch rawValue {
        case "quotaThresholdCrossed": return "Quota warning"
        case "quotaReplenished": return "Quota replenished"
        case "sessionStateTransition": return "Session state changed"
        case "test": return "Test alert"
        default: return "Notification"
        }
    }

    private static func providerLabel(_ provider: ProviderID?) -> String {
        guard let provider else { return "Loom" }
        if provider == .codex { return "Codex" }
        if provider == .claude { return "Claude Code" }
        if provider == .antigravity { return "Antigravity" }
        return "Agent"
    }

    private static func deliveryLabel(_ status: NotificationRecord.DeliveryStatus) -> String {
        switch status {
        case .delivered: return "Queued"
        case .suppressed: return "Suppressed"
        case .failed: return "Failed"
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
