//
//  QuotaThresholdEvaluator.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

/// Persistent or in-memory backing storage for deduplicating quota alert notifications.
public protocol QuotaAlertDeduplicationStore: Sendable {
    func contains(key: String) -> Bool
    func insert(key: String)
    func remove(key: String)
    func removeAll()
    var allKeys: Set<String> { get }
}

/// In-memory implementation of quota alert deduplication store.
public final class InMemoryQuotaAlertStore: QuotaAlertDeduplicationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: Set<String>

    public init(initialKeys: Set<String> = []) {
        self.keys = initialKeys
    }

    public func contains(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return keys.contains(key)
    }

    public func insert(key: String) {
        lock.lock()
        defer { lock.unlock() }
        keys.insert(key)
    }

    public func remove(key: String) {
        lock.lock()
        defer { lock.unlock() }
        keys.remove(key)
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        keys.removeAll()
    }

    public var allKeys: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return keys
    }
}

/// UserDefaults-backed implementation of quota alert deduplication store.
public final class UserDefaultsQuotaAlertStore: QuotaAlertDeduplicationStore, @unchecked Sendable {
    public static let defaultStorageKey = "com.loom.sentQuotaAlertKeys"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults = .standard, storageKey: String = defaultStorageKey) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func contains(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let current = defaults.stringArray(forKey: storageKey) ?? []
        return current.contains(key)
    }

    public func insert(key: String) {
        lock.lock()
        defer { lock.unlock() }
        var current = defaults.stringArray(forKey: storageKey) ?? []
        if !current.contains(key) {
            current.append(key)
            defaults.set(current, forKey: storageKey)
        }
    }

    public func remove(key: String) {
        lock.lock()
        defer { lock.unlock() }
        var current = defaults.stringArray(forKey: storageKey) ?? []
        if let idx = current.firstIndex(of: key) {
            current.remove(at: idx)
            defaults.set(current, forKey: storageKey)
        }
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: storageKey)
    }

    public var allKeys: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        let current = defaults.stringArray(forKey: storageKey) ?? []
        return Set(current)
    }
}

/// Evaluates provider usage snapshots against threshold policies and window replenishment criteria.
public final class QuotaThresholdEvaluator: @unchecked Sendable {
    public static let defaultBucketTrackingDefaultsKey = "com.loom.quotaBucketTracking"

    private struct BucketState: Codable {
        var lastWindowId: String?
        var lastRemainingFraction: Double?
        var wasDepleted: Bool
        var lastResetAt: Date?
        var lastObservedAt: Date?
    }

    private let lock = NSLock()
    private let store: QuotaAlertDeduplicationStore
    private let defaults: UserDefaults?
    private let trackingDefaultsKey: String
    private var bucketStates: [String: BucketState] = [:]

    public init(
        store: QuotaAlertDeduplicationStore,
        userDefaults: UserDefaults? = nil,
        trackingDefaultsKey: String = defaultBucketTrackingDefaultsKey
    ) {
        self.store = store
        self.defaults = userDefaults
        self.trackingDefaultsKey = trackingDefaultsKey
        loadBucketStates()
    }

    public convenience init(
        userDefaults: UserDefaults? = nil,
        trackingDefaultsKey: String = defaultBucketTrackingDefaultsKey
    ) {
        if let userDefaults {
            let persistentStore = UserDefaultsQuotaAlertStore(defaults: userDefaults)
            self.init(store: persistentStore, userDefaults: userDefaults, trackingDefaultsKey: trackingDefaultsKey)
        } else {
            self.init(store: InMemoryQuotaAlertStore(), userDefaults: nil, trackingDefaultsKey: trackingDefaultsKey)
        }
    }

    /// Computes the unique deduplication key for a threshold crossing alert:
    /// `\(provider.rawValue):\(bucket):\(windowId):\(threshold.rawValue)`.
    public func deduplicationKey(
        provider: ProviderID,
        bucket: String,
        windowId: String,
        threshold: QuotaThreshold
    ) -> String {
        "\(provider.rawValue):\(bucket):\(windowId):\(threshold.rawValue)"
    }

    /// Computes the unique deduplication key for a quota replenishment alert:
    /// `\(provider.rawValue):\(bucket):\(windowId):replenished`.
    public func deduplicationKeyForReplenishment(
        provider: ProviderID,
        bucket: String,
        windowId: String
    ) -> String {
        "\(provider.rawValue):\(bucket):\(windowId):replenished"
    }

