//
//  NotificationEventTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import LoomCore

final class NotificationEventTests: XCTestCase {

    // MARK: - Quota Threshold Crossing Tests

    func testQuotaThreshold15PercentCrossing() {
        let evaluator = QuotaThresholdEvaluator()
        let resetDate = Date(timeIntervalSince1970: 1800000000)

        // 1. Initial healthy state: 20% used -> 80% remaining
        let initialBucket = UsageBucket(
            identifier: "codex-primary",
            label: "5h Window",
            usedFraction: 0.20,
            resetsAt: resetDate,
            windowDurationMins: 300
        )
        let initialEvents = evaluator.evaluate(provider: .codex, bucket: initialBucket, windowId: "W1")
        XCTAssertTrue(initialEvents.isEmpty, "Healthy quota should not generate threshold events")

        // 2. Crosses below 15%: 86% used -> 14% remaining
        let lowBucket = UsageBucket(
            identifier: "codex-primary",
            label: "5h Window",
            usedFraction: 0.86,
            resetsAt: resetDate,
            windowDurationMins: 300
        )
        let lowEvents = evaluator.evaluate(provider: .codex, bucket: lowBucket, windowId: "W1")
        XCTAssertEqual(lowEvents.count, 1)

        guard case let .quotaThresholdCrossed(provider, bucket, remainingPercent, windowId, threshold) = lowEvents.first else {
            XCTFail("Expected quotaThresholdCrossed event")
            return
        }

        XCTAssertEqual(provider, .codex)
        XCTAssertEqual(bucket, "codex-primary")
        XCTAssertEqual(windowId, "W1")
        XCTAssertEqual(threshold, .fifteenPercent)
        XCTAssertEqual(Int(remainingPercent.rounded()), 14)
    }

    func testQuotaThreshold5PercentCrossing() {
        let evaluator = QuotaThresholdEvaluator()
        let resetDate = Date(timeIntervalSince1970: 1800000000)

        // First transition to 12% (15% threshold)
        let bucket12 = UsageBucket(
            identifier: "codex-primary",
            label: "5h Window",
            usedFraction: 0.88,
            resetsAt: resetDate,
            windowDurationMins: 300
        )
        let events12 = evaluator.evaluate(provider: .codex, bucket: bucket12, windowId: "W1")
        XCTAssertEqual(events12.count, 1)
        XCTAssertEqual(events12.first, .quotaThresholdCrossed(
            provider: .codex,
            bucket: "codex-primary",
            remainingPercent: 12.0,
            windowId: "W1",
            threshold: .fifteenPercent
        ))

        // Drops further to 4% (5% threshold)
        let bucket4 = UsageBucket(
            identifier: "codex-primary",
            label: "5h Window",
            usedFraction: 0.96,
            resetsAt: resetDate,
            windowDurationMins: 300
        )
        let events4 = evaluator.evaluate(provider: .codex, bucket: bucket4, windowId: "W1")
        XCTAssertEqual(events4.count, 1)

        guard case let .quotaThresholdCrossed(provider, bucket, remainingPercent, windowId, threshold) = events4.first else {
            XCTFail("Expected quotaThresholdCrossed for 5% threshold")
            return
        }

        XCTAssertEqual(provider, .codex)
        XCTAssertEqual(bucket, "codex-primary")
        XCTAssertEqual(windowId, "W1")
        XCTAssertEqual(threshold, .fivePercent)
        XCTAssertEqual(Int(remainingPercent.rounded()), 4)
    }

    func testNoDuplicateAlertsOnRepeatPollsWithSameValue() {
        let evaluator = QuotaThresholdEvaluator()
        let resetDate = Date(timeIntervalSince1970: 1800000000)

        let bucket10 = UsageBucket(
            identifier: "gemini-5h",
            label: "5h Window",
            usedFraction: 0.90, // 10% remaining
            resetsAt: resetDate,
            windowDurationMins: 300
        )

        // Poll 1: 15% alert fires
        let poll1 = evaluator.evaluate(provider: .antigravity, bucket: bucket10, windowId: "W1")
        XCTAssertEqual(poll1.count, 1)

        // Poll 2: identical remaining percentage; must NOT fire duplicate alert
        let poll2 = evaluator.evaluate(provider: .antigravity, bucket: bucket10, windowId: "W1")
        XCTAssertTrue(poll2.isEmpty, "Repeat poll with same value must not fire duplicate alert")

        // Poll 3: identical remaining percentage again
        let poll3 = evaluator.evaluate(provider: .antigravity, bucket: bucket10, windowId: "W1")
        XCTAssertTrue(poll3.isEmpty, "Third poll with same value must not fire duplicate alert")

        // Poll 4: drops to 4% remaining; 5% alert fires once
        let bucket4 = UsageBucket(
            identifier: "gemini-5h",
            label: "5h Window",
            usedFraction: 0.96, // 4% remaining
            resetsAt: resetDate,
            windowDurationMins: 300
        )
        let poll4 = evaluator.evaluate(provider: .antigravity, bucket: bucket4, windowId: "W1")
        XCTAssertEqual(poll4.count, 1)
        XCTAssertEqual(poll4.first, .quotaThresholdCrossed(
            provider: .antigravity,
            bucket: "gemini-5h",
            remainingPercent: 4.0,
            windowId: "W1",
            threshold: .fivePercent
        ))

        // Poll 5: repeat poll with 4% remaining; must NOT fire duplicate
        let poll5 = evaluator.evaluate(provider: .antigravity, bucket: bucket4, windowId: "W1")
        XCTAssertTrue(poll5.isEmpty, "Repeat poll at 4% must not fire duplicate")
    }

