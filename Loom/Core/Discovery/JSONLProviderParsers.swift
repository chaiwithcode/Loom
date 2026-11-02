//
//  JSONLProviderParsers.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public enum JSONLProviderParsers {

    // MARK: - 1. Codex CLI Rollout Parser (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)

    private struct CodexRolloutEnvelope: Decodable {
        let timestamp: String?
        let type: String?
        let payload: CodexPayload?
    }

    private struct CodexPayload: Decodable {
        // session_meta / turn_context fields
        let id: String?
        let cwd: String?
        let model: String?
        let approval_mode: String?

        // event_msg fields
        let type: String?
        let info: CodexEventInfo?
    }

    private struct CodexEventInfo: Decodable {
        let total_token_usage: CodexTokenUsage?
    }

    private struct CodexTokenUsage: Decodable {
        let input_tokens: Int?
        let cached_input_tokens: Int?
        let output_tokens: Int?
        let reasoning_output_tokens: Int?
    }

    public struct CodexParsedTranscript: Sendable {
        public var sessionID: String?
        public var cwd: String?
        public var model: String?
        public var approvalMode: String?
        public var latestTokenUsage: TokenUsageSnapshot?
        public var lastEventType: String?

        public init(
            sessionID: String? = nil,
            cwd: String? = nil,
            model: String? = nil,
            approvalMode: String? = nil,
            latestTokenUsage: TokenUsageSnapshot? = nil,
            lastEventType: String? = nil
        ) {
            self.sessionID = sessionID
            self.cwd = cwd
            self.model = model
            self.approvalMode = approvalMode
            self.latestTokenUsage = latestTokenUsage
            self.lastEventType = lastEventType
        }
    }

    public static func parseCodex(snapshot: JSONLSnapshot) -> CodexParsedTranscript {
        let decoder = JSONDecoder()
        var parsed = CodexParsedTranscript()

        // 1. Parse head lines for `session_meta`
        for line in snapshot.headLines {
            guard let env = try? decoder.decode(CodexRolloutEnvelope.self, from: line) else { continue }
            if env.type == "session_meta" || env.type == "turn_context" {
                if let id = env.payload?.id { parsed.sessionID = id }
                if let cwd = env.payload?.cwd { parsed.cwd = cwd }
                if let model = env.payload?.model { parsed.model = model }
                if let mode = env.payload?.approval_mode { parsed.approvalMode = mode }
            }
        }

        // 2. Parse tail lines for latest context and cumulative `total_token_usage`
        for line in snapshot.tailLines {
            guard let env = try? decoder.decode(CodexRolloutEnvelope.self, from: line) else { continue }
            parsed.lastEventType = env.type

            if env.type == "turn_context" {
                if let cwd = env.payload?.cwd { parsed.cwd = cwd }
                if let model = env.payload?.model { parsed.model = model }
                if let mode = env.payload?.approval_mode { parsed.approvalMode = mode }
            } else if env.type == "event_msg",
                      env.payload?.type == "token_count",
                      let usage = env.payload?.info?.total_token_usage {
                // CRITICAL: Codex `total_token_usage` is already cumulative for the session.
                // Overwrite with the latest snapshot rather than adding!
                parsed.latestTokenUsage = TokenUsageSnapshot(
                    inputTokens: usage.input_tokens ?? 0,
                    cachedInputTokens: usage.cached_input_tokens ?? 0,
                    outputTokens: usage.output_tokens ?? 0,
                    reasoningTokens: usage.reasoning_output_tokens ?? 0
                )
            }
        }

        return parsed
    }

    // MARK: - 2. Claude Code Transcript Parser (~/.claude/projects/*/*.jsonl)

    private struct ClaudeTranscriptLine: Decodable {
        let sessionId: String?
        let cwd: String?
        let gitBranch: String?
        let type: String?
        let timestamp: String?
        let message: ClaudeMessage?
    }

    private struct ClaudeMessage: Decodable {
        let id: String?
        let model: String?
        let stop_reason: String?
        let usage: ClaudeUsage?
    }

    private struct ClaudeUsage: Decodable {
        let input_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let output_tokens: Int?
    }

    public struct ClaudeParsedTranscript: Sendable {
        public var sessionID: String?
        public var cwd: String?
        public var gitBranch: String?
        public var model: String?
        public var lastRecordType: String?
        public var lastStopReason: String?
        public var deduplicatedUsage: TokenUsageSnapshot

        public init(
            sessionID: String? = nil,
            cwd: String? = nil,
            gitBranch: String? = nil,
            model: String? = nil,
            lastRecordType: String? = nil,
            lastStopReason: String? = nil,
            deduplicatedUsage: TokenUsageSnapshot
        ) {
            self.sessionID = sessionID
            self.cwd = cwd
            self.gitBranch = gitBranch
            self.model = model
            self.lastRecordType = lastRecordType
            self.lastStopReason = lastStopReason
            self.deduplicatedUsage = deduplicatedUsage
        }
    }

    public static func parseClaude(snapshot: JSONLSnapshot) -> ClaudeParsedTranscript {
        let decoder = JSONDecoder()
        var sessionID: String?
        var cwd: String?
        var gitBranch: String?
        var model: String?
        var lastRecordType: String?
        var lastStopReason: String?

        // Deduplicate usage by message.id (preserving latest entry per message.id)
        var usageByMessageID: [String: ClaudeUsage] = [:]

        let allLines = snapshot.headLines + snapshot.tailLines
        for line in allLines {
            guard let record = try? decoder.decode(ClaudeTranscriptLine.self, from: line) else { continue }

            if let sid = record.sessionId { sessionID = sid }
            if let dir = record.cwd { cwd = dir }
            if let branch = record.gitBranch { gitBranch = branch }
            if let recType = record.type { lastRecordType = recType }

            if let msg = record.message {
                if let mdl = msg.model { model = mdl }
                lastStopReason = msg.stop_reason

                if let msgID = msg.id, let usage = msg.usage {
                    usageByMessageID[msgID] = usage
                }
            }
        }

        var totalInput = 0
        var totalCached = 0
        var totalOutput = 0

        for usage in usageByMessageID.values {
            totalInput += (usage.input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0)
            totalCached += (usage.cache_read_input_tokens ?? 0)
            totalOutput += (usage.output_tokens ?? 0)
        }

        return ClaudeParsedTranscript(
            sessionID: sessionID,
            cwd: cwd,
            gitBranch: gitBranch,
            model: model,
            lastRecordType: lastRecordType,
            lastStopReason: lastStopReason,
            deduplicatedUsage: TokenUsageSnapshot(
                inputTokens: totalInput,
                cachedInputTokens: totalCached,
                outputTokens: totalOutput,
                reasoningTokens: 0
            )
        )
    }

    // MARK: - 3. Antigravity CLI Transcript Parser (~/.gemini/antigravity-cli/brain/<uuid>/.system_generated/logs/transcript.jsonl)

    private struct AntigravityTranscriptStep: Decodable {
        let step_index: Int?
        let source: String?
        let type: String?
        let status: String?
        let created_at: String?
        let content: String?
        let model: String?
        let input_tokens: Int?
        let cache_read_tokens: Int?
        let output_tokens: Int?
        let tool_calls: [AntigravityToolCallRef]?
    }

    private struct AntigravityToolCallRef: Decodable {
        let name: String?
    }

    public struct AntigravityParsedTranscript: Sendable {
        public var lastStepType: String?
        public var lastStepStatus: String?
        public var lastToolNames: [String]
        public var model: String?
        public var lastCreatedAt: Date?
        public var tokenUsage: TokenUsageSnapshot

        public init(
            lastStepType: String? = nil,
            lastStepStatus: String? = nil,
            lastToolNames: [String] = [],
            model: String? = nil,
            lastCreatedAt: Date? = nil,
            tokenUsage: TokenUsageSnapshot = TokenUsageSnapshot(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningTokens: 0)
        ) {
            self.lastStepType = lastStepType
            self.lastStepStatus = lastStepStatus
            self.lastToolNames = lastToolNames
            self.model = model
            self.lastCreatedAt = lastCreatedAt
            self.tokenUsage = tokenUsage
        }
    }

    public static func parseAntigravity(snapshot: JSONLSnapshot) -> AntigravityParsedTranscript {
        let decoder = JSONDecoder()
        var lastStepType: String?
        var lastStepStatus: String?
        var lastToolNames: [String] = []
        var model: String?
        var lastCreatedAt: Date?

        var latestInputTokens = 0
        var latestCachedTokens = 0
        var totalOutputTokens = 0

        var seenStepIndices = Set<Int>()

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoStandard = ISO8601DateFormatter()
        isoStandard.formatOptions = [.withInternetDateTime]

        let allLines = snapshot.fileSize <= 65536 ? snapshot.tailLines : (snapshot.headLines + snapshot.tailLines)
        for line in allLines {
            guard let step = try? decoder.decode(AntigravityTranscriptStep.self, from: line) else { continue }

            if let idx = step.step_index {
                if seenStepIndices.contains(idx) { continue }
                seenStepIndices.insert(idx)
            }

            if let stType = step.type { lastStepType = stType }
            if let stStatus = step.status { lastStepStatus = stStatus }

            if let calls = step.tool_calls {
                lastToolNames = calls.compactMap { $0.name }
            } else if step.type == "PLANNER_RESPONSE" {
                lastToolNames = []
            }

            if let stepModel = step.model, !stepModel.isEmpty {
                model = stepModel
            } else if let content = step.content {
                if let extracted = extractAntigravityModel(from: content) {
                    model = extracted
                }
            }

            if let createdAtStr = step.created_at {
                if let date = isoFractional.date(from: createdAtStr) ?? isoStandard.date(from: createdAtStr) {
                    lastCreatedAt = date
                }
            }

            if let input = step.input_tokens {
                latestInputTokens = input
            }
            if let cached = step.cache_read_tokens {
                latestCachedTokens = cached
            }
            if let output = step.output_tokens {
                totalOutputTokens += output
            }
        }

        return AntigravityParsedTranscript(
            lastStepType: lastStepType,
            lastStepStatus: lastStepStatus,
            lastToolNames: lastToolNames,
            model: model,
            lastCreatedAt: lastCreatedAt,
            tokenUsage: TokenUsageSnapshot(
                inputTokens: latestInputTokens,
                cachedInputTokens: latestCachedTokens,
                outputTokens: totalOutputTokens,
                reasoningTokens: 0
            )
        )
    }

    private static func extractAntigravityModel(from content: String) -> String? {
        if let range = content.range(of: "Model Selection` from [^`]+ to ([^.\n`]+)", options: .regularExpression) {
            let matched = String(content[range])
            if let toRange = matched.range(of: " to ") {
                let modelPart = String(matched[toRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !modelPart.isEmpty { return modelPart }
            }
        }
        if let range = content.range(of: "as (gemini-[a-zA-Z0-9.-]+)", options: .regularExpression) {
            let matched = String(content[range])
            if let asRange = matched.range(of: "as ") {
                let modelPart = String(matched[asRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !modelPart.isEmpty { return modelPart }
            }
        }
        return nil
    }
}
