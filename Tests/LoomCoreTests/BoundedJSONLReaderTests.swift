//
//  BoundedJSONLReaderTests.swift
//  LoomCoreTests
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
@testable import LoomCore
import XCTest

final class BoundedJSONLReaderTests: XCTestCase {
    var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoundedJSONLReaderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temporaryDirectory = temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        super.tearDown()
    }

    func testSmallFileSinglePassRead() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("small.jsonl")
        let lines = [
            "{\"index\": 1, \"text\": \"hello\"}",
            "{\"index\": 2, \"text\": \"world\"}"
        ]
        let content = lines.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)?.write(to: fileURL)

        let reader = BoundedJSONLReader()
        let snapshot = try XCTUnwrap(reader.readSnapshot(at: fileURL))

        XCTAssertEqual(snapshot.headLines.count, 2)
        XCTAssertEqual(snapshot.tailLines.count, 2)
        XCTAssertEqual(snapshot.fileSize, UInt64(content.utf8.count))
    }

    func testLargeFileHeadAndTailSlicing() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("large.jsonl")
        var fileData = Data()

        // Generate lines exceeding 70 KB
        let firstLine = "{\"type\": \"session_meta\", \"payload\": {\"id\": \"meta-1\", \"model\": \"test\"}}\n"
        fileData.append(Data(firstLine.utf8))

        let paddingLine = "{\"type\": \"step\", \"content\": \"\(String(repeating: "x", count: 1000))\"}\n"
        for _ in 0..<75 {
            fileData.append(Data(paddingLine.utf8))
        }

        let lastLine = "{\"type\": \"event_msg\", \"payload\": {\"type\": \"token_count\", \"info\": {\"total_token_usage\": {\"input_tokens\": 500, \"output_tokens\": 100}}}}\n"
        fileData.append(Data(lastLine.utf8))

        try fileData.write(to: fileURL)

        let reader = BoundedJSONLReader(headByteLimit: 4 * 1024, tailByteLimit: 16 * 1024)
        let snapshot = try XCTUnwrap(reader.readSnapshot(at: fileURL))

        XCTAssertTrue(snapshot.fileSize > 16 * 1024)
        XCTAssertFalse(snapshot.headLines.isEmpty)
        XCTAssertFalse(snapshot.tailLines.isEmpty)

        // Parse with Codex parser to ensure head and tail combine correctly
        let codex = JSONLProviderParsers.parseCodex(snapshot: snapshot)
        XCTAssertEqual(codex.sessionID, "meta-1")
        XCTAssertEqual(codex.model, "test")
        XCTAssertEqual(codex.latestTokenUsage?.inputTokens, 500)
        XCTAssertEqual(codex.latestTokenUsage?.outputTokens, 100)
    }

    func testClaudeTranscriptDeduplication() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("claude.jsonl")
        let lines = [
            "{\"sessionId\": \"claude-1\", \"cwd\": \"/projects/app\", \"type\": \"assistant\", \"message\": {\"id\": \"msg-1\", \"model\": \"sonnet\", \"stop_reason\": \"tool_use\", \"usage\": {\"input_tokens\": 10, \"output_tokens\": 5}}}",
            // Duplicate message id with updated token count
            "{\"sessionId\": \"claude-1\", \"cwd\": \"/projects/app\", \"type\": \"assistant\", \"message\": {\"id\": \"msg-1\", \"model\": \"sonnet\", \"stop_reason\": \"end_turn\", \"usage\": {\"input_tokens\": 20, \"output_tokens\": 15}}}",
            // Distinct message id
            "{\"sessionId\": \"claude-1\", \"cwd\": \"/projects/app\", \"type\": \"assistant\", \"message\": {\"id\": \"msg-2\", \"model\": \"sonnet\", \"stop_reason\": \"end_turn\", \"usage\": {\"input_tokens\": 30, \"output_tokens\": 10}}}"
        ]
        let content = lines.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)?.write(to: fileURL)

        let reader = BoundedJSONLReader()
        let snapshot = try XCTUnwrap(reader.readSnapshot(at: fileURL))

        let claude = JSONLProviderParsers.parseClaude(snapshot: snapshot)
        XCTAssertEqual(claude.sessionID, "claude-1")
        XCTAssertEqual(claude.cwd, "/projects/app")
        XCTAssertEqual(claude.lastStopReason, "end_turn")
        // Deduplicated tokens: msg-1 has 20 in, 15 out. msg-2 has 30 in, 10 out.
        // Total input: 20 + 30 = 50. Total output: 15 + 10 = 25.
        XCTAssertEqual(claude.deduplicatedUsage.inputTokens, 50)
        XCTAssertEqual(claude.deduplicatedUsage.outputTokens, 25)
    }
}
