# PLANS.md — Loom Multi-Agent & T3Code Expansion Specification

## 0. STRICT AGENT GUARDRAILS (READ FIRST)
1. **Zero Shell Subprocesses for Process Scanning:** NEVER use `Process()` / `NSTask` to run `ps`, `lsof`, `pgrep`, or `top` on a timer. All process discovery, Parent PID (`ppid`) lookup, executable path resolution, and working directory (`cwd`) extraction MUST use native Darwin `<libproc.h>` C APIs (`proc_listallpids`, `proc_pidinfo`, `proc_pidpath`).
2. **Read-Only & Privacy-First:** Loom is strictly a read-only monitor. NEVER write to, lock, or mutate any file inside `~/.t3`, `~/.codex`, `~/.claude`, or `~/.gemini`. Open all SQLite databases (if any) with `SQLITE_OPEN_READONLY` and read JSONL files using non-blocking file descriptors (`O_RDONLY | O_NONBLOCK`).
3. **Bounded Tail Reads:** Agent JSONL transcripts can exceed 100 MB. NEVER load an entire `.jsonl` file into memory with `String(contentsOf:)` or `Data(contentsOf:)` on the main thread. Always read the first 4 KB (for session metadata) and seek (`lseek` / `FileHandle.seek(toOffset:)`) to the last 64 KB to parse recent state and cumulative token usage.
4. **Execution Order:** Implement strictly in order: **Phase 0 (Process Scanner) -> Phase 1 (T3Code) -> Phase 2 (Codex CLI) -> Phase 3 (Claude Code) -> Phase 4 (Antigravity CLI) -> Phase 5 (UI Aggregation)**. Do not skip ahead.

---

## Phase 0: Core `libproc` Process Tree & CWD Scanner

### Objective
Build a zero-allocation Darwin process scanner in Swift that snapshots running processes, resolves their `ppid` (Parent PID), full binary path, and current working directory (`cwd`), and builds a parent-to-child map so CLI agents spawned by T3Code are grouped under T3Code rather than duplicated as standalone sessions.

