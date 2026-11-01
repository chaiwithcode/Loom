//
//  CodexCLIDetector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation

public struct CodexLiveProcess: Sendable, Equatable {
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

public struct CodexCLISessionRecord: Sendable, Equatable {
    public let sessionID: String
    public let pid: pid_t?
    public let parentT3PID: pid_t?
    public let surface: AgentSurface
    public let cwd: String?
    public let model: String?
    public let approvalMode: String?
    public let state: AgentRunState
    public let tokenUsage: TokenUsageSnapshot?
    public let fileURL: URL
    public let lastModifiedAt: Date

    public init(
        sessionID: String,
        pid: pid_t? = nil,
        parentT3PID: pid_t? = nil,
        surface: AgentSurface = .cli,
        cwd: String? = nil,
        model: String? = nil,
        approvalMode: String? = nil,
        state: AgentRunState,
        tokenUsage: TokenUsageSnapshot? = nil,
        fileURL: URL,
        lastModifiedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.pid = pid
        self.parentT3PID = parentT3PID
        self.surface = surface
        self.cwd = cwd
        self.model = model
        self.approvalMode = approvalMode
        self.state = state
        self.tokenUsage = tokenUsage
        self.fileURL = fileURL
        self.lastModifiedAt = lastModifiedAt
    }
}

public final class CodexCLIDetector: Sendable {
    private let reader: BoundedJSONLReader
    private let customBaseDirectory: URL?
    public var baseDirectory: URL {
        customBaseDirectory ?? Self.resolveCodexHomeDirectory()
    }
    public var jsonlReader: BoundedJSONLReader { reader }

    public init(
        baseDirectory: URL? = nil,
        reader: BoundedJSONLReader = BoundedJSONLReader()
    ) {
        self.customBaseDirectory = baseDirectory
        self.reader = reader
    }

    public convenience init(reader: BoundedJSONLReader) {
        self.init(baseDirectory: nil, reader: reader)
    }

    public convenience init(baseDirectory: URL?, jsonlReader: BoundedJSONLReader) {
        self.init(baseDirectory: baseDirectory, reader: jsonlReader)
    }

    // MARK: - Main detect() Entrypoint (NEW_PLANS Section 2)

    public func detect(
        processTable: [pid_t: MonitoredProcess],
        t3RootPIDs: Set<pid_t>
    ) -> [AgentSessionStatus] {
        // 1. Identify running `codex` CLI processes
        let liveCodexProcs = processTable.values.filter { proc in
            let lowerName = proc.name.lowercased()
            let lowerPath = proc.executablePath.lowercased()
            return lowerName == "codex"
                || lowerPath.hasSuffix("/codex")
                || lowerPath.contains("@openai/codex")
        }

        // 2. Scan recent rollout-*.jsonl files from ~/.codex/sessions/YYYY/MM/DD/
        let recentRolloutFiles = findRecentRolloutFiles(maxFiles: 12)
        var parsedRollouts: [(url: URL, snapshot: JSONLSnapshot, parsed: JSONLProviderParsers.CodexParsedTranscript)] = []

        for fileURL in recentRolloutFiles {
            guard let snapshot = reader.readSnapshot(at: fileURL) else { continue }
            let parsed = JSONLProviderParsers.parseCodex(snapshot: snapshot)
            parsedRollouts.append((fileURL, snapshot, parsed))
        }

        var matchedRolloutURLs = Set<URL>()
        var results: [AgentSessionStatus] = []

        // 3. Match live processes to their active rollout transcript by CWD
        for proc in liveCodexProcs {
            let parentT3 = ProcessTreeScanner.findAncestor(of: proc.pid, in: processTable, matching: t3RootPIDs)
            let surface: AgentSurface = parentT3 != nil ? .t3Orchestrated : .cli

            let matchingRollout = parsedRollouts.first { candidate in
                guard !matchedRolloutURLs.contains(candidate.url) else { return false }
                guard let procCWD = proc.cwd, let fileCWD = candidate.parsed.cwd else { return false }
                return Self.normalizePath(procCWD) == Self.normalizePath(fileCWD)
            }

            if let match = matchingRollout {
                matchedRolloutURLs.insert(match.url)
            }

            let resolvedCWD = proc.cwd ?? matchingRollout?.parsed.cwd
            let projectName = resolvedCWD.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "codex"
            let hasActiveChild = processTable.values.contains { $0.ppid == proc.pid }

            let state = inferState(
                proc: proc,
                hasActiveChild: hasActiveChild,
                snapshot: matchingRollout?.snapshot,
                parsed: matchingRollout?.parsed
            )

            let sessionID = matchingRollout?.parsed.sessionID ?? "codex-pid-\(proc.pid)"

            results.append(
                AgentSessionStatus(
                    id: sessionID,
                    provider: .codex,
                    surface: surface,
                    pid: proc.pid,
                    parentT3PID: parentT3,
                    projectName: projectName,
                    workspacePath: resolvedCWD,
                    gitBranch: nil,
                    modelName: matchingRollout?.parsed.model,
                    state: state,
                    tokenUsage: matchingRollout?.parsed.latestTokenUsage,
                    lastUpdated: matchingRollout?.snapshot.modifiedAt ?? Date()
                )
            )
        }

        // 4. Include recent inactive sessions from today (so daily token totals remain visible after exit)
        for item in parsedRollouts where !matchedRolloutURLs.contains(item.url) {
            guard Calendar.current.isDateInToday(item.snapshot.modifiedAt) else { continue }
            let cwd = item.parsed.cwd
            let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "codex"
            let sessionID = item.parsed.sessionID ?? item.url.deletingPathExtension().lastPathComponent

            results.append(
                AgentSessionStatus(
                    id: sessionID,
                    provider: .codex,
                    surface: .cli,
                    pid: nil,
                    parentT3PID: nil,
                    projectName: projectName,
                    workspacePath: cwd,
                    gitBranch: nil,
                    modelName: item.parsed.model,
                    state: .inactive,
                    tokenUsage: item.parsed.latestTokenUsage,
                    lastUpdated: item.snapshot.modifiedAt
                )
            )
        }

        return results
    }

