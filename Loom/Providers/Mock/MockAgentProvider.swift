//
//  MockAgentProvider.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
import os

public enum MockProviderError: LocalizedError, Sendable {
    case daemonUnavailable(String)
    case sessionCorrupt(String)

    public var errorDescription: String? {
        switch self {
        case .daemonUnavailable(let msg):
            return msg
        case .sessionCorrupt(let msg):
            return msg
        }
    }
}

public final class MockAgentProvider: AgentProvider, Sendable {
    public let id: ProviderID
    public let displayName: String

    private struct State: Sendable {
        var availability: ProviderAvailability
        var sessions: [AgentSession]
        var usage: ProviderUsageSnapshot?
        var error: (any Error)?
        var delayNanoseconds: UInt64
        var discoverCallCount: Int = 0
    }

    private let stateLock: OSAllocatedUnfairLock<State>

    public init(
        id: ProviderID,
        displayName: String,
        availability: ProviderAvailability = .available,
        sessions: [AgentSession] = [],
        usage: ProviderUsageSnapshot? = nil,
        error: (any Error)? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.stateLock = OSAllocatedUnfairLock(initialState: State(
            availability: availability,
            sessions: sessions,
            usage: usage,
            error: error,
            delayNanoseconds: delayNanoseconds,
            discoverCallCount: 0
        ))
    }

    public var discoverCallCount: Int {
        stateLock.withLock { $0.discoverCallCount }
    }

    public func setSessions(_ sessions: [AgentSession]) {
        stateLock.withLock { $0.sessions = sessions }
    }

    public func setAvailability(_ availability: ProviderAvailability) {
        stateLock.withLock { $0.availability = availability }
    }

    public func setError(_ error: (any Error)?) {
        stateLock.withLock { $0.error = error }
    }

    public func setDelayNanoseconds(_ delay: UInt64) {
        stateLock.withLock { $0.delayNanoseconds = delay }
    }

    public func availability() async -> ProviderAvailability {
        let (delay, avail) = stateLock.withLock { ($0.delayNanoseconds, $0.availability) }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return avail
    }

    public func discoverSessions() async throws -> [AgentSession] {
        let (delay, err, sessions) = stateLock.withLock { state -> (UInt64, (any Error)?, [AgentSession]) in
            state.discoverCallCount += 1
            return (state.delayNanoseconds, state.error, state.sessions)
        }

        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }

        if let err {
            throw err
        }
        return sessions
    }

    public func setUsage(_ usage: ProviderUsageSnapshot?) {
        stateLock.withLock { $0.usage = usage }
    }

    public func fetchUsage() async throws -> ProviderUsageSnapshot? {
        let (delay, err, usage) = stateLock.withLock { ($0.delayNanoseconds, $0.error, $0.usage) }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        if let err {
            throw err
        }
        return usage
    }
}

extension MockAgentProvider {
    public static func createDefaultProviders(referenceDate: Date = Date()) -> [MockAgentProvider] {
        // Codex mock: .working and .idle
        let codexSessions = [
            AgentSession(
                id: "codex-session-1",
                provider: .codex,
                projectName: "XKit",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/XKit"),
                state: .working,
                startedAt: referenceDate.addingTimeInterval(-900), // 15m ago
                lastActivityAt: referenceDate.addingTimeInterval(-480), // 8m ago
                branch: "main",
                summary: "Refactoring authentication middleware"
            ),
            AgentSession(
                id: "codex-session-2",
                provider: .codex,
                projectName: "DevPortal",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/DevPortal"),
                state: .idle,
                startedAt: referenceDate.addingTimeInterval(-7200), // 2h ago
                lastActivityAt: referenceDate.addingTimeInterval(-2700), // 45m ago
                branch: "feature/api",
                summary: "Awaiting next user prompt"
            ),
            AgentSession(
                id: "codex-session-3",
                provider: .codex,
                projectName: "CoreEngine",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/CoreEngine"),
                state: .starting,
                startedAt: referenceDate.addingTimeInterval(-60),
                lastActivityAt: referenceDate.addingTimeInterval(-30),
                branch: "main",
                summary: "Initializing session"
            )
        ]

        let codexUsage = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: referenceDate,
            planType: "plus",
            primaryBucket: UsageBucket(
                identifier: "codex-primary",
                label: "5h Window",
                usedFraction: 0.08,
                resetsAt: referenceDate.addingTimeInterval(14400),
                windowDurationMins: 300
            ),
            secondaryBucket: UsageBucket(
                identifier: "codex-secondary",
                label: "Weekly Window",
                usedFraction: 0.33,
                resetsAt: referenceDate.addingTimeInterval(518400),
                windowDurationMins: 10080
            ),
            additionalGroups: [],
            isStale: false,
            errorMessage: nil
        )

        let codex = MockAgentProvider(
            id: .codex,
            displayName: "Codex (Mock)",
            availability: .available,
            sessions: codexSessions,
            usage: codexUsage
        )

        // Claude mock: .waiting, .failed, and .offline
        let claudeSessions = [
            AgentSession(
                id: "claude-session-1",
                provider: .claude,
                projectName: "SmartRemote",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/SmartRemote"),
                state: .waiting,
                startedAt: referenceDate.addingTimeInterval(-2100), // 35m ago
                lastActivityAt: referenceDate.addingTimeInterval(-120), // 2m ago
                branch: "fix/pairing",
                summary: "Waiting for confirmation: npm test"
            ),
            AgentSession(
                id: "claude-session-2",
                provider: .claude,
                projectName: "Loom",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Loom"),
                state: .failed,
                startedAt: referenceDate.addingTimeInterval(-3600), // 1h ago
                lastActivityAt: referenceDate.addingTimeInterval(-720), // 12m ago
                branch: "v0-kickoff",
                summary: "Build failed: undefined symbol in parser"
            ),
            AgentSession(
                id: "claude-session-3",
                provider: .claude,
                projectName: "IdleService",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/IdleService"),
                state: .idle,
                startedAt: referenceDate.addingTimeInterval(-7200),
                lastActivityAt: referenceDate.addingTimeInterval(-3600),
                branch: "main",
                summary: "Service daemon idle"
            )
        ]

