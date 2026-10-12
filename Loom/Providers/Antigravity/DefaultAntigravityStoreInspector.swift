//
//  DefaultAntigravityStoreInspector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
import SQLite3

public enum AntigravityStoreError: LocalizedError, Sendable, Equatable {
    case databaseOpenFailed(code: Int32, message: String)
    case queryPrepareFailed(code: Int32, message: String)
    case queryStepFailed(code: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let code, let message):
            return "Failed to open Antigravity database (code: \(code)): \(message)"
        case .queryPrepareFailed(let code, let message):
            return "Failed to prepare query on Antigravity database (code: \(code)): \(message)"
        case .queryStepFailed(let code, let message):
            return "Failed to execute query step on Antigravity database (code: \(code)): \(message)"
        }
    }
}

public final class DefaultAntigravityStoreInspector: AntigravityStoreInspecting, Sendable {
    private let databaseURL: URL

    public init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/conversation_summaries.db")
    ) {
        self.databaseURL = databaseURL
    }

    public func fetchActiveSessions() async throws -> [AntigravitySessionRecord] {
        return try await Task.detached { [databaseURL] in
            let standardizedURL = databaseURL.standardizedFileURL
            let path = standardizedURL.path
            guard FileManager.default.fileExists(atPath: path) else {
                return []
            }

            let walURL = URL(fileURLWithPath: path + "-wal")
            let hasWAL = FileManager.default.fileExists(atPath: walURL.path)

            if hasWAL {
                // 1. WAL is present: read directly with live WAL attachment so uncheckpointed WAL updates
                // are immediately visible and session state never becomes stale.
                if let directRecords = Self.tryQuery(url: standardizedURL, querySuffix: nil) {
                    return directRecords
                }

                // 2. If direct query failed (e.g. SQLite lock contention/CANTOPEN on shared memory),
                // copy both DB and -wal to a temporary snapshot to inspect uncheckpointed WAL data.
                if let snapshotRecords = Self.readRecordsFromTemporarySnapshot(sourceURL: standardizedURL) {
                    return snapshotRecords
                }

                // 3. Fallback to direct execution to throw diagnostic error if all attempts fail
                return try Self.executeQuery(url: standardizedURL, querySuffix: nil)
            } else {
                // Absence of -wal is a normal, valid SQLite state (cleanly checkpointed or idle).
                // Use immutable=1 mode=ro to inspect the main database normally without triggering
                // SQLite's attempt to create/recover a missing -wal file in read-only mode (which causes CANTOPEN 14).
                if let directRecords = Self.tryQuery(url: standardizedURL, querySuffix: "?mode=ro&immutable=1") {
                    return directRecords
                }

                // Fallback to snapshot copy if needed
                if let snapshotRecords = Self.readRecordsFromTemporarySnapshot(sourceURL: standardizedURL) {
                    return snapshotRecords
                }

                return try Self.executeQuery(url: standardizedURL, querySuffix: "?mode=ro&immutable=1")
            }
        }.value
    }

    private static func tryQuery(url: URL, querySuffix: String?) -> [AntigravitySessionRecord]? {
        do {
            return try executeQuery(url: url, querySuffix: querySuffix)
        } catch {
            return nil
        }
    }

    private static func executeQuery(url: URL, querySuffix: String?) throws -> [AntigravitySessionRecord] {
        var uri = url.standardizedFileURL.absoluteString
        if let suffix = querySuffix {
            let sep = uri.contains("?") ? "&" : (suffix.hasPrefix("?") ? "" : "?")
            uri = "\(uri)\(sep)\(suffix)"
        }

        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let openStatus = sqlite3_open_v2(uri, &db, openFlags, nil)
        guard openStatus == SQLITE_OK, let validDb = db else {
            let errorMsg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Failed to open SQLite database"
            if let db = db { sqlite3_close(db) }
            throw AntigravityStoreError.databaseOpenFailed(code: openStatus, message: errorMsg)
        }

        defer {
            sqlite3_close(validDb)
        }

        return try readRecords(from: validDb)
    }

    private static func readRecordsFromTemporarySnapshot(sourceURL: URL) -> [AntigravitySessionRecord]? {
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString
        let tempDBURL = tempDir.appendingPathComponent("loom_antigravity_\(uuid).db")
        let tempWALURL = URL(fileURLWithPath: tempDBURL.path + "-wal")
        let sourceWALURL = URL(fileURLWithPath: sourceURL.path + "-wal")

        defer {
            try? FileManager.default.removeItem(at: tempDBURL)
            try? FileManager.default.removeItem(at: tempWALURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: tempDBURL)
            if FileManager.default.fileExists(atPath: sourceWALURL.path) {
                try? FileManager.default.copyItem(at: sourceWALURL, to: tempWALURL)
            }
        } catch {
            return nil
        }

        let hasSnapshotWAL = FileManager.default.fileExists(atPath: tempWALURL.path)
        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let uri = hasSnapshotWAL
            ? tempDBURL.standardizedFileURL.absoluteString
            : "\(tempDBURL.standardizedFileURL.absoluteString)?mode=ro&immutable=1"
        let status = sqlite3_open_v2(uri, &db, openFlags, nil)
        guard status == SQLITE_OK, let validDb = db else {
            if let db = db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(validDb) }

        return try? readRecords(from: validDb)
    }

    private static func readRecords(from validDb: OpaquePointer) throws -> [AntigravitySessionRecord] {
        // Set a busy timeout of 250ms to tolerate concurrent WAL writes from Antigravity
        sqlite3_busy_timeout(validDb, 250)

        let query = """
        SELECT conversation_id, title, workspace_uris, status, not_fully_idle, killed, last_user_input_time, last_modified_time
        FROM conversation_summaries
        WHERE killed = 0 AND (status = 'CASCADE_RUN_STATUS_RUNNING' OR not_fully_idle = 1)
        ORDER BY last_modified_time DESC;
        """

        var stmt: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(validDb, query, -1, &stmt, nil)
        guard prepareStatus == SQLITE_OK, let validStmt = stmt else {
            let errorMsg = String(cString: sqlite3_errmsg(validDb))
            throw AntigravityStoreError.queryPrepareFailed(code: prepareStatus, message: errorMsg)
        }

        defer {
            sqlite3_finalize(validStmt)
        }

        var records: [AntigravitySessionRecord] = []

        while true {
            let stepStatus = sqlite3_step(validStmt)
            if stepStatus == SQLITE_ROW {
                let convId = sqlite3_column_text(validStmt, 0).map { String(cString: $0) } ?? ""
                let title = sqlite3_column_text(validStmt, 1).map { String(cString: $0) } ?? ""
                let workspaceURIs = sqlite3_column_text(validStmt, 2).map { String(cString: $0) } ?? "[]"
                let status = sqlite3_column_text(validStmt, 3).map { String(cString: $0) } ?? ""
                let notFullyIdle = sqlite3_column_int(validStmt, 4) != 0
                let killed = sqlite3_column_int(validStmt, 5) != 0
                let lastUserInputTime = sqlite3_column_text(validStmt, 6).map { String(cString: $0) } ?? ""
                let lastModifiedTime = sqlite3_column_text(validStmt, 7).map { String(cString: $0) } ?? ""

                guard !convId.isEmpty else { continue }

                records.append(AntigravitySessionRecord(
                    conversationId: convId,
                    title: title,
                    workspaceURIsJSON: workspaceURIs,
                    status: status,
                    notFullyIdle: notFullyIdle,
                    killed: killed,
                    lastUserInputTime: lastUserInputTime,
                    lastModifiedTime: lastModifiedTime
                ))
            } else if stepStatus == SQLITE_DONE {
                break
            } else {
                let errorMsg = String(cString: sqlite3_errmsg(validDb))
                throw AntigravityStoreError.queryStepFailed(code: stepStatus, message: errorMsg)
            }
        }

        return records
    }
}
