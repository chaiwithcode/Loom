//
//  NotificationCoordinator.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import AppKit
import Foundation
import UserNotifications
import LoomCore

public enum NotificationAuthorizationStatus: String, Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
}

public enum NotificationPayloadKey {
    public static let targetTab = "targetTab"
    public static let providerID = "providerID"
    public static let sessionID = "sessionID"
    public static let eventType = "eventType"
}

public struct DeepLinkPayload: Sendable, Equatable {
    public let targetTab: String
    public let providerID: ProviderID?
    public let sessionID: String?
    public let actionIdentifier: String

    public init(
        targetTab: String,
        providerID: ProviderID? = nil,
        sessionID: String? = nil,
        actionIdentifier: String = UNNotificationDefaultActionIdentifier
    ) {
        self.targetTab = targetTab
        self.providerID = providerID
        self.sessionID = sessionID
        self.actionIdentifier = actionIdentifier
    }
}

@MainActor
public final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationCoordinator()

    public static let categoryIdentifier = "LOOM_NOTIFICATION_CATEGORY"
    public static let openActionIdentifier = "LOOM_ACTION_VIEW"
    public static let deepLinkNotification = Notification.Name("com.loom.notificationDeepLink")

    public private(set) var lastDeepLinkPayload: DeepLinkPayload?
    public var onDeepLink: ((DeepLinkPayload) -> Void)?

    private let center: UNUserNotificationCenter
    private weak var store: SessionStore?
    private var settings: LoomSettings?
    private var observationTask: Task<Void, Never>?

    public let historyStore: NotificationHistoryStore
    public let quotaEvaluator: QuotaThresholdEvaluator
    public let transitionDetector: SessionTransitionDetector
    private var policy: NotificationPolicy

    public init(
        center: UNUserNotificationCenter = .current(),
        historyStore: NotificationHistoryStore = NotificationHistoryStore(),
        quotaEvaluator: QuotaThresholdEvaluator = QuotaThresholdEvaluator(),
        transitionDetector: SessionTransitionDetector = SessionTransitionDetector()
    ) {
        self.center = center
        self.historyStore = historyStore
        self.quotaEvaluator = quotaEvaluator
        self.transitionDetector = transitionDetector
        self.policy = NotificationPolicy()
        super.init()
    }

    public func configure(settings: LoomSettings, store: SessionStore? = nil) {
        self.settings = settings
        updatePolicyFromSettings()

        settings.onNotificationsEnabledChanged = { [weak self] _ in
            self?.updatePolicyFromSettings()
        }
        settings.onNotifyQuota15PercentChanged = { [weak self] _ in
            self?.updatePolicyFromSettings()
        }
        settings.onNotifyQuota5PercentChanged = { [weak self] _ in
            self?.updatePolicyFromSettings()
        }
        settings.onNotifyQuotaResetChanged = { [weak self] _ in
            self?.updatePolicyFromSettings()
        }
        settings.onNotifySessionWaitingChanged = { [weak self] _ in
            self?.updatePolicyFromSettings()
        }
        settings.onNotifySessionFinishedChanged = { [weak self] _ in
            self?.updatePolicyFromSettings()
        }
        settings.onNotifySessionFailedChanged = { [weak self] _ in
            self?.updatePolicyFromSettings()
        }
        settings.onHideProjectPathsChanged = { [weak self] _ in
            self?.updatePolicyFromSettings()
        }
        // LoomApp owns provider enablement so it can update monitoring.
        // Notification policy reads enabled providers before each evaluation.

        if let store {
            connect(to: store)
        }
    }

    public func connect(to store: SessionStore) {
        self.store = store
        startObservingStore(store)
    }

    public func setupCategories() {
        let viewAction = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "View in Loom",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    public func checkAuthorizationStatus() async -> NotificationAuthorizationStatus {
        let currentSettings = await center.notificationSettings()
        switch currentSettings.authorizationStatus {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        case .provisional:
            return .provisional
        @unknown default:
            return .notDetermined
        }
    }

    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    #if DEBUG
    public func sendTestNotification() async throws {
        let status = await checkAuthorizationStatus()
        if status == .notDetermined {
            let granted = await requestAuthorization()
            if !granted {
                throw NSError(
                    domain: "com.loom.notifications",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Notification authorization was not granted."]
                )
            }
        } else if status == .denied {
            throw NSError(
                domain: "com.loom.notifications",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Notifications are disabled in System Settings."]
            )
        }

        let content = UNMutableNotificationContent()
        content.title = "Loom"
        content.subtitle = "Test Notification"
        content.body = "Notifications are active. You will be alerted for session waiting states and quota thresholds."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            NotificationPayloadKey.targetTab: "sessions",
            NotificationPayloadKey.providerID: ProviderID.codex.rawValue,
            NotificationPayloadKey.eventType: "test"
        ]

        let request = UNNotificationRequest(
            identifier: "loom-test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try await center.add(request)
        historyStore.append(NotificationRecord(
            id: request.identifier,
            title: content.title,
            subtitle: content.subtitle,
            body: content.body,
            provider: .codex,
            eventType: "test",
            deliveredStatus: .delivered
        ))
    }
    #endif

    public func postNotification(
        title: String = "Loom",
        subtitle: String? = nil,
        body: String,
        targetTab: String = "sessions",
        providerID: ProviderID? = nil,
        sessionID: String? = nil,
        eventType: String = "generic",
        identifier: String = UUID().uuidString
    ) async throws {
        guard let settings, settings.notificationsEnabled else { return }

        let status = await checkAuthorizationStatus()
        guard status == .authorized || status == .provisional else {
            historyStore.append(NotificationRecord(
                id: identifier,
                title: title,
                subtitle: subtitle,
                body: body,
                provider: providerID,
                eventType: eventType,
                deliveredStatus: .suppressed
            ))
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            NotificationPayloadKey.targetTab: targetTab,
            NotificationPayloadKey.providerID: providerID?.rawValue as Any,
            NotificationPayloadKey.sessionID: sessionID as Any,
            NotificationPayloadKey.eventType: eventType
        ]

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            historyStore.append(NotificationRecord(
                id: identifier,
                title: title,
                subtitle: subtitle,
                body: body,
                provider: providerID,
                eventType: eventType,
                deliveredStatus: .delivered
            ))
        } catch {
            historyStore.append(NotificationRecord(
                id: identifier,
                title: title,
                subtitle: subtitle,
                body: body,
                provider: providerID,
                eventType: eventType,
                deliveredStatus: .failed
            ))
            throw error
        }
    }

    public func handleMonitoringEvent(_ event: MonitoringEvent) {
        guard let settings, settings.notificationsEnabled else { return }

        updatePolicyFromSettings()

        guard policy.shouldDeliver(event: event) else {
            return
        }

        let formatted = policy.formatNotification(for: event)
        let targetTab: String
        let sessionID: String?

        switch event {
        case .quotaThresholdCrossed, .quotaReplenished:
            targetTab = "usage"
            sessionID = nil
        case .sessionStateTransition(let session, _, _):
            targetTab = "sessions"
            sessionID = session.id
        }

        Task { @MainActor in
            try? await self.postNotification(
                title: formatted.title,
                subtitle: formatted.subtitle,
                body: formatted.body,
                targetTab: targetTab,
                providerID: formatted.provider,
                sessionID: sessionID,
                eventType: formatted.eventType
            )
        }
    }

    public func processStoreUpdate() {
        guard let store, let settings, settings.notificationsEnabled else { return }
        updatePolicyFromSettings()

        // Evaluate quota thresholds
        for snapshot in store.enabledSnapshots {
            if let usage = snapshot.usage {
                let quotaEvents = quotaEvaluator.evaluateUsage(newSnapshot: usage, for: snapshot.providerID)
                for event in quotaEvents {
                    handleMonitoringEvent(event)
                }
            }
        }

        // Evaluate session transitions
        let allSessions = store.allSessions
        let failedProviders = Set(store.providerSnapshots.filter { $0.errorMessage != nil }.map(\.providerID))
        let transitionEvents = transitionDetector.detectTransitions(
            currentSessions: allSessions,
            failedProviders: failedProviders
        )
        for event in transitionEvents {
            handleMonitoringEvent(event)
        }
    }

    private func updatePolicyFromSettings() {
        guard let settings else { return }
        let config = NotificationPolicyConfig(
            notificationsEnabled: settings.notificationsEnabled,
            quotaAlertsEnabled: true,
            quotaFifteenPercentEnabled: settings.notifyQuota15Percent,
            quotaFivePercentEnabled: settings.notifyQuota5Percent,
            quotaReplenishmentEnabled: settings.notifyQuotaReset,
            sessionWaitingEnabled: settings.notifySessionWaiting,
            sessionFinishedEnabled: settings.notifySessionFinished,
            sessionFailedEnabled: settings.notifySessionFailed,
            hideProjectPaths: settings.hideProjectPaths,
            enabledProviders: settings.enabledProviderIDs
        )
        self.policy = NotificationPolicy(config: config)
    }

    private func startObservingStore(_ store: SessionStore) {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self, weak store] in
            while !Task.isCancelled {
                guard let self, let store else { break }
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = store.lastRefreshedAt
                        _ = store.providerSnapshots
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                self.processStoreUpdate()
            }
        }
    }

    @MainActor
    public func handleDeepLink(
        targetTab: String,
        providerID: ProviderID?,
        sessionID: String?,
        actionIdentifier: String = UNNotificationDefaultActionIdentifier
    ) {
        NSApp?.activate(ignoringOtherApps: true)

        let payload = DeepLinkPayload(
            targetTab: targetTab,
            providerID: providerID,
            sessionID: sessionID,
            actionIdentifier: actionIdentifier
        )
        self.lastDeepLinkPayload = payload
        self.onDeepLink?(payload)

        NotificationCenter.default.post(
            name: Self.deepLinkNotification,
            object: nil,
            userInfo: [
                NotificationPayloadKey.targetTab: targetTab,
                NotificationPayloadKey.providerID: providerID?.rawValue as Any,
                NotificationPayloadKey.sessionID: sessionID as Any,
                "actionIdentifier": actionIdentifier
            ]
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let targetTab = userInfo[NotificationPayloadKey.targetTab] as? String ?? "sessions"
        let providerRaw = userInfo[NotificationPayloadKey.providerID] as? String
        let sessionID = userInfo[NotificationPayloadKey.sessionID] as? String
        let providerID = providerRaw != nil ? ProviderID(providerRaw!) : nil

        Task { @MainActor in
            self.handleDeepLink(
                targetTab: targetTab,
                providerID: providerID,
                sessionID: sessionID,
                actionIdentifier: response.actionIdentifier
            )
            completionHandler()
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
