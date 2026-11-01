//
//  AntigravityCLIDetector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation
import os
import SQLite3

public struct AntigravityLiveProcess: Sendable, Equatable {
    public let pid: pid_t
    public let ppid: pid_t
    public let name: String
    public let executablePath: String
    public let cwd: String?
    public let parentT3PID: pid_t?
    public let surface: AgentSurface

    public init(
        pid: pid_t,
        ppid: pid_t,
        name: String,
        executablePath: String,
        cwd: String?,
        parentT3PID: pid_t? = nil,
        surface: AgentSurface = .cli
    ) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.executablePath = executablePath
        self.cwd = cwd
        self.parentT3PID = parentT3PID
        self.surface = surface
    }
}

public struct AntigravityCLISessionRecord: Sendable, Equatable {
    public let sessionID: String
    public let pid: pid_t?
    public let parentT3PID: pid_t?
    public let surface: AgentSurface
    public let cwd: String?
    public let title: String?
    public let model: String?
    public let state: AgentRunState
    public let tokenUsage: TokenUsageSnapshot
    public let fileURL: URL
    public let lastModifiedAt: Date

    public init(
        sessionID: String,
        pid: pid_t? = nil,
        parentT3PID: pid_t? = nil,
        surface: AgentSurface = .cli,
        cwd: String? = nil,
        title: String? = nil,
        model: String? = nil,
        state: AgentRunState,
        tokenUsage: TokenUsageSnapshot,
        fileURL: URL,
        lastModifiedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.pid = pid
        self.parentT3PID = parentT3PID
        self.surface = surface
        self.cwd = cwd
        self.title = title
        self.model = model
        self.state = state
        self.tokenUsage = tokenUsage
        self.fileURL = fileURL
        self.lastModifiedAt = lastModifiedAt
    }
}

public final class AntigravityCLIDetector: Sendable {
    private let reader: BoundedJSONLReader
    private let customBaseDirectory: URL?
    public var baseDirectory: URL {
        customBaseDirectory ?? Self.resolveAntigravityCLIDirectory()
    }
    public var jsonlReader: BoundedJSONLReader { reader }

    /// Thread-safe cache mapping Antigravity conversation UUID -> resolved CWD from live `agy` process.
    private let cwdCache = OSAllocatedUnfairLock(initialState: [String: String]())

    public init(
        baseDirectory: URL? = nil,
        reader: BoundedJSONLReader = BoundedJSONLReader(),
        jsonlReader: BoundedJSONLReader? = nil
    ) {
        self.customBaseDirectory = baseDirectory
        self.reader = jsonlReader ?? reader
    }

    public func recordCWD(_ cwd: String, for sessionID: String) {
        cwdCache.withLock { $0[sessionID] = cwd }
    }

    public func cachedCWD(for sessionID: String) -> String? {
        cwdCache.withLock { $0[sessionID] }
    }

    public struct AntigravityStepLine: Decodable, Sendable {
        public let step_index: Int?
        public let type: String?
        public let created_at: String?
        public let model: String?

        public init(step_index: Int? = nil, type: String? = nil, created_at: String? = nil, model: String? = nil) {
            self.step_index = step_index
            self.type = type
            self.created_at = created_at
            self.model = model
        }
    }

    public struct AntigravitySettingsFile: Decodable, Sendable {
        public let model: String?
        public let defaultModel: String?

        public init(model: String? = nil, defaultModel: String? = nil) {
            self.model = model
            self.defaultModel = defaultModel
        }
    }

    // MARK: - Main detect() Entrypoint (NEW_PLANS Section 4)

