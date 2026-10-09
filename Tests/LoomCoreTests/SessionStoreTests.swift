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

    @MainActor
    func testDemoFixturesAndStates() async throws {
        let standardProviders = DemoFixture.standard.makeProviders()
        XCTAssertEqual(standardProviders.count, 2)
        XCTAssertEqual(standardProviders.map(\.id), [.codex, .antigravity])

        // Verify DemoFixture metadata
        XCTAssertNil(DemoFixture.standard.badgeLabel)
        XCTAssertFalse(DemoFixture.standard.isDemo)
        XCTAssertEqual(DemoFixture.mock.badgeLabel, "DEMO")
        XCTAssertTrue(DemoFixture.mock.isDemo)
        XCTAssertEqual(DemoFixture.empty.badgeLabel, "DEMO EMPTY")
        XCTAssertTrue(DemoFixture.empty.isDemo)
        XCTAssertEqual(DemoFixture.failure.badgeLabel, "DEMO FAIL")
        XCTAssertTrue(DemoFixture.failure.isDemo)

        // Verify SessionStore initializes with fixture and reflects it
        let defaultStore = SessionStore(providers: [])
        XCTAssertEqual(defaultStore.fixture, .standard)
        XCTAssertNil(defaultStore.fixture.badgeLabel)
        XCTAssertFalse(defaultStore.fixture.isDemo)

        let mockStore = SessionStore(providers: [], fixture: .mock)
        XCTAssertEqual(mockStore.fixture, .mock)
        XCTAssertEqual(mockStore.fixture.badgeLabel, "DEMO")
        XCTAssertTrue(mockStore.fixture.isDemo)

        let emptyStore = SessionStore(providers: [], fixture: .empty)
        XCTAssertEqual(emptyStore.fixture, .empty)
        XCTAssertEqual(emptyStore.fixture.badgeLabel, "DEMO EMPTY")

        let failStore = SessionStore(providers: [], fixture: .failure)
        XCTAssertEqual(failStore.fixture, .failure)
        XCTAssertEqual(failStore.fixture.badgeLabel, "DEMO FAIL")

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
        XCTAssertEqual(DemoFixture.resolve(from: ["Loom", "--demo-mock"]), .mock)
        XCTAssertEqual(DemoFixture.resolve(from: ["Loom", "--demo-empty"]), .empty)
        XCTAssertEqual(DemoFixture.resolve(from: ["Loom", "--demo-failure"]), .failure)
    }

    // MARK: - Project Grouping Tests

    func testProjectGroupingSameProjectTwoProviders() {
        let loomPath = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom")
        let codexSession = AgentSession(
            id: "codex-101",
            provider: .codex,
            projectName: "Loom",
            projectPath: loomPath,
            state: .unknown,
            startedAt: Date(timeIntervalSince1970: 1700000000),
            lastActivityAt: nil,
            branch: "main",
            summary: nil,
            pid: 101
        )
        let antigravitySession = AgentSession(
            id: "antigravity-202",
            provider: .antigravity,
            projectName: "Loom",
            projectPath: loomPath,
            state: .working,
            startedAt: nil,
            lastActivityAt: Date(timeIntervalSince1970: 1700000500),
            branch: "main",
            summary: "Implementing session discovery"
        )

        let groups = ProjectGroup.groupSessions([codexSession, antigravitySession])
        XCTAssertEqual(groups.count, 1, "Two sessions for the same project path must be grouped together")

        let group = groups[0]
        XCTAssertEqual(group.projectName, "Loom")
        XCTAssertEqual(group.projectPath, loomPath.standardizedFileURL)
        XCTAssertEqual(group.sessions.count, 2)
        // Antigravity has lastActivityAt (1700000500), Codex has nil lastActivityAt but startedAt (1700000000)
        // Most recent activity first:
        XCTAssertEqual(group.sessions[0].id, "antigravity-202")
        XCTAssertEqual(group.sessions[1].id, "codex-101")
    }

    func testProjectGroupingSameNameDifferentPathsRemainDistinct() {
        let pathA = URL(fileURLWithPath: "/Users/deepak/ClientA/Loom")
        let pathB = URL(fileURLWithPath: "/Users/deepak/ClientB/Loom")

        let sessionA = AgentSession(
            id: "codex-a",
            provider: .codex,
            projectName: "Loom",
            projectPath: pathA,
            state: .unknown
        )
        let sessionB = AgentSession(
            id: "codex-b",
            provider: .codex,
            projectName: "Loom",
            projectPath: pathB,
            state: .unknown
        )

        let groups = ProjectGroup.groupSessions([sessionA, sessionB])
        XCTAssertEqual(groups.count, 2, "Same-name projects with different paths must remain distinct groups")
        XCTAssertNotEqual(groups[0].id, groups[1].id)
        XCTAssertTrue(groups.contains { $0.projectPath == pathA.standardizedFileURL })
        XCTAssertTrue(groups.contains { $0.projectPath == pathB.standardizedFileURL })
    }

    func testProjectGroupingUnknownPathsDistinct() {
        let session1 = AgentSession(
            id: "codex-nil-1",
            provider: .codex,
            projectName: "Untitled Session",
            projectPath: nil,
            state: .unknown
        )
        let session2 = AgentSession(
            id: "codex-nil-2",
            provider: .codex,
            projectName: "Untitled Session",
            projectPath: nil,
            state: .unknown
        )

        let groups = ProjectGroup.groupSessions([session1, session2])
        XCTAssertEqual(groups.count, 2, "Sessions with missing project path (nil) must NOT falsely merge")
        XCTAssertEqual(groups[0].sessions.count, 1)
        XCTAssertEqual(groups[1].sessions.count, 1)
        XCTAssertNotEqual(groups[0].id, groups[1].id)
    }

    func testProjectGroupingDeterministicOrdering() {
        let dateRecent = Date(timeIntervalSince1970: 1700002000)
        let dateOlder = Date(timeIntervalSince1970: 1700001000)

        let pathAlpha = URL(fileURLWithPath: "/tmp/projects/alpha")
        let pathBeta = URL(fileURLWithPath: "/tmp/projects/beta")
        let pathGamma = URL(fileURLWithPath: "/tmp/projects/gamma")

        let sessionAlpha = AgentSession(
            id: "alpha-1",
            provider: .codex,
            projectName: "Alpha",
            projectPath: pathAlpha,
            state: .unknown,
            startedAt: nil,
            lastActivityAt: dateOlder
        )
        let sessionBeta = AgentSession(
            id: "beta-1",
            provider: .codex,
            projectName: "Beta",
            projectPath: pathBeta,
            state: .unknown,
            startedAt: nil,
            lastActivityAt: dateRecent
        )
        let sessionGammaNoDate = AgentSession(
            id: "gamma-1",
            provider: .codex,
            projectName: "Gamma",
            projectPath: pathGamma,
            state: .unknown,
            startedAt: nil,
            lastActivityAt: nil
        )

        // Pass in reverse order
        let groups = ProjectGroup.groupSessions([sessionGammaNoDate, sessionAlpha, sessionBeta])
        XCTAssertEqual(groups.count, 3)

        // Beta has dateRecent -> first
        // Alpha has dateOlder -> second
        // Gamma has nil date -> third
        XCTAssertEqual(groups[0].projectName, "Beta")
        XCTAssertEqual(groups[1].projectName, "Alpha")
        XCTAssertEqual(groups[2].projectName, "Gamma")
    }

    @MainActor
    func testProjectGroupingEmptyAndErrorIsolation() async throws {
        // Empty sessions
        let emptyGroups = ProjectGroup.groupSessions([])
        XCTAssertTrue(emptyGroups.isEmpty)

        struct TestFailingProvider: AgentProvider, Sendable {
            let id: ProviderID = .codex
            let displayName: String = "Codex"
            func availability() async -> ProviderAvailability { .available }
            func discoverSessions() async throws -> [AgentSession] {
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Discovery failed"])
            }
        }

        struct TestWorkingProvider: AgentProvider, Sendable {
            let id: ProviderID = .antigravity
            let displayName: String = "Antigravity"
            let sessions: [AgentSession]
            func availability() async -> ProviderAvailability { .available }
            func discoverSessions() async throws -> [AgentSession] { sessions }
        }

        let failingProvider = TestFailingProvider()
        let goodSession = AgentSession(
            id: "ag-1",
            provider: .antigravity,
            projectName: "IsolatedProject",
            projectPath: URL(fileURLWithPath: "/tmp/isolated"),
            state: .working
        )
        let workingProvider = TestWorkingProvider(sessions: [goodSession])

        let store = SessionStore(providers: [failingProvider, workingProvider])
        await store.refresh()

        // Failing provider has error message, zero sessions
        let codexSnap = store.snapshot(for: .codex)
        XCTAssertNotNil(codexSnap?.errorMessage)
        XCTAssertEqual(codexSnap?.sessions.count, 0)

        // Working provider has session and is grouped cleanly
        let agSnap = store.snapshot(for: .antigravity)
        XCTAssertNil(agSnap?.errorMessage)
        XCTAssertEqual(agSnap?.sessions.count, 1)

        let groups = store.groupedSessions
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].projectName, "IsolatedProject")
        XCTAssertEqual(groups[0].sessions[0].id, "ag-1")
    }

    func testProjectGroupingNilPathProviderQualifiedIdCollisionFree() {
        let codexSession = AgentSession(
            id: "1",
            provider: .codex,
            projectName: "Untitled Session",
            projectPath: nil,
            state: .unknown
        )
        let agSession = AgentSession(
            id: "1",
            provider: .antigravity,
            projectName: "Untitled Session",
            projectPath: nil,
            state: .working
        )

        XCTAssertEqual(codexSession.providerQualifiedId, "codex:1")
        XCTAssertEqual(agSession.providerQualifiedId, "antigravity:1")

        let groups = ProjectGroup.groupSessions([codexSession, agSession])
        XCTAssertEqual(groups.count, 2, "Sessions with colliding IDs across providers must produce 2 distinct groups")

        let groupIDs = Set(groups.map(\.id))
        XCTAssertEqual(groupIDs.count, 2, "Group IDs must not collide")
        XCTAssertTrue(groupIDs.contains("session:codex:1"))
        XCTAssertTrue(groupIDs.contains("session:antigravity:1"))
    }

    func testProviderSnapshotWarningFlags() {
        // Clean snapshot
        let cleanSnap = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            availability: .available
        )
        XCTAssertFalse(cleanSnap.hasWarning)

        // Error message warning
        let errorSnap = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            availability: .available,
            errorMessage: "Discovery failed"
        )
        XCTAssertTrue(errorSnap.hasWarning)

        // Unavailability warning
        let unavailSnap = ProviderSnapshot(
            providerID: .claude,
            displayName: "Claude",
            availability: .unavailable(reason: "CLI missing")
        )
        XCTAssertTrue(unavailSnap.hasWarning)

        // Usage error message warning
        let usageErrSnap = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            availability: .available,
            usageErrorMessage: "Quota rate limit reached"
        )
        XCTAssertTrue(usageErrSnap.hasWarning)

        // Stale usage warning
        let staleUsage = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date(),
            planType: "pro",
            primaryBucket: nil,
            secondaryBucket: nil,
            additionalGroups: [],
            isStale: true,
            errorMessage: nil
        )
        let staleSnap = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            availability: .available,
            usage: staleUsage
        )
        XCTAssertTrue(staleSnap.hasWarning)

        // Usage internal error warning
        let usageWithInternalErr = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date(),
            planType: "pro",
            primaryBucket: nil,
            secondaryBucket: nil,
            additionalGroups: [],
            isStale: false,
            errorMessage: "Upstream rate limit"
        )
        let usageInternalErrSnap = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            availability: .available,
            usage: usageWithInternalErr
        )
        XCTAssertTrue(usageInternalErrSnap.hasWarning)
    }

    @MainActor
    func testHonestEmptySessionStateDistinguishesReasons() async {
        // 1. Genuinely empty state: available providers with 0 sessions and 0 errors
        let emptyCodex = MockAgentProvider(id: .codex, displayName: "Codex", availability: .available, sessions: [])
        let emptyStore = SessionStore(providers: [emptyCodex])
        await emptyStore.refresh()
        XCTAssertEqual(emptyStore.emptySessionReason, .noActiveSessions)
        XCTAssertEqual(emptyStore.emptySessionReason?.message, "No active sessions")
        XCTAssertFalse(emptyStore.hasUsageOrProviderWarning)

        // 2. Discovery failed state: provider threw discovery error
        let failingCodex = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            error: MockProviderError.daemonUnavailable("Failed to connect to daemon")
        )
        let failStore = SessionStore(providers: [failingCodex])
        await failStore.refresh()
        XCTAssertEqual(failStore.emptySessionReason, .discoveryFailed(message: "Discovery failed: Failed to connect to daemon"))
        XCTAssertTrue(failStore.hasUsageOrProviderWarning)

        // 3. Unavailable state: provider is unavailable
        let unavailClaude = MockAgentProvider(
            id: .claude,
            displayName: "Claude",
            availability: .unavailable(reason: "CLI binary not found in PATH")
        )
        let unavailStore = SessionStore(providers: [unavailClaude])
        await unavailStore.refresh()
        XCTAssertEqual(unavailStore.emptySessionReason, .unavailable(message: "CLI binary not found in PATH"))
        XCTAssertTrue(unavailStore.hasUsageOrProviderWarning)

        // 4. Non-empty sessions: emptySessionReason is nil
        let activeCodex = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: [AgentSession(id: "s1", provider: .codex, state: .working)]
        )
        let activeStore = SessionStore(providers: [activeCodex])
        await activeStore.refresh()
        XCTAssertNil(activeStore.emptySessionReason)
    }
}
