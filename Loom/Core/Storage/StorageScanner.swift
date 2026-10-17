//
//  StorageScanner.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct StorageLocation: Sendable, Identifiable {
    public var id: String { url.path }
    public let label: String
    public let url: URL
    public init(label: String, url: URL) { self.label = label; self.url = url }
}

public struct StorageMeasurement: Sendable, Identifiable {
    public var id: String { location.id }
    public let location: StorageLocation
    public let bytes: Int64
    public let fileCount: Int
    public let status: Status
    public enum Status: String, Sendable {
        case complete, missing, partial, inaccessible, symbolicLink
    }
}

public struct ProviderStorageSummary: Sendable, Identifiable, Equatable {
    public var id: ProviderID { providerID }
    public let providerID: ProviderID
    public let name: String
    public let totalBytes: Int64
    public let fileCount: Int
    public let isComplete: Bool
    public let hasData: Bool

    public init(providerID: ProviderID, name: String, totalBytes: Int64, fileCount: Int, isComplete: Bool, hasData: Bool) {
        self.providerID = providerID
        self.name = name
        self.totalBytes = totalBytes
        self.fileCount = fileCount
        self.isComplete = isComplete
        self.hasData = hasData
    }
}

public struct StorageOverview: Sendable, Equatable {
    public let summaries: [ProviderStorageSummary]
    public let scannedAt: Date

    public init(summaries: [ProviderStorageSummary], scannedAt: Date = Date()) {
        self.summaries = summaries
        self.scannedAt = scannedAt
    }

    public var totalBytes: Int64 {
        summaries.reduce(0) { $0 + $1.totalBytes }
    }

    public var totalFiles: Int {
        summaries.reduce(0) { $0 + $1.fileCount }
    }

    public var isComplete: Bool {
        summaries.allSatisfy(\.isComplete)
    }

    public var hasData: Bool {
        summaries.contains(where: \.hasData)
    }

    public func summary(for providerID: ProviderID) -> ProviderStorageSummary? {
        summaries.first(where: { $0.providerID == providerID })
    }

    /// Returns the relative proportion of total agent storage consumed by this provider (0.0 ... 1.0).
    /// If totalBytes == 0 or provider has 0 bytes, returns 0.0.
    /// This is strictly for relative comparison between providers, NOT a quota usage percentage.
    public func proportion(for providerID: ProviderID) -> Double {
        guard totalBytes > 0, let summary = summary(for: providerID), summary.totalBytes > 0 else {
            return 0.0
        }
        return Double(summary.totalBytes) / Double(totalBytes)
    }
}

/// Read-only, bounded metadata scan. Never follows symlinks or reads file contents.
public struct StorageScanner: Sendable {
    public init() {}

    public func measure(_ locations: [StorageLocation], maxFiles: Int = 100_000,
                        secondsPerLocation: TimeInterval = 5) throws -> [StorageMeasurement] {
        let fm = FileManager.default
        var seenFiles = Set<String>()
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey,
            .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileResourceIdentifierKey]
        return try locations.map { location in
            try Task.checkCancellation()
            var bytes: Int64 = 0
            var files = 0
            var partial = false
            let deadline = Date().addingTimeInterval(secondsPerLocation)
            func result(_ status: StorageMeasurement.Status) -> StorageMeasurement {
                StorageMeasurement(location: location, bytes: bytes, fileCount: files, status: status)
            }
            let root: URLResourceValues
            do { root = try location.url.resourceValues(forKeys: keys) }
            catch {
                let ns = error as NSError
                return result(ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError ? .missing : .inaccessible)
            }
            guard root.isSymbolicLink != true else { return result(.symbolicLink) }
            guard root.isDirectory == true else { return result(.inaccessible) }
            guard let enumerator = fm.enumerator(at: location.url, includingPropertiesForKeys: Array(keys),
                options: [], errorHandler: { _, _ in partial = true; return true }) else {
                return result(.inaccessible)
            }
            var visited = 0
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                visited += 1
                if visited > maxFiles || Date() >= deadline { partial = true; break }
                do {
                    let values = try url.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    guard values.isRegularFile == true else { continue }
                    // Resource identity avoids counting hard links again across a provider's roots.
                    let identity = values.fileResourceIdentifier.map { String(describing: $0) } ?? url.path
                    guard seenFiles.insert(identity).inserted else { continue }
                    guard let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize else {
                        partial = true; continue
                    }
                    bytes += Int64(max(0, size))
                    files += 1
                } catch { partial = true }
            }
            return result(partial ? .partial : .complete)
        }
    }

    public func measureOverview(for providers: [ProviderStorageLocations]) throws -> StorageOverview {
        var summaries: [ProviderStorageSummary] = []
        for provider in providers {
            try Task.checkCancellation()
            let measurements = try measure(provider.locations)
            let bytes = measurements.reduce(Int64(0)) { $0 + $1.bytes }
            let files = measurements.reduce(0) { $0 + $1.fileCount }
            let complete = measurements.allSatisfy { $0.status == .complete || $0.status == .missing }
            let hasData = measurements.contains { $0.status == .complete || $0.fileCount > 0 }
            summaries.append(ProviderStorageSummary(
                providerID: provider.id,
                name: provider.name,
                totalBytes: bytes,
                fileCount: files,
                isComplete: complete,
                hasData: hasData
            ))
        }
        return StorageOverview(summaries: summaries, scannedAt: Date())
    }
}
