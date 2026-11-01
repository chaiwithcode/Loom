//
//  AgentMonitoringCoordinator.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation

@MainActor
public final class AgentMonitoringCoordinator: ObservableObject {
    @Published public private(set) var sessions: [AgentSessionStatus] = []

    private let scanner: ProcessTreeScanner
    private let t3Detector: T3CodeDetector
    private let codexDetector: CodexCLIDetector
    private let claudeDetector: ClaudeCodeDetector
    private let agyDetector: AntigravityCLIDetector

    private let watcherQueue = DispatchQueue(label: "com.chaiwithcode.loom.fs-watcher", qos: .utility)
    private var fileWatchers: [DispatchSourceFileSystemObject] = []
    private var debounceWorkItem: DispatchWorkItem?
    private var pollingTask: Task<Void, Never>?

    public init(
        scanner: ProcessTreeScanner = ProcessTreeScanner(),
        t3Detector: T3CodeDetector = T3CodeDetector(),
        codexDetector: CodexCLIDetector = CodexCLIDetector(),
        claudeDetector: ClaudeCodeDetector = ClaudeCodeDetector(),
        agyDetector: AntigravityCLIDetector = AntigravityCLIDetector()
    ) {
        self.scanner = scanner
        self.t3Detector = t3Detector
        self.codexDetector = codexDetector
        self.claudeDetector = claudeDetector
        self.agyDetector = agyDetector
    }

    public func startMonitoring() {
        stopMonitoring()
        setupDirectoryWatchers()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    public func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
        debounceWorkItem?.cancel()
        for watcher in fileWatchers {
            watcher.cancel()
        }
        fileWatchers.removeAll()
    }

    public func refreshAll() async {
        let table = await Task.detached(priority: .utility) { [scanner] in
            scanner.scanProcessTable()
        }.value

        // 1. Run T3Code first to obtain rootT3PIDs for child CLI deduplication
        let t3Result = await t3Detector.detect(processTable: table)
        let rootT3PIDs = t3Result.rootT3PIDs

        // 2. Run CLI detectors in parallel with rootT3PIDs
        async let codexSessions = Task.detached(priority: .utility) { [codexDetector] in
            codexDetector.detect(processTable: table, t3RootPIDs: rootT3PIDs)
        }.value

        async let claudeSessions = Task.detached(priority: .utility) { [claudeDetector] in
            claudeDetector.detect(processTable: table, t3RootPIDs: rootT3PIDs)
        }.value

        async let agySessions = Task.detached(priority: .utility) { [agyDetector] in
            agyDetector.detect(processTable: table, t3RootPIDs: rootT3PIDs)
        }.value

        let combined = t3Result.sessions + (await codexSessions) + (await claudeSessions) + (await agySessions)
        self.sessions = combined.sorted { lhs, rhs in
            if (lhs.state != .inactive) != (rhs.state != .inactive) {
                return lhs.state != .inactive
            }
            return lhs.lastUpdated > rhs.lastUpdated
        }
    }

    // MARK: - 500ms Debounced DispatchSource Watchers

    private func setupDirectoryWatchers() {
        let watchedDirs: [URL] = [
            T3CodeDetector.resolveT3HomeDirectory().appendingPathComponent("userdata"),
            CodexCLIDetector.resolveCodexHomeDirectory().appendingPathComponent("sessions"),
            ClaudeCodeDetector.resolveClaudeProjectsDirectory(),
            AntigravityCLIDetector.resolveAntigravityCLIDirectory().appendingPathComponent("brain")
        ]

        for url in watchedDirs {
            let fd = Darwin.open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename],
                queue: watcherQueue
            )

            source.setEventHandler { [weak self] in
                self?.scheduleDebouncedRefresh()
            }

            source.setCancelHandler {
                Darwin.close(fd)
            }

            source.resume()
            fileWatchers.append(source)
        }
    }

    private func scheduleDebouncedRefresh() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshAll()
            }
        }
        debounceWorkItem = item
        watcherQueue.asyncAfter(deadline: .now() + .milliseconds(500), execute: item)
    }
}