    func testQuotaResetAlertInNewWindow() {
        let evaluator = QuotaThresholdEvaluator()

        // 1. In Window 1, quota is depleted to 8% remaining
        let depletedBucketW1 = UsageBucket(
            identifier: "codex-primary",
            label: "5h Window",
            usedFraction: 0.92,
            resetsAt: Date(timeIntervalSince1970: 1800000000),
            windowDurationMins: 300
        )
        let w1Events = evaluator.evaluate(provider: .codex, bucket: depletedBucketW1, windowId: "window-1")
        XCTAssertFalse(w1Events.isEmpty, "Should alert on low quota in window-1")

        // 2. New Window 2 arrives with fresh replenished quota (98% remaining)
        let replenishedBucketW2 = UsageBucket(
            identifier: "codex-primary",
            label: "5h Window",
            usedFraction: 0.02,
            resetsAt: Date(timeIntervalSince1970: 1800018000),
            windowDurationMins: 300
        )
        let w2Events = evaluator.evaluate(provider: .codex, bucket: replenishedBucketW2, windowId: "window-2")
        XCTAssertEqual(w2Events.count, 1)

        guard case let .quotaReplenished(provider, bucket, windowId) = w2Events.first else {
            XCTFail("Expected quotaReplenished event in window-2")
            return
        }
        XCTAssertEqual(provider, .codex)
        XCTAssertEqual(bucket, "codex-primary")
        XCTAssertEqual(windowId, "window-2")

        // 3. Repeat poll in Window 2: must not fire duplicate replenishment alert
        let w2RepeatEvents = evaluator.evaluate(provider: .codex, bucket: replenishedBucketW2, windowId: "window-2")
        XCTAssertTrue(w2RepeatEvents.isEmpty, "Repeat poll in window-2 must not duplicate replenishment alert")
    }

    func testStaleSnapshotIgnored() {
        let evaluator = QuotaThresholdEvaluator()

        let lowBucket = UsageBucket(
            identifier: "codex-primary",
            label: "5h Window",
            usedFraction: 0.98 // 2% remaining
        )
        let staleSnapshot = ProviderUsageSnapshot(
            providerID: .codex,
            updatedAt: Date().addingTimeInterval(-3600),
            primaryBucket: lowBucket,
            isStale: true
        )

        let events = evaluator.evaluate(snapshot: staleSnapshot)
        XCTAssertTrue(events.isEmpty, "Stale usage snapshots must be completely ignored")
    }

    func testClaudeUnsupportedIgnored() {
        let evaluator = QuotaThresholdEvaluator()

        let bucket = UsageBucket(
            identifier: "claude-bucket",
            label: "Session",
            usedFraction: 0.99
        )
        let claudeSnapshot = ProviderUsageSnapshot(
            providerID: .claude,
            primaryBucket: bucket,
            isStale: false
        )

        let events = evaluator.evaluate(snapshot: claudeSnapshot)
        XCTAssertTrue(events.isEmpty, "Claude Code usage data is unsupported and must be ignored")
    }

    func testFailedSnapshotIgnored() {
        let evaluator = QuotaThresholdEvaluator()

        let failedSnapshot = ProviderUsageSnapshot(
            providerID: .codex,
            primaryBucket: nil,
            secondaryBucket: nil,
            isStale: false,
            errorMessage: "Connection refused: daemon unreachable"
        )

        let events = evaluator.evaluate(snapshot: failedSnapshot)
        XCTAssertTrue(events.isEmpty, "Failed usage snapshots must not trigger alerts")
    }

