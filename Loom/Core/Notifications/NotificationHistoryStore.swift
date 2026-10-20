//
//  NotificationHistoryStore.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

/// Represents a persistent historical log entry for a delivered or evaluated notification.
public struct NotificationRecord: Identifiable, Hashable, Equatable, Sendable, Codable {
    public let id: String
    public let timestamp: Date
    public let title: String
    public let subtitle: String?
    public let body: String
    public let provider: ProviderID?
    public let eventType: String
    public let deliveredStatus: DeliveryStatus

    public enum DeliveryStatus: String, Codable, Sendable {
        case delivered
        case suppressed
        case failed
    }

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        title: String,
        subtitle: String? = nil,
        body: String,
        provider: ProviderID? = nil,
        eventType: String,
        deliveredStatus: DeliveryStatus = .delivered
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.provider = provider
        self.eventType = eventType
        self.deliveredStatus = deliveredStatus
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, title, subtitle, body, provider, eventType, deliveredStatus
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(provider?.rawValue, forKey: .provider)
        try container.encode(eventType, forKey: .eventType)
        try container.encode(deliveredStatus, forKey: .deliveredStatus)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        self.body = try container.decode(String.self, forKey: .body)
        if let rawProvider = try container.decodeIfPresent(String.self, forKey: .provider) {
            self.provider = ProviderID(rawProvider)
        } else {
            self.provider = nil
        }
        self.eventType = try container.decode(String.self, forKey: .eventType)
        self.deliveredStatus = try container.decode(DeliveryStatus.self, forKey: .deliveredStatus)
    }
}

/// A thread-safe, bounded ring buffer for retaining recent delivered notification records.
/// Strictly enforces privacy by scrubbing sensitive auth tokens, API keys, and long shell command transcripts.
public final class NotificationHistoryStore: @unchecked Sendable {
    public static let defaultMaxCapacity = 50

    private let lock = NSLock()
    private var buffer: [NotificationRecord] = []
    public let maxCapacity: Int

    public init(maxCapacity: Int = defaultMaxCapacity) {
        self.maxCapacity = max(1, maxCapacity)
    }

    /// Appends a new notification record, dropping the oldest entry if maxCapacity is reached.
    public func append(_ record: NotificationRecord) {
        lock.lock()
        defer { lock.unlock() }

        let sanitized = sanitize(record)
        buffer.append(sanitized)
        if buffer.count > maxCapacity {
            buffer.removeFirst(buffer.count - maxCapacity)
        }
    }

    /// Convenience builder to record a delivered notification directly.
    public func record(
        title: String,
        subtitle: String? = nil,
        body: String,
        provider: ProviderID? = nil,
        eventType: String,
        status: NotificationRecord.DeliveryStatus = .delivered
    ) {
        let entry = NotificationRecord(
            title: title,
            subtitle: subtitle,
            body: body,
            provider: provider,
            eventType: eventType,
            deliveredStatus: status
        )
        append(entry)
    }

    /// Returns all stored records in chronological order.
    public var records: [NotificationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    /// Returns records sorted from newest to oldest.
    public var recentRecords: [NotificationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return buffer.reversed()
    }

    /// Returns the current number of stored records.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// Clears all historical records from the store.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }

    // MARK: - Privacy & Sensitive Data Sanitization

    private func sanitize(_ record: NotificationRecord) -> NotificationRecord {
        let cleanTitle = Self.scrubSensitiveData(record.title)
        let cleanSubtitle = record.subtitle.map { Self.scrubSensitiveData($0) }
        let cleanBody = Self.scrubSensitiveData(record.body)

        // Ensure body text does not retain long transcripts; cap at 256 characters
        let truncatedBody: String
        if cleanBody.count > 256 {
            let index = cleanBody.index(cleanBody.startIndex, offsetBy: 253)
            truncatedBody = String(cleanBody[..<index]) + "..."
        } else {
            truncatedBody = cleanBody
        }

        return NotificationRecord(
            id: record.id,
            timestamp: record.timestamp,
            title: cleanTitle,
            subtitle: cleanSubtitle,
            body: truncatedBody,
            provider: record.provider,
            eventType: record.eventType,
            deliveredStatus: record.deliveredStatus
        )
    }

    /// Scrubs auth tokens, secret keys, bearer tokens, and complete commands from input text.
    public static func scrubSensitiveData(_ input: String) -> String {
        var text = input

        // 1. Scrub Bearer tokens: Bearer <token>
        text = text.replacingOccurrences(
            of: #"Bearer\s+[A-Za-z0-9_.\-~+/=]+"#,
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )

        // 2. Scrub Anthropic / OpenAI / general API keys: sk-...
        text = text.replacingOccurrences(
            of: #"\bsk-[A-Za-z0-9_\-]{10,}\b"#,
            with: "sk-[REDACTED]",
            options: .regularExpression
        )

        // 3. Scrub GitHub tokens: ghp_..., gho_...
        text = text.replacingOccurrences(
            of: #"\bgh[pousr]_[A-Za-z0-9_]{15,}\b"#,
            with: "gh_[REDACTED]",
            options: .regularExpression
        )

        // 4. Scrub command line shell invocations: bash -c "...", /bin/sh -c "..."
        text = text.replacingOccurrences(
            of: #"(?:/bin/)?(?:bash|sh|zsh)\s+-c\s+["'][^"']+["']"#,
            with: "[Command script redacted]",
            options: .regularExpression
        )

        return text
    }
}
