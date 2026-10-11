//
//  ClaudeParser.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct ClaudeTranscriptTail: Equatable, Sendable {
    public let toolName: String?
    public let toolCommand: String?
    public let toolTarget: String?
    public let isTurnComplete: Bool
    public let lastUserPrompt: String?
    public let timestamp: Date?

    public init(
        toolName: String? = nil,
        toolCommand: String? = nil,
        toolTarget: String? = nil,
        isTurnComplete: Bool = false,
        lastUserPrompt: String? = nil,
        timestamp: Date? = nil
    ) {
        self.toolName = toolName
        self.toolCommand = toolCommand
        self.toolTarget = toolTarget
        self.isTurnComplete = isTurnComplete
        self.lastUserPrompt = lastUserPrompt
        self.timestamp = timestamp
    }
}

public struct ClaudeTranscriptInfo: Equatable, Sendable {
    public let url: URL
    public let sessionID: String
    public let modifiedAt: Date

    public init(url: URL, sessionID: String, modifiedAt: Date) {
        self.url = url
        self.sessionID = sessionID
        self.modifiedAt = modifiedAt
    }
}

public struct ClaudeParser: Sendable {
    private static let psDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    // MARK: - Process Command Matching

    public static func isClaudeCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Tokenize command line
        let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let firstToken = tokens.first else { return false }

        let firstExecutable = URL(fileURLWithPath: firstToken).lastPathComponent.lowercased()

        // 1. Rejection of unrelated utilities
        let rejectedTools: Set<String> = [
            "grep", "egrep", "fgrep", "vim", "nvim", "vi", "nano", "emacs",
            "cat", "less", "more", "head", "tail", "man", "find", "locate",
            "git", "swiftc", "swift", "xcodebuild", "loom", "python", "python3",
            "echo", "sh", "bash", "zsh", "ruby", "perl", "diff"
        ]
        if rejectedTools.contains(firstExecutable) {
            return false
        }

        // 2. Chromium / Electron helper rejection
        if firstExecutable.contains("helper") || trimmed.contains("--type=renderer") || trimmed.contains("--type=gpu-process") {
            return false
        }

        // 3. Direct binary execution: claude
        if firstExecutable == "claude" {
            return true
        }

        // 4. Node / Deno / Bun wrapper: inspect the target entry script only
        if firstExecutable == "node" || firstExecutable == "deno" || firstExecutable == "bun" {
            var tokenIndex = 1
            while tokenIndex < tokens.count {
                let token = tokens[tokenIndex]
                let cleanToken = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                // Skip runner subcommand
                if cleanToken == "run" {
                    tokenIndex += 1
                    continue
                }

                // Skip option flags
                if cleanToken.hasPrefix("-") {
                    let optionName = cleanToken.split(separator: "=", maxSplits: 1).first.map(String.init) ?? cleanToken
                    let optionsWithArg: Set<String> = [
                        "-r", "--require", "--loader", "-e", "--eval", "-c", "--config",
                        "--import", "--target", "-m", "--model", "-p", "--port"
                    ]
                    if optionsWithArg.contains(optionName) && !cleanToken.contains("=") && tokenIndex + 1 < tokens.count {
                        tokenIndex += 2
                    } else {
                        tokenIndex += 1
                    }
                    continue
                }

                // First non-option argument is the entry script
                let scriptLower = cleanToken.lowercased()
                let scriptBasename = URL(fileURLWithPath: cleanToken).lastPathComponent.lowercased()

                if scriptLower.contains("@anthropic-ai/claude-code") {
                    return true
                }

                let validClaudeScriptNames: Set<String> = [
                    "claude.js", "claude.ts", "claude.mjs", "claude.cjs", "claude"
                ]
                if validClaudeScriptNames.contains(scriptBasename) {
                    return true
                }

                if scriptBasename == "cli.js" && (scriptLower.contains("/claude/") || scriptLower.contains("/claude-code/")) {
                    return true
                }

                // Target script is another file (e.g. build.js, test.js, server.js); not Claude Code
                return false
            }
        }

