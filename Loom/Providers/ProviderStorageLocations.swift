//
//  ProviderStorageLocations.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct ProviderStorageLocations: Sendable, Identifiable {
    public let id: ProviderID
    public let name: String
    public let locations: [StorageLocation]

    /// Explicit data roots only. App bundles, repositories and unrelated Gemini data are excluded.
    public static func local(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             environment: [String: String] = ProcessInfo.processInfo.environment) -> [Self] {
        func root(_ path: String, _ label: String) -> StorageLocation {
            StorageLocation(label: label, url: home.appendingPathComponent(path, isDirectory: true))
        }
        let codexRoot = environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(".codex", isDirectory: true)
        let claudeRoot = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(".claude", isDirectory: true)
        return [
            Self(id: .codex, name: "Codex", locations: [
                StorageLocation(label: "CLI data", url: codexRoot),
                root("Library/Application Support/Codex", "Desktop data"),
                root("Library/Application Support/com.openai.codex", "Desktop support data"),
                root("Library/Caches/com.openai.codex", "Desktop cache")]),
            Self(id: .claude, name: "Claude Code", locations: [
                StorageLocation(label: "CLI data", url: claudeRoot),
                root("Library/Application Support/Claude/claude-code-sessions", "Desktop sessions"),
                root("Library/Application Support/Claude/local-agent-mode-sessions", "Local agent sessions")]),
            Self(id: .antigravity, name: "Antigravity", locations: [
                root(".antigravity", "Editor settings and extensions"),
                root(".gemini/antigravity", "Agent data"),
                root(".gemini/antigravity-cli", "CLI data"),
                root("Library/Application Support/Antigravity", "Desktop data"),
                root("Library/Caches/Antigravity", "Desktop cache"),
                root("Library/Caches/com.google.antigravity", "Application cache")])
        ]
    }
}
