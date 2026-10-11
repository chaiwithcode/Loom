//
//  WorkspaceResolver.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct ResolvedWorkspace: Hashable, Equatable, Sendable {
    public let projectName: String
    public let projectPath: URL?
    public let branch: String?
    public let sourceDescription: String

    public init(
        projectName: String,
        projectPath: URL? = nil,
        branch: String? = nil,
        sourceDescription: String = "unknown"
    ) {
        self.projectName = projectName
        self.projectPath = projectPath
        self.branch = branch
        self.sourceDescription = sourceDescription
    }
}

public enum WorkspaceEvidenceSource: String, Sendable, Equatable {
    case codexStateDatabase = "codex-state-database"
    case chatgptProjectMapping = "chatgpt-project-mapping"
    case explicitCommandLine = "command-line"
    case processCWD = "process-cwd"
    case parentProcessCWD = "parent-process-cwd"
    case gitRepository = "git"
    case fallback = "fallback"
}

public struct WorkspaceEvidence: Sendable, Equatable {
    public let path: URL?
    public let projectName: String?
    public let branch: String?
    public let source: WorkspaceEvidenceSource
    public let confidence: Confidence

    public enum Confidence: Int, Comparable, Sendable {
        case low = 1
        case medium = 2
        case high = 3
        case authoritative = 4

        public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public init(
        path: URL? = nil,
        projectName: String? = nil,
        branch: String? = nil,
        source: WorkspaceEvidenceSource,
        confidence: Confidence
    ) {
        self.path = path
        self.projectName = projectName
        self.branch = branch
        self.source = source
        self.confidence = confidence
    }
}

public protocol WorkspaceEvidenceProvider: Sendable {
    func provideEvidence(for process: AgentProcess, parent: AgentProcess?) async -> [WorkspaceEvidence]
}

public protocol WorkspaceResolving: Sendable {
    func resolveWorkspace(
        for process: AgentProcess,
        parent: AgentProcess?,
        explicitMetadataURL: URL?
    ) async -> ResolvedWorkspace
}

public final class DefaultWorkspaceResolver: WorkspaceResolving, Sendable {
    private let gitResolver: any GitRepositoryResolving
    private let fileSystem: any FileSystemInspecting
    private let homeDirectory: URL
    private let evidenceProviders: [any WorkspaceEvidenceProvider]

