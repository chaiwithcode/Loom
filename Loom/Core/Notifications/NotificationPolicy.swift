//
//  NotificationPolicy.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

/// User preferences configuring which notifications are evaluated, filtered, and delivered.
public struct NotificationPolicyConfig: Sendable, Equatable {
    public var notificationsEnabled: Bool
    public var quotaAlertsEnabled: Bool
    public var quotaFifteenPercentEnabled: Bool
    public var quotaFivePercentEnabled: Bool
    public var quotaReplenishmentEnabled: Bool
    public var sessionWaitingEnabled: Bool
    public var minimumWorkingDuration: TimeInterval
    public var sessionFinishedEnabled: Bool
    public var sessionFailedEnabled: Bool
    public var hideProjectPaths: Bool
    public var enabledProviders: Set<ProviderID>?

    public init(
        notificationsEnabled: Bool = true,
        quotaAlertsEnabled: Bool = true,
        quotaFifteenPercentEnabled: Bool = true,
        quotaFivePercentEnabled: Bool = true,
        quotaReplenishmentEnabled: Bool = true,
        sessionWaitingEnabled: Bool = true,
        sessionFinishedEnabled: Bool = true,
        minimumWorkingDuration: TimeInterval = 0,
        sessionFailedEnabled: Bool = true,
        hideProjectPaths: Bool = false,
        enabledProviders: Set<ProviderID>? = nil
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.quotaAlertsEnabled = quotaAlertsEnabled
        self.quotaFifteenPercentEnabled = quotaFifteenPercentEnabled
        self.quotaFivePercentEnabled = quotaFivePercentEnabled
        self.quotaReplenishmentEnabled = quotaReplenishmentEnabled
        self.sessionWaitingEnabled = sessionWaitingEnabled
        self.minimumWorkingDuration = max(0, minimumWorkingDuration)
        self.sessionFinishedEnabled = sessionFinishedEnabled
        self.sessionFailedEnabled = sessionFailedEnabled
        self.hideProjectPaths = hideProjectPaths
        self.enabledProviders = enabledProviders
    }
}

/// Formatted notification content ready for dispatch via native notification center.
public struct FormattedNotification: Equatable, Hashable, Sendable {
    public let title: String
    public let subtitle: String?
    public let body: String
    public let provider: ProviderID?
    public let eventType: String

    public init(
        title: String,
        subtitle: String? = nil,
        body: String,
        provider: ProviderID? = nil,
        eventType: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.provider = provider
        self.eventType = eventType
    }
}

/// Enforces user notification preferences, provider filtering, and privacy path concealment.
public struct NotificationPolicy: Sendable {
    public var config: NotificationPolicyConfig

    public init(config: NotificationPolicyConfig = NotificationPolicyConfig()) {
        self.config = config
    }

    /// Determines if an event should be delivered under the current policy preferences.
    public func shouldDeliver(event: MonitoringEvent, observedWorkingDuration: TimeInterval? = nil) -> Bool {
        guard config.notificationsEnabled else { return false }

        // Filter out events from disabled providers if an explicit enabled set is supplied
        if let enabled = config.enabledProviders, let provider = event.provider {
            guard enabled.contains(provider) else { return false }
        }

        switch event {
        case .quotaThresholdCrossed(_, _, _, _, let threshold):
            guard config.quotaAlertsEnabled else { return false }
            switch threshold {
            case .fifteenPercent:
                return config.quotaFifteenPercentEnabled
            case .fivePercent:
                return config.quotaFivePercentEnabled
            }

        case .quotaReplenished:
            guard config.quotaAlertsEnabled else { return false }
            return config.quotaReplenishmentEnabled

        case .sessionStateTransition(_, _, let toState):
            switch toState {
            case .waiting:
                return config.sessionWaitingEnabled
            case .finished:
                return config.sessionFinishedEnabled &&
                    (observedWorkingDuration ?? 0) >= config.minimumWorkingDuration
            case .failed:
                return config.sessionFailedEnabled
            default:
                return false
            }
        }
    }

    /// Filters and sanitizes a list of events according to policy rules and privacy settings.
    public func filter(events: [MonitoringEvent]) -> [MonitoringEvent] {
        events.compactMap { event in
            guard shouldDeliver(event: event) else { return nil }
            return sanitize(event: event)
        }
    }