### Exact Implementation (`ProcessTreeScanner.swift`)
```swift
import Foundation
import Darwin

public struct MonitoredProcess: Sendable, Equatable {
    public let pid: pid_t
    public let ppid: pid_t
    public let name: String
    public let executablePath: String
    public let cwd: String?
}

public final class ProcessTreeScanner: Sendable {
    public init() {}

    public func scanProcessTable() -> [pid_t: MonitoredProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let actualBytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        let pidCount = Int(actualBytes) / MemoryLayout<pid_t>.stride

        var table: [pid_t: MonitoredProcess] = [:]
        table.reserveCapacity(pidCount)

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            // 1. Get BSD Info (PPID & Process Name)
            var bsdInfo = proc_bsdinfo()
            let bsdSize = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &bsdInfo,
                Int32(MemoryLayout<proc_bsdinfo>.stride)
            )
            guard bsdSize == MemoryLayout<proc_bsdinfo>.stride else { continue }

            let ppid = pid_t(bsdInfo.pbi_ppid)
            let name = withUnsafePointer(to: &bsdInfo.pbi_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }

            // 2. Get Executable Path
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let execPath = pathLen > 0 ? String(cString: pathBuffer) : ""

            // 3. Only resolve CWD for candidate processes to save syscalls
            let isCandidate = Self.isCandidateProcess(name: name, execPath: execPath)
            let cwd = isCandidate ? Self.resolveCWD(for: pid) : nil

            table[pid] = MonitoredProcess(
                pid: pid,
                ppid: ppid,
                name: name,
                executablePath: execPath,
                cwd: cwd
            )
        }
        return table
    }

    private static func isCandidateProcess(name: String, execPath: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerPath = execPath.lowercased()
        let targets = ["t3", "t3code", "codex", "claude", "agy", "antigravity", "node", "bun"]
        return targets.contains { lowerName.contains($0) || lowerPath.contains($0) }
    }

    public static func resolveCWD(for pid: pid_t) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let size = proc_pidinfo(
            pid,
            PROC_PIDVNODEPATHINFO,
            0,
            &vnodeInfo,
            Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        )
        guard size == MemoryLayout<proc_vnodepathinfo>.stride else { return nil }
        return withUnsafePointer(to: &vnodeInfo.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                let str = String(cString: $0)
                return str.isEmpty ? nil : str
            }
        }
    }

    /// Walks up the PPID chain (max depth 8) to check if `pid` is a descendant of `ancestorPIDs`.
    public static func findAncestor(
        of pid: pid_t,
        in table: [pid_t: MonitoredProcess],
        matching ancestorPIDs: Set<pid_t>
    ) -> pid_t? {
        var currentPID = pid
        for _ in 0..<8 {
            guard let proc = table[currentPID], proc.ppid > 1 else { return nil }
            if ancestorPIDs.contains(proc.ppid) {
                return proc.ppid
            }
            currentPID = proc.ppid
        }
        return nil
    }
}


Phase 1: T3Code Detector (Implement First)

How T3Code Works on macOS

T3Code (pingdotgg/t3code) runs a local orchestration server (default port 3773) managed either by the desktop app (T3 Code (Alpha) or T3 Code (Nightly)) or standalone via npx t3 / t3code. It spawns underlying CLI agents (codex, claude, opencode) as child processes and manages git worktrees under ~/.t3/worktrees/<project>/<thread>.

Exact File Paths & Discovery Mechanics

1. Base Directory Resolution:
  ⚬ Check ProcessInfo.processInfo.environment["T3CODE_HOME"], fallback to ~/.t3.
2. Runtime State File (server-runtime.json):
  ⚬ Primary path: ~/.t3/userdata/server-runtime.json
  ⚬ Dev fallback path: ~/.t3/dev/userdata/server-runtime.json
  ⚬ Schema of server-runtime.json:
    {
      "pid": 48291,
      "port": 3773,
      "origin": "[http://127.0.0.1:3773](http://127.0.0.1:3773)",
      "devUrl": null
    }
    
  ⚬ Stale PID Verification (CRITICAL): After a crash, server-runtime.json can hold a stale PID. Always verify that table[pid] exists in ProcessTreeScanner before trusting server-runtime.json.
3. Loopback HTTP Endpoints (Read-Only):
  ⚬ Readiness / Protocol Check: GET <origin>/.well-known/t3/environment (timeout: 1.5s).
  ⚬ Active Projects & Threads: GET <origin>/api/orchestration/shell
    ⚬ Returns active projects (id, title, workspaceRoot) and threads (id, projectId, title, model, status, runStatus, updatedAt).
    ⚬ Thread Status Mapping:
      ⚬ runStatus == "running" -> .working
      ⚬ runStatus == "needs-attention" (or pendingRequests non-empty) -> .awaitingApproval (Waiting for user approval/answer)
      ⚬ status == "active" and runStatus == "idle" -> .idle
      ⚬ status == "settled" or "snoozed" -> .inactive
4. Local NDJSON Trace Fallback (server.trace.ndjson):
  ⚬ Path: ~/.t3/userdata/logs/server.trace.ndjson
  ⚬ If /api/orchestration/shell requires an auth ticket in v2, tail the last 64 KB of server.trace.ndjson for active spans ("starting provider turn", "waiting for approval response").
5. Child CLI Deduplication:
  ⚬ Collect the T3Code server pid (from server-runtime.json) and any running macOS app PIDs whose bundle/app name contains "T3 Code".
  ⚬ Pass this Set<pid_t> into ProcessTreeScanner.findAncestor(of:in:matching:). Any codex or claude CLI process whose ancestor is T3Code MUST be marked managedBy = .t3Code(parentPID) so it attaches to the T3Code session card instead of creating a duplicate standalone CLI row.

Phase 2: Codex CLI Detector (@openai/codex)

How Codex CLI Works on macOS

OpenAI's codex CLI stores all state under $CODEX_HOME (defaults to ~/.codex). In addition to Loom's existing app-server stdio check, standalone terminal sessions write structured append-only JSONL rollout files.

Exact File Paths & Schemas

1. Process Detection:
  ⚬ Match processes in ProcessTreeScanner where name == "codex" or executablePath.hasSuffix("/codex").
  ⚬ Extract cwd directly via ProcessTreeScanner.resolveCWD(for: pid).
2. Session Transcripts Directory:
  ⚬ Path pattern: ~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<session_uuid>.jsonl
  ⚬ Also check ~/.codex/config.toml for custom sqlite_home or configuration overrides.
3. Exact JSONL Record Schema (RolloutLine):
   Every line in rollout-*.jsonl is a JSON object with 3 top-level keys: timestamp (ISO-8601 String), type (or kind in older builds), and payload.
  ⚬ Record 1 (type == "session_meta"): Located on Line 1 of the file.
    {
      "timestamp": "2026-10-31T14:20:00.000Z",
      "type": "session_meta",
      "payload": {
        "id": "abc12345-...",
        "cwd": "/Users/username/Developer/Loom",
        "model": "o3",
        "approval_mode": "suggest"
      }
    }
    
  ⚬ Record 2 (type == "turn_context"): Updates current cwd, model, or sandbox policy mid-session.
  ⚬ Record 3 (type == "event_msg"): Carries token usage and runtime state events.
    ⚬ Token Usage (payload.type == "token_count"):
      {
        "timestamp": "2026-10-31T14:22:10.000Z",
        "type": "event_msg",
        "payload": {
          "type": "token_count",
          "info": {
            "total_token_usage": {
              "input_tokens": 45210,
              "cached_input_tokens": 38100,
              "output_tokens": 1840,
              "reasoning_output_tokens": 620,
              "total_tokens": 47050
            }
          }
        }
      }
      
      ⚬ CRITICAL RULE FOR CODEX TOKENS: total_token_usage is cumulative within a single session file. Do NOT sum total_token_usage across multiple lines in the same file! Take the maximum / final total_token_usage from each session file, and sum those maxima across files modified today to compute daily usage.

Phase 3: Claude Code CLI Detector (@anthropic-ai/claude-code)

How Claude Code Works on macOS

Claude Code (claude) writes one append-only JSONL file per session under ~/.claude/projects/<encoded-project-path>/<session-uuid>.jsonl.

Exact File Paths & Schemas

1. Process Detection:
  ⚬ Match processes where name == "claude" or executablePath.contains("/claude").
  ⚬ Resolve live cwd from ProcessTreeScanner.
2. Session Transcripts Directory:
  ⚬ Root path: ~/.claude/projects/
  ⚬ Subfolders encode the project path by replacing / with - (e.g., /Users/dev/Loom -> -Users-dev-Loom). Do NOT rely on decoding the folder name—always read the explicit cwd field inside the JSONL line!
3. Exact JSONL Record Schema:
   Each line in ~/.claude/projects/*/*.jsonl contains top-level metadata alongside a message object:
   {
     "parentUuid": "...",
     "isSidechain": false,
     "userType": "external",
     "cwd": "/Users/username/Developer/Loom",
     "sessionId": "7f9c2b10-...",
     "version": "1.0.58",
     "gitBranch": "main",
     "type": "assistant",
     "timestamp": "2026-10-31T18:10:04.192Z",
     "message": {
       "id": "msg_019abc...",
       "type": "message",
       "role": "assistant",
       "model": "claude-sonnet-4-6-20260514",
       "stop_reason": "tool_use",
       "content": [
         { "type": "tool_use", "id": "toolu_01...", "name": "Bash", "input": { "command": "swift test" } }
       ],
       "usage": {
         "input_tokens": 340,
         "cache_creation_input_tokens": 1420,
         "cache_read_input_tokens": 28450,
         "output_tokens": 512
       }
     }
   }
   
4. CRITICAL RULES FOR CLAUDE CODE PARSING:
  ⚬ Message ID Deduplication: Streaming or intermediate updates can write multiple JSONL lines with the exact same message.id. You MUST deduplicate by message.id (keeping only the last entry for a given message.id) before summing usage.input_tokens, usage.output_tokens, usage.cache_creation_input_tokens, and usage.cache_read_input_tokens.
  ⚬ State Detection from Tail Line:
    ⚬ If the last record has type == "assistant" and message.stop_reason == "tool_use":
      ⚬ Check if a child process of claude is currently running in ProcessTreeScanner. If no child process is running and Date().timeIntervalSince(lastTimestamp) > 2.0, Claude is waiting for user tool permission -> .awaitingApproval.
      ⚬ If a child process is running -> .working.
    ⚬ If the last record has type == "assistant" and message.stop_reason == "end_turn" -> .idle (waiting for user prompt).

Phase 4: Antigravity CLI (agy) Detector

How Antigravity CLI Works on macOS

Antigravity CLI installs its binary as agy (usually in ~/.local/bin/agy) and stores its state in ~/.gemini/antigravity-cli/—completely separate from the IDE's Markdown artifact directory (~/.gemini/antigravity/brain/).

Exact File Paths & Schemas

1. Process Detection:
  ⚬ Match processes where name == "agy" or name == "antigravity" or executablePath.hasSuffix("/agy").
  ⚬ CRITICAL CWD RULE: The Antigravity CLI transcript does not write the project working directory (cwd) anywhere inside transcript.jsonl! You MUST obtain the project cwd from ProcessTreeScanner.resolveCWD(for: pid) while the agy process is alive, and cache the mapping [conversationUUID: cwd] in memory.
2. Configuration & Settings Path:
  ⚬ ~/.gemini/antigravity-cli/settings.json
  ⚬ ~/.gemini/antigravity-cli/mcp_config.json
3. Session Transcript Path:
  ⚬ ~/.gemini/antigravity-cli/brain/<conversation-uuid>/.system_generated/logs/transcript.jsonl
4. Exact JSONL Record Schema (transcript.jsonl):
   Each line is a step object with step_index (Int), type (String), created_at (ISO-8601 String), and truncated_fields (optional Array):
  ⚬ type == "USER_INPUT": User prompt (note: content wraps the prompt in XML-like envelope tags; strip tags if displaying preview).
  ⚬ type == "PLANNER_RESPONSE": Model response containing content, thinking, and tool_calls[] (name, args).
  ⚬ type == "RUN_COMMAND" | "VIEW_FILE" | "LIST_DIRECTORY" | "GREP_SEARCH" | "CODE_ACTION": Tool execution outputs.
  ⚬ type == "USER_SETTINGS_CHANGE": Contains active model selection changes.
5. Quota Unification with Existing Antigravity Monitor:
  ⚬ Reuse Loom's existing loopback HTTPS quota service for Antigravity, and attach active agy CLI sessions to the unified Antigravity provider card with a surface: .cli badge (agy).

Phase 5: Unified Domain Model & File-Watcher Pipeline

1. Unified Swift Structs (AgentSessionModels.swift)

import Foundation

public enum AgentProviderKind: String, Codable, Sendable, CaseIterable {
    case t3Code = "t3code"
    case codex = "codex"
    case claudeCode = "claude_code"
    case antigravity = "antigravity"
}

public enum AgentSurface: String, Codable, Sendable {
    case cli = "CLI"
    case gui = "GUI"
    case t3Orchestrated = "T3Code"
}

public enum AgentRunState: String, Codable, Sendable {
    case working           // Actively streaming or running a tool
    case awaitingApproval  // Blocked on user permission / question
    case idle              // Process alive, waiting for next user prompt
    case inactive          // Process exited, recent historical session
}

public struct TokenUsageSnapshot: Sendable, Equatable, Codable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningTokens: Int

    public var totalTokens: Int {
        inputTokens + cachedInputTokens + outputTokens + reasoningTokens
    }
}

public struct AgentSessionStatus: Identifiable, Sendable, Equatable {
    public let id: String                  // Session UUID or "pid-<pid>"
    public let provider: AgentProviderKind
    public let surface: AgentSurface
    public let pid: pid_t?
    public let parentT3PID: pid_t?         // Non-nil if spawned by T3Code
    public let projectName: String         // Last path component of cwd
    public let workspacePath: String?      // Full cwd
    public let gitBranch: String?
    public let modelName: String?
    public let state: AgentRunState
    public let tokenUsage: TokenUsageSnapshot?
    public let lastUpdated: Date
}


2. Coordinator Polling & File Watching Cadence

⚬ Process Table Tick: Run ProcessTreeScanner().scanProcessTable() every 3.0 seconds on a background serial DispatchQueue(label: "com.chaiwithcode.loom.process-scanner", qos: .utility).
⚬ Directory Watchers: Attach DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask: .write) on:
  ⚬ ~/.t3/userdata/
  ⚬ ~/.codex/sessions/ (current YYYY/MM/DD leaf directory)
  ⚬ ~/.claude/projects/
  ⚬ ~/.gemini/antigravity-cli/brain/
⚬ Debounce: Coalesce file system events with a 500ms debounce before re-reading the tail 64 KB of modified .jsonl files.

Verification Checklist for Antigravity

⚬ [ ] swift build compiles with zero warnings under Swift 6 strict concurrency (Sendable compliance on all models and detectors).
⚬ [ ] No Process() / NSTask calls exist in any detector for ps, lsof, or pgrep.
⚬ [ ] Launching codex or claude inside T3Code sets surface = .t3Orchestrated and parentT3PID != nil, preventing duplicate standalone rows in the menu bar popover.
⚬ [ ] Codex token calculation reads the latest total_token_usage per session file without summing cumulative snapshots within the same file.
⚬ [ ] Claude Code token calculation deduplicates records by message.id before summing usage fields.
⚬ [ ] Antigravity CLI (agy) resolves its cwd via proc_pidinfo(PROC_PIDVNODEPATHINFO) and maps it to the active brain transcript UUID.


---

### Updated Roadmap Tracker

<TemplateWidget component_placeholder_id="im_cf03b92ecd9062ba" header_title="Loom CLI & T3Code Expansion Roadmap" templateName="checklist">
```json
{
  "categories": [
    "M0: Core Architecture",
    "M1: T3Code (Priority 1)",
    "M2: Codex CLI",
    "M3: Claude Code",
    "M4: Antigravity CLI",
    "M5: UI & WidgetKit"
  ],
  "items": [
    {
      "id": "m0-1",
      "label": "Build libproc ProcessTreeScanner with PPID resolution",
      "sublines": [
        "Use proc_listallpids, PROC_PIDTBSDINFO, and PROC_PIDVNODEPATHINFO in ProcessTreeScanner.swift"
      ],
      "category": "M0: Core Architecture",
      "checked": true
    },
    {
      "id": "m0-2",
      "label": "Define AgentSessionModels & 64KB Tail JSONL Reader",
      "sublines": [
        "Implement non-blocking FileHandle tail reader and 500ms debounced DispatchSource watchers"
      ],
      "category": "M0: Core Architecture",
      "checked": true
    },
    {
      "id": "m1-1",
      "label": "Implement T3CodeDetector (~/.t3/userdata/server-runtime.json)",
      "sublines": [
        "Validate PID against ProcessTreeScanner and query GET /api/orchestration/shell on loopback"
      ],
      "category": "M1: T3Code (Priority 1)",
      "checked": true
    },
    {
      "id": "m1-2",
      "label": "Deduplicate T3Code child CLI processes via PPID chain walk",
      "sublines": [
        "Tag child codex/claude PIDs with surface = .t3Orchestrated and parentT3PID"
      ],
      "category": "M1: T3Code (Priority 1)",
      "checked": true
    },
    {
      "id": "m2-1",
      "label": "Implement CodexCLIDetector (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)",
      "sublines": [
        "Parse session_meta for cwd/model and take max cumulative total_token_usage from event_msg"
      ],
      "category": "M2: Codex CLI",
      "checked": true
    },
    {
      "id": "m3-1",
      "label": "Implement ClaudeCodeDetector (~/.claude/projects/*/*.jsonl)",
      "sublines": [
        "Deduplicate lines by message.id, sum usage tokens, and detect stop_reason == tool_use approval waits"
      ],
      "category": "M3: Claude Code",
      "checked": true
    },
    {
      "id": "m4-1",
      "label": "Implement AntigravityCLIDetector (~/.gemini/antigravity-cli/brain/)",
      "sublines": [
        "Match agy binary, bind live libproc CWD to transcript.jsonl UUID, and merge with loopback quota"
      ],
      "category": "M4: Antigravity CLI",
      "checked": true
    },
    {
      "id": "m5-1",
      "label": "Update Menu Bar Popover & WidgetKit views",
      "sublines": [
        "Render T3Code parent cards, CLI surface badges, and awaitingApproval indicators"
      ],
      "category": "M5: UI & WidgetKit",
      "checked": true
    }
  ]
}


