//
//  NotificationProbe.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
import LoomCore

@main
struct NotificationProbe {
    static func main() async throws {
        print("==================================================")
        print("Starting Loom Notification Verification Probe")
        print("==================================================")

        try testQuotaThresholdCrossings()
        try testQuotaAlertDeduplication()
        try testWindowResetReplenishment()
        try testSessionStateTransitions()
        try testInactivityDowngradeSuppression()
        try testMissingOrStaleUsageIgnored()
        try testStartupDiscoveryStormSuppression()
        try testPrivacyPathConcealment()
        try testBoundedNotificationHistory()

        print("==================================================")
        print("ALL NOTIFICATION PROBE CHECKS PASSED SUCCESSFULLY")
        print("==================================================")
    }

    // MARK: - Check 1: Quota threshold crossings at 15% and 5%
    static func testQuotaThresholdCrossings() throws {
        print("Check 1: Quota threshold crossings at 15% and 5%")
        let store = InMemoryQuotaAlertStore()
        let evaluator = QuotaThresholdEvaluator(store: store)
        let now = Date()

        // Bucket at 20% remaining (80% used) -> Above 15% threshold -> No alert
        let bucketAbove = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.80,
            resetsAt: now.addingTimeInterval(3600)
        )
        let eventsAbove = evaluator.evaluate(provider: .codex, bucket: bucketAbove)
        guard eventsAbove.isEmpty else {
            fatalError("FAIL Check 1: Expected no events for 20% remaining, got: \(eventsAbove)")
        }