    /// Applies privacy concealment to event metadata if hideProjectPaths is true.
    public func sanitize(event: MonitoringEvent) -> MonitoringEvent {
        guard config.hideProjectPaths else { return event }

        switch event {
        case .sessionStateTransition(let session, let fromState, let toState):
            let sanitized = sanitize(session: session)
            return .sessionStateTransition(session: sanitized, fromState: fromState, toState: toState)
        case .quotaThresholdCrossed, .quotaReplenished:
            return event
        }
    }

    /// Sanitizes an AgentSession by concealing full paths while preserving the project base name.
    public func sanitize(session: AgentSession) -> AgentSession {
        guard config.hideProjectPaths else { return session }

        let safeName = Self.safeProjectName(for: session, hidePaths: true)
        let sanitizedSummary = session.summary.map { sanitizePath($0) }

        return AgentSession(
            id: session.id,
            provider: session.provider,
            projectName: safeName,
            projectPath: nil,
            state: session.state,
            startedAt: session.startedAt,
            lastActivityAt: session.lastActivityAt,
            branch: session.branch,
            summary: sanitizedSummary,
            pid: session.pid,
            providerSessionID: session.providerSessionID,
            associatedProcesses: session.associatedProcesses,
            hostApp: session.hostApp,
            diagnostics: session.diagnostics,
            discoveryEvidence: session.discoveryEvidence.map { sanitizePath($0) }
        )
    }

    /// Derives a clean project name, concealing full filesystem paths if hidePaths is true.
    public static func safeProjectName(for session: AgentSession, hidePaths: Bool) -> String {
        let raw = session.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = session.projectPath?.lastPathComponent ?? "Untitled Project"
        let candidate = (raw == nil || raw!.isEmpty) ? fallback : raw!
        if hidePaths {
            if candidate.contains("/") || candidate.contains("~") {
                let last = URL(fileURLWithPath: candidate).lastPathComponent
                return last.isEmpty ? "Project" : last
            }
        }
        return candidate
    }

    /// Sanitizes file paths within a string, replacing absolute or home-relative directory hierarchies
    /// (e.g. `/Users/username/Projects/secret-repo`) with the last component (`secret-repo`).
    public func sanitizePath(_ input: String) -> String {
        guard config.hideProjectPaths else { return input }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("/") || trimmed.hasPrefix("~/")) && !trimmed.contains("\n") && !trimmed.contains(" ") {
            let last = URL(fileURLWithPath: trimmed).lastPathComponent
            return last.isEmpty ? "Project" : last
        }

        // Replace embedded paths in longer text
        let pattern = #"(?:~?/(?:[^\s/,;:"]+/)+([^\s/,;:"]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }

        let nsString = input as NSString
        let range = NSRange(location: 0, length: nsString.length)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "$1")
    }

    /// Formats an event into a user-facing notification structure.
    public func formatNotification(for event: MonitoringEvent) -> FormattedNotification {
        switch event {
        case .quotaThresholdCrossed(let provider, let bucket, let remainingPercent, _, let threshold):
            return FormattedNotification(
                title: "\(provider.displayName): Quota Alert",
                subtitle: bucket,
                body: "Remaining quota dropped below \(threshold.rawValue) (\(Int(remainingPercent.rounded()))% remaining).",
                provider: provider,
                eventType: event.eventType
            )

        case .quotaReplenished(let provider, let bucket, _):
            return FormattedNotification(
                title: "\(provider.displayName): Quota Replenished",
                subtitle: bucket,
                body: "Quota has reset and is back above 95%.",
                provider: provider,
                eventType: event.eventType
            )

        case .sessionStateTransition(let session, _, let toState):
            let projectName = Self.safeProjectName(for: session, hidePaths: config.hideProjectPaths)
            let bodyText: String
            switch toState {
            case .waiting:
                bodyText = "Session requires user input or approval."
            case .finished:
                bodyText = "Session has completed."
            case .failed:
                bodyText = "Session failed."
            default:
                bodyText = "State transitioned to \(toState.displayName)."
            }

            return FormattedNotification(
                title: "\(session.provider.displayName): \(projectName)",
                subtitle: toState.displayName,
                body: bodyText,
                provider: session.provider,
                eventType: event.eventType
            )
        }
    }
}
