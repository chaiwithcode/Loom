//
//  T3CodeDetector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation
import SQLite3

public struct T3ServerRuntime: Codable, Sendable {
    public let pid: pid_t
    public let port: Int?
    public let origin: String?
    public let devUrl: String?
    public let serverVersion: String?
    public let startedAt: String?

    public init(
        pid: pid_t,
        port: Int? = nil,
        origin: String? = nil,
        devUrl: String? = nil,
        serverVersion: String? = nil,
        startedAt: String? = nil
    ) {
        self.pid = pid
        self.port = port
        self.origin = origin
        self.devUrl = devUrl
        self.serverVersion = serverVersion
        self.startedAt = startedAt
    }
}

public struct T3ActiveThreadRecord: Sendable, Equatable {
    public let threadID: String
    public let projectID: String
    public let title: String
    public let provider: String
    public let projectTitle: String?
    public let workspaceRoot: String?
    public let runStatus: String?
    public let pendingRequestsCount: Int
    public let updatedAt: Date?

    public var state: AgentRunState {
        if pendingRequestsCount > 0 {
            return .awaitingApproval
        }
        if let status = runStatus?.lowercased() {
            if ["running", "starting", "preparing"].contains(status) {
                return .working
            }
            if ["needs-attention", "waiting"].contains(status) {
                return .awaitingApproval
            }
        }
        return .idle
    }
}

public final class T3CodeDetector: Sendable {
    public let baseDirectory: URL
    private let urlSession: URLSession
    private let reader: BoundedJSONLReader

    public init(
        baseDirectory: URL? = nil,
        urlSession: URLSession? = nil,
        reader: BoundedJSONLReader = BoundedJSONLReader()
    ) {
        if let baseDirectory = baseDirectory {
            self.baseDirectory = baseDirectory
        } else if let envPath = ProcessInfo.processInfo.environment["T3CODE_HOME"], !envPath.isEmpty {
            self.baseDirectory = URL(fileURLWithPath: envPath)
        } else {
            self.baseDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3")
        }

        self.reader = reader

        if let session = urlSession {
            self.urlSession = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 1.5
            config.timeoutIntervalForResource = 1.5
            config.waitsForConnectivity = false
            self.urlSession = URLSession(configuration: config)
        }
    }

    // MARK: - Server Runtime Resolution

    public func resolveServerRuntime(processTable: [pid_t: MonitoredProcess]? = nil) -> T3ServerRuntime? {
        let candidates = [
            baseDirectory.appendingPathComponent("userdata/server-runtime.json"),
            baseDirectory.appendingPathComponent("dev/userdata/server-runtime.json")
        ]

        let decoder = JSONDecoder()
        for path in candidates {
            guard let data = try? Data(contentsOf: path),
                  let runtime = try? decoder.decode(T3ServerRuntime.self, from: data) else {
                continue
            }

            // CRITICAL: Stale PID Verification
            if let table = processTable {
                guard let proc = table[runtime.pid], proc.pid == runtime.pid else {
                    continue
                }
            } else {
                // Posix probe: kill with signal 0 checks process existence without signaling
                guard kill(runtime.pid, 0) == 0 else {
                    continue
                }
            }

            return runtime
        }
        return nil
    }

    // MARK: - Loopback Environment Probe

    public func probeEnvironment(origin: String) async -> Bool {
        guard let url = URL(string: "\(origin)/.well-known/t3/environment") else { return false }
        do {
            let (_, response) = try await urlSession.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            return false
        }
        return false
    }

    // MARK: - Read-Only SQLite Threads & Runs Inspection

