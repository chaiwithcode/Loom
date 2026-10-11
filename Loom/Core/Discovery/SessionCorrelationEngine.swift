//
//  SessionCorrelationEngine.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct CorrelatedCluster: Sendable {
    public let primaryProcess: AgentProcess
    public let allProcesses: [AgentProcess]
    public let sessionIDToken: String?
    public let hostApp: HostApp?

    public init(
        primaryProcess: AgentProcess,
        allProcesses: [AgentProcess],
        sessionIDToken: String? = nil,
        hostApp: HostApp? = nil
    ) {
        self.primaryProcess = primaryProcess
        self.allProcesses = allProcesses
        self.sessionIDToken = sessionIDToken
        self.hostApp = hostApp
    }
}

public protocol SessionCorrelating: Sendable {
    func correlate(
        processes: [AgentProcess],
        processTree: ProcessTree,
        workspaceResolver: any WorkspaceResolving
    ) async -> [AgentSession]
}

public final class DefaultSessionCorrelationEngine: SessionCorrelating, Sendable {
    private let stateInspector: (any CodexStateStoreInspecting)?

    public init(stateInspector: (any CodexStateStoreInspecting)? = nil) {
        self.stateInspector = stateInspector
    }

    public func correlate(
        processes: [AgentProcess],
        processTree: ProcessTree,
        workspaceResolver: any WorkspaceResolving
    ) async -> [AgentSession] {
        guard !processes.isEmpty else { return [] }

        // 1. Cluster processes based on ranked evidence
        let clusters = clusterProcesses(processes, processTree: processTree)

        // 2. Transform each cluster into a canonical AgentSession
        var sessions: [AgentSession] = []

        for cluster in clusters {
            let primary = cluster.primaryProcess
            let parentProcess = primary.parentPID.flatMap { ppid in
                processes.first(where: { $0.pid == ppid })
            }

            let resolvedWorkspace = await workspaceResolver.resolveWorkspace(
                for: primary,
                parent: parentProcess,
                explicitMetadataURL: nil
            )

            // Look up thread title from metadata store if available
            var threadTitle: String? = nil
            if let token = cluster.sessionIDToken, !token.isEmpty {
                if let meta = await stateInspector?.sessionMetadata(for: token) {
                    threadTitle = meta.title
                }
            }

            // Derive stable session ID:
            // 1. Explicit provider session token (e.g. "codex-98c95ead7ccd476aae7aa8ba50350c54")
            // 2. Workspace path + host app
            // 3. Fallback to primary PID
            // Derive stable session ID:
            // 1. Explicit provider session token (e.g. "codex-98c95ead7ccd476aae7aa8ba50350c54")
            // 2. Fallback: Include primary PID (root identity) alongside host/workspace to avoid collisions
            let stableID: String
            if let token = cluster.sessionIDToken, !token.isEmpty {
                stableID = "\(primary.provider.rawValue)-\(token)"
            } else if let host = cluster.hostApp, let path = resolvedWorkspace.projectPath {
                let pathSlug = slugify(path.path)
                let hostSlug = host.displayName.lowercased().replacingOccurrences(of: " ", with: "-")
                stableID = "\(primary.provider.rawValue)-\(hostSlug)-\(pathSlug)-\(primary.pid)"
            } else if let path = resolvedWorkspace.projectPath, cluster.allProcesses.count > 1 {
                let pathSlug = slugify(path.path)
                stableID = "\(primary.provider.rawValue)-\(pathSlug)-\(primary.pid)"
            } else {
                stableID = "\(primary.provider.rawValue)-\(primary.pid)"
            }

            // Derive timestamps
            let startedAt = cluster.allProcesses.compactMap(\.startedAt).min() ?? primary.startedAt
            let maxStarted = cluster.allProcesses.compactMap(\.startedAt).max()
            let lastActivityAt = (maxStarted != nil && startedAt != nil && maxStarted! > startedAt!) ? maxStarted : nil

            // Determine evidence-driven state and current activity
            let stateResult = deriveStateAndActivity(for: cluster, threadTitle: threadTitle)

            var evidence: [String] = []
            if let token = cluster.sessionIDToken, !token.isEmpty {
                evidence.append("Provider session token: \(token)")
            }
            if let title = threadTitle, !title.isEmpty {
                evidence.append("Thread topic: \(title)")
            }
            evidence.append(contentsOf: stateResult.evidence)
            if cluster.allProcesses.count > 1 {
                evidence.append("Collapsed \(cluster.allProcesses.count) processes via process tree")
            }
            if let host = cluster.hostApp {
                evidence.append("Host application: \(host.displayName)")
            }
            if let path = resolvedWorkspace.projectPath {
                evidence.append("Workspace: \((path.path as NSString).abbreviatingWithTildeInPath)")
            }
            if let branch = resolvedWorkspace.branch {
                evidence.append("Git branch: \(branch)")
            }

            let session = AgentSession(
                id: stableID,
                provider: primary.provider,
                projectName: resolvedWorkspace.projectName,
                projectPath: resolvedWorkspace.projectPath,
                state: stateResult.state,
                startedAt: startedAt,
                lastActivityAt: lastActivityAt,
                branch: resolvedWorkspace.branch,
                summary: stateResult.summary,
                pid: Int(primary.pid),
                providerSessionID: cluster.sessionIDToken,
                associatedProcesses: cluster.allProcesses,
                hostApp: cluster.hostApp,
                diagnostics: nil,
                discoveryEvidence: evidence
            )

            sessions.append(session)
        }

        // Deterministic sort: by startedAt ascending, then stable ID
        sessions.sort { s1, s2 in
            let d1 = s1.startedAt
            let d2 = s2.startedAt
            if let d1 = d1, let d2 = d2, d1 != d2 {
                return d1 < d2
            }
            return s1.id < s2.id
        }

        return sessions
    }

