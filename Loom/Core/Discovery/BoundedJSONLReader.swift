//
//  BoundedJSONLReader.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation

/// Result of a bounded head + tail read on an append-only JSONL transcript.
public struct JSONLSnapshot: Sendable {
    /// Complete JSON lines from the start of the file (typically the first 4 KB).
    public let headLines: [Data]
    /// Complete JSON lines from the end of the file (typically the last 64 KB).
    public let tailLines: [Data]
    /// Total file size in bytes at the time of reading.
    public let fileSize: UInt64
    /// Last modification timestamp from the filesystem.
    public let modifiedAt: Date

    public init(
        headLines: [Data],
        tailLines: [Data],
        fileSize: UInt64,
        modifiedAt: Date
    ) {
        self.headLines = headLines
        self.tailLines = tailLines
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }
}

public struct BoundedJSONLReader: Sendable {
    public let headByteLimit: Int
    public let tailByteLimit: Int

    public init(headByteLimit: Int = 4 * 1024, tailByteLimit: Int = 64 * 1024) {
        self.headByteLimit = headByteLimit
        self.tailByteLimit = tailByteLimit
    }

    /// Reads the head (first 4 KB) and tail (last 64 KB) of a JSONL file without loading the entire file into memory.
    public func readSnapshot(at url: URL) -> JSONLSnapshot? {
        let path = url.path

        // 1. Open via POSIX with O_RDONLY | O_NONBLOCK | O_CLOEXEC so we never block CLI writers
        let fd = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }

        // fileHandle takes ownership and closes fd when close() is called
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer {
            try? handle.close()
        }

        // 2. Stat the file descriptor directly for size and mtime
        var statBuf = Darwin.stat()
        guard fstat(fd, &statBuf) == 0 else { return nil }

        let fileSize = UInt64(max(0, statBuf.st_size))
        let modifiedAt = Date(
            timeIntervalSince1970: TimeInterval(statBuf.st_mtimespec.tv_sec)
                + TimeInterval(statBuf.st_mtimespec.tv_nsec) / 1_000_000_000
        )

        guard fileSize > 0 else {
            return JSONLSnapshot(headLines: [], tailLines: [], fileSize: 0, modifiedAt: modifiedAt)
        }

        do {
            // 3. If the entire file fits within tailByteLimit, read it in a single pass
            if fileSize <= UInt64(tailByteLimit) {
                try handle.seek(toOffset: 0)
                let allData = try handle.readToEnd() ?? Data()
                let lines = Self.extractCompleteLines(
                    from: allData,
                    dropLeadingPartialLine: false,
                    dropTrailingIncompleteLine: true
                )
                return JSONLSnapshot(
                    headLines: Array(lines.prefix(5)),
                    tailLines: lines,
                    fileSize: fileSize,
                    modifiedAt: modifiedAt
                )
            }

            // 4. Large File Path: Read Head (First 4 KB) for session metadata
            try handle.seek(toOffset: 0)
            let headData = try handle.read(upToCount: headByteLimit) ?? Data()
            let headLines = Self.extractCompleteLines(
                from: headData,
                dropLeadingPartialLine: false,
                dropTrailingIncompleteLine: true
            )

            // 5. Seek to Tail (Last 64 KB)
            let tailOffset = fileSize - UInt64(tailByteLimit)
            try handle.seek(toOffset: tailOffset)
            let tailData = try handle.read(upToCount: tailByteLimit) ?? Data()

            // Because tailOffset > 0, the first bytes up to the first '\n' are almost certainly
            // a truncated suffix of an earlier JSON line. Always drop the leading fragment.
            let tailLines = Self.extractCompleteLines(
                from: tailData,
                dropLeadingPartialLine: true,
                dropTrailingIncompleteLine: false
            )

            return JSONLSnapshot(
                headLines: headLines,
                tailLines: tailLines,
                fileSize: fileSize,
                modifiedAt: modifiedAt
            )
        } catch {
            return nil
        }
    }

    // MARK: - Byte-Level Line Splitting

    /// Splits raw UTF-8 JSONL data on `0x0A` (`\n`), safely trimming partial boundary lines.
    public static func extractCompleteLines(
        from data: Data,
        dropLeadingPartialLine: Bool,
        dropTrailingIncompleteLine: Bool
    ) -> [Data] {
        guard !data.isEmpty else { return [] }

        let newline: UInt8 = 0x0A // '\n'
        let carriageReturn: UInt8 = 0x0D // '\r'

        var workingSlice = data[...]

        // 1. If we sought into the middle of a file, discard everything up to and including the first '\n'
        if dropLeadingPartialLine {
            guard let firstNewlineIdx = workingSlice.firstIndex(of: newline) else {
                // Single giant line exceeding 64 KB; cannot safely parse
                return []
            }
            let nextStart = workingSlice.index(after: firstNewlineIdx)
            guard nextStart < workingSlice.endIndex else { return [] }
            workingSlice = workingSlice[nextStart...]
        }

        // 2. If we read a fixed chunk from the start of a file (or if an agent is mid-write without a trailing '\n'),
        // discard bytes after the last '\n' if requested or if the line doesn't end with '}'
        if dropTrailingIncompleteLine, workingSlice.last != newline {
            if let lastNewlineIdx = workingSlice.lastIndex(of: newline) {
                workingSlice = workingSlice[...lastNewlineIdx]
            } else {
                return []
            }
        }

        // 3. Split into non-empty lines and strip optional '\r'
        var result: [Data] = []
        result.reserveCapacity(64)

        var lineStart = workingSlice.startIndex
        var idx = workingSlice.startIndex

        while idx < workingSlice.endIndex {
            if workingSlice[idx] == newline {
                var lineEnd = idx
                if lineEnd > lineStart && workingSlice[workingSlice.index(before: lineEnd)] == carriageReturn {
                    lineEnd = workingSlice.index(before: lineEnd)
                }
                if lineEnd > lineStart {
                    let lineData = Data(workingSlice[lineStart..<lineEnd])
                    if isLikelyCompleteJSONObject(lineData) {
                        result.append(lineData)
                    }
                }
                lineStart = workingSlice.index(after: idx)
            }
            idx = workingSlice.index(after: idx)
        }

        // Handle final trailing line if the file didn't end with '\n' yet is a valid complete JSON object
        if !dropTrailingIncompleteLine && lineStart < workingSlice.endIndex {
            let remaining = Data(workingSlice[lineStart..<workingSlice.endIndex])
            if isLikelyCompleteJSONObject(remaining) {
                result.append(remaining)
            }
        }

        return result
    }

    /// Fast O(1) boundary check ensuring the line starts with `{` and ends with `}` (ignoring ASCII whitespace)
    /// so JSONDecoder never wastes CPU on half-flushed lines while an agent is mid-write.
    private static func isLikelyCompleteJSONObject(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }

        let openBrace: UInt8 = 0x7B  // '{'
        let closeBrace: UInt8 = 0x7D // '}'

        guard let firstNonWS = data.first(where: { $0 > 0x20 }),
              let lastNonWS = data.last(where: { $0 > 0x20 }) else {
            return false
        }
        return firstNonWS == openBrace && lastNonWS == closeBrace
    }
}
