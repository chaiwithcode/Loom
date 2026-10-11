//
//  ClaudeTranscriptInspector.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public protocol ClaudeTranscriptInspecting: Sendable {
    func findTranscripts(for cwd: URL) async -> [ClaudeTranscriptInfo]
    func inspectTranscriptTail(at url: URL) async -> ClaudeTranscriptTail?
    func findOpenTranscript(for pid: pid_t) async -> ClaudeTranscriptInfo?
}

public final class DefaultClaudeTranscriptInspector: ClaudeTranscriptInspecting, Sendable {
    private let homeDirectory: URL
    private let candidateDirectoriesProvider: (@Sendable (URL) -> [URL])?
    private let executor: any ProcessExecuting
    private let lsofPath: String

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        candidateDirectoriesProvider: (@Sendable (URL) -> [URL])? = nil,
        executor: any ProcessExecuting = DefaultProcessExecutor(),
        lsofPath: String = "/usr/sbin/lsof"
    ) {
        self.homeDirectory = homeDirectory
        self.candidateDirectoriesProvider = candidateDirectoriesProvider
        self.executor = executor
        self.lsofPath = lsofPath
    }

    public func findTranscripts(for cwd: URL) async -> [ClaudeTranscriptInfo] {
        let customDirs = candidateDirectoriesProvider?(cwd)
        return await Task.detached { [homeDirectory, customDirs] in
            ClaudeParser.findTranscripts(
                for: cwd.path,
                candidateDirectories: customDirs,
                homeDirectory: homeDirectory,
                fileManager: .default
            )
        }.value
    }

    public func inspectTranscriptTail(at url: URL) async -> ClaudeTranscriptTail? {
        await Task.detached {
            ClaudeParser.inspectTranscriptTail(at: url)
        }.value
    }

    public func findOpenTranscript(for pid: pid_t) async -> ClaudeTranscriptInfo? {
        guard let lsofOutput = try? await executor.execute(
            executablePath: lsofPath,
            arguments: ["-a", "-p", "\(pid)", "-Fn"]
        ) else {
            return nil
        }

        let openURLs = ClaudeParser.parseLsofOpenTranscripts(lsofOutput)
        for url in openURLs {
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
               let size = values.fileSize, size > 0,
               let modDate = values.contentModificationDate {
                let sessionID = url.deletingPathExtension().lastPathComponent
                return ClaudeTranscriptInfo(url: url, sessionID: sessionID, modifiedAt: modDate)
            }
        }
        return nil
    }
}
