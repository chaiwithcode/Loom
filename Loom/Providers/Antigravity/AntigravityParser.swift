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
            return .idle
        default:
            return .unknown
        }
    }

    public static func isAntigravityProcessCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()

        // Filter out false positives
        if lower.contains("grep") ||
           lower.contains("loom") ||
           lower.contains("swiftc") ||
           lower.contains("xcodebuild") ||
           lower.contains("deriveddata") {
            return false
        }

        // 1. Antigravity Desktop App
        if lower.contains("/antigravity.app/contents/macos/antigravity") ||
           lower.contains("antigravity helper") {
            return true
        }

        // 2. Language Server with Antigravity parameters
        if lower.contains("language_server") &&
           (lower.contains("antigravity") || lower.contains("--subclient_type hub")) {
            return true
        }

        // 3. Antigravity CLI binary
        if lower.contains("/agy") || lower.contains("bin/agy") || trimmed.hasPrefix("agy ") {
            return true
        }

        return false
    }
}