</TemplateWidget>


---

### Updated Roadmap Tracker

<TemplateWidget component_placeholder_id="im_cf03b92ecd9062ba" header_title="Loom CLI & T3Code Expansion Roadmap" templateName="checklist">
```json
{
  "categories": [
    "M0: Core Architecture",
    "M1: T3Code (Priority 1)",
    "M2: Codex CLI",
    "M3: Claude Code",
    "M4: Antigravity CLI",
    "M5: UI & WidgetKit"
  ],
  "items": [
    {
      "id": "m0-1",
      "label": "Build libproc ProcessTreeScanner with PPID resolution",
      "sublines": [
        "Use proc_listallpids, PROC_PIDTBSDINFO, and PROC_PIDVNODEPATHINFO in ProcessTreeScanner.swift"
      ],
      "category": "M0: Core Architecture",
      "checked": false
    },
    {
      "id": "m0-2",
      "label": "Define AgentSessionModels & 64KB Tail JSONL Reader",
      "sublines": [
        "Implement non-blocking FileHandle tail reader and 500ms debounced DispatchSource watchers"
      ],
      "category": "M0: Core Architecture",
      "checked": false
    },
    {
      "id": "m1-1",
      "label": "Implement T3CodeDetector (~/.t3/userdata/server-runtime.json)",
      "sublines": [
        "Validate PID against ProcessTreeScanner and query GET /api/orchestration/shell on loopback"
      ],
      "category": "M1: T3Code (Priority 1)",
      "checked": false
    },
    {
      "id": "m1-2",
      "label": "Deduplicate T3Code child CLI processes via PPID chain walk",
      "sublines": [
        "Tag child codex/claude PIDs with surface = .t3Orchestrated and parentT3PID"
      ],
      "category": "M1: T3Code (Priority 1)",
      "checked": false
    },
    {
      "id": "m2-1",
      "label": "Implement CodexCLIDetector (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)",
      "sublines": [
        "Parse session_meta for cwd/model and take max cumulative total_token_usage from event_msg"
      ],
      "category": "M2: Codex CLI",
      "checked": false
    },
    {
      "id": "m3-1",
      "label": "Implement ClaudeCodeDetector (~/.claude/projects/*/*.jsonl)",
      "sublines": [
        "Deduplicate lines by message.id, sum usage tokens, and detect stop_reason == tool_use approval waits"
      ],
      "category": "M3: Claude Code",
      "checked": false
    },
    {
      "id": "m4-1",
      "label": "Implement AntigravityCLIDetector (~/.gemini/antigravity-cli/brain/)",
      "sublines": [
        "Match agy binary, bind live libproc CWD to transcript.jsonl UUID, and merge with loopback quota"
      ],
      "category": "M4: Antigravity CLI",
      "checked": false
    },
    {
      "id": "m5-1",
      "label": "Update Menu Bar Popover & WidgetKit views",
      "sublines": [
        "Render T3Code parent cards, CLI surface badges, and awaitingApproval indicators"
      ],
      "category": "M5: UI & WidgetKit",
      "checked": false
    }
  ]
}