    private func clusterProcesses(
        _ processes: [AgentProcess],
        processTree: ProcessTree
    ) -> [CorrelatedCluster] {
        var unassigned = processes
        var clusters: [[AgentProcess]] = []

        // Criterion 1: Group by explicit sessionIDToken
        var byToken: [String: [AgentProcess]] = [:]
        var withoutToken: [AgentProcess] = []

        for p in unassigned {
            if let token = p.sessionIDToken, !token.isEmpty {
                byToken[token, default: []].append(p)
            } else {
                withoutToken.append(p)
            }
        }

        // For each token group in `byToken`, merge any related processes from `withoutToken`
        // (children, descendants, or ancestors in process tree) into the token cluster.
        var mergedByToken: [[AgentProcess]] = []
        var remainingWithoutToken = withoutToken

        for (_, tokenGroup) in byToken {
            var group = tokenGroup
            var addedMore = true
            while addedMore {
                addedMore = false
                let currentGroupPIDs = Set(group.map(\.pid))
                var unmerged: [AgentProcess] = []

                for candidate in remainingWithoutToken {
                    let isRelated = currentGroupPIDs.contains(candidate.parentPID ?? -1) ||
                        group.contains { $0.parentPID == candidate.pid } ||
                        group.contains { processTree.descendants(of: $0.pid).contains { $0.pid == candidate.pid } } ||
                        group.contains { processTree.ancestors(of: $0.pid).contains { $0.pid == candidate.pid } }

                    if isRelated {
                        group.append(candidate)
                        addedMore = true
                    } else {
                        unmerged.append(candidate)
                    }
                }
                remainingWithoutToken = unmerged
            }
            mergedByToken.append(group)
        }

        clusters.append(contentsOf: mergedByToken)
        unassigned = remainingWithoutToken

        // Criterion 2: Process tree relationships (parent-child or ancestor/descendant relationship)
        while !unassigned.isEmpty {
            let first = unassigned.removeFirst()
            var group = [first]
            var remaining: [AgentProcess] = []

            for candidate in unassigned {
                let groupPIDs = Set(group.map(\.pid))
                let isRelated = groupPIDs.contains(candidate.parentPID ?? -1) ||
                    group.contains { $0.parentPID == candidate.pid } ||
                    processTree.descendants(of: first.pid).contains { $0.pid == candidate.pid } ||
                    processTree.ancestors(of: first.pid).contains { $0.pid == candidate.pid }

                if isRelated {
                    group.append(candidate)
                } else {
                    remaining.append(candidate)
                }
            }

            clusters.append(group)
            unassigned = remaining
        }

        // Build CorrelatedCluster objects with elected primary process
        var result: [CorrelatedCluster] = []

        for group in clusters {
            guard !group.isEmpty else { continue }

            // Elect primary process:
            // Prefer root process (process that is not a child of any other in the group),
            // or process with the earliest startedAt / lowest PID.
            let pidsInGroup = Set(group.map(\.pid))
            let roots = group.filter { p in
                guard let ppid = p.parentPID else { return true }
                return !pidsInGroup.contains(ppid)
            }

            let primary = roots.first ?? group.min(by: { $0.pid < $1.pid }) ?? group[0]
            let token = group.compactMap(\.sessionIDToken).first
            let host = primary.hostApp ?? group.compactMap(\.hostApp).first ?? processTree.resolveHostApp(for: primary.pid)

            result.append(CorrelatedCluster(
                primaryProcess: primary,
                allProcesses: group.sorted(by: { $0.pid < $1.pid }),
                sessionIDToken: token,
                hostApp: host
            ))
        }

        return result
    }

