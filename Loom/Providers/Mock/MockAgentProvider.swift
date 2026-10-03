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
        error: (any Error)? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.stateLock = OSAllocatedUnfairLock(initialState: State(
            availability: availability,
            sessions: sessions,
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
}

extension MockAgentProvider {
    public static func createDefaultProviders(referenceDate: Date = Date()) -> [MockAgentProvider] {
        // Codex mock: .working and .idle
        let codexSessions = [
            AgentSession(
                id: "codex-session-1",
                provider: .codex,
                projectName: "XKit",
                projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/XKit"),
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
                projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/DevPortal"),
                state: .idle,
                startedAt: referenceDate.addingTimeInterval(-7200), // 2h ago
                lastActivityAt: referenceDate.addingTimeInterval(-2700), // 45m ago
                branch: "feature/api",
                summary: "Awaiting next user prompt"
            )
        ]

        let codex = MockAgentProvider(
            id: .codex,
            displayName: "Codex (Mock)",
            availability: .available,
            sessions: codexSessions
        )

        // Claude mock: .waiting and .failed
        let claudeSessions = [
            AgentSession(
                id: "claude-session-1",
                provider: .claude,
                projectName: "SmartRemote",
                projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/SmartRemote"),
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
                projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom"),
                state: .failed,
                startedAt: referenceDate.addingTimeInterval(-3600), // 1h ago
                lastActivityAt: referenceDate.addingTimeInterval(-720), // 12m ago
                branch: "v0-kickoff",
                summary: "Build failed: undefined symbol in parser"
            )
        ]

        let claude = MockAgentProvider(
            id: .claude,
            displayName: "Claude Code (Mock)",
            availability: .available,
            sessions: claudeSessions
        )

        // Antigravity mock: .finished and .unknown
        let antigravitySessions = [
            AgentSession(
                id: "antigravity-session-1",
                provider: .antigravity,
                projectName: "Experiment",
                projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Experiment"),
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
                projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/KernelMod"),
                state: .unknown,
                startedAt: referenceDate.addingTimeInterval(-10800), // 3h ago
                lastActivityAt: referenceDate.addingTimeInterval(-1500), // 25m ago
                branch: "patch-1",
                summary: "Process detached without final status report"
            )
        ]

        let antigravity = MockAgentProvider(
            id: .antigravity,
            displayName: "Antigravity (Mock)",
            availability: .available,
            sessions: antigravitySessions
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
            let codex = CodexProvider()
            let mocks = MockAgentProvider.createDefaultProviders().filter { $0.id != .codex }
            return [codex] + mocks
        case .mock:
            return MockAgentProvider.createDefaultProviders()
        case .empty:
            return MockAgentProvider.createEmptyProviders()
        case .failure:
            return MockAgentProvider.createFailureProviders()
        }
    }
}