        let claude = MockAgentProvider(
            id: .claude,
            displayName: "Claude Code (Mock)",
            availability: .available,
            sessions: claudeSessions
        )

        // Antigravity mock: .finished, .unknown, and .failed
        let antigravitySessions = [
            AgentSession(
                id: "antigravity-session-1",
                provider: .antigravity,
                projectName: "Experiment",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/Experiment"),
                state: .finished,
                startedAt: referenceDate.addingTimeInterval(-3000), // 50m ago
                lastActivityAt: referenceDate.addingTimeInterval(-300), // 5m ago
                branch: "prototype-v2",
                summary: "Completed test suite optimization"
            ),
            AgentSession(
                id: "antigravity-session-2",
                provider: .antigravity,
                projectName: "KernelMod",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/KernelMod"),
                state: .unknown,
                startedAt: referenceDate.addingTimeInterval(-10800), // 3h ago
                lastActivityAt: referenceDate.addingTimeInterval(-1500), // 25m ago
                branch: "patch-1",
                summary: "Process detached without final status report"
            ),
            AgentSession(
                id: "antigravity-session-3",
                provider: .antigravity,
                projectName: "CrashProbe",
                projectPath: URL(fileURLWithPath: "/Users/developer/Desktop/Projects/oss/CrashProbe"),
                state: .failed,
                startedAt: referenceDate.addingTimeInterval(-1800),
                lastActivityAt: referenceDate.addingTimeInterval(-900),
                branch: "main",
                summary: "Fatal exception in runtime"
            )
        ]

        let antigravityUsage = ProviderUsageSnapshot(
            providerID: .antigravity,
            updatedAt: referenceDate,
            planType: nil,
            primaryBucket: UsageBucket(
                identifier: "gemini-5h",
                label: "Gemini 5h",
                usedFraction: 0.15,
                resetsAt: referenceDate.addingTimeInterval(8820),
                windowDurationMins: 300
            ),
            secondaryBucket: UsageBucket(
                identifier: "gemini-weekly",
                label: "Gemini Weekly",
                usedFraction: 0.13,
                resetsAt: referenceDate.addingTimeInterval(518400),
                windowDurationMins: 10080
            ),
            additionalGroups: [
                UsageGroup(
                    identifier: "claude-and-gpt",
                    label: "Claude & GPT",
                    buckets: [
                        UsageBucket(
                            identifier: "3p-5h",
                            label: "3P 5h",
                            usedFraction: 0.0,
                            resetsAt: referenceDate.addingTimeInterval(14400),
                            windowDurationMins: 300
                        )
                    ]
                )
            ],
            isStale: false,
            errorMessage: nil
        )

        let antigravity = MockAgentProvider(
            id: .antigravity,
            displayName: "Antigravity (Mock)",
            availability: .available,
            sessions: antigravitySessions,
            usage: antigravityUsage
        )

        return [codex, claude, antigravity]
    }

    public static func createEmptyProviders() -> [MockAgentProvider] {
        [
            MockAgentProvider(id: .codex, displayName: "Codex (Mock)", availability: .available, sessions: []),
            MockAgentProvider(id: .claude, displayName: "Claude Code (Mock)", availability: .available, sessions: []),
            MockAgentProvider(id: .antigravity, displayName: "Antigravity (Mock)", availability: .available, sessions: [])
        ]
    }

    public static func createFailureProviders() -> [MockAgentProvider] {
        [
            MockAgentProvider(
                id: .codex,
                displayName: "Codex (Mock)",
                availability: .available,
                sessions: [],
                error: MockProviderError.daemonUnavailable("Failed to connect to local Codex daemon on port 4512")
            ),
            MockAgentProvider(
                id: .claude,
                displayName: "Claude Code (Mock)",
                availability: .unavailable(reason: "Claude Code CLI not found in PATH"),
                sessions: []
            ),
            MockAgentProvider(
                id: .antigravity,
                displayName: "Antigravity (Mock)",
                availability: .available,
                sessions: [],
                error: MockProviderError.sessionCorrupt("Encountered corrupt state in ~/.gemini/antigravity-cli")
            )
        ]
    }
}

public enum DemoFixture: Sendable, Equatable {
    case standard
    case mock
    case empty
    case failure

    public var isDemo: Bool {
        self != .standard
    }

    public var badgeLabel: String? {
        switch self {
        case .standard:
            return nil
        case .mock:
            return "DEMO"
        case .empty:
            return "DEMO EMPTY"
        case .failure:
            return "DEMO FAIL"
        }
    }

    public static func resolve(from arguments: [String] = ProcessInfo.processInfo.arguments) -> DemoFixture {
        if arguments.contains("--demo-empty") {
            return .empty
        }
        if arguments.contains("--demo-failure") {
            return .failure
        }
        if arguments.contains("--demo-mock") {
            return .mock
        }
        return .standard
    }

    public func makeProviders() -> [any AgentProvider] {
        switch self {
        case .standard:
            return [CodexProvider(), ClaudeProvider(), AntigravityProvider()]
        case .mock:
            return MockAgentProvider.createDefaultProviders()
        case .empty:
            return MockAgentProvider.createEmptyProviders()
        case .failure:
            return MockAgentProvider.createFailureProviders()
        }
    }
}