    public init(
        gitResolver: any GitRepositoryResolving = DefaultGitRepositoryResolver(),
        fileSystem: any FileSystemInspecting = DefaultFileSystemInspector(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        evidenceProviders: [any WorkspaceEvidenceProvider] = []
    ) {
        self.gitResolver = gitResolver
        self.fileSystem = fileSystem
        self.homeDirectory = homeDirectory
        self.evidenceProviders = evidenceProviders
    }

    public func resolveWorkspace(
        for process: AgentProcess,
        parent: AgentProcess? = nil,
        explicitMetadataURL: URL? = nil
    ) async -> ResolvedWorkspace {
        // Collect evidence from external evidence providers (e.g. Codex SQLite state DB)
        var gatheredEvidence: [WorkspaceEvidence] = []
        for provider in evidenceProviders {
            let ev = await provider.provideEvidence(for: process, parent: parent)
            gatheredEvidence.append(contentsOf: ev)
        }
        gatheredEvidence.sort { $0.confidence > $1.confidence }

        // Tier 1: Authoritative or High confidence evidence from providers
        if let topEvidence = gatheredEvidence.first(where: { $0.confidence >= .high }) {
            return await resolveFromEvidence(topEvidence, fallbackProcess: process)
        }

        // Tier 2: Explicit provider metadata URL
        if let metaURL = explicitMetadataURL, metaURL.path != "/" {
            return await resolveFromURL(metaURL, source: "provider-metadata")
        }

        // Tier 3: Extract from command line flags
        if let extractedURL = extractWorkspaceURL(from: process.commandLine) {
            return await resolveFromURL(extractedURL, source: "command-line")
        }

        // Tier 4: Process CWD
        if let cwd = process.workingDirectory, cwd.path != "/" {
            return await resolveFromURL(cwd, source: "process-cwd")
        }

        // Tier 5: Parent process command line or CWD
        if let parent = parent {
            if let parentExtracted = extractWorkspaceURL(from: parent.commandLine) {
                return await resolveFromURL(parentExtracted, source: "parent-command-line")
            }
            if let parentCWD = parent.workingDirectory, parentCWD.path != "/" {
                return await resolveFromURL(parentCWD, source: "parent-cwd")
            }
        }

        // Tier 6: Medium or Low confidence evidence from providers
        if let fallbackEvidence = gatheredEvidence.first {
            return await resolveFromEvidence(fallbackEvidence, fallbackProcess: process)
        }

        // Fallback when no workspace directory could be found
        let defaultName: String
        switch process.provider {
        case .codex: defaultName = "Codex Session"
        case .antigravity: defaultName = "Antigravity Session"
        case .claude: defaultName = "Claude Session"
        default: defaultName = "Agent Session"
        }

        return ResolvedWorkspace(
            projectName: defaultName,
            projectPath: nil,
            branch: nil,
            sourceDescription: "fallback"
        )
    }

    private func resolveFromEvidence(
        _ evidence: WorkspaceEvidence,
        fallbackProcess: AgentProcess
    ) async -> ResolvedWorkspace {
        let candidatePath = evidence.path?.standardizedFileURL
        let candidateName = evidence.projectName

        // If path is provided, try to resolve git details or real repository
        if let path = candidatePath {
            // Check if path is in a ChatGPT sandbox mirror
            if path.path.contains(".chatgpt-projects") {
                let name = candidateName ?? resolveHumanProjectName(from: path) ?? path.lastPathComponent
                let resolvedLocalPath = resolveLocalRepositoryFromMirror(path, projectName: name) ?? path

                if let gitInfo = await gitResolver.resolveRepository(for: resolvedLocalPath) {
                    return ResolvedWorkspace(
                        projectName: candidateName ?? gitInfo.projectName,
                        projectPath: gitInfo.rootURL.standardizedFileURL,
                        branch: evidence.branch ?? gitInfo.branch,
                        sourceDescription: "\(evidence.source.rawValue)+git"
                    )
                }

                return ResolvedWorkspace(
                    projectName: name,
                    projectPath: resolvedLocalPath,
                    branch: evidence.branch,
                    sourceDescription: evidence.source.rawValue
                )
            }

            // Normal path
            if let gitInfo = await gitResolver.resolveRepository(for: path) {
                return ResolvedWorkspace(
                    projectName: candidateName ?? gitInfo.projectName,
                    projectPath: gitInfo.rootURL.standardizedFileURL,
                    branch: evidence.branch ?? gitInfo.branch,
                    sourceDescription: "\(evidence.source.rawValue)+git"
                )
            }

            return ResolvedWorkspace(
                projectName: candidateName ?? path.lastPathComponent,
                projectPath: path,
                branch: evidence.branch,
                sourceDescription: evidence.source.rawValue
            )
        }

        // Name only (no path)
        if let name = candidateName, !name.isEmpty {
            return ResolvedWorkspace(
                projectName: name,
                projectPath: nil,
                branch: evidence.branch,
                sourceDescription: evidence.source.rawValue
            )
        }

        let fallbackName = "\(fallbackProcess.provider.rawValue.capitalized) Session"
        return ResolvedWorkspace(
            projectName: fallbackName,
            projectPath: nil,
            branch: evidence.branch,
            sourceDescription: evidence.source.rawValue
        )
    }

    private func resolveFromURL(_ url: URL, source: String) async -> ResolvedWorkspace {
        let standardized = url.standardizedFileURL

        // 1. Try Git repository resolution
        if let gitInfo = await gitResolver.resolveRepository(for: standardized) {
            return ResolvedWorkspace(
                projectName: gitInfo.projectName,
                projectPath: gitInfo.rootURL.standardizedFileURL,
                branch: gitInfo.branch,
                sourceDescription: "\(source)+git"
            )
        }

        // 2. Try project metadata file resolution (AGENTS.md mirror notice, global state, etc.)
        if let namedFromMetadata = resolveHumanProjectName(from: standardized) {
            let recoveredPath = resolveLocalRepositoryFromMirror(standardized, projectName: namedFromMetadata) ?? standardized
            let gitInfo = await gitResolver.resolveRepository(for: recoveredPath)

            return ResolvedWorkspace(
                projectName: namedFromMetadata,
                projectPath: gitInfo?.rootURL.standardizedFileURL ?? recoveredPath,
                branch: gitInfo?.branch,
                sourceDescription: "\(source)+project-metadata"
            )
        }

        // 3. Normal directory name
        let last = standardized.lastPathComponent
        let name = (last.isEmpty || last == "/") ? "Project" : last

        return ResolvedWorkspace(
            projectName: name,
            projectPath: standardized,
            branch: nil,
            sourceDescription: source
        )
    }

    /// Attempts to locate the real local Git repository on disk if directory is a mirror.
    private func resolveLocalRepositoryFromMirror(_ directoryURL: URL, projectName: String? = nil) -> URL? {
        // 1. Inspect AGENTS.md, PLAN.md, README.md inside the mirror directory for "Repository: /path"
        let candidateFiles = ["AGENTS.md", "PLAN.md", "README.md"]
        for file in candidateFiles {
            let filePath = directoryURL.appendingPathComponent(file).path
            if let content = try? fileSystem.readFile(atPath: filePath) {
                if let repoPath = extractRepositoryPath(from: content) {
                    let url = URL(fileURLWithPath: repoPath).standardizedFileURL
                    if fileSystem.fileExists(atPath: url.path, isDirectory: nil) {
                        return url
                    }
                }
            }
        }

        // 2. If projectName is known (e.g. "Naviik - SmartRemote"), look for matching local repository
        if let name = projectName, !name.isEmpty {
            let candidateNames = [
                name,
                name.components(separatedBy: " - ").last?.trimmingCharacters(in: .whitespaces),
                name.components(separatedBy: " - ").first?.trimmingCharacters(in: .whitespaces)
            ].compactMap { $0 }.filter { !$0.isEmpty }

            let baseProjects = [
                homeDirectory.appendingPathComponent("Desktop/Projects/indie"),
                homeDirectory.appendingPathComponent("Desktop/Projects/oss"),
                homeDirectory.appendingPathComponent("Desktop/Projects"),
                homeDirectory.appendingPathComponent("Projects")
            ]

            for base in baseProjects {
                for candidateName in candidateNames {
                    let candidateDir = base.appendingPathComponent(candidateName)
                    let gitDir = candidateDir.appendingPathComponent(".git")
                    if fileSystem.fileExists(atPath: gitDir.path, isDirectory: nil) {
                        return candidateDir.standardizedFileURL
                    }
                }
            }
        }

        return nil
    }

    private func extractRepositoryPath(from text: String) -> String? {
        let patterns = ["Repository:", "Repo:"]
        for prefix in patterns {
            if let range = text.range(of: prefix) {
                let remainder = text[range.upperBound...]
                let lines = remainder.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                        let expanded = (trimmed as NSString).expandingTildeInPath
                        let clean = expanded.components(separatedBy: .whitespaces).first ?? expanded
                        return clean
                    }
                }
            }
        }
        return nil
    }

