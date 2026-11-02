//
//  ClaudeCodeDetector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation

public struct ClaudeLiveProcess: Sendable, Equatable {
    public let pid: pid_t
    public let ppid: pid_t
    public let name: String
    public let executablePath: String
    public let cwd: String?
    public let parentT3PID: pid_t?
    public let surface: AgentSurface
    public let childPIDs: [pid_t]

    public init(
        pid: pid_t,
        ppid: pid_t,
        name: String,
        executablePath: String,
        cwd: String?,
        parentT3PID: pid_t? = nil,
        surface: AgentSurface = .cli,
        childPIDs: [pid_t] = []
    ) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.executablePath = executablePath
        self.cwd = cwd
        self.parentT3PID = parentT3PID
        self.surface = surface
        self.childPIDs = childPIDs
    }
}

public struct ClaudeCLISessionRecord: Sendable, Equatable {
    public let sessionID: String
    public let pid: pid_t?
    public let parentT3PID: pid_t?
    public let surface: AgentSurface
    public let cwd: String?
    public let gitBranch: String?
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
        gitBranch: String? = nil,
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
        self.gitBranch = gitBranch
        self.model = model
        self.state = state
        self.tokenUsage = tokenUsage
        self.fileURL = fileURL
        self.lastModifiedAt = lastModifiedAt
    }
}

public final class ClaudeCodeDetector: Sendable {
    private let reader: BoundedJSONLReader
    private let customBaseDirectory: URL?
    public var baseDirectory: URL {
        customBaseDirectory ?? Self.resolveClaudeHomeDirectory()
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

    // MARK: - Main detect() Entrypoint (NEW_PLANS Section 3)

    public func detect(
        processTable: [pid_t: MonitoredProcess],
        t3RootPIDs: Set<pid_t>
    ) -> [AgentSessionStatus] {
        // 1. Find running `claude` CLI processes
        let liveClaudeProcs = processTable.values.filter { proc in
            let lowerName = proc.name.lowercased()
            let lowerPath = proc.executablePath.lowercased()
            return lowerName == "claude"
                || lowerPath.hasSuffix("/claude")
                || lowerPath.contains("@anthropic-ai/claude-code")
        }

        // 2. Discover recent ~/.claude/projects/*/*.jsonl transcripts
        let recentTranscripts = findRecentClaudeTranscripts(maxFiles: 15)
        var parsedFiles: [(url: URL, snapshot: JSONLSnapshot, parsed: JSONLProviderParsers.ClaudeParsedTranscript)] = []

        for fileURL in recentTranscripts {
            guard let snapshot = reader.readSnapshot(at: fileURL) else { continue }
            let parsed = JSONLProviderParsers.parseClaude(snapshot: snapshot)
            parsedFiles.append((fileURL, snapshot, parsed))
        }

        var matchedURLs = Set<URL>()
        var results: [AgentSessionStatus] = []

        // 3. Bind live `claude` processes to their active transcript
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let recentThreshold = Date().addingTimeInterval(-300) // 5 minutes

        for proc in liveClaudeProcs {
            let parentT3 = ProcessTreeScanner.findAncestor(of: proc.pid, in: processTable, matching: t3RootPIDs)
            let surface: AgentSurface = parentT3 != nil ? .t3Orchestrated : .cli

            let normalizedCwd = proc.cwd.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

            let matchingFile = parsedFiles.first { candidate in
                guard !matchedURLs.contains(candidate.url) else { return false }
                guard let procCWD = proc.cwd, let fileCWD = candidate.parsed.cwd else { return false }
                guard Self.normalizePath(procCWD) == Self.normalizePath(fileCWD) else { return false }

                if normalizedCwd == "/" {
                    return false
                }
                if normalizedCwd == homePath {
                    return candidate.snapshot.modifiedAt >= recentThreshold && candidate.parsed.cwd == homePath
                }
                return true
            }

            // Filter out background claude helper processes whose cwd == "/" or cwd == homePath if they have no matching transcript
            if matchingFile == nil && (normalizedCwd == nil || normalizedCwd == "/" || normalizedCwd == homePath) {
                continue
            }

            if let match = matchingFile {
                matchedURLs.insert(match.url)
            }

            let resolvedCWD = proc.cwd ?? matchingFile?.parsed.cwd
            let projectName: String = {
                guard let path = resolvedCWD else { return "claude" }
                let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
                if URL(fileURLWithPath: path).standardizedFileURL.path == homePath {
                    return "Home (~)"
                }
                let rawName = URL(fileURLWithPath: path).lastPathComponent
                return (rawName.isEmpty || rawName == "/") ? "claude" : rawName
            }()
            let hasActiveChild = processTable.values.contains { $0.ppid == proc.pid }

            let state = inferClaudeState(
                hasActiveChild: hasActiveChild,
                snapshot: matchingFile?.snapshot,
                parsed: matchingFile?.parsed
            )

            let sessionID = matchingFile?.parsed.sessionID ?? "claude-pid-\(proc.pid)"

            results.append(
                AgentSessionStatus(
                    id: sessionID,
                    provider: .claudeCode,
                    surface: surface,
                    pid: proc.pid,
                    parentT3PID: parentT3,
                    projectName: projectName,
                    workspacePath: resolvedCWD,
                    gitBranch: matchingFile?.parsed.gitBranch,
                    modelName: matchingFile?.parsed.model,
                    state: state,
                    tokenUsage: matchingFile?.parsed.deduplicatedUsage,
                    lastUpdated: matchingFile?.snapshot.modifiedAt ?? Date()
                )
            )
        }

        // 4. Append today's completed/inactive sessions for accurate daily quota tracking
        for item in parsedFiles where !matchedURLs.contains(item.url) {
            guard Calendar.current.isDateInToday(item.snapshot.modifiedAt) else { continue }
            let cwd = item.parsed.cwd
            let projectName: String = {
                guard let path = cwd else { return "claude" }
                let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
                if URL(fileURLWithPath: path).standardizedFileURL.path == homePath {
                    return "Home (~)"
                }
                let rawName = URL(fileURLWithPath: path).lastPathComponent
                return (rawName.isEmpty || rawName == "/") ? "claude" : rawName
            }()
            let sessionID = item.parsed.sessionID ?? item.url.deletingPathExtension().lastPathComponent

            results.append(
                AgentSessionStatus(
                    id: sessionID,
                    provider: .claudeCode,
                    surface: .cli,
                    pid: nil,
                    parentT3PID: nil,
                    projectName: projectName,
                    workspacePath: cwd,
                    gitBranch: item.parsed.gitBranch,
                    modelName: item.parsed.model,
                    state: .inactive,
                    tokenUsage: item.parsed.deduplicatedUsage,
                    lastUpdated: item.snapshot.modifiedAt
                )
            )
        }

        return results
    }

    // MARK: - Helpers

    public static func resolveClaudeHomeDirectory() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["CLAUDE_HOME"], !envPath.isEmpty {
            return URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    public static func resolveClaudeProjectsDirectory() -> URL {
        resolveClaudeHomeDirectory().appendingPathComponent("projects", isDirectory: true)
    }

    public func findRecentClaudeTranscripts(maxFiles: Int = 15) -> [URL] {
        let projectsRoot = baseDirectory.appendingPathComponent("projects", isDirectory: true)
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var jsonlFiles: [(url: URL, mtime: Date)] = []
        let cutoff = Date().addingTimeInterval(-48 * 3600) // Last 48 hours

        for dir in projectDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                guard mtime >= cutoff else { continue }
                jsonlFiles.append((file, mtime))
            }
        }

        jsonlFiles.sort { $0.mtime > $1.mtime }
        return Array(jsonlFiles.prefix(maxFiles).map(\.url))
    }

