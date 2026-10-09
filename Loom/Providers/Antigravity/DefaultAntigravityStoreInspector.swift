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

            var db: OpaquePointer?
            let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
            let uri = standardizedURL.absoluteString
            let openStatus = sqlite3_open_v2(uri, &db, openFlags, nil)
            guard openStatus == SQLITE_OK, let validDb = db else {
                let errorMsg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error"
                if let db = db { sqlite3_close(db) }
                throw AntigravityStoreError.databaseOpenFailed(code: openStatus, message: errorMsg)
            }

            defer {
                sqlite3_close(validDb)
            }

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
        }.value
    }
}
