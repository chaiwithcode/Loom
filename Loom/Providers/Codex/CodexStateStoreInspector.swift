//
//  CodexStateStoreInspector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
import SQLite3

public struct CodexSessionMetadata: Sendable, Equatable {
    public let sessionID: String
    public let projectName: String?
    public let workingDirectory: URL?
    public let gitBranch: String?
    public let title: String?

    public init(
        sessionID: String,
        projectName: String? = nil,
        workingDirectory: URL? = nil,
        gitBranch: String? = nil,
        title: String? = nil
    ) {
        self.sessionID = sessionID
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.title = title
    }
}

public struct CodexProjectRootRecord: Sendable, Equatable {
    public let projectID: String
    public let projectName: String
    public let path: String

    public init(projectID: String, projectName: String, path: String) {
        self.projectID = projectID
        self.projectName = projectName
        self.path = path
    }
}

public protocol CodexStateStoreInspecting: Sendable {
    func loadProjectRoots() async -> [CodexProjectRootRecord]
    func projectName(forPath url: URL) async -> String?
    func sessionMetadata(for sessionID: String) async -> CodexSessionMetadata?
}

public final class DefaultCodexStateStoreInspector: CodexStateStoreInspecting, Sendable {
    private let explicitDatabaseURL: URL?
    private let stateDirectoryURL: URL

    public init(
        databaseURL: URL? = nil,
        stateDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    ) {
        self.explicitDatabaseURL = databaseURL
        self.stateDirectoryURL = stateDirectoryURL
    }

    /// Resolves the most recent state SQLite database (e.g. state_5.sqlite).
    public func resolveDatabaseURL() -> URL? {
        if let explicit = explicitDatabaseURL {
            return explicit
        }

        let fileManager = FileManager.default
        let dirPath = stateDirectoryURL.path
        guard fileManager.fileExists(atPath: dirPath) else {
            return nil
        }

        // Look for state_*.sqlite files and pick the highest numbered version
        guard let items = try? fileManager.contentsOfDirectory(atPath: dirPath) else {
            return nil
        }

        let candidates = items.compactMap { filename -> (name: String, version: Int)? in
            guard filename.hasPrefix("state_") && filename.hasSuffix(".sqlite") else { return nil }
            let middle = filename.dropFirst("state_".count).dropLast(".sqlite".count)
            guard let ver = Int(middle) else { return nil }
            return (filename, ver)
        }.sorted { $0.version > $1.version }

        if let best = candidates.first {
            return stateDirectoryURL.appendingPathComponent(best.name)
        }

        let defaultState5 = stateDirectoryURL.appendingPathComponent("state_5.sqlite")
        if fileManager.fileExists(atPath: defaultState5.path) {
            return defaultState5
        }

        return nil
    }

    public func loadProjectRoots() async -> [CodexProjectRootRecord] {
        guard let dbURL = resolveDatabaseURL() else { return [] }

        return await Task.detached { [dbURL] in
            guard let db = Self.openDatabase(at: dbURL) else { return [] }
            defer { sqlite3_close(db) }

            let query = """
            SELECT p.id, p.name, r.path
            FROM project_roots r
            LEFT JOIN projects p ON r.project_id = p.id
            LIMIT 1024;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
                return []
            }
            defer { sqlite3_finalize(stmt) }

            var records: [CodexProjectRootRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let projectID = Self.extractString(from: stmt, column: 0) ?? ""
                let projectName = Self.extractString(from: stmt, column: 1) ?? ""
                guard let rawPath = Self.extractString(from: stmt, column: 2), !rawPath.isEmpty else {
                    continue
                }

                let standardizedPath = URL(fileURLWithPath: rawPath).standardizedFileURL.path
                records.append(CodexProjectRootRecord(
                    projectID: projectID,
                    projectName: projectName,
                    path: standardizedPath
                ))
            }

            return records
        }.value
    }

    public func projectName(forPath url: URL) async -> String? {
        let roots = await loadProjectRoots()
        guard !roots.isEmpty else { return nil }

        let normalizedPath = url.standardizedFileURL.path
        let matches = roots.filter { record in
            normalizedPath == record.path || normalizedPath.hasPrefix(record.path == "/" ? "/" : record.path + "/")
        }

        guard let maxLen = matches.map(\.path.count).max() else { return nil }
        let closest = matches.filter { $0.path.count == maxLen }
        return closest.first?.projectName.isEmpty == false ? closest.first?.projectName : nil
    }

    public func sessionMetadata(for sessionID: String) async -> CodexSessionMetadata? {
        guard !sessionID.isEmpty, let dbURL = resolveDatabaseURL() else { return nil }

        return await Task.detached { [dbURL, sessionID] in
            guard let db = Self.openDatabase(at: dbURL) else { return nil }
            defer { sqlite3_close(db) }

            let query = """
            SELECT t.id, t.cwd, t.title, t.git_branch, p.name
            FROM threads t
            LEFT JOIN projects p ON t.project_id = p.id
            WHERE t.id = ?1
            LIMIT 1;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
                return nil
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (sessionID as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = Self.extractString(from: stmt, column: 0) ?? sessionID
                let rawCWD = Self.extractString(from: stmt, column: 1)
                let title = Self.extractString(from: stmt, column: 2)
                let branch = Self.extractString(from: stmt, column: 3)
                let projectName = Self.extractString(from: stmt, column: 4)

                let cwdURL = rawCWD.flatMap { path -> URL? in
                    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return URL(fileURLWithPath: trimmed).standardizedFileURL
                }

                return CodexSessionMetadata(
                    sessionID: id,
                    projectName: projectName,
                    workingDirectory: cwdURL,
                    gitBranch: branch,
                    title: title
                )
            }

            return nil
        }.value
    }

    private static func openDatabase(at url: URL) -> OpaquePointer? {
        let uriPath = "\(url.standardizedFileURL.path)?mode=ro&immutable=1"
        var db: OpaquePointer?

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        if sqlite3_open_v2(uriPath, &db, flags, nil) == SQLITE_OK, let validDB = db {
            sqlite3_busy_timeout(validDB, 100)
            return validDB
        }

        if let db = db {
            sqlite3_close(db)
        }

        // Fallback without URI params
        var fallbackDB: OpaquePointer?
        if sqlite3_open_v2(url.standardizedFileURL.path, &fallbackDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
           let validFallback = fallbackDB {
            sqlite3_busy_timeout(validFallback, 100)
            return validFallback
        }

        if let fallbackDB = fallbackDB {
            sqlite3_close(fallbackDB)
        }

        return nil
    }

    private static func extractString(from stmt: OpaquePointer, column: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