        // Bucket crossing below 15% (86% used -> 14% remaining) -> 15% alert triggered
        let bucket15 = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.86,
            resetsAt: now.addingTimeInterval(3600)
        )
        let events15 = evaluator.evaluate(provider: .codex, bucket: bucket15)
        guard events15.count == 1,
              case .quotaThresholdCrossed(let p, let b, let rem, _, let t) = events15[0],
              p == .codex, b == "5h", t == .fifteenPercent, abs(rem - 14.0) < 0.1 else {
            fatalError("FAIL Check 1: Expected 15% threshold crossing alert, got: \(events15)")
        }

        // Bucket crossing below 5% (96% used -> 4% remaining) -> 5% alert triggered
        let bucket5 = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.96,
            resetsAt: now.addingTimeInterval(3600)
        )
        let events5 = evaluator.evaluate(provider: .codex, bucket: bucket5)
        guard events5.count == 1,
              case .quotaThresholdCrossed(let p, let b, let rem, _, let t) = events5[0],
              p == .codex, b == "5h", t == .fivePercent, abs(rem - 4.0) < 0.1 else {
            fatalError("FAIL Check 1: Expected 5% threshold crossing alert, got: \(events5)")
        }

        print("  PASS: 15% and 5% threshold crossings trigger verified notification events")
    }

    // MARK: - Check 2: Deduplication prevents repeat alerts within same window and threshold
    static func testQuotaAlertDeduplication() throws {
        print("Check 2: Deduplication prevents repeat alerts within same window and threshold")
        let store = InMemoryQuotaAlertStore()
        let evaluator = QuotaThresholdEvaluator(store: store)
        let fixedWindow = "2026-10-21T12:00:00Z"
        let now = Date()

        let bucket14 = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.86, // 14% remaining
            resetsAt: now.addingTimeInterval(3600)
        )

        // First evaluation: fires 15% alert
        let first = evaluator.evaluate(provider: .antigravity, bucket: bucket14, windowId: fixedWindow)
        guard first.count == 1,
              case .quotaThresholdCrossed(_, _, _, let w, let t) = first[0],
              w == fixedWindow, t == .fifteenPercent else {
            fatalError("FAIL Check 2: First evaluation did not fire 15% alert")
        }

        // Second evaluation in same window: must be deduplicated
        let second = evaluator.evaluate(provider: .antigravity, bucket: bucket14, windowId: fixedWindow)
        guard second.isEmpty else {
            fatalError("FAIL Check 2: Second evaluation fired duplicate alert: \(second)")
        }

        // Even if quota drops slightly further (12% remaining), still within 15% tier in same window: must deduplicate
        let bucket12 = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.88, // 12% remaining
            resetsAt: now.addingTimeInterval(3600)
        )
        let third = evaluator.evaluate(provider: .antigravity, bucket: bucket12, windowId: fixedWindow)
        guard third.isEmpty else {
            fatalError("FAIL Check 2: Repeat drop within 15% threshold emitted duplicate alert: \(third)")
        }

        // Next threshold (5%) crossed in same window: must fire 5% alert
        let bucket4 = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.96, // 4% remaining
            resetsAt: now.addingTimeInterval(3600)
        )
        let fourth = evaluator.evaluate(provider: .antigravity, bucket: bucket4, windowId: fixedWindow)
        guard fourth.count == 1,
              case .quotaThresholdCrossed(_, _, _, let w, let t) = fourth[0],
              w == fixedWindow, t == .fivePercent else {
            fatalError("FAIL Check 2: Crossing into 5% threshold did not fire 5% alert")
        }

        // Repeat evaluation of 5% in same window: must be deduplicated
        let fifth = evaluator.evaluate(provider: .antigravity, bucket: bucket4, windowId: fixedWindow)
        guard fifth.isEmpty else {
            fatalError("FAIL Check 2: Repeat 5% evaluation fired duplicate alert: \(fifth)")
        }

        print("  PASS: Deduplication strictly suppresses repeat alerts within the same window and threshold tier")
    }

    // MARK: - Check 3: Window reset alerts trigger only upon verified quota replenishment
    static func testWindowResetReplenishment() throws {
        print("Check 3: Window reset alerts trigger only upon verified quota replenishment in a new window")
        let store = InMemoryQuotaAlertStore()
        let evaluator = QuotaThresholdEvaluator(store: store)
        let window1 = "2026-10-21T10:00:00Z"
        let window2 = "2026-10-21T15:00:00Z"
        let now = Date()

        // 1. Deplete quota in window 1 (4% remaining -> 5% threshold crossed)
        let depletedBucket = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.96,
            resetsAt: now.addingTimeInterval(1800)
        )
        _ = evaluator.evaluate(provider: .codex, bucket: depletedBucket, windowId: window1)

        // 2. Window changes to window 2, but quota is only 60% remaining (40% used): NOT yet replenished (requires >= 95%)
        let partialBucket = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.40,
            resetsAt: now.addingTimeInterval(18000)
        )
        let partialEvents = evaluator.evaluate(provider: .codex, bucket: partialBucket, windowId: window2)
        guard partialEvents.isEmpty else {
            fatalError("FAIL Check 3: Partial recovery (< 95%) must not emit replenishment event: \(partialEvents)")
        }

        // 3. Window changes to window 3 with fresh observation confirming quota recovered to ~100% (2% used -> 98% remaining >= 95%)
        let window3 = "2026-10-21T20:00:00Z"
        let replenishedBucket = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.02,
            resetsAt: now.addingTimeInterval(36000)
        )
        let replenishmentEvents = evaluator.evaluate(provider: .codex, bucket: replenishedBucket, windowId: window3)
        guard replenishmentEvents.count == 1,
              case .quotaReplenished(let p, let b, let w) = replenishmentEvents[0],
              p == .codex, b == "5h", w == window3 else {
            fatalError("FAIL Check 3: Verified replenishment in window 3 did not trigger alert: \(replenishmentEvents)")
        }

        // 4. Repeat evaluation in window 3: deduplication prevents repeat replenishment alerts
        let duplicateReplenishment = evaluator.evaluate(provider: .codex, bucket: replenishedBucket, windowId: window3)
        guard duplicateReplenishment.isEmpty else {
            fatalError("FAIL Check 3: Replenishment emitted duplicate alert in same window: \(duplicateReplenishment)")
        }

        // 5. Un-depleted window transition: a bucket that was never depleted must never fire replenishment on window transition
        let cleanEvaluator = QuotaThresholdEvaluator(store: InMemoryQuotaAlertStore())
        _ = cleanEvaluator.evaluate(provider: .codex, bucket: replenishedBucket, windowId: "2026-10-21T00:00:00Z")
        let unDepletedEvents = cleanEvaluator.evaluate(provider: .codex, bucket: replenishedBucket, windowId: "2026-10-21T05:00:00Z")
        guard unDepletedEvents.isEmpty else {
            fatalError("FAIL Check 3: Window transition without prior depletion fired false replenishment alert: \(unDepletedEvents)")
        }

        print("  PASS: Window reset replenishment requires verified observation >= 95% following confirmed depletion")
    }

    // MARK: - Check 4: Confirmed waiting-for-input, finished, and failed states emit session alerts
    static func testSessionStateTransitions() throws {
        print("Check 4: Confirmed waiting-for-input, finished, and failed states emit session alerts")
        let detector = SessionTransitionDetector()
        let now = Date()

        let baseSession = AgentSession(
            id: "session-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom"),
            state: .working,
            startedAt: now.addingTimeInterval(-300),
            lastActivityAt: now.addingTimeInterval(-10),
            branch: "main",
            summary: "Compiling verification probes",
            discoveryEvidence: ["Active CLI process pid 1234"]
        )

        // Seed initial state silently
        detector.seed(sessions: [baseSession], for: .codex)

        // Transition 1: .working -> .waiting (confirmed prompt waiting)
        let waitingSession = AgentSession(
            id: "session-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: baseSession.projectPath,
            state: .waiting,
            startedAt: baseSession.startedAt,
            lastActivityAt: now,
            branch: "main",
            summary: "Awaiting user confirmation to proceed",
            discoveryEvidence: ["Waiting for confirmation prompt in terminal"]
        )
        let waitingEvents = detector.detectTransitions(currentSessions: [waitingSession])
        guard waitingEvents.count == 1,
              case .sessionStateTransition(let s, let from, let to) = waitingEvents[0],
              s.id == "session-1", from == .working, to == .waiting else {
            fatalError("FAIL Check 4: Transition to .waiting did not emit event: \(waitingEvents)")
        }

        // Transition 2: .waiting -> .working -> no transition alert for working state
        let resumeWorkingSession = AgentSession(
            id: "session-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: baseSession.projectPath,
            state: .working,
            startedAt: baseSession.startedAt,
            lastActivityAt: now,
            branch: "main",
            summary: "User confirmed; executing tasks",
            discoveryEvidence: ["Active CLI process"]
        )
        let workingEvents = detector.detectTransitions(currentSessions: [resumeWorkingSession])
        guard workingEvents.isEmpty else {
            fatalError("FAIL Check 4: Resuming .working emitted unexpected event: \(workingEvents)")
        }

        // Transition 3: .working -> .finished (clean process exit)
        let finishedSession = AgentSession(
            id: "session-1",
            provider: .codex,
            projectName: "Loom",
            projectPath: baseSession.projectPath,
            state: .finished,
            startedAt: baseSession.startedAt,
            lastActivityAt: now,
            branch: "main",
            summary: "Session completed with code 0",
            discoveryEvidence: ["CLI exited cleanly with status 0"]
        )
        let finishedEvents = detector.detectTransitions(currentSessions: [finishedSession])
        guard finishedEvents.count == 1,
              case .sessionStateTransition(let s, let from, let to) = finishedEvents[0],
              s.id == "session-1", from == .working, to == .finished else {
            fatalError("FAIL Check 4: Transition to .finished did not emit event: \(finishedEvents)")
        }

        // Transition 4: .working -> .failed (abnormal exit)
        let session2 = AgentSession(
            id: "session-2",
            provider: .antigravity,
            projectName: "Project2",
            projectPath: URL(fileURLWithPath: "/tmp/project2"),
            state: .working,
            startedAt: now.addingTimeInterval(-60),
            lastActivityAt: now
        )
        detector.seed(sessions: [session2], for: .antigravity)

        let failedSession = AgentSession(
            id: "session-2",
            provider: .antigravity,
            projectName: "Project2",
            projectPath: URL(fileURLWithPath: "/tmp/project2"),
            state: .failed,
            startedAt: session2.startedAt,
            lastActivityAt: now,
            summary: "Language server crashed with fatal exception"
        )
        let failedEvents = detector.detectTransitions(currentSessions: [failedSession])
        guard failedEvents.count == 1,
              case .sessionStateTransition(let s, let from, let to) = failedEvents[0],
              s.id == "session-2", from == .working, to == .failed else {
            fatalError("FAIL Check 4: Transition to .failed did not emit event: \(failedEvents)")
        }

        print("  PASS: Confirmed transitions to waiting, finished, and failed emit session alerts")
    }

    // MARK: - Check 5: Inactivity downgrades do NOT emit false "needs input" alerts
    static func testInactivityDowngradeSuppression() throws {
        print("Check 5: Inactivity downgrades do NOT emit false 'needs input' alerts")
        let detector = SessionTransitionDetector()
        let now = Date()

        let activeSession = AgentSession(
            id: "session-idle-1",
            provider: .claude,
            projectName: "ClaudeWork",
            projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/ClaudeWork"),
            state: .working,
            startedAt: now.addingTimeInterval(-1800),
            lastActivityAt: now.addingTimeInterval(-1200)
        )
        detector.seed(sessions: [activeSession], for: .claude)

        // Session downgraded to waiting due to inactivity timeout (no user prompt evidence)
        let staleTimeoutSession = AgentSession(
            id: "session-idle-1",
            provider: .claude,
            projectName: "ClaudeWork",
            projectPath: activeSession.projectPath,
            state: .waiting,
            startedAt: activeSession.startedAt,
            lastActivityAt: activeSession.lastActivityAt,
            summary: "Awaiting activity: no new updates in 20 minutes",
            discoveryEvidence: ["Stale activity: process quiet for > 15m"]
        )

        let events = detector.detectTransitions(currentSessions: [staleTimeoutSession])
        guard events.isEmpty else {
            fatalError("FAIL Check 5: Inactivity downgrade fired false 'needs input' alert: \(events)")
        }

        print("  PASS: Inactivity downgrades are strictly suppressed and do not emit false input alerts")
    }

    // MARK: - Check 6: Missing or stale usage snapshots never trigger alerts
    static func testMissingOrStaleUsageIgnored() throws {
        print("Check 6: Missing or stale usage snapshots never trigger alerts")
        let store = InMemoryQuotaAlertStore()
        let evaluator = QuotaThresholdEvaluator(store: store)
        let now = Date()

        let lowBucket = UsageBucket(
            identifier: "5h",
            label: "5-hour window",
            usedFraction: 0.98, // 2% remaining -> would trigger 5% threshold if fresh
            resetsAt: now.addingTimeInterval(1200)
        )

        // Stale snapshot marked with error
        let staleSnapshot = ProviderUsageSnapshot(
            providerID: .codex,
            planType: "Plus",
            primaryBucket: lowBucket,
            isStale: true,
            errorMessage: "Connection timed out fetching usage limits"
        )
        let staleEvents = evaluator.evaluate(snapshot: staleSnapshot)
        guard staleEvents.isEmpty else {
            fatalError("FAIL Check 6: Stale snapshot fired alert: \(staleEvents)")
        }

        // Individual bucket with isStale: true
        let staleBucketEvents = evaluator.evaluate(provider: .codex, bucket: lowBucket, isStale: true)
        guard staleBucketEvents.isEmpty else {
            fatalError("FAIL Check 6: Stale bucket evaluation fired alert: \(staleBucketEvents)")
        }

        // Claude snapshot (quota tracking unsupported)
        let claudeSnapshot = ProviderUsageSnapshot(
            providerID: .claude,
            planType: nil,
            primaryBucket: lowBucket
        )
        let claudeEvents = evaluator.evaluate(snapshot: claudeSnapshot)
        guard claudeEvents.isEmpty else {
            fatalError("FAIL Check 6: Unsupported Claude quota fired alert: \(claudeEvents)")
        }

        // Snapshot with error message and no valid bucket values
        let emptyErrorBucket = UsageBucket(identifier: "5h", label: "5-hour window", usedFraction: nil)
        let erroredSnapshot = ProviderUsageSnapshot(
            providerID: .codex,
            planType: "Plus",
            primaryBucket: emptyErrorBucket,
            errorMessage: "Rate limit endpoint returned 500"
        )
        let errorEvents = evaluator.evaluate(snapshot: erroredSnapshot)
        guard errorEvents.isEmpty else {
            fatalError("FAIL Check 6: Errored snapshot with nil bucket fired alert: \(errorEvents)")
        }

        print("  PASS: Missing, stale, errored, and unsupported usage snapshots never trigger alerts")
    }

    // MARK: - Check 7: Initial startup discovery does not cause alert storms
    static func testStartupDiscoveryStormSuppression() throws {
        print("Check 7: Initial startup discovery does not cause alert storms")
        let detector = SessionTransitionDetector()
        let now = Date()

        // 10 active sessions discovered on initial app launch (mix of working, waiting, finished)
        var startupSessions: [AgentSession] = []
        for i in 1...10 {
            let provider: ProviderID = (i % 2 == 0) ? .codex : .antigravity
            let state: AgentState
            if i == 1 {
                state = .waiting
            } else if i == 2 {
                state = .finished
            } else {
                state = .working
            }
            let session = AgentSession(
                id: "initial-\(i)",
                provider: provider,
                projectName: "Repo\(i)",
                projectPath: URL(fileURLWithPath: "/tmp/repo\(i)"),
                state: state,
                startedAt: now.addingTimeInterval(-Double(i * 300)),
                lastActivityAt: now
            )
            startupSessions.append(session)
        }

        // First global scan on startup without prior seeding: MUST return []
        let initialEvents = detector.detectTransitions(currentSessions: startupSessions)
        guard initialEvents.isEmpty else {
            fatalError("FAIL Check 7: Startup discovery fired alert storm of \(initialEvents.count) events!")
        }

        // Subsequent scan where ONE session transitions to finished: MUST emit only that single alert
        var nextSessions = startupSessions
        let transitionedIndex = nextSessions.firstIndex(where: { $0.id == "initial-3" })!
        nextSessions[transitionedIndex] = AgentSession(
            id: "initial-3",
            provider: .antigravity,
            projectName: "Repo3",
            projectPath: URL(fileURLWithPath: "/tmp/repo3"),
            state: .finished,
            startedAt: now.addingTimeInterval(-900),
            lastActivityAt: now,
            summary: "Task finished successfully"
        )

        let nextEvents = detector.detectTransitions(currentSessions: nextSessions)
        guard nextEvents.count == 1,
              case .sessionStateTransition(let s, _, let to) = nextEvents[0],
              s.id == "initial-3", to == .finished else {
            fatalError("FAIL Check 7: Second scan did not detect the single real transition: \(nextEvents)")
        }

        print("  PASS: Initial startup scan seeds baseline cleanly with zero alert storm emissions")
    }

    // MARK: - Check 8: Privacy path concealment properly hides raw paths in notification content
    static func testPrivacyPathConcealment() throws {
        print("Check 8: Privacy path concealment properly hides raw paths in notification content")

        // 1. Path sanitizer unit assertions
        let policyConcealed = NotificationPolicy(config: NotificationPolicyConfig(hideProjectPaths: true))
        let policyRaw = NotificationPolicy(config: NotificationPolicyConfig(hideProjectPaths: false))

        let rawPath = "/Users/deepak/Desktop/Projects/secret-internal-tool"
        let sanitized = policyConcealed.sanitizePath(rawPath)
        guard sanitized == "secret-internal-tool" else {
            fatalError("FAIL Check 8: Expected 'secret-internal-tool', got: '\(sanitized)'")
        }

        let rawPreserved = policyRaw.sanitizePath(rawPath)
        guard rawPreserved == rawPath else {
            fatalError("FAIL Check 8: Expected unchanged path when privacy off, got: '\(rawPreserved)'")
        }

        // 2. Embedded path replacement in long summary text
        let summaryWithPaths = "Compiled executable at /Users/deepak/Desktop/Projects/secret-app/build/release/bin"
        let sanitizedSummary = policyConcealed.sanitizePath(summaryWithPaths)
        guard !sanitizedSummary.contains("/Users/deepak"),
              sanitizedSummary.contains("bin") else {
            fatalError("FAIL Check 8: Embedded path was not concealed in summary: \(sanitizedSummary)")
        }

        // 3. Formatted notification content verification
        let session = AgentSession(
            id: "priv-1",
            provider: .codex,
            projectName: "/Users/deepak/Desktop/Projects/confidential-firmware",
            projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/confidential-firmware"),
            state: .waiting,
            startedAt: Date(),
            lastActivityAt: Date(),
            summary: "Awaiting approval for /Users/deepak/Desktop/Projects/confidential-firmware/flash.sh"
        )

        let event = MonitoringEvent.sessionStateTransition(session: session, fromState: .working, toState: .waiting)

        // Filter and format with privacy active
        let filtered = policyConcealed.filter(events: [event])
        guard filtered.count == 1 else {
            fatalError("FAIL Check 8: Filter dropped valid waiting event")
        }

        let formatted = policyConcealed.formatNotification(for: filtered[0])
        guard !formatted.title.contains("/Users/deepak"),
              !formatted.body.contains("/Users/deepak") else {
            fatalError("FAIL Check 8: Notification exposed raw path: title='\(formatted.title)', body='\(formatted.body)'")
        }
        guard formatted.title.contains("confidential-firmware") else {
            fatalError("FAIL Check 8: Title missing base project name: '\(formatted.title)'")
        }

        print("  PASS: Privacy path concealment masks filesystem directory hierarchies while retaining project identity")
    }

    // MARK: - Check 9: Bounded notification history caps entries at max capacity
    static func testBoundedNotificationHistory() throws {
        print("Check 9: Bounded notification history caps entries at max capacity")
        let capacity = 10
        let history = NotificationHistoryStore(maxCapacity: capacity)

        // Record 25 entries
        for i in 1...25 {
            history.record(
                title: "Alert \(i)",
                body: "Body message for event \(i)",
                provider: .codex,
                eventType: "quotaThresholdCrossed"
            )
        }

        let records = history.records
        guard records.count == capacity else {
            fatalError("FAIL Check 9: Expected buffer count \(capacity), got: \(records.count)")
        }

        // Oldest 15 records (1...15) must have been dropped; newest 10 (16...25) must remain
        guard let first = records.first, first.title == "Alert 16" else {
            fatalError("FAIL Check 9: Expected first preserved record to be 'Alert 16', got: '\(records.first?.title ?? "nil")'")
        }
        guard let last = records.last, last.title == "Alert 25" else {
            fatalError("FAIL Check 9: Expected last preserved record to be 'Alert 25', got: '\(records.last?.title ?? "nil")'")
        }

        // Verify sensitive token sanitization in history
        history.record(
            title: "Codex Auth",
            body: "Connecting with token sk-ant-api03-abcdef1234567890 and Bearer secret-token-xyz",
            provider: .codex,
            eventType: "auth"
        )
        let newest = history.records.last!
        guard !newest.body.contains("abcdef1234567890"),
              !newest.body.contains("secret-token-xyz") else {
            fatalError("FAIL Check 9: Sensitive auth token was not scrubbed from history record: '\(newest.body)'")
        }

        print("  PASS: Notification history strictly caps entries at max capacity and scrubs credentials")
    }
}
