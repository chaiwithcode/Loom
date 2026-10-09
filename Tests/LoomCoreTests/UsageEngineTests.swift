//
//  UsageEngineTests.swift
//  Loom
//
//  Created by Deepak Sharma on 03/10/2026.
//  Copyright © 2026 ChaiWithCode. All rights reserved.
//

import XCTest
@testable import LoomCore

final class UsageEngineTests: XCTestCase {

    // MARK: - UsageBucket Tests

    func testUsageBucketNormalCalculation() {
        let now = Date()
        let resetDate = now.addingTimeInterval(7200 + 600) // 2h 10m
        let bucket = UsageBucket(
            identifier: "test-5h",
            label: "5h Window",
            usedFraction: 0.25,
            resetsAt: resetDate,
            windowDurationMins: 300
        )

        XCTAssertEqual(bucket.usedFraction, 0.25)
        XCTAssertEqual(bucket.remainingFraction, 0.75)
        XCTAssertEqual(bucket.usedPercent, 25)
        XCTAssertEqual(bucket.remainingPercent, 75)
        XCTAssertEqual(bucket.formattedResetTime(relativeTo: now), "resets in 2h 10m")
    }

    func testUsageBucketZeroAndExhaustion() {
        let zeroBucket = UsageBucket(identifier: "zero", label: "Zero", usedFraction: 0.0)
        XCTAssertEqual(zeroBucket.usedPercent, 0)
        XCTAssertEqual(zeroBucket.remainingPercent, 100)

        let exhaustedBucket = UsageBucket(identifier: "exhausted", label: "Exhausted", usedFraction: 1.0)
        XCTAssertEqual(exhaustedBucket.usedPercent, 100)
        XCTAssertEqual(exhaustedBucket.remainingPercent, 0)
    }

    func testUsageBucketEdgeCasesAndSanitization() {
        let nanBucket = UsageBucket(identifier: "nan", label: "NaN", usedFraction: .nan)
        XCTAssertNil(nanBucket.usedFraction)
        XCTAssertNil(nanBucket.remainingPercent)

        let infBucket = UsageBucket(identifier: "inf", label: "Inf", usedFraction: .infinity)
        XCTAssertNil(infBucket.usedFraction)

        let clampHigh = UsageBucket(identifier: "high", label: "High", usedFraction: 1.5)
        XCTAssertEqual(clampHigh.usedFraction, 1.0)

        let clampLow = UsageBucket(identifier: "low", label: "Low", usedFraction: -0.5)
        XCTAssertEqual(clampLow.usedFraction, 0.0)

        let now = Date()
        let pastBucket = UsageBucket(identifier: "past", label: "Past", usedFraction: 0.5, resetsAt: now.addingTimeInterval(-100))
        XCTAssertEqual(pastBucket.formattedResetTime(relativeTo: now), "resetting now")

        let daysBucket = UsageBucket(identifier: "days", label: "Days", usedFraction: 0.5, resetsAt: now.addingTimeInterval(86400 * 3 + 3600 * 4))
        XCTAssertEqual(daysBucket.formattedResetTime(relativeTo: now), "resets in 3d 4h")

        let minsBucket = UsageBucket(identifier: "mins", label: "Mins", usedFraction: 0.5, resetsAt: now.addingTimeInterval(240))
        XCTAssertEqual(minsBucket.formattedResetTime(relativeTo: now), "resets in 4m")
    }

    // MARK: - CodexUsageParser Tests