    /// Attempts to extract a human project name from AGENTS.md or Codex state files
    /// when the directory is an opaque ID or sandboxed mirror.
    private func resolveHumanProjectName(from directoryURL: URL) -> String? {
        let dirPath = directoryURL.path

        // Check AGENTS.md in the directory
        let agentsPath = directoryURL.appendingPathComponent("AGENTS.md").path
        if let agentsContent = try? fileSystem.readFile(atPath: agentsPath) {
            // Check for mirror notice: "local mirror of the ChatGPT project “Naviik - SmartRemote”"
            if let name = extractProjectNameFromAgentsDoc(agentsContent) {
                return name
            }
        }

        // Check if path is inside .codex/.chatgpt-projects/g-p-...
        if dirPath.contains(".chatgpt-projects") {
            let projectID = directoryURL.lastPathComponent
            if projectID.hasPrefix("g-p-") {
                let globalStatePath = homeDirectory.appendingPathComponent(".codex/.codex-global-state.json").path
                if let stateContent = try? fileSystem.readFile(atPath: globalStatePath),
                   let name = extractProjectNameFromGlobalState(stateContent, projectID: projectID) {
                    return name
                }
            }
        }

        return nil
    }

    private func extractProjectNameFromAgentsDoc(_ text: String) -> String? {
        let quotes = [("“", "”"), ("\"", "\""), ("'", "'")]
        for (qOpen, qClose) in quotes {
            let needle = "ChatGPT project \(qOpen)"
            if let range = text.range(of: needle) {
                let remainder = text[range.upperBound...]
                if let endQuote = remainder.range(of: qClose) {
                    let candidate = String(remainder[..<endQuote.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !candidate.isEmpty {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private func extractProjectNameFromGlobalState(_ jsonString: String, projectID: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let localProjects = root["local-projects"] as? [String: Any],
              let projectInfo = localProjects[projectID] as? [String: Any],
              let name = projectInfo["name"] as? String else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Extracts a workspace path from command-line arguments.
    public func extractWorkspaceURL(from command: String) -> URL? {
        let flags = ["--working-dir", "--add-dir", "--cwd", "--cd", "-C"]

        for flag in flags {
            var searchRange = command.startIndex..<command.endIndex
            while let range = command.range(of: flag, range: searchRange) {
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
                            let pathToken = extractFirstArgument(from: String(valueSubstring))
                            if let url = resolveWorkspaceURL(from: pathToken) {
                                return url
                            }
                        } else if nextChar.isWhitespace {
                            let valueSubstring = command[after...]
                            let pathToken = extractFirstArgument(from: String(valueSubstring))
                            if let url = resolveWorkspaceURL(from: pathToken) {
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

        // Also check positional directory arguments after subcommands or script targets
        let parts = command.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for (idx, part) in parts.enumerated() {
            if (part == "sandbox" || part == "exec" || part.hasSuffix(".js")) && idx + 1 < parts.count {
                for nextIdx in (idx + 1)..<parts.count {
                    let candidate = parts[nextIdx]
                    if candidate.hasPrefix("-") { continue }
                    if candidate.hasPrefix("/") || candidate.hasPrefix("~") {
                        if let url = resolveWorkspaceURL(from: candidate) {
                            return url
                        }
                    }
                    break
                }
            }
        }

        return nil
    }

    private func resolveWorkspaceURL(from pathToken: String) -> URL? {
        let trimmed = pathToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != "/" else { return nil }

        if trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            if expanded != "/" && (expanded as NSString).isAbsolutePath {
                return URL(fileURLWithPath: expanded).standardizedFileURL
            }
            return nil
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        return nil
    }

    private func extractFirstArgument(from string: String) -> String {
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
}