    public func inferClaudeState(
        hasActiveChild: Bool,
        snapshot: JSONLSnapshot?,
        parsed: JSONLProviderParsers.ClaudeParsedTranscript?
    ) -> AgentRunState {
        if hasActiveChild {
            return .working
        }
        guard let snapshot = snapshot, let parsed = parsed else {
            return .idle
        }

        let age = Date().timeIntervalSince(snapshot.modifiedAt)

        if parsed.lastRecordType == "assistant" && parsed.lastStopReason == "tool_use" {
            // If Claude requested a tool_use more than 2 seconds ago and no child process is running,
            // it is waiting on the user's permission prompt in the terminal.
            return age > 2.0 ? .awaitingApproval : .working
        }

        if age < 3.0 {
            return .working
        }

        return .idle
    }

    private static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    // MARK: - Compatibility Methods (for Existing Tests)

    public func findLiveClaudeProcesses(
        table: [pid_t: MonitoredProcess],
        t3AncestorPIDs: Set<pid_t> = []
    ) -> [ClaudeLiveProcess] {
        var processes: [ClaudeLiveProcess] = []

        // Build a quick map of parent to direct children
        var childrenByPPID: [pid_t: [pid_t]] = [:]
        for (pid, proc) in table {
            if proc.ppid > 1 {
                childrenByPPID[proc.ppid, default: []].append(pid)
            }
        }

        for (pid, proc) in table {
            guard pid > 1 else { continue }
            let lowerName = proc.name.lowercased()
            let lowerPath = proc.executablePath.lowercased()

            let isClaude = lowerName == "claude" ||
                lowerPath.hasSuffix("/claude") ||
                lowerPath.contains("/@anthropic-ai/claude-code")

            guard isClaude else { continue }

            let parentT3 = ProcessTreeScanner.findAncestor(of: pid, in: table, matching: t3AncestorPIDs)
            let surface: AgentSurface = parentT3 != nil ? .t3Orchestrated : .cli
            let cwd = proc.cwd ?? ProcessTreeScanner.resolveCWD(for: pid)
            let childPIDs = childrenByPPID[pid] ?? []

            processes.append(
                ClaudeLiveProcess(
                    pid: pid,
                    ppid: proc.ppid,
                    name: proc.name,
                    executablePath: proc.executablePath,
                    cwd: cwd,
                    parentT3PID: parentT3,
                    surface: surface,
                    childPIDs: childPIDs
                )
            )
        }

        return processes
    }