    // MARK: - Helpers

    public static func resolveCodexHomeDirectory() -> URL {
        if let customHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !customHome.isEmpty {
            return URL(fileURLWithPath: (customHome as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    public func findRecentRolloutFiles(maxFiles: Int = 12) -> [URL] {
        let sessionsRoot = baseDirectory.appendingPathComponent("sessions", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsRoot.path) else { return [] }

        let cal = Calendar.current
        let now = Date()
        let candidateDates = [now, cal.date(byAdding: .day, value: -1, to: now)].compactMap { $0 }

        var filesWithDates: [(url: URL, mtime: Date)] = []

        for date in candidateDates {
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            guard let y = comps.year, let m = comps.month, let d = comps.day else { continue }
            let dayPath = String(format: "%04d/%02d/%02d", y, m, d)
            let dayDir = sessionsRoot.appendingPathComponent(dayPath, isDirectory: true)

            guard let items = try? fm.contentsOfDirectory(
                at: dayDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in items where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                filesWithDates.append((url, mtime))
            }
        }

        filesWithDates.sort { $0.mtime > $1.mtime }
        return Array(filesWithDates.prefix(maxFiles).map(\.url))
    }

    public func inferState(
        proc: MonitoredProcess,
        hasActiveChild: Bool,
        snapshot: JSONLSnapshot?,
        parsed: JSONLProviderParsers.CodexParsedTranscript?
    ) -> AgentRunState {
        if hasActiveChild {
            return .working
        }
        if let snapshot = snapshot {
            let age = Date().timeIntervalSince(snapshot.modifiedAt)
            if age < 4.0 {
                return .working
            }
            if parsed?.approvalMode == "suggest" && age >= 4.0 && age < 300.0 && parsed?.lastEventType == "event_msg" {
                return .awaitingApproval
            }
        }
        return .idle
    }

    private static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    // MARK: - Compatibility Methods (for Existing Tests)

    public func findLiveCodexProcesses(
        table: [pid_t: MonitoredProcess],
        t3AncestorPIDs: Set<pid_t> = []
    ) -> [CodexLiveProcess] {
        var processes: [CodexLiveProcess] = []

        for (pid, proc) in table {
            guard pid > 1 else { continue }
            let lowerName = proc.name.lowercased()
            let lowerPath = proc.executablePath.lowercased()

            let isCodex = lowerName == "codex" ||
                lowerPath.hasSuffix("/codex") ||
                lowerPath.contains("/.codex/") ||
                lowerPath.contains("@openai/codex")

            guard isCodex else { continue }

            let parentT3 = ProcessTreeScanner.findAncestor(of: pid, in: table, matching: t3AncestorPIDs)
            let surface: AgentSurface = parentT3 != nil ? .t3Orchestrated : .cli
            let cwd = proc.cwd ?? ProcessTreeScanner.resolveCWD(for: pid)

            processes.append(
                CodexLiveProcess(
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

    public func findRecentRolloutFileURLs(
        calendar: Calendar = Calendar.current,
        now: Date = Date(),
        daysBack: Int = 1
    ) -> [URL] {
        let sessionsDir = baseDirectory.appendingPathComponent("sessions")
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else { return [] }

        var rolloutURLs: [URL] = []
        let fileManager = FileManager.default

        for dayOffset in 0...daysBack {
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let year = String(format: "%04d", calendar.component(.year, from: targetDate))
            let month = String(format: "%02d", calendar.component(.month, from: targetDate))
            let day = String(format: "%02d", calendar.component(.day, from: targetDate))

            let dayDir = sessionsDir
                .appendingPathComponent(year)
                .appendingPathComponent(month)
                .appendingPathComponent(day)

            guard let enumerator = fileManager.enumerator(
                at: dayDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.hasPrefix("rollout-") && fileURL.pathExtension == "jsonl" {
                    rolloutURLs.append(fileURL)
                }
            }
        }

        // Sort by modification date descending
        return rolloutURLs.sorted { u1, u2 in
            let date1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let date2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return date1 > date2
        }
    }

    public func detectSessions(
        table: [pid_t: MonitoredProcess],
        t3AncestorPIDs: Set<pid_t> = []
    ) -> [CodexCLISessionRecord] {
        let liveProcesses = findLiveCodexProcesses(table: table, t3AncestorPIDs: t3AncestorPIDs)
        let rolloutURLs = findRecentRolloutFileURLs()

        var sessions: [CodexCLISessionRecord] = []
        var claimedPIDs = Set<pid_t>()

        for url in rolloutURLs {
            guard let snapshot = reader.readSnapshot(at: url) else { continue }
            let parsed = JSONLProviderParsers.parseCodex(snapshot: snapshot)

            let sessionID = parsed.sessionID ?? url.deletingPathExtension().lastPathComponent

            // Try to correlate with a live process by matching CWD
            let matchingProcess = liveProcesses.first { proc in
                !claimedPIDs.contains(proc.pid) &&
                proc.cwd != nil &&
                proc.cwd == parsed.cwd
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

                // Check runtime state from latest events
                if parsed.approvalMode == "suggest" && parsed.lastEventType == "turn_context" {
                    state = .awaitingApproval
                } else if parsed.lastEventType == "event_msg" {
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
                CodexCLISessionRecord(
                    sessionID: sessionID,
                    pid: pid,
                    parentT3PID: parentT3,
                    surface: surface,
                    cwd: parsed.cwd,
                    model: parsed.model,
                    approvalMode: parsed.approvalMode,
                    state: state,
                    tokenUsage: parsed.latestTokenUsage,
                    fileURL: url,
                    lastModifiedAt: snapshot.modifiedAt
                )
            )
        }

        // Add any remaining live codex processes without an existing rollout file
        for proc in liveProcesses where !claimedPIDs.contains(proc.pid) {
            let sessionID = "pid-\(proc.pid)"
            sessions.append(
                CodexCLISessionRecord(
                    sessionID: sessionID,
                    pid: proc.pid,
                    parentT3PID: proc.parentT3PID,
                    surface: proc.surface,
                    cwd: proc.cwd,
                    model: nil,
                    approvalMode: nil,
                    state: .working,
                    tokenUsage: nil,
                    fileURL: URL(fileURLWithPath: proc.executablePath),
                    lastModifiedAt: Date()
                )
            )
        }

        return sessions
    }

    public func computeDailyTokenUsage(
        calendar: Calendar = Calendar.current,
        now: Date = Date()
    ) -> TokenUsageSnapshot {
        let todayRollouts = findRecentRolloutFileURLs(calendar: calendar, now: now, daysBack: 0)

        var totalInput = 0
        var totalCached = 0
        var totalOutput = 0
        var totalReasoning = 0

        for url in todayRollouts {
            guard let snapshot = reader.readSnapshot(at: url) else { continue }
            let parsed = JSONLProviderParsers.parseCodex(snapshot: snapshot)

            if let usage = parsed.latestTokenUsage {
                totalInput += usage.inputTokens
                totalCached += usage.cachedInputTokens
                totalOutput += usage.outputTokens
                totalReasoning += usage.reasoningTokens
            }
        }

        return TokenUsageSnapshot(
            inputTokens: totalInput,
            cachedInputTokens: totalCached,
            outputTokens: totalOutput,
            reasoningTokens: totalReasoning
        )
    }

    public func calculateDailyTokenUsage(
        calendar: Calendar = Calendar.current,
        now: Date = Date()
    ) -> TokenUsageSnapshot {
        computeDailyTokenUsage(calendar: calendar, now: now)
    }
}