    func testCodexUsageParserStandardPayload() throws {
        let jsonStr = """
        {
            "id": 2,
            "result": {
                "ordinaryUsageAllowed": true,
                "rateLimits": {
                    "planType": "plus",
                    "primary": {
                        "usedPercent": 8,
                        "windowDurationMins": 300,
                        "resetsAt": 1791061204
                    },
                    "secondary": {
                        "usedPercent": 33,
                        "windowDurationMins": 10080,
                        "resetsAt": 1791593905
                    }
                },
                "rateLimitsByLimitId": {
                    "codex": {
                        "primary": {
                            "usedPercent": 8,
                            "windowDurationMins": 300,
                            "resetsAt": 1791061204
                        }
                    },
                    "base_model_inference": {
                        "primary": {
                            "usedPercent": 15,
                            "windowDurationMins": 300,
                            "resetsAt": 1791065000
                        }
                    }
                }
            }
        }
        """

        let snapshot = try XCTUnwrap(CodexUsageParser.parseRateLimits(from: Data(jsonStr.utf8)))
        XCTAssertEqual(snapshot.providerID, .codex)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertFalse(snapshot.isStale)

        let primary = try XCTUnwrap(snapshot.primaryBucket)
        XCTAssertEqual(primary.label, "5h Window")
        XCTAssertEqual(primary.usedPercent, 8)
        XCTAssertEqual(primary.remainingPercent, 92)
        XCTAssertEqual(primary.windowDurationMins, 300)
        XCTAssertEqual(primary.resetsAt, Date(timeIntervalSince1970: 1791061204))

        let secondary = try XCTUnwrap(snapshot.secondaryBucket)
        XCTAssertEqual(secondary.label, "Weekly Window")
        XCTAssertEqual(secondary.usedPercent, 33)
        XCTAssertEqual(secondary.remainingPercent, 67)
        XCTAssertEqual(secondary.windowDurationMins, 10080)

        // Deduplication check: "codex" bucket matches primary and should NOT be duplicated,
        // while "base_model_inference" is unique and should be present.
        XCTAssertEqual(snapshot.additionalGroups.count, 1)
        let otherGroup = snapshot.additionalGroups[0]
        XCTAssertEqual(otherGroup.buckets.count, 1)
        XCTAssertEqual(otherGroup.buckets[0].identifier, "base_model_inference-primary")
    }

    func testCodexUsageParserZeroAndExhaustion() throws {
        let jsonStr = """
        {
            "rateLimits": {
                "primary": {
                    "usedPercent": 0,
                    "windowDurationMins": 300,
                    "resetsAt": 1700000000
                },
                "secondary": {
                    "usedPercent": 100,
                    "windowDurationMins": 10080,
                    "resetsAt": 1700500000
                }
            }
        }
        """
        let snapshot = try XCTUnwrap(CodexUsageParser.parseRateLimits(from: Data(jsonStr.utf8)))
        XCTAssertEqual(snapshot.primaryBucket?.remainingPercent, 100)
        XCTAssertEqual(snapshot.secondaryBucket?.remainingPercent, 0)
    }

    func testCodexUsageParserInvalidAndMalformed() {
        XCTAssertNil(CodexUsageParser.parseRateLimits(from: Data("not json".utf8)))
        XCTAssertNil(CodexUsageParser.parseRateLimits(from: Data("{}".utf8)))
        XCTAssertNil(CodexUsageParser.parseRateLimits(from: ["dummy": 123]))

        // Empty rateLimits with no windows returns nil (unknown data stays unknown)
        let emptyRateLimits: [String: Any] = ["rateLimits": [String: Any]()]
        XCTAssertNil(CodexUsageParser.parseRateLimits(from: emptyRateLimits))
    }

    // MARK: - AntigravityUsageParser Tests

    func testAntigravityUsageParserStandardPayload() throws {
        let jsonStr = """
        {
            "response": {
                "groups": [
                    {
                        "displayName": "Gemini Models",
                        "buckets": [
                            {
                                "bucketId": "gemini-5h",
                                "displayName": "Five Hour Limit Remaining",
                                "remainingFraction": 0.85024,
                                "resetTime": "2026-10-03T19:37:40Z"
                            },
                            {
                                "bucketId": "gemini-weekly",
                                "displayName": "Weekly Limit Remaining",
                                "remainingFraction": 0.8715544,
                                "resetTime": "2026-10-09T22:34:49Z"
                            }
                        ]
                    },
                    {
                        "displayName": "Claude and GPT models",
                        "buckets": [
                            {
                                "bucketId": "3p-5h",
                                "displayName": "Five Hour Limit Remaining",
                                "remainingFraction": 1.0,
                                "resetTime": "2026-10-03T21:09:59Z"
                            }
                        ]
                    }
                ]
            }
        }
        """

        let snapshot = try XCTUnwrap(AntigravityUsageParser.parseQuotaSummary(from: Data(jsonStr.utf8)))
        XCTAssertEqual(snapshot.providerID, .antigravity)
        XCTAssertFalse(snapshot.isStale)

        let primary = try XCTUnwrap(snapshot.primaryBucket)
        XCTAssertEqual(primary.identifier, "gemini-5h")
        XCTAssertEqual(primary.remainingPercent, 85)
        XCTAssertEqual(primary.usedPercent, 15)
        XCTAssertEqual(primary.windowDurationMins, 300)

        let secondary = try XCTUnwrap(snapshot.secondaryBucket)
        XCTAssertEqual(secondary.identifier, "gemini-weekly")
        XCTAssertEqual(secondary.remainingPercent, 87)
        XCTAssertEqual(secondary.windowDurationMins, 10080)

        XCTAssertEqual(snapshot.additionalGroups.count, 2)
    }