        // 5. Explicit path ending in /claude
        if firstToken.hasSuffix("/claude") {
            return true
        }

        return false
    }

    public static func extractSessionIDToken(from command: String) -> String? {
        let tokens = command.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for (i, token) in tokens.enumerated() {
            if token == "--session-id" || token == "--resume" {
                if i + 1 < tokens.count {
                    let next = tokens[i + 1]
                    if !next.hasPrefix("-") {
                        return next.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                }
            } else if token.hasPrefix("--session-id=") {
                let id = String(token.dropFirst("--session-id=".count))
                return id.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if token.hasPrefix("--resume=") {
                let id = String(token.dropFirst("--resume=".count))
                return id.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    // MARK: - CWD Escaping & Project Paths

    public static func escapedCWD(_ cwd: String) -> String {
        String(cwd.unicodeScalars.map { scalar in
            let val = scalar.value
            let isAlphanumeric = (48...57).contains(val) || (65...90).contains(val) || (97...122).contains(val)
            return isAlphanumeric ? Character(scalar) : "-"
        })
    }

    public static func projectDirectories(
        cwd: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let escaped = escapedCWD(cwd)
        let standard = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(escaped, isDirectory: true)
        let desktopSessions = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("claude-code-sessions", isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(escaped, isDirectory: true)
        let desktopLocalAgent = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(escaped, isDirectory: true)
        return [standard, desktopSessions, desktopLocalAgent]
    }

    // MARK: - Transcript Discovery & Correlation

    public static func findTranscripts(
        for cwd: String,
        candidateDirectories: [URL]? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [ClaudeTranscriptInfo] {
        let directories = candidateDirectories ?? projectDirectories(cwd: cwd, homeDirectory: homeDirectory)
        var results: [ClaudeTranscriptInfo] = []

        for dir in directories {
            guard fileManager.fileExists(atPath: dir.path),
                  let enumerator = fileManager.enumerator(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "jsonl" else { continue }
                guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let size = values.fileSize, size > 0,
                      let modDate = values.contentModificationDate else {
                    continue
                }

                let sessionID = fileURL.deletingPathExtension().lastPathComponent
                results.append(ClaudeTranscriptInfo(url: fileURL, sessionID: sessionID, modifiedAt: modDate))
            }
        }

        // Sort descending by modifiedAt (newest first)
        results.sort { $0.modifiedAt > $1.modifiedAt }
        return results
    }

    public static func findTranscript(
        matchingSessionID sessionID: String,
        in transcripts: [ClaudeTranscriptInfo],
        usedPaths: inout Set<String>
    ) -> ClaudeTranscriptInfo? {
        let cleanID = sessionID.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !cleanID.isEmpty else { return nil }

        for transcript in transcripts {
            guard !usedPaths.contains(transcript.url.path) else { continue }
            if transcript.sessionID == cleanID || transcript.url.deletingPathExtension().lastPathComponent == cleanID {
                usedPaths.insert(transcript.url.path)
                return transcript
            }
        }
        return nil
    }

    public static func parseLsofOpenTranscripts(_ lsofOutput: String) -> [URL] {
        var results: [URL] = []
        let lines = lsofOutput.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("n") else { continue }
            let path = String(trimmed.dropFirst())
            guard path.hasSuffix(".jsonl") else { continue }
            if path.contains(".claude") || path.contains("claude-code") || path.contains("projects") {
                let url = URL(fileURLWithPath: path)
                if !results.contains(url) {
                    results.append(url)
                }
            }
        }
        return results
    }

    public static func correlateTranscript(
        for processStartedAt: Date?,
        in transcripts: [ClaudeTranscriptInfo],
        usedPaths: inout Set<String>
    ) -> ClaudeTranscriptInfo? {
        guard let started = processStartedAt else {
            return nil
        }

        // Look for newest unused transcript modified at or after process started (with 5s clock skew tolerance)
        for transcript in transcripts {
            guard !usedPaths.contains(transcript.url.path) else { continue }
            if transcript.modifiedAt >= started.addingTimeInterval(-5) {
                usedPaths.insert(transcript.url.path)
                return transcript
            }
        }

        // Truthful: return nil rather than binding an arbitrary historical transcript from yesterday
        return nil
    }

    // MARK: - Transcript Tail Parsing

    public static func parseTranscriptTail(from content: String) -> ClaudeTranscriptTail? {
        let lines = Array(content.components(separatedBy: .newlines).reversed())
        var pendingTail: (toolName: String?, toolCommand: String?, toolTarget: String?, isTurnComplete: Bool)? = nil
        var lastUserPrompt: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            // Check assistant turn if we haven't found the latest tail action yet
            if pendingTail == nil && type == "assistant" {
                let message = json["message"] as? [String: Any]
                let stopReason = message?["stop_reason"] as? String
                let contentArray = message?["content"] as? [[String: Any]] ?? []

                var foundTool = false
                for item in contentArray.reversed() {
                    if item["type"] as? String == "tool_use" {
                        let name = item["name"] as? String
                        let input = item["input"] as? [String: Any]

                        let command: String? = input?["command"] as? String
                        let target: String? = input?["file_path"] as? String
                            ?? input?["path"] as? String
                            ?? input?["pattern"] as? String
                            ?? input?["query"] as? String

                        pendingTail = (toolName: name, toolCommand: command, toolTarget: target, isTurnComplete: false)
                        foundTool = true
                        break
                    }
                }

                if !foundTool && stopReason == "end_turn" {
                    pendingTail = (toolName: nil, toolCommand: nil, toolTarget: nil, isTurnComplete: true)
                }
            }

            // Check progress if no assistant action found yet
            if pendingTail == nil && type == "progress" {
                let status = json["status"] as? String ?? "working"
                pendingTail = (toolName: nil, toolCommand: nil, toolTarget: status, isTurnComplete: false)
            }

            // Record user turn for context
            if type == "user" && lastUserPrompt == nil {
                let msg = json["message"] as? [String: Any]
                if let promptText = msg?["content"] as? String {
                    lastUserPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let contentArr = msg?["content"] as? [[String: Any]] {
                    for item in contentArr {
                        if item["type"] as? String == "text", let text = item["text"] as? String {
                            lastUserPrompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            break
                        }
                    }
                }
            }

            // If we have both the latest assistant action and the preceding user prompt, we can finish early
            if pendingTail != nil && lastUserPrompt != nil {
                break
            }
        }

        if let tail = pendingTail {
            return ClaudeTranscriptTail(
                toolName: tail.toolName,
                toolCommand: tail.toolCommand,
                toolTarget: tail.toolTarget,
                isTurnComplete: tail.isTurnComplete,
                lastUserPrompt: lastUserPrompt
            )
        } else if let prompt = lastUserPrompt {
            return ClaudeTranscriptTail(
                toolName: nil,
                toolCommand: nil,
                toolTarget: nil,
                isTurnComplete: false,
                lastUserPrompt: prompt
            )
        }

        return nil
    }

    public static func inspectTranscriptTail(
        at fileURL: URL,
        maxBytes: Int = 32 * 1024
    ) -> ClaudeTranscriptTail? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        } catch {
            return nil
        }

        let readBytes = min(fileSize, UInt64(maxBytes))
        if fileSize > readBytes {
            try? handle.seek(toOffset: fileSize - readBytes)
        }

        guard let data = try? handle.read(upToCount: Int(readBytes)),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return parseTranscriptTail(from: text)
    }

    // MARK: - Activity Summary & State Derivation

    public static func activitySummary(
        tail: ClaudeTranscriptTail?,
        childWorker: AgentProcess?,
        projectName: String?
    ) -> (summary: String, evidence: String) {
        if let worker = childWorker {
            let summary = DefaultSessionCorrelationEngine.formatActivitySummary(
                for: worker.commandLine,
                executable: worker.executable
            )
            return (summary: summary, evidence: "Active worker: PID \(worker.pid) (\(summary))")
        }

        if let tool = tail?.toolName, !tool.isEmpty {
            switch tool {
            case "Bash":
                if let cmd = tail?.toolCommand, !cmd.isEmpty {
                    let formatted = DefaultSessionCorrelationEngine.formatActivitySummary(for: cmd, executable: "bash")
                    return (summary: formatted, evidence: "Activity from transcript tool_use: 'Bash (\(cmd))'")
                }
                return (summary: "Executing command", evidence: "Activity from transcript tool_use: 'Bash'")
            case "FileEdit", "Edit":
                if let target = tail?.toolTarget, !target.isEmpty {
                    let filename = URL(fileURLWithPath: target).lastPathComponent
                    return (summary: "Editing \(filename)", evidence: "Activity from transcript tool_use: '\(tool) (\(target))'")
                }
                return (summary: "Editing file", evidence: "Activity from transcript tool_use: '\(tool)'")
            case "FileView", "View", "Read":
                if let target = tail?.toolTarget, !target.isEmpty {
                    let filename = URL(fileURLWithPath: target).lastPathComponent
                    return (summary: "Reading \(filename)", evidence: "Activity from transcript tool_use: '\(tool) (\(target))'")
                }
                return (summary: "Reading file", evidence: "Activity from transcript tool_use: '\(tool)'")
            case "Grep", "Glob":
                if let pattern = tail?.toolTarget, !pattern.isEmpty {
                    return (summary: "Searching '\(pattern)'", evidence: "Activity from transcript tool_use: '\(tool) (\(pattern))'")
                }
                return (summary: "Searching files", evidence: "Activity from transcript tool_use: '\(tool)'")
            default:
                return (summary: "Running \(tool)", evidence: "Activity from transcript tool_use: '\(tool)'")
            }
        }

        if tail?.isTurnComplete == true {
            return (summary: "Awaiting user input", evidence: "State: Waiting (assistant turn complete; awaiting user input)")
        }

        if let prompt = tail?.lastUserPrompt, !prompt.isEmpty {
            let preview = prompt.count > 30 ? String(prompt.prefix(30)) + "…" : prompt
            return (summary: "Awaiting turn: \(preview)", evidence: "Activity from user prompt: '\(preview)'")
        }

        let fallback = projectName ?? "Claude Session"
        return (summary: fallback, evidence: "Activity from Claude process")
    }

    public static func mapState(
        hasChildWorkers: Bool,
        isStarting: Bool,
        isInteractive: Bool,
        tail: ClaudeTranscriptTail?,
        hasTranscript: Bool
    ) -> AgentState {
        if hasChildWorkers {
            return .working
        }
        if tail?.toolName != nil {
            return .working
        }
        if isStarting {
            return .starting
        }
        if tail?.isTurnComplete == true || isInteractive {
            return .waiting
        }
        if hasTranscript {
            return .waiting
        }
        return .unknown
    }

    public static func stateEvidence(state: AgentState, detail: String? = nil) -> String {
        switch state {
        case .working:
            return "State: Working (\(detail ?? "active task in progress"))"
        case .waiting:
            return "State: Waiting (\(detail ?? "awaiting user input"))"
        case .starting:
            return "State: Starting (\(detail ?? "process recently launched"))"
        case .idle:
            return "State: Idle (\(detail ?? "daemon/server mode"))"
        case .finished:
            return "State: Finished (\(detail ?? "session terminated"))"
        case .failed:
            return "State: Failed (\(detail ?? "error encountered"))"
        case .unknown:
            return "State: Unknown (\(detail ?? "bare process without worker subprocesses or session metadata"))"
        }
    }

    // MARK: - lsof Output Parsing

    public static func parseLsofCwdOutput(_ output: String) -> URL? {
        var currentCwd: String? = nil
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("n/") {
                currentCwd = String(trimmed.dropFirst(1))
            }
        }

        guard let path = currentCwd, !path.isEmpty else {
            return nil
        }

        if path == "/" {
            return nil
        }

        return URL(fileURLWithPath: path).standardizedFileURL
    }
}
