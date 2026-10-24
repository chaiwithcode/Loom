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
        // Privacy-safe demo sessions; the app retains its visible DEMO marker.
        let codexSessions = [
            AgentSession(
                id: "demo-codex-sentinel",
                provider: .codex,
                projectName: "Sentinel",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/sentinel"),
                state: .unknown,
                startedAt: referenceDate.addingTimeInterval(-7200),
                lastActivityAt: referenceDate.addingTimeInterval(-1800),
                branch: "main",
                summary: "Worker process detached unexpectedly",
                pid: 41061,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41061,
                        parentPID: 41060,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/sentinel"),
                        startedAt: referenceDate.addingTimeInterval(-7200),
                        provider: .codex,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            ),
            AgentSession(
                id: "demo-codex-harbor",
                provider: .codex,
                projectName: "Harbor",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/harbor"),
                state: .waiting,
                startedAt: referenceDate.addingTimeInterval(-5400),
                lastActivityAt: referenceDate.addingTimeInterval(-45),
                branch: "fix/navigation",
                summary: "Approval needed to execute migration",
                pid: 41041,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41041,
                        parentPID: 41040,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/harbor"),
                        startedAt: referenceDate.addingTimeInterval(-5400),
                        provider: .codex,
                        hostApp: .xcode
                    )
                ],
                hostApp: .xcode
            ),
            AgentSession(
                id: "demo-codex-valkyrie",
                provider: .codex,
                projectName: "Valkyrie",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/valkyrie"),
                state: .waiting,
                startedAt: referenceDate.addingTimeInterval(-4200),
                lastActivityAt: referenceDate.addingTimeInterval(-60),
                branch: "chore/db-reset",
                summary: "Confirming destructive schema reset",
                pid: 41051,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41051,
                        parentPID: 41050,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/valkyrie"),
                        startedAt: referenceDate.addingTimeInterval(-4200),
                        provider: .codex,
                        hostApp: .vsCode
                    )
                ],
                hostApp: .vsCode
            ),
            AgentSession(
                id: "demo-codex-loom",
                provider: .codex,
                projectName: "Loom",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/loom"),
                state: .working,
                startedAt: referenceDate.addingTimeInterval(-900),
                lastActivityAt: referenceDate.addingTimeInterval(-8),
                branch: "feature/liquid-glass",
                summary: "Refining session cards",
                pid: 41001,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41001,
                        parentPID: 41000,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/loom"),
                        startedAt: referenceDate.addingTimeInterval(-900),
                        provider: .codex,
                        hostApp: .xcode
                    )
                ],
                hostApp: .xcode
            ),
            AgentSession(
                id: "demo-codex-helios",
                provider: .codex,
                projectName: "Helios",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/helios"),
                state: .working,
                startedAt: referenceDate.addingTimeInterval(-1800),
                lastActivityAt: referenceDate.addingTimeInterval(-15),
                branch: "feature/streaming",
                summary: "Generating streaming parser tests",
                pid: 41011,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41011,
                        parentPID: 41010,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/helios"),
                        startedAt: referenceDate.addingTimeInterval(-1800),
                        provider: .codex,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            ),
            AgentSession(
                id: "demo-codex-atlas-api",
                provider: .codex,
                projectName: "Atlas API",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/atlas-api"),
                state: .idle,
                startedAt: referenceDate.addingTimeInterval(-3600),
                lastActivityAt: referenceDate.addingTimeInterval(-240),
                branch: "feature/cache",
                summary: "Ready for the next prompt",
                pid: 41021,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41021,
                        parentPID: 41020,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/atlas-api"),
                        startedAt: referenceDate.addingTimeInterval(-3600),
                        provider: .codex,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            ),
            AgentSession(
                id: "demo-codex-chronos",
                provider: .codex,
                projectName: "Chronos",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/chronos"),
                state: .idle,
                startedAt: referenceDate.addingTimeInterval(-5000),
                lastActivityAt: referenceDate.addingTimeInterval(-400),
                branch: "main",
                summary: "Task complete, standing by",
                pid: 41031,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41031,
                        parentPID: 41030,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/chronos"),
                        startedAt: referenceDate.addingTimeInterval(-5000),
                        provider: .codex,
                        hostApp: .cursor
                    )
                ],
                hostApp: .cursor
            ),
            AgentSession(
                id: "demo-codex-gateway",
                provider: .codex,
                projectName: "Gateway",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/gateway"),
                state: .starting,
                startedAt: referenceDate.addingTimeInterval(-30),
                lastActivityAt: referenceDate.addingTimeInterval(-5),
                branch: "infra/gateway",
                summary: "Spawning background worker",
                pid: 41071,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41071,
                        parentPID: 41070,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/gateway"),
                        startedAt: referenceDate.addingTimeInterval(-30),
                        provider: .codex,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            ),
            AgentSession(
                id: "demo-codex-polaris",
                provider: .codex,
                projectName: "Polaris",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/polaris"),
                state: .finished,
                startedAt: referenceDate.addingTimeInterval(-9000),
                lastActivityAt: referenceDate.addingTimeInterval(-1200),
                branch: "fix/build-cache",
                summary: "Cleaned build cache and verified types",
                pid: 41081,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41081,
                        parentPID: 41080,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/polaris"),
                        startedAt: referenceDate.addingTimeInterval(-9000),
                        provider: .codex,
                        hostApp: .xcode
                    )
                ],
                hostApp: .xcode
            ),
            AgentSession(
                id: "demo-codex-vortex",
                provider: .codex,
                projectName: "Vortex",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/vortex"),
                state: .failed,
                startedAt: referenceDate.addingTimeInterval(-6400),
                lastActivityAt: referenceDate.addingTimeInterval(-900),
                branch: "refactor/core",
                summary: "Fatal compiler exit code 1",
                pid: 41091,
                associatedProcesses: [
                    AgentProcess(
                        pid: 41091,
                        parentPID: 41090,
                        executable: "codex",
                        commandLine: "codex",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/vortex"),
                        startedAt: referenceDate.addingTimeInterval(-6400),
                        provider: .codex,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            )
        ]

        let codexUsage = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: referenceDate,
            planType: "plus",
            primaryBucket: UsageBucket(
                identifier: "codex-primary",
                label: "5h Window",
                usedFraction: 0.18,
                resetsAt: referenceDate.addingTimeInterval(17160),
                windowDurationMins: 300
            ),
            secondaryBucket: UsageBucket(
                identifier: "codex-secondary",
                label: "Weekly Window",
                usedFraction: 0.77,
                resetsAt: referenceDate.addingTimeInterval(237600),
                windowDurationMins: 10080
            ),
            additionalGroups: [],
            isStale: false,
            errorMessage: nil
        )

        let codex = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: codexSessions,
            usage: codexUsage
        )

        let claudeSessions = [
            AgentSession(
                id: "demo-claude-strata",
                provider: .claude,
                projectName: "Strata",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/strata"),
                state: .unknown,
                startedAt: referenceDate.addingTimeInterval(-10800),
                lastActivityAt: referenceDate.addingTimeInterval(-2400),
                branch: "experiment/streaming",
                summary: "Subprocess disconnected",
                pid: 42061,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42061,
                        parentPID: 42060,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/strata"),
                        startedAt: referenceDate.addingTimeInterval(-10800),
                        provider: .claude,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            ),
            AgentSession(
                id: "demo-claude-beacon",
                provider: .claude,
                projectName: "Beacon",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/beacon"),
                state: .waiting,
                startedAt: referenceDate.addingTimeInterval(-2100),
                lastActivityAt: referenceDate.addingTimeInterval(-30),
                branch: "fix/login",
                summary: "Approval needed to run migration",
                pid: 42001,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42001,
                        parentPID: 42000,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/beacon"),
                        startedAt: referenceDate.addingTimeInterval(-2100),
                        provider: .claude,
                        hostApp: .vsCode
                    )
                ],
                hostApp: .vsCode
            ),
            AgentSession(
                id: "demo-claude-aurora",
                provider: .claude,
                projectName: "Aurora",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/aurora"),
                state: .waiting,
                startedAt: referenceDate.addingTimeInterval(-3300),
                lastActivityAt: referenceDate.addingTimeInterval(-50),
                branch: "chore/deploy-script",
                summary: "Permission requested to execute script",
                pid: 42011,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42011,
                        parentPID: 42010,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/aurora"),
                        startedAt: referenceDate.addingTimeInterval(-3300),
                        provider: .claude,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            ),
            AgentSession(
                id: "demo-claude-meridian",
                provider: .claude,
                projectName: "Meridian",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/meridian"),
                state: .working,
                startedAt: referenceDate.addingTimeInterval(-1500),
                lastActivityAt: referenceDate.addingTimeInterval(-12),
                branch: "feature/oauth",
                summary: "Writing OAuth token refresh tests",
                pid: 42021,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42021,
                        parentPID: 42020,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/meridian"),
                        startedAt: referenceDate.addingTimeInterval(-1500),
                        provider: .claude,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            ),
            AgentSession(
                id: "demo-claude-cipher",
                provider: .claude,
                projectName: "Cipher",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/cipher"),
                state: .working,
                startedAt: referenceDate.addingTimeInterval(-2400),
                lastActivityAt: referenceDate.addingTimeInterval(-20),
                branch: "security/aes-gcm",
                summary: "Refactoring encryption primitives",
                pid: 42031,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42031,
                        parentPID: 42030,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/cipher"),
                        startedAt: referenceDate.addingTimeInterval(-2400),
                        provider: .claude,
                        hostApp: .cursor
                    )
                ],
                hostApp: .cursor
            ),
            AgentSession(
                id: "demo-claude-forge",
                provider: .claude,
                projectName: "Forge",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/forge"),
                state: .idle,
                startedAt: referenceDate.addingTimeInterval(-4800),
                lastActivityAt: referenceDate.addingTimeInterval(-350),
                branch: "refactor/pipeline",
                summary: "Awaiting next prompt",
                pid: 42041,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42041,
                        parentPID: 42040,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/forge"),
                        startedAt: referenceDate.addingTimeInterval(-4800),
                        provider: .claude,
                        hostApp: .cursor
                    )
                ],
                hostApp: .cursor
            ),
            AgentSession(
                id: "demo-claude-solaris",
                provider: .claude,
                projectName: "Solaris",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/solaris"),
                state: .idle,
                startedAt: referenceDate.addingTimeInterval(-7200),
                lastActivityAt: referenceDate.addingTimeInterval(-600),
                branch: "main",
                summary: "Lint pass succeeded, waiting",
                pid: 42051,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42051,
                        parentPID: 42050,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/solaris"),
                        startedAt: referenceDate.addingTimeInterval(-7200),
                        provider: .claude,
                        hostApp: .vsCode
                    )
                ],
                hostApp: .vsCode
            ),
            AgentSession(
                id: "demo-claude-nebula",
                provider: .claude,
                projectName: "Nebula",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/nebula"),
                state: .starting,
                startedAt: referenceDate.addingTimeInterval(-45),
                lastActivityAt: referenceDate.addingTimeInterval(-8),
                branch: "feature/mcp",
                summary: "Bootstrapping MCP servers",
                pid: 42071,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42071,
                        parentPID: 42070,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/nebula"),
                        startedAt: referenceDate.addingTimeInterval(-45),
                        provider: .claude,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            ),
            AgentSession(
                id: "demo-claude-zenith",
                provider: .claude,
                projectName: "Zenith",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/zenith"),
                state: .finished,
                startedAt: referenceDate.addingTimeInterval(-10000),
                lastActivityAt: referenceDate.addingTimeInterval(-1500),
                branch: "docs/api-guide",
                summary: "Documentation generation completed",
                pid: 42081,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42081,
                        parentPID: 42080,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/zenith"),
                        startedAt: referenceDate.addingTimeInterval(-10000),
                        provider: .claude,
                        hostApp: .vsCode
                    )
                ],
                hostApp: .vsCode
            ),
            AgentSession(
                id: "demo-claude-echo",
                provider: .claude,
                projectName: "Echo",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/echo"),
                state: .failed,
                startedAt: referenceDate.addingTimeInterval(-8000),
                lastActivityAt: referenceDate.addingTimeInterval(-1100),
                branch: "experiment/context",
                summary: "Context window limit exceeded",
                pid: 42091,
                associatedProcesses: [
                    AgentProcess(
                        pid: 42091,
                        parentPID: 42090,
                        executable: "claude",
                        commandLine: "claude",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/echo"),
                        startedAt: referenceDate.addingTimeInterval(-8000),
                        provider: .claude,
                        hostApp: .terminal
                    )
                ],
                hostApp: .terminal
            )
        ]

        let claude = MockAgentProvider(
            id: .claude,
            displayName: "Claude Code",
            availability: .available,
            sessions: claudeSessions
        )

        let antigravitySessions = [
            AgentSession(
                id: "demo-antigravity-nexus",
                provider: .antigravity,
                projectName: "Nexus",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/nexus"),
                state: .unknown,
                startedAt: referenceDate.addingTimeInterval(-14400),
                lastActivityAt: referenceDate.addingTimeInterval(-3600),
                branch: "prototype/rag",
                summary: "Language server not responding",
                pid: 43061,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43061,
                        parentPID: 43060,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/nexus"),
                        startedAt: referenceDate.addingTimeInterval(-14400),
                        provider: .antigravity,
                        hostApp: .antigravity
                    )
                ],
                hostApp: .antigravity
            ),
            AgentSession(
                id: "demo-antigravity-pulsar",
                provider: .antigravity,
                projectName: "Pulsar",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/pulsar"),
                state: .waiting,
                startedAt: referenceDate.addingTimeInterval(-2700),
                lastActivityAt: referenceDate.addingTimeInterval(-40),
                branch: "feature/telemetry",
                summary: "Waiting for user confirmation on schema change",
                pid: 43021,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43021,
                        parentPID: 43020,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/pulsar"),
                        startedAt: referenceDate.addingTimeInterval(-2700),
                        provider: .antigravity,
                        hostApp: .antigravity
                    )
                ],
                hostApp: .antigravity
            ),
            AgentSession(
                id: "demo-antigravity-astral",
                provider: .antigravity,
                projectName: "Astral",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/astral"),
                state: .waiting,
                startedAt: referenceDate.addingTimeInterval(-3900),
                lastActivityAt: referenceDate.addingTimeInterval(-55),
                branch: "feature/sandbox",
                summary: "Shell execution approval required",
                pid: 43031,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43031,
                        parentPID: 43030,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/astral"),
                        startedAt: referenceDate.addingTimeInterval(-3900),
                        provider: .antigravity,
                        hostApp: .antigravity
                    )
                ],
                hostApp: .antigravity
            ),
            AgentSession(
                id: "demo-antigravity-orbit",
                provider: .antigravity,
                projectName: "Orbit",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/orbit"),
                state: .working,
                startedAt: referenceDate.addingTimeInterval(-1200),
                lastActivityAt: referenceDate.addingTimeInterval(-5),
                branch: "feature/search",
                summary: "Indexing workspace",
                pid: 43001,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43001,
                        parentPID: 43000,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/orbit"),
                        startedAt: referenceDate.addingTimeInterval(-1200),
                        provider: .antigravity,
                        hostApp: .antigravity
                    )
                ],
                hostApp: .antigravity
            ),
            AgentSession(
                id: "demo-antigravity-titan",
                provider: .antigravity,
                projectName: "Titan",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/titan"),
                state: .working,
                startedAt: referenceDate.addingTimeInterval(-2100),
                lastActivityAt: referenceDate.addingTimeInterval(-18),
                branch: "model/embeddings",
                summary: "Training local embedding model",
                pid: 43011,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43011,
                        parentPID: 43010,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/titan"),
                        startedAt: referenceDate.addingTimeInterval(-2100),
                        provider: .antigravity,
                        hostApp: .antigravity
                    )
                ],
                hostApp: .antigravity
            ),
            AgentSession(
                id: "demo-antigravity-quarry",
                provider: .antigravity,
                projectName: "Quarry",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/quarry"),
                state: .idle,
                startedAt: referenceDate.addingTimeInterval(-6000),
                lastActivityAt: referenceDate.addingTimeInterval(-500),
                branch: "main",
                summary: "Plan completed, standing by",
                pid: 43041,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43041,
                        parentPID: 43040,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/quarry"),
                        startedAt: referenceDate.addingTimeInterval(-6000),
                        provider: .antigravity,
                        hostApp: .vsCode
                    )
                ],
                hostApp: .vsCode
            ),
            AgentSession(
                id: "demo-antigravity-hyperion",
                provider: .antigravity,
                projectName: "Hyperion",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/hyperion"),
                state: .idle,
                startedAt: referenceDate.addingTimeInterval(-8400),
                lastActivityAt: referenceDate.addingTimeInterval(-720),
                branch: "feature/review",
                summary: "Code review comments addressed",
                pid: 43051,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43051,
                        parentPID: 43050,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/hyperion"),
                        startedAt: referenceDate.addingTimeInterval(-8400),
                        provider: .antigravity,
                        hostApp: .vsCode
                    )
                ],
                hostApp: .vsCode
            ),
            AgentSession(
                id: "demo-antigravity-vector",
                provider: .antigravity,
                projectName: "Vector",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/vector"),
                state: .starting,
                startedAt: referenceDate.addingTimeInterval(-25),
                lastActivityAt: referenceDate.addingTimeInterval(-4),
                branch: "infra/sidecar",
                summary: "Initializing language model sidecar",
                pid: 43071,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43071,
                        parentPID: 43070,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/vector"),
                        startedAt: referenceDate.addingTimeInterval(-25),
                        provider: .antigravity,
                        hostApp: .antigravity
                    )
                ],
                hostApp: .antigravity
            ),
            AgentSession(
                id: "demo-antigravity-cosmos",
                provider: .antigravity,
                projectName: "Cosmos",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/cosmos"),
                state: .finished,
                startedAt: referenceDate.addingTimeInterval(-11200),
                lastActivityAt: referenceDate.addingTimeInterval(-1800),
                branch: "db/migration-v3",
                summary: "Migration script executed safely",
                pid: 43081,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43081,
                        parentPID: 43080,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/cosmos"),
                        startedAt: referenceDate.addingTimeInterval(-11200),
                        provider: .antigravity,
                        hostApp: .antigravity
                    )
                ],
                hostApp: .antigravity
            ),
            AgentSession(
                id: "demo-antigravity-supernova",
                provider: .antigravity,
                projectName: "Supernova",
                projectPath: URL(fileURLWithPath: "/Users/developer/Projects/supernova"),
                state: .failed,
                startedAt: referenceDate.addingTimeInterval(-9600),
                lastActivityAt: referenceDate.addingTimeInterval(-1400),
                branch: "feature/indexer",
                summary: "Out of memory during vector indexing",
                pid: 43091,
                associatedProcesses: [
                    AgentProcess(
                        pid: 43091,
                        parentPID: 43090,
                        executable: "antigravity",
                        commandLine: "antigravity",
                        workingDirectory: URL(fileURLWithPath: "/Users/developer/Projects/supernova"),
                        startedAt: referenceDate.addingTimeInterval(-9600),
                        provider: .antigravity,
                        hostApp: .antigravity
                    )
                ],
                hostApp: .antigravity
            )
        ]

        let antigravityUsage = ProviderUsageSnapshot(
            providerID: .antigravity,
            updatedAt: referenceDate,
            planType: nil,
            primaryBucket: UsageBucket(
                identifier: "gemini-primary",
                label: "Gemini 5h",
                usedFraction: 0.36,
                resetsAt: referenceDate.addingTimeInterval(8820),
                windowDurationMins: 300
            ),
            secondaryBucket: UsageBucket(
                identifier: "gemini-secondary",
                label: "Gemini Weekly",
                usedFraction: 0.92,
                resetsAt: referenceDate.addingTimeInterval(118800),
                windowDurationMins: 10080
            ),
            additionalGroups: [],
            isStale: false,
            errorMessage: nil
        )

        let antigravity = MockAgentProvider(
            id: .antigravity,
            displayName: "Antigravity",
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

