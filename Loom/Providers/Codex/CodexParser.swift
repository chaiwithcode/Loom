import Foundation

public struct CodexParser: Sendable {
    private static let psDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    public static func parsePsOutput(_ output: String) -> [(pid: pid_t, command: String, startedAt: Date?)] {
        var results: [(pid: pid_t, command: String, startedAt: Date?)] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Extract PID
            let scanner = Scanner(string: trimmed)
            guard let pidInt = scanner.scanInt32(), pidInt > 0 else {
                continue
            }
            let pid = pid_t(pidInt)

            let remainder = trimmed[scanner.currentIndex...].trimmingCharacters(in: .whitespaces)
            guard !remainder.isEmpty else { continue }

            let (startedAt, command) = splitDateAndCommand(from: remainder)
            guard isCodexCommand(command) else { continue }

            results.append((pid: pid, command: command, startedAt: startedAt))
        }

        return results
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

    public static func isCodexCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Filter out false positives
        let lower = trimmed.lowercased()
        if lower.contains("grep") ||
           lower.contains("agy") ||
           lower.contains("loom") ||
           lower.contains("swiftc") ||
           lower.contains("xcodebuild") ||
           lower.contains("DerivedData") {
            return false
        }

        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let executable = parts.first else { return false }

        let executableName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()

        // 1. Direct codex binary
        if executableName == "codex" || executableName == "codex-cli" {
            return true
        }

        // 2. Node/Deno/Bun executing codex script
        if executableName == "node" || executableName == "deno" || executableName == "bun" {
            for arg in parts.dropFirst() {
                let argName = URL(fileURLWithPath: arg).lastPathComponent.lowercased()
                if argName == "codex" || argName == "codex.js" || argName == "codex-cli" {
                    return true
                }
            }
        }

        return false
    }

    public static func parseLsofCwdOutput(_ output: String) -> URL? {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("n/") {
                let path = String(trimmed.dropFirst())
                if !path.isEmpty {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return nil
    }
}