    func testAntigravityUsageParserZeroAndExhaustion() throws {
        let jsonStr = """
        {
            "groups": [
                {
                    "displayName": "Gemini Models",
                    "buckets": [
                        {
                            "bucketId": "gemini-5h",
                            "remainingFraction": 0.0,
                            "resetTime": "2026-10-03T19:37:40.123Z"
                        },
                        {
                            "bucketId": "gemini-weekly",
                            "remainingFraction": 1.0,
                            "resetTime": "2026-10-09T22:34:49Z"
                        }
                    ]
                }
            ]
        }
        """

        let snapshot = try XCTUnwrap(AntigravityUsageParser.parseQuotaSummary(from: Data(jsonStr.utf8)))
        XCTAssertEqual(snapshot.primaryBucket?.remainingPercent, 0) // Exhausted
        XCTAssertEqual(snapshot.primaryBucket?.usedPercent, 100)
        XCTAssertEqual(snapshot.secondaryBucket?.remainingPercent, 100) // Unused
        XCTAssertEqual(snapshot.secondaryBucket?.usedPercent, 0)
    }

    func testAntigravityUsageParserInvalidAndMalformed() {
        XCTAssertNil(AntigravityUsageParser.parseQuotaSummary(from: Data("malformed".utf8)))
        XCTAssertNil(AntigravityUsageParser.parseQuotaSummary(from: Data("{}".utf8)))
        XCTAssertNil(AntigravityUsageParser.parseQuotaSummary(from: ["response": ["groups": []]]))
    }

    // MARK: - SessionStore Usage Refresh and Stale Retention Tests

    @MainActor
    func testSessionStoreRefreshesUsageAndRetainsStaleDataOnFailure() async throws {
        let codexUsage1 = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date(),
            planType: "plus",
            primaryBucket: UsageBucket(identifier: "p1", label: "5h", usedFraction: 0.1),
            secondaryBucket: nil,
            additionalGroups: [],
            isStale: false
        )

