import Foundation
import SQLite3

public final class DefaultAntigravityStoreInspector: AntigravityStoreInspecting, Sendable {
    private let databaseURL: URL

    public init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/conversation_summaries.db")
    ) {
        self.databaseURL = databaseURL
    }

    public func fetchActiveSessions() async throws -> [AntigravitySessionRecord] {
        return await Task.detached { [databaseURL] in
            let path = databaseURL.path
            guard FileManager.default.fileExists(atPath: path) else {
                return []
            }

            var db: OpaquePointer?
            let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
            guard sqlite3_open_v2(path, &db, openFlags, nil) == SQLITE_OK, let db = db else {
                if let db = db { sqlite3_close(db) }
                return []
            }

            defer {
                sqlite3_close(db)
            }

            // Set a busy timeout of 250ms to tolerate concurrent WAL writes from Antigravity
            sqlite3_busy_timeout(db, 250)

            let query = """
            SELECT conversation_id, title, workspace_uris, status, not_fully_idle, killed, last_user_input_time, last_modified_time
            FROM conversation_summaries
            WHERE killed = 0 AND (status = 'CASCADE_RUN_STATUS_RUNNING' OR not_fully_idle = 1)
            ORDER BY last_modified_time DESC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
                return []
            }

            defer {
                sqlite3_finalize(stmt)
            }

            var records: [AntigravitySessionRecord] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                let convId = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let workspaceURIs = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "[]"
                let status = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                let notFullyIdle = sqlite3_column_int(stmt, 4) != 0
                let killed = sqlite3_column_int(stmt, 5) != 0
                let lastUserInputTime = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
                let lastModifiedTime = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""

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
            }

            return records
        }.value
    }
}
