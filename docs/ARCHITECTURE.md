# Architecture

## Layers

**Core** defines provider-neutral session/usage models, normalization, settings and refresh coordination. **Providers** own local detection, discovery, transport and provider parsing. **UI** consumes normalized state through SwiftUI menu, settings and About views.

SwiftPM exposes `LoomCore` from `Loom/Core` and `Loom/Providers`, and the `Loom` executable from `Loom/App` and `Loom/UI`. Xcode provides the shared Loom scheme. There are no third-party package dependencies.

## Data flow

```text
Raw OS / Process Evidence
  -> ProcessTree (ancestry, host app, child worker tracking)
  -> WorkspaceResolver (Git, mirror project documents, CLI flags, CWD)
  -> SessionCorrelationEngine (collapse child workers, deduplicate sessions, rank evidence)
  -> Canonical AgentSession + ProviderDiscoveryDiagnostics
  -> SessionStore (stale reconciliation, wake handling, diagnostics)
  -> SwiftUI Sessions / Usage
```

`AgentProcess` represents raw process-level evidence (PID, parent PID, command line, executable, CWD, start time, host app). `AgentSession` represents one logical AI coding session (stable ID, provider session token, workspace path, project name, associated process tree, truthful normalized state, discovery evidence, diagnostics). Do not use PID alone as session identity; multiple helper/child processes belonging to the same logical task collapse into one session.

### Provider Health vs Session Lifecycle

Provider availability and session state are strictly separated concepts:
- **Provider Health** (`ProviderAvailability`): `.available`, `.degraded(reason:)`, `.unavailable(reason:)`, `.error(reason:)`. Represents the daemon/tool installation and metadata reachability.
- **Session Lifecycle** (`AgentState`): `.starting`, `.working`, `.waiting`, `.idle`, `.finished`, `.failed`, `.unknown`. Represents the execution phase of a specific project task.

Failure of optional metadata (e.g., SQLite lock contention or unreachable metadata endpoints) degrades provider health without failing discovered processes or marking active sessions as dead.

### Stale-Session Lifecycle & Wake Handling

Dead sessions must not linger permanently as `.working`:
- When an active session's processes terminate (user quits terminal, IDE closes, worker exits), reconciliation transitions the session to `.finished` with a recorded termination timestamp.
- When a provider encounters a fatal error or becomes unavailable, active sessions are moved out of `.working` (to `.failed` or `.idle`) rather than remaining perpetually active.
- `SessionStore` subscribes to `NSWorkspace.didWakeNotification` so that waking from sleep immediately triggers a fresh liveness sweep across all providers.

Do not leak raw provider JSON, logs or configuration into core/UI. Upstream formats change; parser fixtures and graceful failure belong at the adapter boundary. Optional metadata source failures must never fail an entire provider; discovery degrades gracefully to running process and workspace detection with diagnostic reporting. Missing evidence produces unknown metadata or state rather than a guess.

## Registration and refresh

Normal launch registers Codex and Antigravity. Explicit demo flags select mock, empty or failure fixtures; Claude's presence in fixtures is not a live implementation.

The store coordinates manual and periodic refresh (60 seconds by default, configurable). Cancellation and overlap handling prevent competing refreshes. Provider failures must not erase other providers' results. Retained successful usage snapshots must be identified as stale after errors. Provider discovery diagnostics record process detection count, logical session count, workspace resolution ratio, metadata health, and discovery duration in milliseconds.

## Local interfaces and privacy

Codex session discovery inspects running processes and resolves Git/project metadata; it reports Unknown state rather than inferring activity from process existence. Antigravity session discovery reads provider-local metadata. Codex usage uses a local app-server subprocess over standard input/output. Antigravity usage discovers a language-server port and queries it over loopback HTTPS with an ephemeral token.

Antigravity transport applies a TLS trust exception only to the discovered loopback host and port, and rejects redirects. This is not normal certificate-chain validation or proof that every loopback process is trustworthy. Provider credentials are not persisted by Loom; diagnostics must not expose them. See [SECURITY](../SECURITY.md).

Prefer documented local interfaces, then stable CLI output or metadata, with narrow tested fallbacks. Adapter failures must not block the app. Loom does not inject prompts or modify sessions.

## Presentation and verification

`MenuBarExtra` presents the primary window. Sessions/Usage retain independent state. Content measurement bounds the menu to available screen height; overflow scrolls rather than clipping. The full-color application icon is separate from the template monochrome glyph.

Parser/store tests cover normalized behavior; the native menu probe checks sizing and interactions. The [CI workflow](../.github/workflows/ci.yml) uses explicit portable test selection. Full-suite discovery and subprocess cancellation limitations are documented in [CONTRIBUTING](../CONTRIBUTING.md); excluded or unrun checks are not a full pass.