    public func findRecentTranscriptURLs() -> [URL] {
        let projectsDir = baseDirectory.appendingPathComponent("projects")
        guard FileManager.default.fileExists(atPath: projectsDir.path) else { return [] }

        var transcriptURLs: [URL] = []
        let fileManager = FileManager.default

        guard let projectFolders = try? fileManager.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for folder in projectFolders {
            guard let files = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for file in files {
                if file.pathExtension == "jsonl" {
                    transcriptURLs.append(file)
                }
            }
        }

        // Sort descending by modification date
        return transcriptURLs.sorted { u1, u2 in
            let date1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let date2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return date1 > date2
        }
    }

    public func detectSessions(
        table: [pid_t: MonitoredProcess],
        t3AncestorPIDs: Set<pid_t> = [],
        now: Date = Date()
    ) -> [ClaudeCLISessionRecord] {
        let liveProcesses = findLiveClaudeProcesses(table: table, t3AncestorPIDs: t3AncestorPIDs)
        let transcriptURLs = findRecentTranscriptURLs()

        var sessions: [ClaudeCLISessionRecord] = []
        var claimedPIDs = Set<pid_t>()

        for url in transcriptURLs {
            guard let snapshot = reader.readSnapshot(at: url) else { continue }
            let parsed = JSONLProviderParsers.parseClaude(snapshot: snapshot)

            let sessionID = parsed.sessionID ?? url.deletingPathExtension().lastPathComponent

            // Correlate with running claude process via CWD
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

                // State determination from tail event and child process activity
                if parsed.lastStopReason == "tool_use" {
                    if !proc.childPIDs.isEmpty {
                        state = .working
                    } else if now.timeIntervalSince(snapshot.modifiedAt) > 2.0 {
                        state = .awaitingApproval
                    } else {
                        state = .working
                    }
                } else if parsed.lastStopReason == "end_turn" {
                    state = .idle
                } else if parsed.lastRecordType == "user" {
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
                ClaudeCLISessionRecord(
                    sessionID: sessionID,
                    pid: pid,
                    parentT3PID: parentT3,
                    surface: surface,
                    cwd: parsed.cwd,
                    gitBranch: parsed.gitBranch,
                    model: parsed.model,
                    state: state,
                    tokenUsage: parsed.deduplicatedUsage,
                    fileURL: url,
                    lastModifiedAt: snapshot.modifiedAt
                )
            )
        }

        // Add any active claude processes that haven't written a transcript file yet
        for proc in liveProcesses where !claimedPIDs.contains(proc.pid) {
            let sessionID = "pid-\(proc.pid)"
            sessions.append(
                ClaudeCLISessionRecord(
                    sessionID: sessionID,
                    pid: proc.pid,
                    parentT3PID: proc.parentT3PID,
                    surface: proc.surface,
                    cwd: proc.cwd,
                    gitBranch: nil,
                    model: nil,
                    state: .working,
                    tokenUsage: TokenUsageSnapshot(),
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
        let transcriptURLs = findRecentTranscriptURLs()

        var totalInput = 0
        var totalCached = 0
        var totalOutput = 0

        for url in transcriptURLs {
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            guard calendar.isDate(modDate, inSameDayAs: now) else { continue }

            guard let snapshot = reader.readSnapshot(at: url) else { continue }
            let parsed = JSONLProviderParsers.parseClaude(snapshot: snapshot)

            totalInput += parsed.deduplicatedUsage.inputTokens
            totalCached += parsed.deduplicatedUsage.cachedInputTokens
            totalOutput += parsed.deduplicatedUsage.outputTokens
        }

        return TokenUsageSnapshot(
            inputTokens: totalInput,
            cachedInputTokens: totalCached,
            outputTokens: totalOutput,
            reasoningTokens: 0
        )
    }

    public func calculateDailyTokenUsage(
        calendar: Calendar = Calendar.current,
        now: Date = Date()
    ) -> TokenUsageSnapshot {
        computeDailyTokenUsage(calendar: calendar, now: now)
    }
}