    public static func isProcessAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return true }
        let res = kill(pid, 0)
        if res == 0 { return true }
        return errno == EPERM
    }

    private struct StateAndActivityResult {
        let state: AgentState
        let summary: String?
        let evidence: [String]
    }

    private func deriveStateAndActivity(
        for cluster: CorrelatedCluster,
        threadTitle: String?
    ) -> StateAndActivityResult {
        let children = cluster.allProcesses.filter { $0.pid != cluster.primaryProcess.pid }

        // 1. Multiple processes: active child worker subprocesses running
        if !children.isEmpty {
            let activeWorker = children.max(by: { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }) ?? children[0]
            let workerSummary = Self.formatActivitySummary(for: activeWorker.commandLine, executable: activeWorker.executable)
            let fullSummary: String
            if let title = threadTitle, !title.isEmpty {
                fullSummary = "\(workerSummary) · \(title)"
            } else {
                fullSummary = workerSummary
            }

            let evidence = [
                "State: Working (\(children.count) worker processes in tree)",
                "Active worker: PID \(activeWorker.pid) (\(workerSummary))"
            ]
            return StateAndActivityResult(state: .working, summary: fullSummary, evidence: evidence)
        }

        let primary = cluster.primaryProcess

        // 2. Starting check: process started recently (< 8 seconds) with no children
        if let started = primary.startedAt, Date().timeIntervalSince(started) < 8 {
            let summary = threadTitle != nil ? "Starting session · \(threadTitle!)" : "Starting session"
            let evidence = ["State: Starting (process started \(max(1, Int(Date().timeIntervalSince(started))))s ago with no worker children)"]
            return StateAndActivityResult(state: .starting, summary: summary, evidence: evidence)
        }

        // Parse options and subcommands strictly before the prompt boundary
        let infrastructureTokens = CodexParser.commandInfrastructureTokens(primary.commandLine)
        let primaryExecLower = URL(fileURLWithPath: primary.executable).lastPathComponent.lowercased()

        // 3. Worker command running standalone
        let isWorkerBinary = primaryExecLower.contains("kernel.js") ||
            primaryExecLower.contains("sandbox-exec") ||
            primaryExecLower.contains("sbx") ||
            primaryExecLower == "trusted-worker.js"
        let isWorkerSubcommand = infrastructureTokens.contains("exec") || infrastructureTokens.contains("sandbox")

        if isWorkerBinary || isWorkerSubcommand {
            let workerSummary = Self.formatActivitySummary(for: primary.commandLine, executable: primary.executable)
            let summary = threadTitle != nil ? "\(workerSummary) · \(threadTitle!)" : workerSummary
            let evidence = ["State: Working (active worker command: PID \(primary.pid))"]
            return StateAndActivityResult(state: .working, summary: summary, evidence: evidence)
        }

        // 4. Idle daemon / server check
        let isDaemonBinary = primaryExecLower.contains("language_server")
        let isDaemonToken = infrastructureTokens.contains("app-server") ||
            infrastructureTokens.contains("exec-server") ||
            infrastructureTokens.contains("daemon") ||
            infrastructureTokens.contains("server") ||
            infrastructureTokens.contains("--managed-daemon")

        if isDaemonBinary || isDaemonToken {
            let summary = "Idling (daemon/server mode)"
            let evidence = ["State: Idle (server daemon idling, awaiting requests)"]
            return StateAndActivityResult(state: .idle, summary: summary, evidence: evidence)
        }

        // 5. Waiting check: when we have session evidence (session token, thread title, or interactive flag)
        let isInteractive = infrastructureTokens.contains("--interactive") ||
            infrastructureTokens.contains("-i") ||
            infrastructureTokens.contains("--ask-for-approval")
        let hasSessionToken = cluster.sessionIDToken != nil && !cluster.sessionIDToken!.isEmpty
        let hasThreadTitle = threadTitle != nil && !threadTitle!.isEmpty

        if isInteractive || hasSessionToken || hasThreadTitle {
            let summaryText: String
            let evidenceText: String
            if isInteractive {
                summaryText = hasThreadTitle ? "Awaiting confirmation: \(threadTitle!)" : "Awaiting user confirmation"
                evidenceText = "State: Waiting (interactive prompt active)"
            } else if hasThreadTitle {
                summaryText = "Awaiting input: \(threadTitle!)"
                evidenceText = "State: Waiting (thread active with no worker subprocesses; awaiting user input)"
            } else {
                summaryText = "Awaiting user input"
                evidenceText = "State: Waiting (session active with no worker subprocesses; awaiting user input)"
            }
            return StateAndActivityResult(state: .waiting, summary: summaryText, evidence: [evidenceText])
        }

        // 6. Lone process with no session token, no thread metadata, and no child workers:
        // Truthful to AGENTS.md rule 10 ("Unknown state is preferable to a guessed state").
        return StateAndActivityResult(
            state: .unknown,
            summary: nil,
            evidence: ["State: Unknown (bare process without worker subprocesses or session metadata)"]
        )
    }

    public static func formatActivitySummary(for commandLine: String, executable: String) -> String {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let name = URL(fileURLWithPath: executable).lastPathComponent
            return name.isEmpty ? "Executing task" : "Running \(name)"
        }

        let lower = trimmed.lowercased()
        if lower.contains("swift test") {
            return "Running swift test"
        } else if lower.contains("swift build") {
            return "Compiling Swift target"
        } else if lower.contains("xcodebuild") {
            return "Running xcodebuild"
        } else if lower.contains("git status") {
            return "Checking git status"
        } else if lower.contains("git diff") {
            return "Inspecting git diff"
        } else if lower.contains("git commit") {
            return "Committing git changes"
        } else if lower.contains("npm test") || lower.contains("bun test") || lower.contains("cargo test") || lower.contains("pytest") {
            return "Running test suite"
        } else if lower.contains("kernel.js") || lower.contains("sandbox") {
            return "Executing sandbox worker"
        }

        let execName = URL(fileURLWithPath: executable).lastPathComponent
        let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if !execName.isEmpty && execName != "sh" && execName != "bash" && execName != "zsh" {
            if tokens.count > 1 {
                let firstArg = URL(fileURLWithPath: tokens[1]).lastPathComponent
                if !firstArg.hasPrefix("-") && !firstArg.isEmpty {
                    return "Running \(execName) \(firstArg)"
                }
            }
            return "Running \(execName)"
        }

        if tokens.count > 1 {
            let subcommand = tokens[1]
            if !subcommand.hasPrefix("-") {
                return "Running \(subcommand)"
            }
        }

        return "Running \(execName.isEmpty ? "worker" : execName)"
    }

    private func slugify(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let clean = name.replacingOccurrences(of: " ", with: "-")
        return clean.isEmpty ? "workspace" : clean
    }
}
