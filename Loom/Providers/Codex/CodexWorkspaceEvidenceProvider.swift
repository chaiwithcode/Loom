//
//  CodexWorkspaceEvidenceProvider.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public final class CodexWorkspaceEvidenceProvider: WorkspaceEvidenceProvider, Sendable {
    private let stateInspector: any CodexStateStoreInspecting
    private let fileSystem: any FileSystemInspecting

    public init(
        stateInspector: any CodexStateStoreInspecting = DefaultCodexStateStoreInspector(),
        fileSystem: any FileSystemInspecting = DefaultFileSystemInspector()
    ) {
        self.stateInspector = stateInspector
        self.fileSystem = fileSystem
    }

    public func provideEvidence(
        for process: AgentProcess,
        parent: AgentProcess?
    ) async -> [WorkspaceEvidence] {
        guard process.provider == .codex else { return [] }

        var evidence: [WorkspaceEvidence] = []

        // 1. Session ID token lookup from threads table (Authoritative)
        if let token = process.sessionIDToken, !token.isEmpty {
            if let meta = await stateInspector.sessionMetadata(for: token) {
                var projectName = meta.projectName
                if projectName == nil || projectName?.isEmpty == true {
                    if let cwd = meta.workingDirectory {
                        projectName = await stateInspector.projectName(forPath: cwd)
                    }
                }

                evidence.append(WorkspaceEvidence(
                    path: meta.workingDirectory,
                    projectName: projectName ?? meta.title,
                    branch: meta.gitBranch,
                    source: .codexStateDatabase,
                    confidence: .authoritative
                ))
            }
        }

        // 2. Process working directory matched against project roots (High confidence)
        if let cwd = process.workingDirectory, cwd.path != "/" {
            if let name = await stateInspector.projectName(forPath: cwd) {
                evidence.append(WorkspaceEvidence(
                    path: cwd,
                    projectName: name,
                    branch: nil,
                    source: .codexStateDatabase,
                    confidence: .high
                ))
            }
        }

        // 3. Command-line flags matched against project roots
        if let cmdURL = extractWorkspaceURL(from: process.commandLine) {
            if let name = await stateInspector.projectName(forPath: cmdURL) {
                evidence.append(WorkspaceEvidence(
                    path: cmdURL,
                    projectName: name,
                    branch: nil,
                    source: .codexStateDatabase,
                    confidence: .high
                ))
            }
        }

        // 4. Parent process checks if child process has no explicit metadata
        if let parent = parent {
            if let parentToken = parent.sessionIDToken, !parentToken.isEmpty {
                if let meta = await stateInspector.sessionMetadata(for: parentToken) {
                    evidence.append(WorkspaceEvidence(
                        path: meta.workingDirectory,
                        projectName: meta.projectName ?? meta.title,
                        branch: meta.gitBranch,
                        source: .codexStateDatabase,
                        confidence: .medium
                    ))
                }
            }

            if let parentCWD = parent.workingDirectory, parentCWD.path != "/" {
                if let name = await stateInspector.projectName(forPath: parentCWD) {
                    evidence.append(WorkspaceEvidence(
                        path: parentCWD,
                        projectName: name,
                        branch: nil,
                        source: .codexStateDatabase,
                        confidence: .medium
                    ))
                }
            }
        }

        return evidence
    }

    private func extractWorkspaceURL(from command: String) -> URL? {
        let flags = ["--working-dir", "--add-dir", "--cwd", "--cd", "-C"]

        for flag in flags {
            var searchRange = command.startIndex..<command.endIndex
            while let range = command.range(of: flag, range: searchRange) {
                let isLeadingBoundary = range.lowerBound == command.startIndex ||
                    command[command.index(before: range.lowerBound)].isWhitespace ||
                    command[command.index(before: range.lowerBound)] == "\"" ||
                    command[command.index(before: range.lowerBound)] == "'"

                if isLeadingBoundary {
                    let afterFlag = command[range.upperBound...]
                    let trimmed = afterFlag.trimmingCharacters(in: .whitespaces)

                    var candidate: String?
                    if trimmed.hasPrefix("=") {
                        let afterEquals = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                        candidate = parsePathToken(String(afterEquals))
                    } else if !trimmed.isEmpty {
                        candidate = parsePathToken(trimmed)
                    }

                    if let path = candidate, !path.isEmpty {
                        let expanded = (path as NSString).expandingTildeInPath
                        return URL(fileURLWithPath: expanded).standardizedFileURL
                    }
                }
                searchRange = range.upperBound..<command.endIndex
            }
        }
        return nil
    }

    private func parsePathToken(_ string: String) -> String {
        if string.hasPrefix("\"") {
            let withoutLeading = string.dropFirst()
            if let closingQuote = withoutLeading.firstIndex(of: "\"") {
                return String(withoutLeading[..<closingQuote])
            }
        } else if string.hasPrefix("'") {
            let withoutLeading = string.dropFirst()
            if let closingQuote = withoutLeading.firstIndex(of: "'") {
                return String(withoutLeading[..<closingQuote])
            }
        }
        return string.components(separatedBy: .whitespaces).first ?? string
    }
}
