//
//  SharedAppGroup.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

/// Result of reading a shared widget snapshot from the App Group container.
public enum SnapshotReadResult: Sendable, Equatable {
    case success(LoomWidgetSnapshot)
    case notFound
    case corrupted(String)
    case unsupportedVersion(Int)
}

/// Provides safe, atomic access to the shared App Group container for Loom and its extensions.
public final class SharedAppGroup: Sendable {
    public static let shared = SharedAppGroup()

    /// The App Group identifier shared between Loom and LoomWidgetExtension.
    public static let appGroupIdentifier = "group.com.chaiwithcode.loom"

    /// Candidate App Group identifiers, prioritizing Team ID prefixed identifiers for sandboxed macOS extensions.
    public static let candidateAppGroupIdentifiers = [
        "K9UNF256S9.group.com.chaiwithcode.loom",
        "group.com.chaiwithcode.loom"
    ]

    /// The canonical filename for the shared widget snapshot.
    public static let snapshotFilename = "widget-snapshot.json"

    private let customBaseDirectory: URL?

    public init(customBaseDirectory: URL? = nil) {
        self.customBaseDirectory = customBaseDirectory
    }

    /// Resolves the base container directory.
    /// Falls back gracefully to Application Support if running in an unentitled/development environment.
    public var containerURL: URL? {
        if let customBaseDirectory {
            return customBaseDirectory
        }

        // Only query system security daemon for App Group container when running inside an entitled bundle.
        // In headless test harnesses, querying containerURL without an entitlement causes a 25s syspolicyd timeout.
        let bundleID = Bundle.main.bundleIdentifier
        if bundleID == "com.chaiwithcode.loom" || bundleID == "com.chaiwithcode.loom.widget" {
            for groupID in Self.candidateAppGroupIdentifiers {
                if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
                    return groupURL
                }
            }
        }

        // Development/test fallback when App Group entitlement is unavailable
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupport?.appendingPathComponent("com.chaiwithcode.loom/shared", isDirectory: true)
    }

    /// Resolves the full URL for the snapshot file.
    public var snapshotFileURL: URL? {
        containerURL?.appendingPathComponent(Self.snapshotFilename, isDirectory: false)
    }

    /// Atomically writes a widget snapshot to the shared container.
    @discardableResult
    public func writeSnapshot(_ snapshot: LoomWidgetSnapshot) -> Bool {
        guard let url = snapshotFileURL else { return false }
        do {
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)

            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// Safely reads the widget snapshot from the shared container.
    public func readSnapshot() -> SnapshotReadResult {
        guard let url = snapshotFileURL else {
            return .notFound
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .notFound
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(LoomWidgetSnapshot.self, from: data)

            guard snapshot.schemaVersion == LoomWidgetSnapshot.currentSchemaVersion else {
                return .unsupportedVersion(snapshot.schemaVersion)
            }

            return .success(snapshot)
        } catch {
            return .corrupted(error.localizedDescription)
        }
    }

    /// Removes the snapshot file (used in tests and cleanups).
    @discardableResult
    public func removeSnapshot() -> Bool {
        guard let url = snapshotFileURL, FileManager.default.fileExists(atPath: url.path) else {
            return true
        }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
