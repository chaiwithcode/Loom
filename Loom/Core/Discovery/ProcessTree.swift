//
//  ProcessTree.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct ProcessNode: Identifiable, Hashable, Equatable, Sendable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let parentPID: pid_t?
    public let command: String
    public let executable: String
    public let startedAt: Date?

    public init(
        pid: pid_t,
        parentPID: pid_t? = nil,
        command: String,
        executable: String,
        startedAt: Date? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
        self.executable = executable
        self.startedAt = startedAt
    }
}

public struct ProcessTree: Sendable {
    private let nodesByPID: [pid_t: ProcessNode]
    private let childrenByPID: [pid_t: [pid_t]]

    public init(nodes: [ProcessNode]) {
        var byPID: [pid_t: ProcessNode] = [:]
        var children: [pid_t: [pid_t]] = [:]

        for node in nodes {
            byPID[node.pid] = node
            if let ppid = node.parentPID {
                children[ppid, default: []].append(node.pid)
            }
        }

        self.nodesByPID = byPID
        self.childrenByPID = children
    }

    public var allNodes: [ProcessNode] {
        Array(nodesByPID.values)
    }

    public func node(for pid: pid_t) -> ProcessNode? {
        nodesByPID[pid]
    }

    public func children(of pid: pid_t) -> [ProcessNode] {
        let childPIDs = childrenByPID[pid] ?? []
        return childPIDs.compactMap { nodesByPID[$0] }
    }

    public func descendants(of pid: pid_t) -> [ProcessNode] {
        var results: [ProcessNode] = []
        var queue = children(of: pid)
        var visited: Set<pid_t> = [pid]

        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard !visited.contains(next.pid) else { continue }
            visited.insert(next.pid)
            results.append(next)
            queue.append(contentsOf: children(of: next.pid))
        }