    public func detect(
        processTable: [pid_t: MonitoredProcess],
        t3RootPIDs: Set<pid_t>
    ) -> [AgentSessionStatus] {
        // 1. Match live `agy` or `antigravity` CLI processes (excluding GUI .app bundles)
        let liveAgyProcs = processTable.values.filter { proc in
            let lowerName = proc.name.lowercased()
            let lowerPath = proc.executablePath.lowercased()
            guard !lowerPath.contains(".app/contents/") else { return false }
            return lowerName == "agy"
                || lowerName == "antigravity"
                || lowerPath.hasSuffix("/agy")
                || lowerPath.contains("antigravity-cli")
        }

        let configuredModel = readConfiguredModel()
        let recentTranscripts = findRecentBrainTranscripts(maxConversations: 8)

        var results: [AgentSessionStatus] = []
        var matchedUUIDs = Set<String>()

        // 2. Pair running `agy` processes with the most recently modified transcript
        for (index, proc) in liveAgyProcs.enumerated() {
            let parentT3 = ProcessTreeScanner.findAncestor(of: proc.pid, in: processTable, matching: t3RootPIDs)
            let surface: AgentSurface = parentT3 != nil ? .t3Orchestrated : .cli

            let transcriptEntry = index < recentTranscripts.count ? recentTranscripts[index] : nil
            let uuid = transcriptEntry?.uuid ?? "agy-pid-\(proc.pid)"

            if let entry = transcriptEntry {
                matchedUUIDs.insert(entry.uuid)
                if let liveCWD = proc.cwd {
                    cwdCache.withLock { $0[entry.uuid] = liveCWD }
                }
            }

            let resolvedCWD = proc.cwd ?? cwdCache.withLock { $0[uuid] }
            let projectName = resolvedCWD.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "agy"

            var state: AgentRunState = .idle
            var lastUpdated = Date()
            var detectedModel = configuredModel

            if let entry = transcriptEntry, let snapshot = reader.readSnapshot(at: entry.url) {
                lastUpdated = snapshot.modifiedAt
                let parsedStep = parseTailStep(from: snapshot)
                if let stepModel = parsedStep?.model {
                    detectedModel = stepModel
                }
                state = inferState(
                    proc: proc,
                    processTable: processTable,
                    snapshot: snapshot,
                    lastStepType: parsedStep?.type
                )
            }

            results.append(
                AgentSessionStatus(
                    id: uuid,
                    provider: .antigravity,
                    surface: surface,
                    pid: proc.pid,
                    parentT3PID: parentT3,
                    projectName: projectName,
                    workspacePath: resolvedCWD,
                    gitBranch: nil,
                    modelName: detectedModel,
                    state: state,
                    tokenUsage: nil,
                    lastUpdated: lastUpdated
                )
            )
        }

        // 3. Surface recent inactive CLI brain sessions from today if cached CWD exists
        for entry in recentTranscripts where !matchedUUIDs.contains(entry.uuid) {
            guard Calendar.current.isDateInToday(entry.mtime) else { continue }
            let cachedCWD = cwdCache.withLock { $0[entry.uuid] }
            let projectName = cachedCWD.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "agy-session"

            results.append(
                AgentSessionStatus(
                    id: entry.uuid,
                    provider: .antigravity,
                    surface: .cli,
                    pid: nil,
                    parentT3PID: nil,
                    projectName: projectName,
                    workspacePath: cachedCWD,
                    gitBranch: nil,
                    modelName: configuredModel,
                    state: .inactive,
                    tokenUsage: nil,
                    lastUpdated: entry.mtime
                )
            )
        }

        return results
    }

    // MARK: - Helpers