    public func readActiveThreads() -> [T3ActiveThreadRecord] {
        let sqliteURL = baseDirectory.appendingPathComponent("userdata/statev2.sqlite")
        guard FileManager.default.fileExists(atPath: sqliteURL.path) else { return [] }

        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        let uri = "file:\(sqliteURL.path)?mode=ro"
        let status = sqlite3_open_v2(uri, &db, openFlags, nil)
        guard status == SQLITE_OK, let validDB = db else {
            if let db = db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(validDB) }

        sqlite3_busy_timeout(validDB, 250)

        let query = """
        SELECT 
            t.thread_id,
            t.project_id,
            t.title,
            t.default_provider,
            p.title AS project_title,
            p.workspace_root,
            r.status AS run_status,
            (SELECT COUNT(*) FROM orchestration_v2_projection_runtime_requests req WHERE req.thread_id = t.thread_id AND req.status = 'pending') AS pending_requests_count,
            t.updated_at
        FROM orchestration_v2_projection_threads t
        LEFT JOIN projection_projects p ON t.project_id = p.project_id
        LEFT JOIN (
            SELECT thread_id, status FROM orchestration_v2_projection_runs r1
            WHERE ordinal = (SELECT MAX(ordinal) FROM orchestration_v2_projection_runs r2 WHERE r2.thread_id = r1.thread_id)
        ) r ON t.thread_id = r.thread_id
        WHERE t.deleted_at IS NULL AND t.archived_at IS NULL
        ORDER BY t.updated_at DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(validDB, query, -1, &statement, nil) == SQLITE_OK,
              let stmt = statement else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var records: [T3ActiveThreadRecord] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        while sqlite3_step(stmt) == SQLITE_ROW {
            let threadID = String(cString: sqlite3_column_text(stmt, 0))
            let projectID = String(cString: sqlite3_column_text(stmt, 1))
            let title = String(cString: sqlite3_column_text(stmt, 2))
            let provider = String(cString: sqlite3_column_text(stmt, 3))
            let projectTitle = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let workspaceRoot = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            let runStatus = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            let pendingCount = Int(sqlite3_column_int(stmt, 7))
            let updatedAtString = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
            let updatedAt = updatedAtString.flatMap {
                isoFormatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
            }

            records.append(
                T3ActiveThreadRecord(
                    threadID: threadID,
                    projectID: projectID,
                    title: title,
                    provider: provider,
                    projectTitle: projectTitle,
                    workspaceRoot: workspaceRoot,
                    runStatus: runStatus,
                    pendingRequestsCount: pendingCount,
                    updatedAt: updatedAt
                )
            )
        }

        return records
    }

    // MARK: - Child Process Deduplication Helper

    public func collectT3AncestorPIDs(
        table: [pid_t: MonitoredProcess],
        serverPID: pid_t?
    ) -> Set<pid_t> {
        var t3PIDs = Set<pid_t>()
        if let sPID = serverPID, sPID > 1 {
            t3PIDs.insert(sPID)
        }

        for (pid, proc) in table {
            let lowerName = proc.name.lowercased()
            let lowerPath = proc.executablePath.lowercased()
            if lowerName.contains("t3") || lowerName.contains("t3 code") ||
               lowerPath.contains("t3 code") || lowerPath.contains("/t3code") {
                t3PIDs.insert(pid)
            }
        }
        return t3PIDs
    }

    // MARK: - Orchestrator detect() Entrypoint

    public struct DetectionResult: Sendable {
        public let sessions: [AgentSessionStatus]
        /// All root PIDs owned by T3Code (server daemon + macOS wrapper apps) used to deduplicate child CLIs.
        public let rootT3PIDs: Set<pid_t>

        public init(sessions: [AgentSessionStatus], rootT3PIDs: Set<pid_t>) {
            self.sessions = sessions
            self.rootT3PIDs = rootT3PIDs
        }
    }

    public static func resolveT3HomeDirectory() -> URL {
        if let customHome = ProcessInfo.processInfo.environment["T3CODE_HOME"], !customHome.isEmpty {
            return URL(fileURLWithPath: (customHome as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3", isDirectory: true)
    }

    public func findRunningT3AppPIDs(in processTable: [pid_t: MonitoredProcess]) -> Set<pid_t> {
        var pids = Set<pid_t>()
        for (pid, proc) in processTable {
            let lowerName = proc.name.lowercased()
            let lowerPath = proc.executablePath.lowercased()
            if lowerName == "t3code" || lowerName == "t3" || lowerPath.contains("t3 code") || lowerPath.contains("/t3code") {
                pids.insert(pid)
            }
        }
        return pids
    }

    public func detect(processTable: [pid_t: MonitoredProcess]) async -> DetectionResult {
        var rootPIDs = findRunningT3AppPIDs(in: processTable)

        // 1. Check server-runtime.json (prod and dev paths)
        let activeRuntime = resolveServerRuntime(processTable: processTable)
        if let runtime = activeRuntime {
            rootPIDs.insert(runtime.pid)
        }

        // If neither the server PID nor any T3Code process is alive, return empty
        guard !rootPIDs.isEmpty else {
            return DetectionResult(sessions: [], rootT3PIDs: [])
        }

        let primaryPID = activeRuntime?.pid ?? rootPIDs.first

        // 2. Try querying loopback /api/orchestration/shell if runtime origin is valid
        if let runtime = activeRuntime,
           let origin = runtime.origin,
           let shellURL = URL(string: origin)?.appendingPathComponent("api/orchestration/shell"),
           let shellSessions = await fetchOrchestrationSessions(from: shellURL, daemonPID: runtime.pid) {
            if !shellSessions.isEmpty {
                return DetectionResult(sessions: shellSessions, rootT3PIDs: rootPIDs)
            }
        }

        // 2b. Fallback to SQLite statev2 database
        let sqliteThreads = readActiveThreads()
        if !sqliteThreads.isEmpty {
            var sessions: [AgentSessionStatus] = []
            for thread in sqliteThreads {
                let projectName = thread.workspaceRoot.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? thread.projectTitle
                    ?? thread.title
                sessions.append(
                    AgentSessionStatus(
                        id: "t3-\(thread.threadID)",
                        provider: .t3Code,
                        surface: .gui,
                        pid: primaryPID,
                        parentT3PID: nil,
                        projectName: projectName,
                        workspacePath: thread.workspaceRoot,
                        gitBranch: nil,
                        modelName: nil,
                        state: thread.state,
                        tokenUsage: nil,
                        lastUpdated: thread.updatedAt ?? Date()
                    )
                )
            }
            return DetectionResult(sessions: sessions, rootT3PIDs: rootPIDs)
        }

        // 3. Fallback: Parse ~/.t3/userdata/logs/server.trace.ndjson or process CWD
        let fallbackSession = buildFallbackSession(
            primaryPID: primaryPID,
            processTable: processTable
        )
        return DetectionResult(sessions: [fallbackSession], rootT3PIDs: rootPIDs)
    }

    private struct OrchestrationShellResponse: Decodable, Sendable {
        let projects: [T3Project]?
        let threads: [T3Thread]?
    }

    private struct T3Project: Decodable, Sendable {
        let id: String
        let title: String?
        let workspaceRoot: String?
    }

    private struct T3Thread: Decodable, Sendable {
        let id: String
        let projectId: String?
        let title: String?
        let model: String?
        let status: String?
        let runStatus: String?
        let updatedAt: String?
    }

    private struct TraceSpanLine: Decodable, Sendable {
        let timestamp: String?
        let name: String?
        let message: String?
        let threadId: String?
        let model: String?
    }

    private func fetchOrchestrationSessions(from url: URL, daemonPID: pid_t) async -> [AgentSessionStatus]? {
        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let shell = try JSONDecoder().decode(OrchestrationShellResponse.self, from: data)
            let projectsByID = Dictionary(
                uniqueKeysWithValues: (shell.projects ?? []).map { ($0.id, $0) }
            )

            var results: [AgentSessionStatus] = []
            let isoFormatter = ISO8601DateFormatter()

            for thread in shell.threads ?? [] {
                let status = thread.status ?? "active"
                if status == "settled" || status == "snoozed" { continue }

                let project = thread.projectId.flatMap { projectsByID[$0] }
                let workspacePath = project?.workspaceRoot
                let projectName = workspacePath.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? project?.title
                    ?? thread.title
                    ?? "T3Code Workspace"

                let runState: AgentRunState
                switch thread.runStatus {
                case "running":
                    runState = .working
                case "needs-attention":
                    runState = .awaitingApproval
                default:
                    runState = .idle
                }

                let updatedDate = thread.updatedAt.flatMap { isoFormatter.date(from: $0) } ?? Date()

                results.append(
                    AgentSessionStatus(
                        id: "t3-\(thread.id)",
                        provider: .t3Code,
                        surface: .gui,
                        pid: daemonPID,
                        parentT3PID: nil,
                        projectName: projectName,
                        workspacePath: workspacePath,
                        gitBranch: nil,
                        modelName: thread.model,
                        state: runState,
                        tokenUsage: nil,
                        lastUpdated: updatedDate
                    )
                )
            }
            return results
        } catch {
            return nil
        }
    }

    private func buildFallbackSession(
        primaryPID: pid_t?,
        processTable: [pid_t: MonitoredProcess]
    ) -> AgentSessionStatus {
        let traceURL = baseDirectory.appendingPathComponent("userdata/logs/server.trace.ndjson")
        var state: AgentRunState = .idle
        var detectedModel: String?
        var lastUpdated = Date()

        if let snapshot = reader.readSnapshot(at: traceURL) {
            lastUpdated = snapshot.modifiedAt
            let decoder = JSONDecoder()
            if let lastLine = snapshot.tailLines.last,
               let trace = try? decoder.decode(TraceSpanLine.self, from: lastLine) {
                let combined = ((trace.name ?? "") + " " + (trace.message ?? "")).lowercased()
                if combined.contains("waiting for approval") || combined.contains("needs-attention") {
                    state = .awaitingApproval
                } else if combined.contains("starting provider turn") || combined.contains("streaming") {
                    state = .working
                }
                detectedModel = trace.model
            }
        }

        let cwd = primaryPID.flatMap { processTable[$0]?.cwd }
        let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "T3Code"

        return AgentSessionStatus(
            id: "t3-daemon-\(primaryPID ?? 0)",
            provider: .t3Code,
            surface: .gui,
            pid: primaryPID,
            parentT3PID: nil,
            projectName: projectName,
            workspacePath: cwd,
            gitBranch: nil,
            modelName: detectedModel,
            state: state,
            tokenUsage: nil,
            lastUpdated: lastUpdated
        )
    }
}
