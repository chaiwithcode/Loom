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

        // 1. Match genuine node / deno / bun script execution
        if matchesNodeOrDenoOrBunScript(trimmed) {
            return true
        }

        // 2. Identify the command executable and its remainder arguments
        guard let (executable, remainder) = extractExecutableAndRemainder(trimmed) else {
            return false
        }

        // 3. Reject Chromium / Electron helper processes and non-user daemons by executable
        if isHelperExecutable(executable) {
            return false
        }

        // 4. Validate that the executable is genuinely a codex binary
        guard isValidCodexExecutable(executable) else {
            return false
        }

        // 5. Chromium helper flags check (defense in depth on top-level arguments)
        if hasChromiumHelperFlags(remainder: remainder) {
            return false
        }

        // 6. Distinguish app-server infrastructure from genuine user coding sessions
        if isAppServerInfrastructure(remainder: remainder) {
            return false
        }

        return true
    }

    private static func extractExecutableAndRemainder(_ command: String) -> (executable: String, remainder: String)? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Quoted executable at start: "path/to/exec" or 'path/to/exec'
        if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
            let quote = trimmed.first!
            let withoutQuote = trimmed.dropFirst()
            if let closingIndex = withoutQuote.firstIndex(of: quote) {
                let exec = String(withoutQuote[..<closingIndex])
                let afterQuote = withoutQuote.index(after: closingIndex)
                if afterQuote == withoutQuote.endIndex {
                    return (executable: exec, remainder: "")
                } else if withoutQuote[afterQuote] == " " || withoutQuote[afterQuote] == "\t" || withoutQuote[afterQuote] == "\n" {
                    let rem = String(withoutQuote[afterQuote...]).trimmingCharacters(in: .whitespaces)
                    return (executable: exec, remainder: rem)
                }
            }
            return nil
        }

        // 2. Direct simple invocation without path
        if trimmed == "codex" || trimmed == "codex-cli" {
            return (executable: trimmed, remainder: "")
        }
        if trimmed.hasPrefix("codex ") || trimmed.hasPrefix("codex\t") {
            let rem = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return (executable: "codex", remainder: rem)
        }
        if trimmed.hasPrefix("codex-cli ") || trimmed.hasPrefix("codex-cli\t") {
            let rem = String(trimmed.dropFirst(10)).trimmingCharacters(in: .whitespaces)
            return (executable: "codex-cli", remainder: rem)
        }

        // 3. macOS App Bundle executables: Contents/MacOS/<binary>
        if let macOSRng = trimmed.range(of: "Contents/MacOS/", options: .backwards) {
            let afterMacOS = trimmed[macOSRng.upperBound...]
            let binaryAndArgs = String(afterMacOS).trimmingCharacters(in: .whitespaces)
            let binaryTokens = binaryAndArgs.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let firstBinaryToken = binaryTokens.first {
                let lowerToken = firstBinaryToken.lowercased()
                if lowerToken == "codex" || lowerToken == "codex-cli" {
                    let execPath = String(trimmed[..<macOSRng.upperBound]) + firstBinaryToken
                    let rem = binaryTokens.dropFirst().joined(separator: " ")
                    return (executable: execPath, remainder: rem)
                } else {
                    let rem = binaryTokens.dropFirst().joined(separator: " ")
                    return (executable: String(trimmed[..<macOSRng.upperBound]) + firstBinaryToken, remainder: rem)
                }
            }
        }

        // 4. Unquoted executable path
        let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let firstToken = tokens.first else { return nil }

        // If the path might contain spaces (e.g. "/Applications/Codex Tools/bin/codex resume"),
        // collect candidate tokens until an argument boundary is hit.
        // A path continuation token cannot start with '/', '-', '"', or '\''.
        // Check for the longest candidate path ending in "codex" or "codex-cli".
        var candidateTokens: [String] = [firstToken]
        var bestCodexMatch: (executable: String, remainder: String)? = nil

        let firstLastComp = URL(fileURLWithPath: firstToken).lastPathComponent.lowercased()
        if (firstLastComp == "codex" || firstLastComp == "codex-cli") && isValidCodexExecutable(firstToken) {
            let rem = tokens.dropFirst().joined(separator: " ")
            bestCodexMatch = (executable: firstToken, remainder: rem)
        }

        for (index, token) in tokens.dropFirst().enumerated() {
            if token.hasPrefix("/") || token.hasPrefix("-") || token.hasPrefix("\"") || token.hasPrefix("'") {
                break
            }
            let lower = token.lowercased()
            if lower == "resume" || lower == "exec" || lower == "sandbox" ||
               lower == "app-server" || lower == "exec-server" {
                break
            }

            candidateTokens.append(token)
            let candidatePath = candidateTokens.joined(separator: " ")
            let lastComp = URL(fileURLWithPath: candidatePath).lastPathComponent.lowercased()
            if (lastComp == "codex" || lastComp == "codex-cli") && isValidCodexExecutable(candidatePath) {
                let remTokens = tokens.dropFirst(index + 2)
                let rem = remTokens.joined(separator: " ")
                bestCodexMatch = (executable: candidatePath, remainder: rem)
            }
        }

        if let match = bestCodexMatch {
            return match
        }

        // If not a recognized codex executable, treat firstToken as the executable
        let rem = tokens.dropFirst().joined(separator: " ")
        return (executable: firstToken, remainder: rem)
    }

    private static func isHelperExecutable(_ executable: String) -> Bool {
        let clean = executable.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let lower = clean.lowercased()

        if lower.contains("helper.app") ||
           lower.contains("helpers/") ||
           lower.contains("helper (") ||
           lower.contains("framework.framework") ||
           lower.contains("sparkle.framework") ||
           lower.contains("crashpad_handler") ||
           lower.contains("skycomputeruseservice") ||
           lower.contains("bare-modifier-monitor") ||
           lower.contains("autoupdate") {
            return true
        }

        let last = URL(fileURLWithPath: clean).lastPathComponent.lowercased()
        if last.contains("helper") ||
           last.contains("(renderer)") ||
           last.contains("(service)") ||
           last.contains("(gpu)") {
            return true
        }

        return false
    }

    private static func isValidCodexExecutable(_ path: String) -> Bool {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if isHelperExecutable(clean) {
            return false
        }
        let last = URL(fileURLWithPath: clean).lastPathComponent.lowercased()
        return last == "codex" || last == "codex-cli"
    }

    private static func hasChromiumHelperFlags(remainder: String) -> Bool {
        let tokens = commandRoleTokens(remainder)
        for token in tokens {
            if token == "--type=renderer" ||
               token == "--type=utility" ||
               token == "--type=gpu-process" ||
               token == "--type=crashpad-handler" ||
               token == "--type=zygote" {
                return true
            }
        }
        return false
    }

    private static func isAppServerInfrastructure(remainder: String) -> Bool {
        commandRoleTokens(remainder).contains { token in
            let option = String(token.split(separator: "=", maxSplits: 1).first ?? "")
            return token == "app-server" || token == "exec-server" ||
                option == "--code-mode-host" || option == "--managed-daemon"
        }
    }

    private static func commandRoleTokens(_ remainder: String) -> [String] {
        // Only global options and the first subcommand describe the process's role.
        // Everything after a user subcommand or the first prompt word is user input.
        let valueOptions: Set<String> = [
            "-c", "--config", "-m", "--model", "-p", "--profile",
            "-s", "--sandbox", "-a", "--ask-for-approval", "-C", "--cd",
            "--working-dir", "--cwd", "--add-dir", "--enable", "--disable",
            "-i", "--image", "--prompt"
        ]
        let tokens = commandArgumentTokens(remainder)
        var roleTokens: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "--" { break }
            roleTokens.append(token)
            if !token.hasPrefix("-") {
                break
            }
            let option = String(token.split(separator: "=", maxSplits: 1).first ?? "")
            if valueOptions.contains(option) && !token.contains("=") {
                index += 1
            }
            index += 1
        }
        return roleTokens
    }

    private static func commandArgumentTokens(_ arguments: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        var escaped = false
        for character in arguments {
            if escaped {
                token.append(character)
                escaped = false
            } else if character == "\\" && quote != "'" {
                token.append(character)
                escaped = true
            } else if let activeQuote = quote {
                token.append(character)
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                token.append(character)
                quote = character
            } else if character.isWhitespace {
                if !token.isEmpty { tokens.append(token); token = "" }
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty { tokens.append(token) }
        return tokens
    }

    private static func matchesNodeOrDenoOrBunScript(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let first = parts.first else { return false }

        let firstClean = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let firstBinary = URL(fileURLWithPath: firstClean).lastPathComponent.lowercased()

        guard firstBinary == "node" || firstBinary == "deno" || firstBinary == "bun" else {
            return false
        }

        // Search the remaining command for a codex script target
        let scriptNames = ["codex.js", "codex", "codex-cli"]
        for arg in parts.dropFirst() {
            let argClean = arg.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if argClean.hasPrefix("-") {
                continue
            }
            let argLower = argClean.lowercased()
            let argName = URL(fileURLWithPath: argClean).lastPathComponent.lowercased()
            if scriptNames.contains(argName) {
                return true
            }

            // If an argument ends with a script extension (.js, .mjs, .cjs, .ts) and is not codex,
            // then it is a different script being executed by node/deno/bun.
            if argLower.hasSuffix(".js") || argLower.hasSuffix(".mjs") || argLower.hasSuffix(".cjs") || argLower.hasSuffix(".ts") {
                return false
            }
        }

        return false
    }

    /// Attempts to extract a workspace directory from command flags like `--working-dir`, `-C`, `--cwd`, `--cd`.
    public static func extractWorkspaceDirectory(from command: String, relativeTo baseURL: URL? = nil) -> URL? {
        let flags = ["--working-dir", "--cwd", "--cd", "-C"]

        for flag in flags {
            var searchRange = command.startIndex..<command.endIndex
            while let range = command.range(of: flag, range: searchRange) {
                // 1. Verify leading token boundary:
                // Preceding character must be start-of-command, whitespace, or quote
                let isLeadingBoundary: Bool
                if range.lowerBound == command.startIndex {
                    isLeadingBoundary = true
                } else {
                    let prevChar = command[command.index(before: range.lowerBound)]
                    isLeadingBoundary = (prevChar == " " || prevChar == "\t" || prevChar == "\n" || prevChar == "\"" || prevChar == "'")
                }

                if isLeadingBoundary {
                    let after = range.upperBound
                    if after < command.endIndex {
                        let nextChar = command[after]
                        if nextChar == "=" {
                            // flag=value
                            let valueSubstring = command[command.index(after: after)...]
                            let pathToken = extractFirstArgument(from: String(valueSubstring))
                            if let url = resolveWorkspaceURL(from: pathToken, relativeTo: baseURL) {
                                return url
                            }
                        } else if nextChar == " " || nextChar == "\t" {
                            // flag value
                            let valueSubstring = command[after...]
                            let pathToken = extractFirstArgument(from: String(valueSubstring))
                            if let url = resolveWorkspaceURL(from: pathToken, relativeTo: baseURL) {
                                return url
                            }
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

    private static func resolveWorkspaceURL(from pathToken: String, relativeTo baseURL: URL?) -> URL? {
        let trimmed = pathToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != "/" else { return nil }

        if trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            if expanded != "/" && (expanded as NSString).isAbsolutePath {
                return URL(fileURLWithPath: expanded)
            }
            return nil
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }

        // Relative path: only resolve if an explicit non-root absolute baseURL is provided.
        // Never resolve relative paths against Loom's process cwd.
        if let baseURL = baseURL, baseURL.path != "/", (baseURL.path as NSString).isAbsolutePath {
            let resolved = URL(fileURLWithPath: trimmed, relativeTo: baseURL).standardizedFileURL
            if resolved.path != "/" {
                return resolved
            }
        }

        return nil
    }

    private static func extractFirstArgument(from string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("\"") {
            let withoutLeading = trimmed.dropFirst()
            if let endQuote = withoutLeading.firstIndex(of: "\"") {
                return String(withoutLeading[..<endQuote])
            }
        } else if trimmed.hasPrefix("'") {
            let withoutLeading = trimmed.dropFirst()
            if let endQuote = withoutLeading.firstIndex(of: "'") {
                return String(withoutLeading[..<endQuote])
            }
        }

        return trimmed.components(separatedBy: .whitespaces).first ?? ""
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