    public static func resolveAntigravityCLIDirectory() -> URL {
        if let customHome = ProcessInfo.processInfo.environment["ANTIGRAVITY_HOME"], !customHome.isEmpty {
            return URL(fileURLWithPath: (customHome as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)
    }

    public func readConfiguredModel() -> String? {
        let settingsURL = baseDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AntigravitySettingsFile.self, from: data) else {
            return "gemini-3.8-flash"
        }
        return settings.model ?? settings.defaultModel ?? "gemini-3.8-flash"
    }

    public func findRecentBrainTranscripts(maxConversations: Int = 8) -> [(uuid: String, url: URL, mtime: Date)] {
        let brainRoot = baseDirectory.appendingPathComponent("brain", isDirectory: true)
        let fm = FileManager.default
        guard let convDirs = try? fm.contentsOfDirectory(
            at: brainRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var transcripts: [(uuid: String, url: URL, mtime: Date)] = []

        for dir in convDirs {
            let uuid = dir.lastPathComponent
            let transcriptURL = dir.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard fm.fileExists(atPath: transcriptURL.path),
                  let mtime = try? transcriptURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                continue
            }
            transcripts.append((uuid, transcriptURL, mtime))
        }

        transcripts.sort { $0.mtime > $1.mtime }
        return Array(transcripts.prefix(maxConversations))
    }

    public func parseTailStep(from snapshot: JSONLSnapshot) -> AntigravityStepLine? {
        let decoder = JSONDecoder()
        for line in snapshot.tailLines.reversed() {
            if let step = try? decoder.decode(AntigravityStepLine.self, from: line) {
                return step
            }
        }
        return nil
    }

    public func inferState(
        proc: MonitoredProcess,
        processTable: [pid_t: MonitoredProcess],
        snapshot: JSONLSnapshot,
        lastStepType: String?
    ) -> AgentRunState {
        let hasActiveChild = processTable.values.contains { $0.ppid == proc.pid }
        if hasActiveChild {
            return .working
        }

        let age = Date().timeIntervalSince(snapshot.modifiedAt)
        if age < 4.0 {
            return .working
        }

        switch lastStepType {
        case "USER_INPUT", "RUN_COMMAND", "VIEW_FILE", "GREP_SEARCH", "LIST_DIRECTORY", "CODE_ACTION":
            return age < 15.0 ? .working : .awaitingApproval
        default:
            return .idle
        }
    }

    // MARK: - Compatibility Methods (for Existing Tests)

    public func findLiveAntigravityProcesses(
        table: [pid_t: MonitoredProcess],
        t3AncestorPIDs: Set<pid_t> = []
    ) -> [AntigravityLiveProcess] {
        var processes: [AntigravityLiveProcess] = []

        for (pid, proc) in table {
            guard pid > 1 else { continue }
            let lowerName = proc.name.lowercased()
            let lowerPath = proc.executablePath.lowercased()

            let isAgy = lowerName == "agy" ||
                lowerPath.hasSuffix("/agy") ||
                lowerName.hasPrefix("agy_") ||
                lowerPath.contains("/antigravity-cli/")

            guard isAgy else { continue }

            let parentT3 = ProcessTreeScanner.findAncestor(of: pid, in: table, matching: t3AncestorPIDs)
            let surface: AgentSurface = parentT3 != nil ? .t3Orchestrated : .cli
            let cwd = proc.cwd ?? ProcessTreeScanner.resolveCWD(for: pid)

            processes.append(
                AntigravityLiveProcess(
                    pid: pid,
                    ppid: proc.ppid,
                    name: proc.name,
                    executablePath: proc.executablePath,
                    cwd: cwd,
                    parentT3PID: parentT3,
                    surface: surface
                )
            )
        }

        return processes
    }

    public func findRecentTranscriptURLs() -> [URL] {
        let brainDir = baseDirectory.appendingPathComponent("brain")
        guard FileManager.default.fileExists(atPath: brainDir.path) else { return [] }

        let fileManager = FileManager.default
        guard let subdirs = try? fileManager.contentsOfDirectory(
            at: brainDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidateURLs: [URL] = []
        for dir in subdirs {
            let transcriptURL = dir
                .appendingPathComponent(".system_generated")
                .appendingPathComponent("logs")
                .appendingPathComponent("transcript.jsonl")

            if fileManager.fileExists(atPath: transcriptURL.path) {
                candidateURLs.append(transcriptURL)
            }
        }

        // Sort descending by modification date
        return candidateURLs.sorted { u1, u2 in
            let date1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let date2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return date1 > date2
        }
    }

    public func detectSessions(
        table: [pid_t: MonitoredProcess],
        t3AncestorPIDs: Set<pid_t> = [],
        now: Date = Date()
    ) -> [AntigravityCLISessionRecord] {
        let liveProcesses = findLiveAntigravityProcesses(table: table, t3AncestorPIDs: t3AncestorPIDs)
        let transcriptURLs = findRecentTranscriptURLs()

        // Read conversation_summaries.db if present to seed CWD and titles
        let dbSummaries = readConversationSummaries()

        var sessions: [AntigravityCLISessionRecord] = []
        var claimedPIDs = Set<pid_t>()

        for url in transcriptURLs {
            guard let snapshot = reader.readSnapshot(at: url) else { continue }
            let parsed = JSONLProviderParsers.parseAntigravity(snapshot: snapshot)

            // The conversation UUID is 3 path components up from transcript.jsonl
            // (.../brain/<UUID>/.system_generated/logs/transcript.jsonl)
            let sessionID = url
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .lastPathComponent

            let summary = dbSummaries[sessionID]

            // Resolve CWD: check memory cache -> check DB summary -> check single live proc
            var resolvedCWD = cwdCache.withLock { $0[sessionID] } ?? summary?.cwd
            if resolvedCWD == nil, liveProcesses.count == 1, let singleCWD = liveProcesses.first?.cwd {
                resolvedCWD = singleCWD
                cwdCache.withLock { $0[sessionID] = singleCWD }
            }

            // Correlate with running process via resolved CWD
            let matchingProcess = liveProcesses.first { proc in
                !claimedPIDs.contains(proc.pid) &&
                proc.cwd != nil &&
                proc.cwd == resolvedCWD
            }

            let pid: pid_t?
            let parentT3: pid_t?
            let surface: AgentSurface
            let state: AgentRunState

            if let proc = matchingProcess {
                claimedPIDs.insert(proc.pid)
                pid = proc.pid
                parentT3 = proc.parentT3PID
                surface = proc.surface

                if let procCWD = proc.cwd {
                    resolvedCWD = procCWD
                    cwdCache.withLock { $0[sessionID] = procCWD }
                }

                // Determine state
                if parsed.lastStepType == "USER_INPUT" {
                    state = .working
                } else if parsed.lastStepType == "PLANNER_RESPONSE" {
                    if parsed.lastToolNames.contains("ask_question") {
                        state = .awaitingApproval
                    } else if parsed.lastStepStatus == "DONE" && parsed.lastToolNames.isEmpty {
                        let stepDate = parsed.lastCreatedAt ?? snapshot.modifiedAt
                        if now.timeIntervalSince(stepDate) > 2.0 {
                            state = .idle
                        } else {
                            state = .working
                        }
                    } else {
                        state = .working
                    }
                } else if parsed.lastStepType != nil && parsed.lastStepType != "USER_SETTINGS_CHANGE" {
                    state = .working
                } else {
                    state = .idle
                }
            } else {
                pid = nil
                parentT3 = nil
                surface = .cli
                state = .inactive
            }

            sessions.append(
                AntigravityCLISessionRecord(
                    sessionID: sessionID,
                    pid: pid,
                    parentT3PID: parentT3,
                    surface: surface,
                    cwd: resolvedCWD,
                    title: summary?.title,
                    model: parsed.model,
                    state: state,
                    tokenUsage: parsed.tokenUsage,
                    fileURL: url,
                    lastModifiedAt: snapshot.modifiedAt
                )
            )
        }

        return sessions
    }

    public func calculateDailyTokenUsage(
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> TokenUsageSnapshot {
        let transcriptURLs = findRecentTranscriptURLs()
        var totalInput = 0
        var totalCached = 0
        var totalOutput = 0

        for url in transcriptURLs {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  calendar.isDate(modDate, inSameDayAs: now) else {
                continue
            }

            guard let snapshot = reader.readSnapshot(at: url) else { continue }
            let parsed = JSONLProviderParsers.parseAntigravity(snapshot: snapshot)

            totalInput += parsed.tokenUsage.inputTokens
            totalCached += parsed.tokenUsage.cachedInputTokens
            totalOutput += parsed.tokenUsage.outputTokens
        }

        return TokenUsageSnapshot(
            inputTokens: totalInput,
            cachedInputTokens: totalCached,
            outputTokens: totalOutput,
            reasoningTokens: 0
        )
    }

    private struct ConversationSummaryEntry {
        let title: String
        let cwd: String?
    }

    private func readConversationSummaries() -> [String: ConversationSummaryEntry] {
        let dbURL = baseDirectory.appendingPathComponent("conversation_summaries.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return [:] }

        var db: OpaquePointer?
        let uri = "file://\(dbURL.standardizedFileURL.path)?mode=ro&immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI

        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let validDB = db else {
            if let db = db { sqlite3_close(db) }
            return [:]
        }
        defer { sqlite3_close(validDB) }

        let query = "SELECT conversation_id, title, workspace_uris FROM conversation_summaries"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(validDB, query, -1, &stmt, nil) == SQLITE_OK, let validStmt = stmt else {
            return [:]
        }
        defer { sqlite3_finalize(validStmt) }

        var results: [String: ConversationSummaryEntry] = [:]

        while sqlite3_step(validStmt) == SQLITE_ROW {
            guard let idCol = sqlite3_column_text(validStmt, 0) else { continue }
            let id = String(cString: idCol)
            let title = sqlite3_column_text(validStmt, 1).map { String(cString: $0) } ?? ""
            let urisJSON = sqlite3_column_text(validStmt, 2).map { String(cString: $0) } ?? ""

            var parsedCWD: String? = nil
            if let data = urisJSON.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
               let firstURI = arr.first,
               let url = URL(string: firstURI),
               url.scheme == "file" {
                parsedCWD = url.path
            }

            results[id] = ConversationSummaryEntry(title: title, cwd: parsedCWD)
        }

        return results
    }
}