        return results
    }

    public func ancestors(of pid: pid_t) -> [ProcessNode] {
        var results: [ProcessNode] = []
        var currentPID = pid
        var visited: Set<pid_t> = []

        while let current = nodesByPID[currentPID], let ppid = current.parentPID, ppid > 0 {
            guard !visited.contains(ppid) else { break }
            visited.insert(ppid)
            if let parent = nodesByPID[ppid] {
                results.append(parent)
                currentPID = ppid
            } else {
                break
            }
        }

        return results
    }

    /// Resolves the host application by walking up the ancestry chain.
    public func resolveHostApp(for pid: pid_t) -> HostApp? {
        let chain = ancestors(of: pid)

        for ancestor in chain {
            let cmd = ancestor.command.lowercased()
            let exec = ancestor.executable.lowercased()

            if exec.contains("chatgpt.app") || cmd.contains("contents/macos/chatgpt") {
                return .chatGPT
            }
            if exec.contains("visual studio code.app") || exec.contains("code.app") ||
                cmd.contains("visual studio code") || cmd.contains("code --") ||
                cmd.contains("code-insiders") {
                return .vsCode
            }
            if exec.contains("cursor.app") || cmd.contains("cursor") {
                return .cursor
            }
            if exec.contains("xcode.app") || exec.contains("xcodebuild") {
                return .xcode
            }
            if exec.contains("antigravity.app") || cmd.contains("contents/macos/antigravity") {
                return .antigravity
            }
            if exec.contains("terminal.app") || exec.contains("iterm") ||
                exec.contains("alacritty") || exec.contains("kitty") ||
                exec.contains("ghostty") || exec.contains("wezterm") {
                return .terminal
            }
        }

        // Check if direct parent is a recognized interactive shell launched without an app wrapper
        if let directParent = chain.first {
            let lastComp = URL(fileURLWithPath: directParent.executable).lastPathComponent.lowercased()
            if lastComp == "zsh" || lastComp == "bash" || lastComp == "fish" {
                return .terminal
            }
        }

        return nil
    }

    /// Extracts an explicit session ID token (e.g. from `--session-id <uuid>`, `--session-id=<uuid>`,
    /// or `--conversation <uuid>`).
    public static func extractSessionIDToken(from command: String) -> String? {
        let patterns = ["--session-id", "--conversation", "--conversation-id"]

        for pattern in patterns {
            var searchRange = command.startIndex..<command.endIndex
            while let range = command.range(of: pattern, range: searchRange) {
                let isLeadingBoundary = range.lowerBound == command.startIndex ||
                    command[command.index(before: range.lowerBound)].isWhitespace ||
                    command[command.index(before: range.lowerBound)] == "\"" ||
                    command[command.index(before: range.lowerBound)] == "'"

                if isLeadingBoundary {
                    let after = range.upperBound
                    if after < command.endIndex {
                        let nextChar = command[after]
                        if nextChar == "=" {
                            let valueSubstring = command[command.index(after: after)...]
                            let token = extractToken(from: String(valueSubstring))
                            if !token.isEmpty { return token }
                        } else if nextChar.isWhitespace {
                            let valueSubstring = command[after...]
                            let token = extractToken(from: String(valueSubstring))
                            if !token.isEmpty { return token }
                        }
                    }
                }

                if range.upperBound < command.endIndex {
                    searchRange = command.index(after: range.lowerBound)..<command.endIndex
                } else {
                    break
                }
            }
        }

        return nil
    }

    private static func extractToken(from string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
            let quote = trimmed.first!
            let withoutLeading = trimmed.dropFirst()
            if let endQuote = withoutLeading.firstIndex(of: quote) {
                return String(withoutLeading[..<endQuote])
            }
        }

        return trimmed.components(separatedBy: .whitespaces).first ?? ""
    }

    // MARK: - Parsing ps Output

    private static let psDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Parses output from `/bin/ps -ax -o pid=,ppid=,lstart=,command=`
    public static func parsePsOutput(_ output: String) -> [ProcessNode] {
        var results: [ProcessNode] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let scanner = Scanner(string: trimmed)
            scanner.charactersToBeSkipped = nil

            // 1. Scan PID
            _ = scanner.scanCharacters(from: .whitespaces)
            guard let pidInt = scanner.scanInt32(), pidInt > 0 else { continue }
            let pid = pid_t(pidInt)

            // 2. Scan PPID (optional second integer before lstart tokens)
            _ = scanner.scanCharacters(from: .whitespaces)
            let beforePPIDIndex = scanner.currentIndex
            var ppid: pid_t? = nil
            if let ppidInt = scanner.scanInt32(), ppidInt >= 0 {
                // Peek ahead: after PPID there should be whitespace and a day of week
                _ = scanner.scanCharacters(from: .whitespaces)
                let remainderPeek = String(trimmed[scanner.currentIndex...])
                if isDateStart(remainderPeek) {
                    ppid = pid_t(ppidInt)
                } else {
                    // Not a PPID; rewind scanner
                    scanner.currentIndex = beforePPIDIndex
                }
            }

            // 3. Scan remainder
            _ = scanner.scanCharacters(from: .whitespaces)
            let remainder = String(trimmed[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
            guard !remainder.isEmpty else { continue }

            let (startedAt, command) = splitDateAndCommand(from: remainder)
            guard !command.isEmpty else { continue }

            let executable = extractExecutable(from: command)

            results.append(ProcessNode(
                pid: pid,
                parentPID: ppid,
                command: command,
                executable: executable,
                startedAt: startedAt
            ))
        }

        return results
    }

    private static func isDateStart(_ str: String) -> Bool {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for day in days {
            if str.hasPrefix(day) { return true }
        }
        return false
    }

    private static func splitDateAndCommand(from remainder: String) -> (startedAt: Date?, command: String) {
        let scanner = Scanner(string: remainder)
        scanner.charactersToBeSkipped = nil

        var tokens: [String] = []
        var lastTokenEndIndex = remainder.startIndex

        while !scanner.isAtEnd && tokens.count < 5 {
            _ = scanner.scanCharacters(from: .whitespaces)
            guard !scanner.isAtEnd else { break }

            if let token = scanner.scanUpToCharacters(from: .whitespaces) {
                tokens.append(token)
                lastTokenEndIndex = scanner.currentIndex
            }
        }

        if tokens.count == 5 {
            let dateCandidate = tokens.joined(separator: " ")
            if let date = psDateFormatter.date(from: dateCandidate) {
                let cmd = remainder[lastTokenEndIndex...].trimmingCharacters(in: .whitespaces)
                if !cmd.isEmpty {
                    return (startedAt: date, command: cmd)
                }
            }
        }

        return (startedAt: nil, command: remainder)
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
        return trimmed.components(separatedBy: .whitespaces).first ?? trimmed
    }
}