    /// Derives a stable window identifier from a usage bucket, using resetsAt ISO8601 string or fallback.
    public static func windowId(for bucket: UsageBucket) -> String {
        if let resetsAt = bucket.resetsAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: resetsAt)
        }
        return "current"
    }

    /// Evaluates a full provider usage snapshot, ignoring stale, missing, failed, or unsupported providers.
    public func evaluate(snapshot: ProviderUsageSnapshot) -> [MonitoringEvent] {
        // 1. Check for stale snapshot
        guard !snapshot.isStale else { return [] }

        // 2. Claude Code does not provide machine-readable quota snapshots; ignore
        guard snapshot.providerID != .claude else { return [] }

        // Error/cached payloads do not prove a fresh threshold or reset.
        guard snapshot.errorMessage == nil else { return [] }

        let buckets = snapshot.allBuckets
        guard !buckets.isEmpty else { return [] }

        var events: [MonitoringEvent] = []
        for bucket in buckets {
            events.append(contentsOf: evaluate(provider: snapshot.providerID, bucket: bucket, observedAt: snapshot.updatedAt))
        }
        return events
    }

    /// Evaluates usage snapshot for a provider (convenience overload).
    public func evaluateUsage(newSnapshot: ProviderUsageSnapshot, for providerID: ProviderID? = nil) -> [MonitoringEvent] {
        return evaluate(snapshot: newSnapshot)
    }

    /// Evaluates an individual bucket for threshold crossings and window replenishment.
    public func evaluate(
        provider: ProviderID,
        bucket: UsageBucket,
        windowId: String? = nil,
        isStale: Bool = false,
        observedAt: Date = Date()
    ) -> [MonitoringEvent] {
        guard !isStale else { return [] }
        guard provider != .claude else { return [] }
        guard let used = bucket.usedFraction, used.isFinite, (0...1).contains(used) else { return [] }

        let remainingFraction = max(0.0, min(1.0, 1.0 - used))
        let remainingPercent = (remainingFraction * 10000.0).rounded() / 100.0
        let effectiveWindowId = windowId ?? Self.windowId(for: bucket)

        lock.lock()
        defer { lock.unlock() }

        let bucketKey = "\(provider.rawValue):\(bucket.identifier)"
        var state = bucketStates[bucketKey] ?? BucketState(lastWindowId: nil, lastRemainingFraction: nil, wasDepleted: false)
        var events: [MonitoringEvent] = []

        // Replayed/out-of-order observations cannot cross a reset boundary.
        if let lastObservedAt = state.lastObservedAt, observedAt <= lastObservedAt { return [] }
        let isNewWindow = state.lastWindowId != nil && state.lastWindowId != effectiveWindowId
        let crossedKnownReset: Bool
        if let priorReset = state.lastResetAt, let priorObservation = state.lastObservedAt,
           let nextReset = bucket.resetsAt {
            crossedKnownReset = priorObservation < priorReset && observedAt >= priorReset &&
                nextReset > priorReset && nextReset > observedAt
        } else {
            crossedKnownReset = false
        }
        if isNewWindow && crossedKnownReset && state.wasDepleted && remainingPercent >= 95.0 {
            let replenishmentKey = deduplicationKeyForReplenishment(
                provider: provider,
                bucket: bucket.identifier,
                windowId: effectiveWindowId
            )
            if !store.contains(key: replenishmentKey) {
                store.insert(key: replenishmentKey)
                events.append(.quotaReplenished(
                    provider: provider,
                    bucket: bucket.identifier,
                    windowId: effectiveWindowId
                ))
            }
        }

        // Threshold crossing: 15%
        if remainingPercent <= 15.0001 {
            let key15 = deduplicationKey(
                provider: provider,
                bucket: bucket.identifier,
                windowId: effectiveWindowId,
                threshold: .fifteenPercent
            )
            if !store.contains(key: key15) {
                store.insert(key: key15)
                events.append(.quotaThresholdCrossed(
                    provider: provider,
                    bucket: bucket.identifier,
                    remainingPercent: remainingPercent,
                    windowId: effectiveWindowId,
                    threshold: .fifteenPercent
                ))
            }
        }

        // Threshold crossing: 5%
        if remainingPercent <= 5.0001 {
            let key5 = deduplicationKey(
                provider: provider,
                bucket: bucket.identifier,
                windowId: effectiveWindowId,
                threshold: .fivePercent
            )
            if !store.contains(key: key5) {
                store.insert(key: key5)
                events.append(.quotaThresholdCrossed(
                    provider: provider,
                    bucket: bucket.identifier,
                    remainingPercent: remainingPercent,
                    windowId: effectiveWindowId,
                    threshold: .fivePercent
                ))
            }
        }

        // Update tracking state
        state.lastResetAt = bucket.resetsAt
        state.lastObservedAt = observedAt
        state.lastWindowId = effectiveWindowId
        state.lastRemainingFraction = remainingFraction
        state.wasDepleted = (remainingPercent < 95.0)
        bucketStates[bucketKey] = state
        saveBucketStates()

        return events
    }

    /// Resets all tracked state and deduplication keys.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        store.removeAll()
        bucketStates.removeAll()
        defaults?.removeObject(forKey: trackingDefaultsKey)
    }

    // MARK: - Private Persistence Helpers

    private func loadBucketStates() {
        guard let defaults, let data = defaults.data(forKey: trackingDefaultsKey) else { return }
        do {
            bucketStates = try JSONDecoder().decode([String: BucketState].self, from: data)
        } catch {
            bucketStates = [:]
        }
    }

    private func saveBucketStates() {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder().encode(bucketStates)
            defaults.set(data, forKey: trackingDefaultsKey)
        } catch {
            // Non-critical persistence failure
        }
    }
}
