# Loom 2.2 — T3 Code Support, Multi-Agent Telemetry & Notification Polish

Version **2.2.0**, build **7**.

## Highlights

- **T3 Code Integration**: Native detection, orchestration hierarchy mapping, and real-time lifecycle tracking for T3 Code sessions alongside child CLI agent processes.
- **Multi-Agent CLI Telemetry**: Robust session detection and token usage metrics across Codex CLI, Claude Code, and Antigravity CLI with live process tree scanning.
- **Phantom Process Filtering**: Eliminated phantom `Home (~)` sessions and bare idle background daemons/helpers (`codex app-server`, `ChatGPT.app` crashpad handlers) when no real user coding session is active.
- **Provider Reordering**: Drag-and-drop reordering of providers in Settings with persisted preferences and dynamic Menu Bar sections.
- **Developer App Launchers**: One-click quick launch for registered AI coding agent environments and workspaces.
- **GitHub Star Community Prompt & Notification**: Native macOS notification with structured 3-line hierarchy, zero-truncation subtitle (`github.com/chaiwithcode/Loom`), SF Symbol hover actions (`★ Star on GitHub` and `Maybe Later`), and deduplicated Menu Bar invitation card.

## Monitoring & Discovery

- **Strict CWD & Transcript Correlation**: Background CLI processes running with `cwd == "/"` or `cwd == ~` are only linked to transcripts modified within the last 5 minutes, preventing stale background helpers from inflating session counts.
- **Process Hierarchy & Descendant Traversal**: Automatic attribution of child worker subprocesses to their parent agent sessions.
- **Bare Unknown Process Suppression**: Processes without workspace metadata, worker subprocesses, or valid transcripts are cleanly filtered from active session lists and diagnostics.

## Compatibility & Distribution

- Requires macOS 14.0 (Sonoma) or later on Apple Silicon (arm64).
- Production artifacts are signed with Developer ID, notarized by Apple Notary Service, and verified with `stapler`.
- Automated Sparkle 2 appcast and Homebrew Cask release updates.