    func testDeduplicationAcrossSimulatedRestarts() {
        let suiteName = "TestQuotaDeduplication_\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let bucket = UsageBucket(
            identifier: "codex-primary",
            label: "5h Window",
            usedFraction: 0.90, // 10% remaining
            resetsAt: Date(timeIntervalSince1970: 1800000000),
            windowDurationMins: 300
        )

        // Run 1: First app instance runs and detects threshold crossing
        let instance1 = QuotaThresholdEvaluator(userDefaults: userDefaults)
        let events1 = instance1.evaluate(provider: .codex, bucket: bucket, windowId: "W1")
        XCTAssertEqual(events1.count, 1, "First instance should fire alert")

        // Simulate App Restart: Deallocate instance1, create instance2 with same persisted defaults
        let instance2 = QuotaThresholdEvaluator(userDefaults: userDefaults)
        let events2 = instance2.evaluate(provider: .codex, bucket: bucket, windowId: "W1")
        XCTAssertTrue(events2.isEmpty, "Second instance after restart must deduplicate using persisted keys")
    }

    // MARK: - Session State Transition Tests

    func testSessionInitialDiscoveryDoesNotFire() {
        let detector = SessionTransitionDetector()

        let initialSession = AgentSession(
            id: "session-1",
            provider: .codex,
            projectName: "Loom",
            state: .working,
            discoveryEvidence: ["State: Working (active task)"]
        )

        // First scan after app launch
        let events = detector.detectTransitions(currentSessions: [initialSession])
        XCTAssertTrue(events.isEmpty, "Initial discovery scan must seed state and never fire transition alerts")
    }

    func testSessionWorkingToConfirmedWaitingFires() {
        let detector = SessionTransitionDetector()

        let workingSession = AgentSession(
            id: "session-1",
            provider: .claude,
            projectName: "Loom",
            state: .working,
            discoveryEvidence: ["State: Working (tool execution)"]
        )

        // Seed initial state
        _ = detector.detectTransitions(currentSessions: [workingSession])

        // Cycle 2: transitions to confirmed waiting (user input required)
        let waitingSession = AgentSession(
            id: "session-1",
            provider: .claude,
            projectName: "Loom",
            state: .waiting,
            summary: "Awaiting confirmation: run tests",
            discoveryEvidence: ["State: Waiting (user input required)"]
        )

        let events = detector.detectTransitions(currentSessions: [waitingSession])
        XCTAssertEqual(events.count, 1)

        guard case let .sessionStateTransition(session, fromState, toState) = events.first else {
            XCTFail("Expected sessionStateTransition event")
            return
        }

        XCTAssertEqual(session.id, "session-1")
        XCTAssertEqual(fromState, .working)
        XCTAssertEqual(toState, .waiting)
    }

    func testSessionWorkingToFinishedFires() {
        let detector = SessionTransitionDetector()

        let workingSession = AgentSession(
            id: "session-2",
            provider: .antigravity,
            projectName: "ProjectX",
            state: .working,
            discoveryEvidence: ["State: Working (running)"]
        )

        _ = detector.detectTransitions(currentSessions: [workingSession])

        // Cycle 2: Session finishes cleanly
        let finishedSession = AgentSession(
            id: "session-2",
            provider: .antigravity,
            projectName: "ProjectX",
            state: .finished,
            discoveryEvidence: ["State: Finished (task completed)"]
        )

        let events = detector.detectTransitions(currentSessions: [finishedSession])
        XCTAssertEqual(events.count, 1)

        guard case let .sessionStateTransition(session, fromState, toState) = events.first else {
            XCTFail("Expected sessionStateTransition event")
            return
        }

        XCTAssertEqual(session.id, "session-2")
        XCTAssertEqual(fromState, .working)
        XCTAssertEqual(toState, .finished)
    }

    func testSessionWorkingToFailedFires() {
        let detector = SessionTransitionDetector()

        let workingSession = AgentSession(
            id: "session-3",
            provider: .codex,
            projectName: "AppEngine",
            state: .working
        )

        _ = detector.detectTransitions(currentSessions: [workingSession])

        // Cycle 2: Session failed
        let failedSession = AgentSession(
            id: "session-3",
            provider: .codex,
            projectName: "AppEngine",
            state: .failed,
            summary: "Command terminated with fatal signal 9"
        )

        let events = detector.detectTransitions(currentSessions: [failedSession])
        XCTAssertEqual(events.count, 1)

        guard case let .sessionStateTransition(session, fromState, toState) = events.first else {
            XCTFail("Expected sessionStateTransition event")
            return
        }

        XCTAssertEqual(session.id, "session-3")
        XCTAssertEqual(fromState, .working)
        XCTAssertEqual(toState, .failed)
    }

    func testInactivityDowngradeDoesNotFireFalseNeedsInput() {
        let detector = SessionTransitionDetector()

        let workingSession = AgentSession(
            id: "session-4",
            provider: .codex,
            projectName: "DataPipeline",
            state: .working,
            discoveryEvidence: ["State: Working (processing)"]
        )

        _ = detector.detectTransitions(currentSessions: [workingSession])

        // Cycle 2: Inactivity timeout reconciler downgrade
        let inactiveSession = AgentSession(
            id: "session-4",
            provider: .codex,
            projectName: "DataPipeline",
            state: .waiting,
            summary: "Awaiting activity",
            discoveryEvidence: ["Stale activity: no recorded activity for 31m; transitioned to Waiting"]
        )

        let events = detector.detectTransitions(currentSessions: [inactiveSession])
        XCTAssertTrue(events.isEmpty, "Inactivity timeout downgrade must not fire false 'needs input' alert")
    }

    func testSessionFinishedSuppressedOnProviderDiscoveryFailure() {
        let detector = SessionTransitionDetector()

        let workingSession = AgentSession(
            id: "session-5",
            provider: .codex,
            projectName: "BackendService",
            state: .working
        )

        _ = detector.detectTransitions(currentSessions: [workingSession])

        // Cycle 2: Codex discovery failed with an error, so no sessions returned
        let events = detector.detectTransitions(
            currentSessions: [],
            failedProviders: [.codex]
        )

        XCTAssertTrue(events.isEmpty, "Must not fire Finished notification when provider discovery failed")
    }

    func testSessionFinishedSuppressedOnProviderCancellation() {
        let detector = SessionTransitionDetector()

        let workingSession = AgentSession(
            id: "session-6",
            provider: .antigravity,
            projectName: "SearchTool",
            state: .working
        )

        _ = detector.detectTransitions(currentSessions: [workingSession])

        // Cycle 2: Antigravity scan cancelled
        let events = detector.detectTransitions(
            currentSessions: [],
            cancelledProviders: [.antigravity]
        )

        XCTAssertTrue(events.isEmpty, "Must not fire Finished notification when provider discovery was cancelled")
    }

    func testSessionHelperProcessDeduplication() {
        let detector = SessionTransitionDetector()

        // Same session ID represented by parent and helper processes
        let parentProc = AgentProcess(pid: 100, executable: "node", commandLine: "node index.js", provider: .codex)
        let workerProc = AgentProcess(pid: 101, parentPID: 100, executable: "node", commandLine: "node worker.js", provider: .codex)

        let initialParent = AgentSession(
            id: "session-logical-1",
            provider: .codex,
            projectName: "Cluster",
            state: .working,
            pid: 100,
            associatedProcesses: [parentProc, workerProc]
        )
        let initialWorker = AgentSession(
            id: "session-logical-1",
            provider: .codex,
            projectName: "Cluster",
            state: .working,
            pid: 101,
            associatedProcesses: [parentProc, workerProc]
        )

        _ = detector.detectTransitions(currentSessions: [initialParent, initialWorker])

        // Cycle 2: Both child processes report finished
        let finishedParent = AgentSession(
            id: "session-logical-1",
            provider: .codex,
            projectName: "Cluster",
            state: .finished,
            pid: 100
        )
        let finishedWorker = AgentSession(
            id: "session-logical-1",
            provider: .codex,
            projectName: "Cluster",
            state: .finished,
            pid: 101
        )

        let events = detector.detectTransitions(currentSessions: [finishedParent, finishedWorker])
        XCTAssertEqual(events.count, 1, "Helper processes with same logical session ID must deduplicate to 1 transition event")
    }

    // MARK: - Notification Policy Tests

    func testNotificationPolicyPreferencesFiltering() {
        var config = NotificationPolicyConfig()
        let policy = NotificationPolicy(config: config)

        let quota15Event = MonitoringEvent.quotaThresholdCrossed(
            provider: .codex,
            bucket: "codex-primary",
            remainingPercent: 12.0,
            windowId: "W1",
            threshold: .fifteenPercent
        )
        let quota5Event = MonitoringEvent.quotaThresholdCrossed(
            provider: .codex,
            bucket: "codex-primary",
            remainingPercent: 3.0,
            windowId: "W1",
            threshold: .fivePercent
        )
        let sessionWaitingEvent = MonitoringEvent.sessionStateTransition(
            session: AgentSession(id: "s1", provider: .codex, state: .waiting),
            fromState: .working,
            toState: .waiting
        )

        // 1. By default, all are enabled
        XCTAssertTrue(policy.shouldDeliver(event: quota15Event))
        XCTAssertTrue(policy.shouldDeliver(event: quota5Event))
        XCTAssertTrue(policy.shouldDeliver(event: sessionWaitingEvent))

        // 2. Disable 15% threshold alerts specifically
        config.quotaFifteenPercentEnabled = false
        let policyNo15 = NotificationPolicy(config: config)
        XCTAssertFalse(policyNo15.shouldDeliver(event: quota15Event))
        XCTAssertTrue(policyNo15.shouldDeliver(event: quota5Event))

        // 3. Disable master toggle
        config.notificationsEnabled = false
        let policyDisabled = NotificationPolicy(config: config)
        XCTAssertFalse(policyDisabled.shouldDeliver(event: quota5Event))
        XCTAssertFalse(policyDisabled.shouldDeliver(event: sessionWaitingEvent))

        // 4. Filter by enabled providers
        var providerConfig = NotificationPolicyConfig()
        providerConfig.enabledProviders = [.claude]
        let policyClaudeOnly = NotificationPolicy(config: providerConfig)
        XCTAssertFalse(policyClaudeOnly.shouldDeliver(event: quota15Event), "Codex event should be blocked when only Claude is enabled")
    }

    func testNotificationPolicyPrivacyPathConcealment() {
        let privacyConfig = NotificationPolicyConfig(hideProjectPaths: true)
        let policy = NotificationPolicy(config: privacyConfig)

        let fullPath = URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/secret-repo")
        let session = AgentSession(
            id: "s-private",
            provider: .codex,
            projectName: "/Users/deepak/Desktop/Projects/secret-repo",
            projectPath: fullPath,
            state: .waiting,
            summary: "Task in /Users/deepak/Desktop/Projects/secret-repo/Sources/main.swift",
            discoveryEvidence: ["Opened /Users/deepak/Desktop/Projects/secret-repo"]
        )

        let event = MonitoringEvent.sessionStateTransition(
            session: session,
            fromState: .working,
            toState: .waiting
        )

        let sanitized = policy.sanitize(event: event)
        guard case let .sessionStateTransition(sanitizedSession, _, _) = sanitized else {
            XCTFail("Expected sessionStateTransition event")
            return
        }

        XCTAssertEqual(sanitizedSession.projectName, "secret-repo", "Full path must be masked to project name")
        XCTAssertNil(sanitizedSession.projectPath, "Full project path URL must be concealed")
        XCTAssertFalse(sanitizedSession.summary?.contains("/Users/deepak") ?? true, "Summary must not leak absolute home directories")

        let notification = policy.formatNotification(for: sanitized)
        XCTAssertEqual(notification.title, "Codex: secret-repo")
        XCTAssertFalse(notification.title.contains("/Users/"))
        XCTAssertFalse(notification.body.contains("/Users/"))
    }

    // MARK: - Notification History Store Tests

    func testNotificationHistoryStoreBoundedRingBuffer() {
        let store = NotificationHistoryStore(maxCapacity: 5)
        XCTAssertEqual(store.count, 0)

        // Append 8 items into capacity 5
        for i in 1...8 {
            store.record(
                title: "Alert \(i)",
                body: "Body \(i)",
                provider: .codex,
                eventType: "quotaThresholdCrossed"
            )
        }

        XCTAssertEqual(store.count, 5, "Ring buffer must not exceed maxCapacity")
        let titles = store.records.map(\.title)
        XCTAssertEqual(titles, ["Alert 4", "Alert 5", "Alert 6", "Alert 7", "Alert 8"], "Oldest 3 records must be dropped")
    }

    func testNotificationHistoryStoreSensitiveDataScrubbing() {
        let store = NotificationHistoryStore()

        store.record(
            title: "Codex Alert",
            body: "Failed with key sk-ant-api03-abcdef1234567890 and Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz",
            provider: .codex,
            eventType: "quotaThresholdCrossed"
        )

        guard let record = store.records.first else {
            XCTFail("Expected stored record")
            return
        }

        XCTAssertFalse(record.body.contains("sk-ant-api03-abcdef1234567890"), "API key must be redacted")
        XCTAssertTrue(record.body.contains("sk-[REDACTED]"))
        XCTAssertFalse(record.body.contains("eyJhbGciOi"), "Bearer token must be redacted")
        XCTAssertTrue(record.body.contains("Bearer [REDACTED]"))
    }
}
