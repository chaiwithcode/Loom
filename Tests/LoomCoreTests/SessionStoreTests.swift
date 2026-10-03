import XCTest
import os
@testable import LoomCore

// MARK: - Test Concurrency Primitives

actor AsyncGate {
    private var isOpened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpened { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpened else { return }
        isOpened = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func isGateOpened() -> Bool {
        isOpened
    }
}

actor ConcurrencyBarrier {
    private let expectedArrivals: Int
    private var arrivedCount: Int = 0
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    init(expectedArrivals: Int) {
        self.expectedArrivals = expectedArrivals
    }

    func arriveAndAwaitRelease() async {
        arrivedCount += 1
        if arrivedCount >= expectedArrivals {
            let waiters = arrivalWaiters
            arrivalWaiters.removeAll()
            for w in waiters {
                w.resume()
            }
        }

        if isReleased { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilAllArrived() async {
        if arrivedCount >= expectedArrivals { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters.append(continuation)
        }
    }

    func releaseAll() {
        guard !isReleased else { return }
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for w in waiters {
            w.resume()
        }
    }

    func getArrivedCount() -> Int {
        arrivedCount
    }
}

private enum TestTimeoutError: Error {
    case timedOut
}

@MainActor
private func withTimeout<T: Sendable>(
    seconds: Double = 3.0,
    operation: @escaping @MainActor () async throws -> T
) async throws -> T {
    let workTask = Task { @MainActor in
        try await operation()
    }
    let timerTask = Task<T, any Error> {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw TestTimeoutError.timedOut
    }
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await workTask.value
        }
        group.addTask {
            try await timerTask.value
        }
        let result = try await group.next()!
        workTask.cancel()
        timerTask.cancel()
        group.cancelAll()
        return result
    }
}

// MARK: - Immutable Test Providers (Checked Sendable)

final class BarrierMockProvider: AgentProvider, Sendable {
    let id: ProviderID
    let displayName: String
    let barrier: ConcurrencyBarrier

    init(id: ProviderID, displayName: String, barrier: ConcurrencyBarrier) {
        self.id = id
        self.displayName = displayName
        self.barrier = barrier
    }

    func availability() async -> ProviderAvailability {
        .available
    }

    func discoverSessions() async throws -> [AgentSession] {
        await barrier.arriveAndAwaitRelease()
        return [
            AgentSession(id: "\(id.rawValue)-1", provider: id, state: .working)
        ]
    }
}

final class OverlapMockProvider: AgentProvider, Sendable {
    let id: ProviderID = .codex
    let displayName: String = "Codex"
    let startedGate: AsyncGate
    let releaseGate: AsyncGate
    private let callCounter = OSAllocatedUnfairLock(initialState: 0)

    init(startedGate: AsyncGate, releaseGate: AsyncGate) {
        self.startedGate = startedGate
        self.releaseGate = releaseGate
    }

    var callCount: Int {
        callCounter.withLock { $0 }
    }

    func availability() async -> ProviderAvailability {
        .available
    }

    func discoverSessions() async throws -> [AgentSession] {
        callCounter.withLock { $0 += 1 }
        await startedGate.open()
        await releaseGate.wait()
        return [
            AgentSession(id: "s1", provider: id, state: .working)
        ]
    }
}

final class GatedCodexProvider: AgentProvider, Sendable {
    let id: ProviderID = .codex
    let displayName: String = "Codex"
    let startedGate: AsyncGate
    let releaseGate: AsyncGate

    init(startedGate: AsyncGate, releaseGate: AsyncGate) {
        self.startedGate = startedGate
        self.releaseGate = releaseGate
    }

    func availability() async -> ProviderAvailability {
        .available
    }

    func discoverSessions() async throws -> [AgentSession] {
        await startedGate.open()
        await releaseGate.wait()
        return [
            AgentSession(id: "codex-1", provider: .codex, projectName: "XKit", state: .working)
        ]
    }
}

final class FastClaudeProvider: AgentProvider, Sendable {
    let id: ProviderID = .claude
    let displayName: String = "Claude"

    func availability() async -> ProviderAvailability {
        .available
    }

    func discoverSessions() async throws -> [AgentSession] {
        [
            AgentSession(id: "claude-1", provider: .claude, projectName: "SmartRemote", state: .waiting)
        ]
    }
}

// MARK: - Unit Tests

final class SessionStoreTests: XCTestCase {

    @MainActor
    func testInitialState() {
        let provider = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: []
        )
        let store = SessionStore(providers: [provider])

        XCTAssertEqual(store.providerSnapshots.count, 1)
        XCTAssertEqual(store.providerSnapshots.first?.providerID, .codex)
        XCTAssertEqual(store.providerSnapshots.first?.availability, .unknown, "Initial availability must be .unknown")
        XCTAssertEqual(store.providerSnapshots.first?.sessions.count, 0)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertNil(store.lastRefreshedAt)
    }

    @MainActor
    func testConcurrency() async throws {
        let barrier = ConcurrencyBarrier(expectedArrivals: 3)
        defer {
            Task { await barrier.releaseAll() }
        }

        let p1 = BarrierMockProvider(id: ProviderID("p1"), displayName: "P1", barrier: barrier)
        let p2 = BarrierMockProvider(id: ProviderID("p2"), displayName: "P2", barrier: barrier)
        let p3 = BarrierMockProvider(id: ProviderID("p3"), displayName: "P3", barrier: barrier)

        let store = SessionStore(providers: [p1, p2, p3])

        try await withTimeout(seconds: 3.0) {
            let refreshTask = Task {
                await store.refresh()
            }

            // Prove all providers start before any release
            await barrier.waitUntilAllArrived()
            let arrived = await barrier.getArrivedCount()
            XCTAssertEqual(arrived, 3, "All 3 providers must start and arrive before any release")

            // Release all providers to complete
            await barrier.releaseAll()
            await refreshTask.value
        }

        XCTAssertEqual(store.allSessions.count, 3)
        XCTAssertFalse(store.isRefreshing)
    }

    @MainActor
    func testOverlappingRefreshProtection() async throws {
        let startedGate = AsyncGate()
        let releaseGate = AsyncGate()
        defer {
            Task { await releaseGate.open() }
        }

        let provider = OverlapMockProvider(startedGate: startedGate, releaseGate: releaseGate)
        let store = SessionStore(providers: [provider])

        try await withTimeout(seconds: 3.0) {
            // First refresh call starts discovery and pauses at releaseGate
            let t1 = Task {
                await store.refresh()
            }

            await startedGate.wait()
            XCTAssertTrue(store.isRefreshing, "Store should be refreshing")
            XCTAssertEqual(provider.callCount, 1, "First refresh triggered discovery")

            // Second overlapping call while first is in-flight
            let t2 = Task {
                await store.refresh()
            }

            // Yield to allow t2 to attempt refresh and join in-flight task
            await Task.yield()

            // Release the gate
            await releaseGate.open()

            await t1.value
            await t2.value

            // Prove overlapping calls caused exactly one discovery
            XCTAssertEqual(
                provider.callCount,
                1,
                "Overlapping refresh calls must join active task, causing exactly one discovery invocation"
            )
            XCTAssertFalse(store.isRefreshing)
        }
    }

    @MainActor
    func testGatedIncrementalResults() async throws {
        let codexStartedGate = AsyncGate()
        let codexReleaseGate = AsyncGate()
        defer {
            Task { await codexReleaseGate.open() }
        }

        let codex = GatedCodexProvider(startedGate: codexStartedGate, releaseGate: codexReleaseGate)
        let claude = FastClaudeProvider()
        let store = SessionStore(providers: [codex, claude])

        try await withTimeout(seconds: 3.0) {
            let refreshTask = Task {
                await store.refresh()
            }

            // Wait for Codex to start discovery and be held
            await codexStartedGate.wait()

            // Claude is fast and completes while Codex is still held.
            // Wait for Claude sessions to be applied to the store.
            while store.snapshot(for: .claude)?.sessions.isEmpty ?? true {
                await Task.yield()
            }

            // Assert Claude sessions visible while Codex and store are still refreshing
            let claudeSnap = store.snapshot(for: .claude)
            XCTAssertEqual(claudeSnap?.sessions.count, 1, "Claude sessions must be visible incrementally")
            XCTAssertEqual(claudeSnap?.sessions.first?.projectName, "SmartRemote")
            XCTAssertFalse(claudeSnap?.isRefreshing ?? true, "Claude snapshot must have completed")

            let codexSnap = store.snapshot(for: .codex)
            XCTAssertTrue(codexSnap?.isRefreshing ?? false, "Codex must still be refreshing")
            XCTAssertTrue(codexSnap?.sessions.isEmpty ?? false, "Codex sessions must not yet be populated")
            XCTAssertTrue(store.isRefreshing, "Store must still be refreshing while Codex is held")

            // Release Codex and finish
            await codexReleaseGate.open()
            await refreshTask.value

            // Both providers completed
            XCTAssertFalse(store.isRefreshing, "Store must finish refreshing after Codex releases")
            XCTAssertEqual(store.snapshot(for: .codex)?.sessions.count, 1)
            XCTAssertEqual(store.snapshot(for: .claude)?.sessions.count, 1)
        }
    }

    @MainActor
    func testOneProviderFailureDoesNotAffectOthers() async {
        let p1 = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            sessions: [
                AgentSession(id: "s1", provider: .codex, projectName: "Project A", state: .working)
            ]
        )
        let p2 = MockAgentProvider(
            id: .claude,
            displayName: "Claude",
            error: MockProviderError.daemonUnavailable("Failed to connect to daemon")
        )
        let p3 = MockAgentProvider(
            id: .antigravity,
            displayName: "Antigravity",
            sessions: [
                AgentSession(id: "s3", provider: .antigravity, projectName: "Project C", state: .finished)
            ]
        )

        let store = SessionStore(providers: [p1, p2, p3])
        await store.refresh()

        let snap1 = store.snapshot(for: .codex)
        XCTAssertNotNil(snap1)
        XCTAssertEqual(snap1?.sessions.count, 1)
        XCTAssertNil(snap1?.errorMessage)

        let snap2 = store.snapshot(for: .claude)
        XCTAssertNotNil(snap2)
        XCTAssertEqual(snap2?.sessions.count, 0)
        XCTAssertEqual(snap2?.errorMessage, "Failed to connect to daemon")

        let snap3 = store.snapshot(for: .antigravity)
        XCTAssertNotNil(snap3)
        XCTAssertEqual(snap3?.sessions.count, 1)
        XCTAssertNil(snap3?.errorMessage)
    }

    @MainActor
    func testExplicitUnavailability() async {
        let provider = MockAgentProvider(
            id: .claude,
            displayName: "Claude Code",
            availability: .unavailable(reason: "CLI binary not found in PATH"),
            sessions: [
                AgentSession(id: "should-not-show", provider: .claude, state: .working)
            ]
        )

        let store = SessionStore(providers: [provider])
        await store.refresh()

        let snap = store.snapshot(for: .claude)
        XCTAssertEqual(snap?.availability, .unavailable(reason: "CLI binary not found in PATH"))
        XCTAssertEqual(snap?.sessions.count, 0)
        XCTAssertNil(snap?.errorMessage)
        XCTAssertEqual(provider.discoverCallCount, 0, "Discovery must be skipped for unavailable providers")
    }

    @MainActor
    func testStaleReplacement() async {
        let s1 = AgentSession(id: "s1", provider: .codex, projectName: "Old Project", state: .working)
        let s2 = AgentSession(id: "s2", provider: .codex, projectName: "Old Project 2", state: .idle)
        let provider = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [s1, s2])

        let store = SessionStore(providers: [provider])
        await store.refresh()

        XCTAssertEqual(store.snapshot(for: .codex)?.sessions.map(\.id), ["s1", "s2"])

        // Now provider updates to only return s3
        let s3 = AgentSession(id: "s3", provider: .codex, projectName: "New Project", state: .finished)
        provider.setSessions([s3])

        await store.refresh()

        let refreshedSessions = store.snapshot(for: .codex)?.sessions ?? []
        XCTAssertEqual(refreshedSessions.map(\.id), ["s3"], "Stale sessions must be replaced, not appended")
    }

    @MainActor
    func testEmptyResults() async {
        let provider = MockAgentProvider(
            id: .antigravity,
            displayName: "Antigravity",
            availability: .available,
            sessions: []
        )

        let store = SessionStore(providers: [provider])
        await store.refresh()

        let snap = store.snapshot(for: .antigravity)
        XCTAssertEqual(snap?.availability, .available)
        XCTAssertEqual(snap?.sessions.count, 0)
        XCTAssertNil(snap?.errorMessage)
    }

    func testDemoFixturesAndStates() async throws {
        let standardProviders = DemoFixture.standard.makeProviders()
        XCTAssertEqual(standardProviders.count, 3)

        // Verify all 6 states are covered in default mock providers
        let allDefaultProviders = MockAgentProvider.createDefaultProviders()
        var coveredStates = Set<AgentState>()
        for provider in allDefaultProviders {
            for session in try await provider.discoverSessions() {
                coveredStates.insert(session.state)
            }
        }
        XCTAssertEqual(
            coveredStates,
            Set(AgentState.allCases),
            "Default mock providers must cover all six normalized AgentState values"
        )

        // Verify empty fixture
        let emptyProviders = DemoFixture.empty.makeProviders()
        XCTAssertEqual(emptyProviders.count, 3)
        for p in emptyProviders {
            let sessions = try await p.discoverSessions()
            XCTAssertTrue(sessions.isEmpty)
        }

        // Verify CLI argument resolution
        XCTAssertEqual(DemoFixture.resolve(from: ["Loom"]), .standard)
        XCTAssertEqual(DemoFixture.resolve(from: ["Loom", "--demo-empty"]), .empty)
        XCTAssertEqual(DemoFixture.resolve(from: ["Loom", "--demo-failure"]), .failure)
    }
}