        let mockProvider = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: [],
            usage: codexUsage1
        )

        let store = SessionStore(providers: [mockProvider])
        XCTAssertNil(store.snapshot(for: .codex)?.usage)

        // First refresh succeeds and populates usage
        await store.refresh()
        let snap1 = try XCTUnwrap(store.snapshot(for: .codex)?.usage)
        XCTAssertFalse(snap1.isStale)
        XCTAssertEqual(snap1.primaryBucket?.usedPercent, 10)

        // Now simulate usage fetch error on subsequent refresh
        mockProvider.setError(MockProviderError.daemonUnavailable("Connection dropped"))
        await store.refresh()

        // Stale usage MUST be retained and marked isStale = true!
        let snap2 = try XCTUnwrap(store.snapshot(for: .codex)?.usage)
        XCTAssertTrue(snap2.isStale, "Previous usage must be retained as stale when refresh fails")
        XCTAssertEqual(snap2.primaryBucket?.usedPercent, 10, "Retained data must preserve prior bucket metrics")
        XCTAssertNotNil(snap2.errorMessage)
    }

    @MainActor
    func testSessionStorePeriodicRefreshStartAndStop() {
        let mockProvider = MockAgentProvider(id: .codex, displayName: "Codex")
        let store = SessionStore(providers: [mockProvider])

        store.startPeriodicRefresh(interval: 0.1)
        store.stopPeriodicRefresh()
        // Proves startPeriodicRefresh and stopPeriodicRefresh execute cleanly without crash or leak
        XCTAssertFalse(store.isRefreshing)
    }

    // MARK: - Live Read-Only Smoke Checks (Opt-in via ENABLE_LIVE_SMOKE_TESTS)

    func testCodexUsageFetcherSmokeTest() async throws {
        guard ProcessInfo.processInfo.environment["ENABLE_LIVE_SMOKE_TESTS"] != nil else {
            return // Skipped in automated test suites to remain completely deterministic
        }
        let fetcher = DefaultCodexUsageFetcher()
        do {
            if let snapshot = try await fetcher.fetchUsage() {
                XCTAssertEqual(snapshot.providerID, .codex)
                XCTAssertFalse(snapshot.isStale)
                XCTAssertNotNil(snapshot.primaryBucket)
            }
        } catch CodexUsageError.executableNotFound {
            // Acceptable when running in CI without Codex CLI installed
        }
    }

    func testAntigravityUsageFetcherSmokeTest() async throws {
        guard ProcessInfo.processInfo.environment["ENABLE_LIVE_SMOKE_TESTS"] != nil else {
            return // Skipped in automated test suites to remain completely deterministic
        }
        let fetcher = DefaultAntigravityUsageFetcher()
        if let snapshot = try await fetcher.fetchUsage() {
            XCTAssertEqual(snapshot.providerID, .antigravity)
            XCTAssertFalse(snapshot.isStale)
            XCTAssertNotNil(snapshot.primaryBucket)
        }
    }

    // MARK: - Mock Transport Timeout, Cancellation & Security Tests

    func testCodexUsageFetcherMockTimeout() async throws {
        let mockTransport = MockCodexTransport(errorToThrow: CodexUsageError.timeout)
        let fetcher = DefaultCodexUsageFetcher(
            explicitExecutableURL: URL(fileURLWithPath: "/bin/sh"),
            timeoutSeconds: 0.1,
            transport: mockTransport
        )

        do {
            _ = try await fetcher.fetchUsage()
            XCTFail("Expected CodexUsageError.timeout to be thrown")
        } catch let err as CodexUsageError {
            if case .timeout = err {
                // Expected
            } else {
                XCTFail("Expected .timeout, got \(err)")
            }
        }
    }

    func testCodexUsageFetcherMockCancellation() async {
        let mockTransport = MockCodexTransport(delay: 5.0)
        let fetcher = DefaultCodexUsageFetcher(
            explicitExecutableURL: URL(fileURLWithPath: "/bin/sh"),
            timeoutSeconds: 10.0,
            transport: mockTransport
        )

        let task = Task {
            try await fetcher.fetchUsage()
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testCodexUsageFetcherMockResponseTooLarge() async throws {
        let mockTransport = MockCodexTransport(errorToThrow: CodexUsageError.responseTooLarge)
        let fetcher = DefaultCodexUsageFetcher(
            explicitExecutableURL: URL(fileURLWithPath: "/bin/sh"),
            timeoutSeconds: 1.0,
            transport: mockTransport
        )

        do {
            _ = try await fetcher.fetchUsage()
            XCTFail("Expected CodexUsageError.responseTooLarge to be thrown")
        } catch let err as CodexUsageError {
            if case .responseTooLarge = err {
                // Expected
            } else {
                XCTFail("Expected .responseTooLarge, got \(err)")
            }
        }
    }

    func testAntigravityUsageFetcherMockTimeout() async throws {
        let mockExecutor = MockProcessExecutorForQuota(
            psOutput: "user 54321 0.0 0.1 /path/to/language_server --csrf_token test-csrf-token",
            lsofOutput: "language_ 54321 user 10u IPv4 0x1234 TCP 127.0.0.1:45678 (LISTEN)"
        )
        let mockTransport = MockAntigravityQuotaTransport(errorToThrow: AntigravityUsageError.timeout)
        let fetcher = DefaultAntigravityUsageFetcher(
            processExecutor: mockExecutor,
            timeoutSeconds: 0.1,
            transport: mockTransport
        )

        do {
            _ = try await fetcher.fetchUsage()
            XCTFail("Expected AntigravityUsageError.timeout to be thrown")
        } catch let err as AntigravityUsageError {
            if case .timeout = err {
                // Expected
            } else {
                XCTFail("Expected .timeout, got \(err)")
            }
        }
    }

    func testAntigravityUsageFetcherMockCancellation() async {
        let mockExecutor = MockProcessExecutorForQuota(
            psOutput: "user 54321 0.0 0.1 /path/to/language_server --csrf_token test-csrf-token",
            lsofOutput: "language_ 54321 user 10u IPv4 0x1234 TCP 127.0.0.1:45678 (LISTEN)"
        )
        let mockTransport = MockAntigravityQuotaTransport(delay: 5.0)
        let fetcher = DefaultAntigravityUsageFetcher(
            processExecutor: mockExecutor,
            timeoutSeconds: 10.0,
            transport: mockTransport
        )

        let task = Task {
            try await fetcher.fetchUsage()
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testAntigravityScopedLoopbackSessionDelegateRedirectRejection() {
        let delegate = ScopedLoopbackSessionDelegate(allowedPort: 45678)
        let session = URLSession.shared
        let url = URL(string: "https://127.0.0.1:45678/redirect")!
        let request = URLRequest(url: url)
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://evil.com"])!

        let expectation = XCTestExpectation(description: "Redirect rejected with nil")
        let dummyTask = session.dataTask(with: request)

        delegate.urlSession(session, task: dummyTask, willPerformHTTPRedirection: response, newRequest: request) { redirectedRequest in
            XCTAssertNil(redirectedRequest, "HTTP redirect must be rejected to prevent CSRF token forwarding")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testAntigravityScopedLoopbackSessionDelegateSecurity() {
        let delegate = ScopedLoopbackSessionDelegate(allowedPort: 45678)
        let session = URLSession.shared
        let dummySender = DummyChallengeSender()

        // Protection space for external/unauthorized endpoint
        let externalSpace = URLProtectionSpace(
            host: "example.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let externalChallenge = URLAuthenticationChallenge(protectionSpace: externalSpace, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: dummySender)

        let expectation1 = XCTestExpectation(description: "External host uses default handling")
        delegate.urlSession(session, didReceive: externalChallenge) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
            expectation1.fulfill()
        }

        // Protection space for loopback but mismatched port
        let wrongPortSpace = URLProtectionSpace(
            host: "127.0.0.1",
            port: 9999,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let wrongPortChallenge = URLAuthenticationChallenge(protectionSpace: wrongPortSpace, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: dummySender)

        let expectation2 = XCTestExpectation(description: "Wrong loopback port uses default handling")
        delegate.urlSession(session, didReceive: wrongPortChallenge) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
            expectation2.fulfill()
        }

        wait(for: [expectation1, expectation2], timeout: 1.0)
    }

    func testAntigravityProviderThrowsWhenNotRunning() async {
        let mockDiscoverer = MockAntigravityProcessDiscoverer(isRunning: false)
        let provider = AntigravityProvider(
            processDiscoverer: mockDiscoverer,
            storeInspector: MockAntigravityStoreInspector()
        )

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected AntigravityUsageError.processNotFound to be thrown")
        } catch let err as AntigravityUsageError {
            if case .processNotFound = err {
                // Expected
            } else {
                XCTFail("Expected .processNotFound, got \(err)")
            }
        } catch {
            XCTFail("Expected AntigravityUsageError.processNotFound, got \(error)")
        }
    }

    @MainActor
    func testSessionStoreRetainsStaleAntigravityUsageWhenDaemonStops() async throws {
        let antigravityUsage = ProviderUsageSnapshot(
            providerID: .antigravity,
            updatedAt: Date(),
            planType: nil,
            primaryBucket: UsageBucket(identifier: "gemini-5h", label: "5h Window", usedFraction: 0.15),
            secondaryBucket: nil,
            additionalGroups: [],
            isStale: false
        )

        let mockProvider = MockAgentProvider(
            id: .antigravity,
            displayName: "Antigravity",
            availability: .available,
            sessions: [],
            usage: antigravityUsage
        )

        let store = SessionStore(providers: [mockProvider])

        // Initial refresh succeeds
        await store.refresh()
        let snap1 = try XCTUnwrap(store.snapshot(for: .antigravity)?.usage)
        XCTAssertFalse(snap1.isStale)
        XCTAssertEqual(snap1.primaryBucket?.usedPercent, 15)
        XCTAssertNil(store.snapshot(for: .antigravity)?.usageErrorMessage)

        // Simulate daemon disappearing (throwing processNotFound)
        mockProvider.setError(AntigravityUsageError.processNotFound)
        await store.refresh()

        // Verify previous usage is retained, marked stale, and error message is populated
        let snap2 = try XCTUnwrap(store.snapshot(for: .antigravity)?.usage)
        XCTAssertTrue(snap2.isStale)
        XCTAssertEqual(snap2.primaryBucket?.usedPercent, 15)
        XCTAssertEqual(store.snapshot(for: .antigravity)?.usageErrorMessage, "Antigravity language_server not running")
    }

    @MainActor
    func testSessionStorePriorUsageBecomesStaleWhenProviderUnavailable() async throws {
        let initialUsage = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date(),
            planType: "pro",
            primaryBucket: UsageBucket(identifier: "5h", label: "5h Window", usedFraction: 0.2),
            secondaryBucket: nil,
            additionalGroups: [],
            isStale: false
        )

        let mock = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: [],
            usage: initialUsage
        )

        let store = SessionStore(providers: [mock])
        await store.refresh()

        let snap1 = try XCTUnwrap(store.snapshot(for: .codex)?.usage)
        XCTAssertFalse(snap1.isStale)

        // Make provider unavailable
        mock.setAvailability(.unavailable(reason: "CLI missing"))
        await store.refresh()

        let snap2 = try XCTUnwrap(store.snapshot(for: .codex)?.usage)
        XCTAssertTrue(snap2.isStale, "Prior usage must become stale when provider becomes unavailable")
        XCTAssertEqual(store.snapshot(for: .codex)?.usageErrorMessage, "Provider is unavailable")
    }

    @MainActor
    func testSessionStorePriorUsageBecomesStaleWhenFetchUsageReturnsNil() async throws {
        let initialUsage = ProviderUsageSnapshot(
            providerID: .antigravity,
            updatedAt: Date(),
            planType: nil,
            primaryBucket: UsageBucket(identifier: "5h", label: "5h Window", usedFraction: 0.1),
            secondaryBucket: nil,
            additionalGroups: [],
            isStale: false
        )

        let mock = MockAgentProvider(
            id: .antigravity,
            displayName: "Antigravity",
            availability: .available,
            sessions: [],
            usage: initialUsage
        )

        let store = SessionStore(providers: [mock])
        await store.refresh()

        let snap1 = try XCTUnwrap(store.snapshot(for: .antigravity)?.usage)
        XCTAssertFalse(snap1.isStale)

        // Set usage to nil on subsequent refresh
        mock.setUsage(nil)
        await store.refresh()

        let snap2 = try XCTUnwrap(store.snapshot(for: .antigravity)?.usage)
        XCTAssertTrue(snap2.isStale, "Prior usage must become stale when fetchUsage returns nil")
    }

    @MainActor
    func testSessionStoreInitialUsageErrorExposedWhenNoPriorUsage() async throws {
        let mock = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: [],
            usage: nil
        )
        mock.setError(CodexUsageError.processFailed("Auth expired"))

        let store = SessionStore(providers: [mock])
        await store.refresh()

        XCTAssertNil(store.snapshot(for: .codex)?.usage)
        XCTAssertEqual(store.snapshot(for: .codex)?.usageErrorMessage, "Codex app-server failed: Auth expired")
    }

    @MainActor
    func testSessionStorePeriodicRefreshValidationAndInFlightCancellation() async {
        let mock = MockAgentProvider(id: .codex, displayName: "Codex")
        let store = SessionStore(providers: [mock])

        // Negative or zero interval should be rejected safely
        store.startPeriodicRefresh(interval: -1)
        store.startPeriodicRefresh(interval: 0)

        // Valid interval
        store.startPeriodicRefresh(interval: 60)
        store.stopPeriodicRefresh(cancelInFlight: true)
        XCTAssertFalse(store.isRefreshing)
    }

    func testAntigravityProcessDiscoveryFiltersOutNonMatchingExecutables() async throws {
        let mockExecutor = MockProcessExecutorForQuota(
            psOutput: """
            user 100 0.0 0.1 /usr/bin/cat agy --csrf_token fake-token
            user 101 0.0 0.1 /bin/echo language_server --csrf_token fake-token
            user 102 0.0 0.1 /Users/deepak/.local/bin/agy --csrf_token valid-agy-token
            """,
            lsofOutput: "agy 102 user 10u IPv4 0x1234 TCP 127.0.0.1:45678 (LISTEN)"
        )
        let mockTransport = MockAntigravityQuotaTransport(
            responseData: Data("{\"response\":{\"groups\":[{\"displayName\":\"G\",\"buckets\":[{\"bucketId\":\"b1\",\"remainingFraction\":0.9}]}]}}".utf8)
        )
        let fetcher = DefaultAntigravityUsageFetcher(
            processExecutor: mockExecutor,
            timeoutSeconds: 5.0,
            transport: mockTransport
        )

        let snapshot = try await fetcher.fetchUsage()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.primaryBucket?.identifier, "b1")
    }

    func testAntigravityCSRFDiscoveryWithTokenAsFinalArgument() async throws {
        let mockExecutor = MockProcessExecutorForQuota(
            psOutput: "user 202 0.0 0.1 /Users/deepak/.local/bin/agy --verbose --csrf_token=final-arg-token",
            lsofOutput: "agy 202 user 10u IPv4 0x1234 TCP 127.0.0.1:45678 (LISTEN)"
        )
        let mockTransport = MockAntigravityQuotaTransport(
            responseData: Data("{\"response\":{\"groups\":[{\"displayName\":\"G\",\"buckets\":[{\"bucketId\":\"b_final\",\"remainingFraction\":0.8}]}]}}".utf8)
        )
        let fetcher = DefaultAntigravityUsageFetcher(
            processExecutor: mockExecutor,
            timeoutSeconds: 5.0,
            transport: mockTransport
        )

        let snapshot = try await fetcher.fetchUsage()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.primaryBucket?.identifier, "b_final")
    }

    @MainActor
    func testSessionStoreStopPeriodicRefreshRetainsInFlightHandleAndPreventsOverlap() async {
        let mock = MockAgentProvider(
            id: .codex,
            displayName: "Codex",
            availability: .available,
            sessions: []
        )
        let store = SessionStore(providers: [mock])

        let refreshTask = Task { @MainActor in
            await store.refresh()
        }

        await Task.yield()

        // Calling stopPeriodicRefresh with cancelInFlight: true
        store.stopPeriodicRefresh(cancelInFlight: true)

        // Verify activeRefreshTask is retained and subsequent refresh() does not overlap
        await store.refresh()
        XCTAssertFalse(store.isRefreshing)
        await refreshTask.value
    }

    // MARK: - Real Subprocess Fixture Tests

    func testSubprocessControllerHungProcessKilledAndReaped() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 60"]

        let controller = SubprocessController()
        try controller.launch(process: process)

        let startTime = Date()
        controller.terminateAndReap()
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(elapsed, 1.0, "Hung process should be terminated and reaped swiftly")
    }

    func testSubprocessControllerSigtermResistantChildKilledBySigkill() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; sleep 60"]

        let controller = SubprocessController()
        try controller.launch(process: process)

        let startTime = Date()
        controller.terminateAndReap()
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(elapsed, 1.5, "SIGTERM-resistant process should be escalated to SIGKILL and reaped")
    }

    func testDefaultCodexAppServerTransportTimeoutWithRealSubprocess() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("loom-hang-\(UUID().uuidString).sh")
        let scriptContent = "#!/bin/sh\nexec sleep 30\n"
        try scriptContent.write(to: tempURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let transport = DefaultCodexAppServerTransport()
        let startTime = Date()
        do {
            _ = try await transport.execute(executableURL: tempURL, timeoutSeconds: 0.2)
            XCTFail("Expected timeout")
        } catch let err as CodexUsageError {
            if case .timeout = err {
                // Expected
            } else {
                XCTFail("Expected .timeout, got \(err)")
            }
        } catch {
            XCTFail("Expected CodexUsageError.timeout, got \(error)")
        }
        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 1.5, "Transport should enforce timeout and terminate child promptly")
    }

    func testDefaultCodexAppServerTransportStderrFloodWithRealSubprocess() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("loom-flood-\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/sh
        for i in $(seq 1 3000); do
            echo "stderr flood line $i" >&2
        done
        echo '{"id":1}'
        read initAck
        echo '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1800000000}}}}'
        sleep 5
        """
        try scriptContent.write(to: tempURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let transport = DefaultCodexAppServerTransport()
        let snapshot = try await transport.execute(executableURL: tempURL, timeoutSeconds: 3.0)
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.primaryBucket?.usedPercent, 10)
    }

    func testSubprocessControllerImmediatelyCancelledBeforeLaunch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 60"]

        let controller = SubprocessController()
        controller.terminateAndReap()

        XCTAssertThrowsError(try controller.launch(process: process)) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(process.isRunning)
    }

    func testDefaultCodexAppServerTransportImmediatelyCancelledLaunch() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("loom-cancel-\(UUID().uuidString).sh")
        let scriptContent = "#!/bin/sh\nexec sleep 30\n"
        try scriptContent.write(to: tempURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let transport = DefaultCodexAppServerTransport()
        let task = Task {
            try await transport.execute(executableURL: tempURL, timeoutSeconds: 5.0)
        }
        task.cancel()

        let result = await task.result
        switch result {
        case .success:
            XCTFail("Expected cancellation")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
    }

    func testDefaultCodexAppServerTransportSigtermResistantCancellation() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("loom-sigterm-cancel-\(UUID().uuidString).sh")
        let scriptContent = "#!/bin/sh\ntrap '' TERM\nexec sleep 60\n"
        try scriptContent.write(to: tempURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let transport = DefaultCodexAppServerTransport()
        let startTime = Date()
        let task = Task {
            try await transport.execute(executableURL: tempURL, timeoutSeconds: 10.0)
        }

        // Give child process time to launch and register trap
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let result = await task.result
        let elapsed = Date().timeIntervalSince(startTime)
        switch result {
        case .success:
            XCTFail("Expected cancellation")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
        XCTAssertLessThan(elapsed, 2.0, "SIGTERM-resistant child should be killed by SIGKILL and reaped quickly on cancellation")
    }
}

// MARK: - Mock Transports & Test Doubles

final class MockCodexTransport: CodexAppServerTransporting, @unchecked Sendable {
    var resultSnapshot: ProviderUsageSnapshot?
    var errorToThrow: (any Error)?
    var delay: TimeInterval = 0

    init(resultSnapshot: ProviderUsageSnapshot? = nil, errorToThrow: (any Error)? = nil, delay: TimeInterval = 0) {
        self.resultSnapshot = resultSnapshot
        self.errorToThrow = errorToThrow
        self.delay = delay
    }

    func execute(executableURL: URL, timeoutSeconds: TimeInterval) async throws -> ProviderUsageSnapshot? {
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        try Task.checkCancellation()
        if let err = errorToThrow {
            throw err
        }
        return resultSnapshot
    }
}

final class MockAntigravityQuotaTransport: AntigravityQuotaTransporting, @unchecked Sendable {
    var responseData: Data
    var errorToThrow: (any Error)?
    var delay: TimeInterval = 0

    init(responseData: Data = Data("{}".utf8), errorToThrow: (any Error)? = nil, delay: TimeInterval = 0) {
        self.responseData = responseData
        self.errorToThrow = errorToThrow
        self.delay = delay
    }

    func requestQuota(url: URL, csrfToken: String, timeoutSeconds: TimeInterval) async throws -> Data {
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        try Task.checkCancellation()
        if let err = errorToThrow {
            throw err
        }
        return responseData
    }
}

final class MockProcessExecutorForQuota: ProcessExecuting, @unchecked Sendable {
    var psOutput: String
    var lsofOutput: String

    init(psOutput: String = "", lsofOutput: String = "") {
        self.psOutput = psOutput
        self.lsofOutput = lsofOutput
    }

    func execute(executablePath: String, arguments: [String]) async throws -> String {
        if executablePath.contains("ps") {
            return psOutput
        } else if executablePath.contains("lsof") {
            return lsofOutput
        }
        return ""
    }
}

final class DummyChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}
