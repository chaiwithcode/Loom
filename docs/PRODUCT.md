# Loom — Product Brief

## Problem and thesis

Developers run independent AI coding agents across repositories. Sessions and quota information are fragmented across terminals and apps. Loom is a small native macOS surface that shows what is running, where it is working, what needs attention, and whether usage limits are approaching.

The core object is an agent session and its relationship to a project. Usage complements this context without replacing session monitoring.

## Current experience

- **Sessions:** Provider selector allows switching between monitored providers independently of session scrolling. Project sessions display normalized lifecycle states (`working`, `idle`, `waiting`, `starting`, `finished`, `failed`, `unknown`). Expanded session cards show available metadata, active process details, and a Finder reveal button when a valid project path exists.
- **Usage:** Quota remaining, reset windows, and additional model limits. Stale, unavailable, and failed responses remain visible with clear indicators.

A shared header provides manual refresh, last updated timestamp, and access to Settings. Menu content height dynamically adapts up to available screen space, with scrollable content containers preserving independent scroll and disclosure state across tabs.

## Integration status

All three real providers are registered in standard launch mode (`CodexProvider`, `ClaudeProvider`, and `AntigravityProvider`):
- **Codex:** Discovers running processes and Git workspace metadata. Sessions with uncertain live evidence report truthful `Unknown` state rather than guessing.
- **Claude Code:** Discovers local CLI processes, inspects active workspaces, and resolves session status.
- **Antigravity:** Discovers running processes and reads local session and workspace state.

Provider availability indicates local environment readiness; it is distinct from authentication, active sessions, and a usable quota response. Demo fixture modes (`--demo-mock`, `--demo-empty`, `--demo-failure`) require explicit command-line flags and are visibly badged.

## Settings & controls

Loom provides configuration in its Settings window (and associated Dock menu actions):
- **Provider Monitoring:** Toggle monitoring individually for Codex, Claude, and Antigravity.
- **Default Provider:** Designate the initial selected provider tab.
- **Session Retention:** Toggle inclusion of recent sessions, and configure automatic hiding of finished sessions (`never`, `1h`, `24h`, `7d`).
- **Privacy Controls:** Option to hide project paths and path evidence across menu bar views and session details.
- **Dock & Menu Integration:** Optional Dock icon display alongside standard menu bar presence.
- **Refresh Rates:** Configurable background refresh intervals (30s, 60s, 2m, 5m; default 60s) and on-demand manual refresh.

## V0 acceptance criteria

- **Presentation & Navigation:** Native SwiftUI macOS 14+ menu bar popover (`LSUIElement`) with responsive vertical sizing and independent scroll state across the Sessions and Usage tabs. *Verification:* Provider switching remains accessible and responsive even with long session lists, and switching between Sessions and Usage tabs preserves their independent scroll positions.
- **Local Provider Discovery:** Independent local discovery for Codex, Claude, and Antigravity without cross-provider blocking. *Verification:* Disabling all providers in Settings renders an empty/paused state gracefully; re-enabling triggers targeted provider polling without requiring app relaunch.
- **Truthful Metadata & Evidence:** Clear lifecycle states grounded in verifiable process/workspace evidence; missing or ambiguous data reports `Unknown`.
- **Configurable Controls & Persistence:** Dedicated Settings panel managing provider toggles, default selection, session retention rules, privacy path hiding, and Dock activation. *Verification:* Settings changes persist across launches, and **Restore Defaults** resets all settings immediately.
- **Failure Isolation:** Individual provider errors or rate limits do not crash or stall monitoring for remaining providers. *Verification:* Simulating or encountering a provider failure retains a visibly labeled stale usage snapshot or clear error status without stalling healthy providers.
- **Test Strategy & Prerequisites:** Portable test suite covers parsing, lifecycle reconciliation, settings, and UI layout in CI without live-provider store dependencies. Native layout probe validates menu sizing separately. Smoke tests requiring live provider stores/tools run locally only when those external prerequisites exist and are not claimed when unavailable.
- **Local-Only Architecture:** Purely local monitoring with no Loom backend, no network telemetry, no persisted credentials, and no control/write actions against provider runtimes. Monitored provider tools retain their own independent network and account behavior.

## Priorities

Reliable discovery and lifecycle normalization come first. Next: upstream compatibility, diagnostics, and accessibility. Safe actions, notifications, and richer repository context require separate product decisions. Remote control, cloud synchronization, and multi-agent orchestration remain outside scope.

## Brand

Three vertical agent strands weave into one circular base. Preserve this approved silhouette, refined material colors, and native macOS balance. Use the full-color icon for app identity and a simplified monochrome glyph for the menu bar. No vendor-specific logos belong in the core mark.
