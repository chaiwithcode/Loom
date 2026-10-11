//
//  AntigravityParser.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct AntigravityParser: Sendable {
    public static func parseDate(from dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Format 1: "2026-10-03 12:29:53.903014+00:00"
        let spaceFractionalFormatter = DateFormatter()
        spaceFractionalFormatter.locale = Locale(identifier: "en_US_POSIX")
        spaceFractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        spaceFractionalFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
        if let date = spaceFractionalFormatter.date(from: trimmed) {
            return date
        }

        // Format 2: ISO8601 with fractional seconds
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: trimmed) {
            return date
        }

        // Format 3: Standard ISO8601
        let isoStandard = ISO8601DateFormatter()
        isoStandard.formatOptions = [.withInternetDateTime]
        if let date = isoStandard.date(from: trimmed) {
            return date
        }

        // Format 4: "2026-10-03 12:29:53"
        let spaceFormatter = DateFormatter()
        spaceFormatter.locale = Locale(identifier: "en_US_POSIX")
        spaceFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        spaceFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = spaceFormatter.date(from: trimmed) {
            return date
        }

        return nil
    }

    public static func parseWorkspaceURLs(from jsonString: String) -> [URL] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }

        var urls: [URL] = []
        for rawURI in jsonArray {
            let trimmedURI = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURI.isEmpty else { continue }

            if let parsedURL = URL(string: trimmedURI), parsedURL.scheme == "file" {
                let filePath = parsedURL.path
                if !filePath.isEmpty {
                    urls.append(URL(fileURLWithPath: filePath).standardizedFileURL)
                }
            } else if trimmedURI.hasPrefix("/") {
                urls.append(URL(fileURLWithPath: trimmedURI).standardizedFileURL)
            }
        }

        return urls
    }


    public static func isActiveSession(status: String, notFullyIdle: Bool, killed: Bool) -> Bool {
        if killed { return false }
        return status == "CASCADE_RUN_STATUS_RUNNING" || notFullyIdle
    }

    public static func mapState(status: String, notFullyIdle: Bool) -> AgentState {
        switch status {
        case "CASCADE_RUN_STATUS_RUNNING":
            return .working
        case "CASCADE_RUN_STATUS_IDLE":
            return notFullyIdle ? .waiting : .idle
        case "CASCADE_RUN_STATUS_WAITING", "CASCADE_RUN_STATUS_USER_INPUT_REQUIRED":
            return .waiting
        case "CASCADE_RUN_STATUS_ERROR", "CASCADE_RUN_STATUS_FAILED":
            return .failed
        default:
            return .unknown
        }
    }

    public static func stateEvidence(status: String, notFullyIdle: Bool) -> String {
        switch status {
        case "CASCADE_RUN_STATUS_RUNNING":
            return "State: Working (cascade run active)"
        case "CASCADE_RUN_STATUS_IDLE":
            return notFullyIdle ?
                "State: Waiting (cascade run idle, not_fully_idle=true; awaiting user turn)" :
                "State: Idle (cascade run idle)"
        case "CASCADE_RUN_STATUS_WAITING", "CASCADE_RUN_STATUS_USER_INPUT_REQUIRED":
            return "State: Waiting (user input required)"
        case "CASCADE_RUN_STATUS_ERROR", "CASCADE_RUN_STATUS_FAILED":
            return "State: Failed (cascade run error)"
        default:
            return "State: Unknown (status: \(status))"
        }
    }

    public static func parseTranscriptTail(from content: String) -> (action: String?, toolName: String?, type: String?)? {
        let lines = content.components(separatedBy: .newlines).reversed()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            if let toolCalls = json["tool_calls"] as? [[String: Any]],
               let firstTool = toolCalls.last ?? toolCalls.first {
                let name = firstTool["name"] as? String
                let args = firstTool["args"] as? [String: Any]
                let toolAction = args?["toolAction"] as? String

                return (action: toolAction, toolName: name, type: type)
            }

            if type == "PLANNER_RESPONSE" || type == "USER_INPUT" {
                return (action: nil, toolName: nil, type: type)
            }
        }
        return nil
    }

    public static func inspectTranscriptTail(
        for conversationId: String,
        baseDirectory: URL? = nil
    ) -> (action: String?, toolName: String?, type: String?)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidateDirectories: [URL] = [
            baseDirectory,
            home.appendingPathComponent(".gemini/antigravity-cli/brain/\(conversationId)/.system_generated/logs"),
            home.appendingPathComponent(".gemini/antigravity/conversations/\(conversationId)")
        ].compactMap { $0 }

        for dir in candidateDirectories {
            let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
            guard FileManager.default.fileExists(atPath: transcriptURL.path),
                  let handle = try? FileHandle(forReadingFrom: transcriptURL) else {
                continue
            }
            defer { try? handle.close() }

            let fileSize: UInt64
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: transcriptURL.path)
                fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            } catch {
                continue
            }

            let readBytes = min(fileSize, 32 * 1024)
            if fileSize > readBytes {
                try? handle.seek(toOffset: fileSize - readBytes)
            }

            guard let data = try? handle.read(upToCount: Int(readBytes)),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }

            if let result = parseTranscriptTail(from: text) {
                return result
            }
        }

        return nil
    }

    public static func activitySummary(
        conversationId: String,
        status: String,
        title: String,
        transcriptDirectory: URL? = nil
    ) -> (summary: String, evidence: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let transcript = inspectTranscriptTail(for: conversationId, baseDirectory: transcriptDirectory) {
            if let action = transcript.action, !action.isEmpty {
                let summary = cleanTitle.isEmpty ? action : "\(action) · \(cleanTitle)"
                return (summary: summary, evidence: "Activity from transcript toolAction: '\(action)'")
            }

            if let toolName = transcript.toolName, !toolName.isEmpty {
                let friendlyTool = friendlyToolDescription(toolName)
                let summary = cleanTitle.isEmpty ? friendlyTool : "\(friendlyTool) · \(cleanTitle)"
                return (summary: summary, evidence: "Activity from transcript tool: '\(toolName)'")
            }

            if transcript.type == "PLANNER_RESPONSE" {
                let summary = cleanTitle.isEmpty ? "Generating response" : "Generating response · \(cleanTitle)"
                return (summary: summary, evidence: "Activity from transcript step: PLANNER_RESPONSE")
            }

            if transcript.type == "USER_INPUT" {
                let summary = cleanTitle.isEmpty ? "Awaiting user input" : "Awaiting input: \(cleanTitle)"
                return (summary: summary, evidence: "Activity from transcript step: USER_INPUT")
            }
        }

        // Fallback to conversation title
        if status == "CASCADE_RUN_STATUS_RUNNING" {
            let summary = cleanTitle.isEmpty ? "Active Antigravity task" : cleanTitle
            return (summary: summary, evidence: "Activity from conversation title")
        } else {
            let summary = cleanTitle.isEmpty ? "Awaiting user turn" : "Awaiting turn: \(cleanTitle)"
            return (summary: summary, evidence: "Activity from conversation title (idle/waiting)")
        }
    }

    private static func friendlyToolDescription(_ toolName: String) -> String {
        switch toolName {
        case "run_command": return "Executing command"
        case "view_file": return "Reading file"
        case "replace_file_content": return "Editing file"
        case "write_to_file": return "Creating file"
        case "search_web": return "Searching web"
        case "manage_task": return "Managing background task"
        default: return "Running \(toolName)"
        }
    }

    public static func isAntigravityProcessCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()

        // Filter out build / derived artifacts
        if lower.contains("deriveddata") || lower.contains("/.build/") {
            return false
        }

        let rawExecutable = extractExecutable(from: trimmed)
        guard !rawExecutable.isEmpty else { return false }
        let execURL = URL(fileURLWithPath: rawExecutable)
        let execBasename = execURL.lastPathComponent.lowercased()

        // 1. Rejection of unrelated utilities where /agy might only appear in arguments
        let rejectedTools: Set<String> = [
            "grep", "egrep", "fgrep", "vim", "nvim", "vi", "nano", "emacs",
            "cat", "less", "more", "head", "tail", "man", "find", "locate",
            "git", "swiftc", "swift", "xcodebuild", "loom", "python", "python3",
            "echo", "sh", "bash", "zsh", "node", "ruby", "perl", "diff"
        ]
        if rejectedTools.contains(execBasename) {
            return false
        }

        let rawExecLower = rawExecutable.lowercased()

        // 2. Antigravity Desktop App / Helper
        if rawExecLower.contains("/antigravity.app/contents/macos/antigravity") ||
           rawExecLower.contains("/antigravity helper.app/") ||
           rawExecLower.hasSuffix("antigravity helper") ||
           (execBasename == "antigravity" && rawExecLower.contains("antigravity.app")) {
            return true
        }

        // 3. Language Server with Antigravity parameters
        if (execBasename == "language_server" || execBasename.hasPrefix("language_server")) &&
           (lower.contains("--subclient_type hub") ||
            lower.contains("--override_ide_name antigravity") ||
            lower.contains("--app_data_dir=antigravity") ||
            lower.contains("antigravity")) {
            return true
        }

        // 4. Antigravity CLI binary: executable basename must strictly be "agy"
        if execBasename == "agy" {
            return true
        }

        return false
    }

    private static func extractExecutable(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
            let quote = trimmed.first!
            let withoutQuote = trimmed.dropFirst()
            if let closingIndex = withoutQuote.firstIndex(of: quote) {
                return String(withoutQuote[..<closingIndex])
            }
        }
        return trimmed.components(separatedBy: .whitespaces).first ?? ""
    }
}
