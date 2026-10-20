# Loom — Product Brief

## Problem and Thesis

Developers routinely run multiple autonomous and interactive AI coding agents across various repositories. Sessions, process trees, and token quotas are fragmented across terminal multiplexers, IDE extensions, background daemons, and browser dashboards. Answering a simple operational question becomes frustratingly tedious: *"What are all my local AI coding agents doing on my Mac right now?"*

Loom provides a compact, native macOS menu-bar surface that illuminates what is executing, where it is working, which tasks require human attention, and whether usage quotas are approaching exhaustion.

The core conceptual entity in Loom is an **agent session** and its verified association with a **project repository**. Usage and quota tracking complement this operational context without replacing active session monitoring.

---

## Evolution & Product Milestones

### v1.0 Baseline
- Native SwiftUI menu-bar popover (`LSUIElement`) with responsive vertical sizing.
- Unified monitoring of three local AI coding providers: **OpenAI Codex**, **Anthropic Claude Code**, and **Google Antigravity**.
- Process tree correlation collapsing parent processes, language servers, subagents, and workers into a single logical session per repository task.
- Truthful, normalized lifecycle states (`starting`, `working`, `waiting`, `idle`, `finished`, `failed`, `unknown`).
- Usage quota snapshots with remaining percentages, rolling window reset times, and model-specific caps.
- Local on-disk storage scanning measuring caches, transcripts, and indices.
- Desktop widgets across Small, Medium, and Large families for Quotas, Sessions, and Usage Overview.
- Privacy-first architecture: strictly read-only, local-first inspection, no cloud backend, no analytics SDKs, and a path concealment toggle (`hideProjectPaths`).

### v1.1 — Liquid Glass Redesign & Native Notifications
- **Liquid Glass Visual Foundation**: Native macOS 26+ popover redesign adopting Apple's Liquid Glass aesthetics (`.glassEffect` / `GlassEffectContainer`) with graceful, high-craft material fallbacks (`.ultraThinMaterial`) on macOS 14 and 15.
- **Attention-First Session Prioritization**: Deterministic ordering surfacing sessions requiring human decision-making (`waiting` for input, `failed`) at the top of the popover.
- **Collapsible Recent Sessions**: Completed tasks tuck cleanly into a collapsible disclosure section, eliminating popover clutter.
- **Unified Segmented Navigation**: A single native segmented control cleanly switching between `Sessions`, `Usage`, and `Storage`.
- **Truthful Quota Pacing & Reset Timestamps**: Quota velocity calculations grounded strictly in verified observations and known window timing, alongside exact reset timestamps whenever exposed by providers.
- **Native macOS Notifications**: System alerts via `UNUserNotificationCenter` for quota exhaustion thresholds (15% and 5% remaining), verified quota replenishment, and confirmed session transitions (`waiting`, `finished`, `failed`).
- **Persistent Deduplication & Privacy**: Cross-restart alert deduplication and automatic filesystem path masking in notifications when privacy mode is active.
- **Decoupled Polling Cadence**: Lightweight process liveness sweeps (~5–10s) separated from expensive quota IPC polling (~30–120s), eliminating false-positive waiting states caused by inactivity timeouts.

### v1.2 — Session Productivity, Diagnostics & Status Modes
- **Session Productivity Quick Actions**: Safe, local, read-only interactions to focus running Terminal/IDE host apps, copy process PIDs, copy repository paths, copy session IDs, and reveal directories in Finder.
- **Session Search & Filter Bar**: Instant filtering by search terms (repository name, branch, path) and category chips (`All`, `Needs Attention`, `Working`, `Recent`).
- **Enhanced Provider Diagnostics**: In-depth health disclosure displaying live discovery latency, workspace resolution ratio, process counts, and distinct discovery vs quota error indicators.
- **Configurable Menu Bar Status Modes**: Custom status item display options (`Icon Only`, `Active Sessions count`, `Lowest Quota` percentage) designed with minimal horizontal footprint for notched MacBook displays.
- **Privacy Quick Action Toggle**: One-click menu-bar toggle to instantly synchronize and flip `hideProjectPaths`.
- **Notification History & Auditing**: Bounded local history log in Settings auditing past notifications without storing private transcripts, commands, or credentials.

---

## Detailed Feature Specifications

### 1. Liquid Glass Popover Experience (v1.1)

```text
+--------------------------------------------------------------+
| [Glyph] Loom      2 Active · 1 Needs Attention    [⟳] [⚙] [⚿] | <- Compact Glass Header
+--------------------------------------------------------------+
| [   Sessions (3)   ] [      Usage      ] [     Storage     ] | <- Segmented Control
+--------------------------------------------------------------+
| [Search sessions...                            ] [X]        | <- Filter Bar (v1.2)
| [ All ] [ Needs Attention (1) ] [ Working (2) ] [ Recent (1) ] |
+--------------------------------------------------------------+
| ▼ NEEDS ATTENTION                                            |
|   ● Loom — main (Codex)                              WAITING | <- Priority Attention Card
|     Waiting for user confirmation on commit                  |
|     Host: VS Code (PID 48210) · 2m ago                       |
|     [Focus IDE] [Copy PID] [Copy Path] [Reveal in Finder]    | <- Quick Actions (v1.2)
+--------------------------------------------------------------+
| ▼ WORKING                                                    |
|   ● WebApp — feature/auth (Claude Code)              WORKING |
|     Running test suite · 4 processes · 12s ago               |
+--------------------------------------------------------------+
| ▶ RECENT SESSIONS (1 finished)                               | <- Collapsible Section
+--------------------------------------------------------------+
| Codex [●] · Claude Code [●] · Antigravity [●]                | <- Provider Selector
+--------------------------------------------------------------+
| Updated 4s ago • v1.1.0 • All systems healthy                | <- Footer Freshness
+--------------------------------------------------------------+
```

- **Compact Header**: Houses the monochrome Loom brand mark, an activity summary badge ("2 Active · 1 Attention"), manual refresh button, Settings gear, and quick privacy toggle.
- **Unified Segmented Navigation**: Eliminates multiple competing navigation bars by using a standard macOS segmented control across `Sessions`, `Usage`, and `Storage`.
- **Hierarchy of Session Cards**:
  1. **Needs Attention**: Prominently surfaced at top with high-contrast amber/red indicators for sessions waiting for human input or failed.
  2. **Active Work**: Sessions currently `working` or `starting`.
  3. **Idle & Unknown**: Low-confidence or paused sessions maintained truthfully without guessing.
  4. **Recent Sessions**: Collapsible disclosure group for `finished` sessions that prevents stale entries from dominating the popover.
- **Truthful Quota Presentation**:
  - Displays remaining percentages prominently.
  - Quota pacing calculates consumption rate solely from verifiable delta observations over known window intervals.
  - Exact reset timestamps (e.g. "Resets tomorrow at 04:30 AM") rendered alongside relative countdowns.

### 2. Native macOS Notifications (v1.1)

Loom delivers actionable desktop alerts through `UNUserNotificationCenter` without running persistent invasive daemons:
- **Quota Depletion Alerts**:
  - **15% Remaining**: Early warning that token/request quotas are nearing exhaustion.
  - **5% Remaining**: Critical warning advising the developer to pace agent execution or conclude active milestones.
  - Evaluated independently across 5-hour and weekly quota windows for each enabled provider.
- **Verified Quota Replenishment Alerts**:
  - Triggers an alert when a fresh provider observation confirms quota recovery to ~100% in a new window.
  - Never triggers prematurely based solely on countdown timer expiration.
- **Session Lifecycle Transitions**:
  - **Waiting for Input**: Alerts when an agent requires human decision-making, terminal confirmation, or parameter review.
  - **Finished**: Alerts when a long-running background task finishes cleanly.
  - **Failed**: Alerts when an agent process exits with an error or encounters a fatal provider failure.
- **Alert Deduplication & Hygiene**:
  - Unique deduplication key: `<provider>:<bucket>:<windowId>:<threshold>` persisted in `UserDefaults` (`SharedAppGroup`).
  - No alert storms on application launch (initial scan seeds the baseline state silently).
  - Stale snapshots, mock fixtures, and disabled providers are strictly suppressed.
- **Privacy Path Concealment**: When `hideProjectPaths` is active, notification titles and bodies redact repository directory paths, substituting project names or generic workspace labels. Clicking a notification opens Loom directly to the relevant provider and session.

### 3. Session Productivity Quick Actions (v1.2)

Every session card provides instant, safe, read-only utilities:
- **Focus Terminal / IDE**: Inspects the parent host application (e.g. `com.microsoft.VSCode`, `com.apple.Terminal`, `com.googlecode.iterm2`, `com.todesktop.230313mzl4w4u92`) and brings its windows forward using `NSWorkspace.shared.runningApplications`.
- **Copy Process PID**: Copies the root worker PID to the macOS pasteboard.
- **Copy Repository Path**: Copies the absolute filesystem path (or masked identifier if privacy mode is enabled).
- **Copy Session ID**: Copies the upstream provider session token for correlation with external logs.
- **Reveal in Finder**: Opens the project directory in macOS Finder (`NSWorkspace.shared.activateFileViewerSelecting`).
- **Safety Guarantee**: Loom offers zero process termination (`kill`, `SIGTERM`), code execution, or prompt injection affordances.

### 4. Session Search & Filter Bar (v1.2)

- **Search Bar**: Real-time filtering across repository names, Git branches, host apps, and session identifiers.
- **Filter Chips**:
  - `All`: Full list of discovered sessions.
  - `Needs Attention`: Filters strictly to sessions in `waiting` or `failed` states.
  - `Working`: Filters strictly to sessions in `working` or `starting` states.
  - `Recent`: Filters to recently completed (`finished`) sessions within the configured retention window.
- Preserves independent scroll positions and card disclosure state across filter switches.

### 5. Enhanced Diagnostics (v1.2)

Available via the expandable provider diagnostics card:
- **Reachability Status**: Differentiates between normal operation, degraded performance (e.g. SQLite WAL lock contention, slow CLI response), unavailable environments, and connection errors.
- **Live Discovery Latency**: Reports last discovery duration in milliseconds.
- **Metrics Breakdown**: Displays total running processes detected, logical sessions grouped, and workspace resolution ratio (resolved workspaces vs total sessions).
- **Error Isolation**: Clear distinction between process discovery errors and quota IPC failures. Stale usage snapshots are visibly badged without failing session tracking.

### 6. Menu Bar Status Modes (v1.2)

Configurable in Settings (`General` tab) to optimize status bar footprint:
- **Icon Only** (Default): Standard monochrome woven Loom mark (minimal footprint).
- **Active Sessions Count**: Displays the glyph plus the total count of running/working agents (e.g. `⎇ 3`).
- **Lowest Quota Percentage**: Displays the glyph plus the lowest verified remaining quota across enabled providers (e.g. `⎇ 12%`). Automatically color-shifts or badges when crossing critical thresholds.

---

## Integration Status & Supported Providers

All three production providers are registered and active in standard launch mode:

| Provider | Process & Session Discovery | Quota & Rate Limit Inspection | Local Disk Footprint Scanning | Status |
| :--- | :--- | :--- | :--- | :--- |
| **OpenAI Codex** | Running CLI processes, process tree correlation, and Git workspace metadata. | Local app-server IPC protocol over standard input/output (`stdio`). | Caches, conversation sessions, and local logs in `~/.codex`. | Production |
| **Anthropic Claude Code** | CLI process inspection, transcript inspection, and working directory resolution. | Not currently exposed by local CLI (truthfully badged as *Quota not supported*). | Config, state files, and transcripts in `~/.claude`. | Production |
| **Google Antigravity** | Process tree tracking and local session/workspace state inspection. | Loopback HTTPS connection to discovered language server port using ephemeral token. | State database, artifacts, and logs in `~/.gemini/antigravity-cli`. | Production |

*Demo fixture modes (`--demo-mock`, `--demo-empty`, `--demo-failure`) are strictly opt-in via command-line flags and are visibly badged.*

---

## Settings & Controls

Accessible via `⌘,`, the header gear icon, or the macOS Dock menu:

1. **General Tab**:
   - Menu Bar Status Mode (`Icon Only`, `Active Sessions`, `Lowest Quota`).
   - Dock Icon activation policy (Show in Dock alongside Menu Bar).
   - Polling refresh intervals: fast liveness (~5–10s) and slow quota polling (30s, 60s, 2m, 5m; default 60s).
   - Sparkle software update feed and automatic update checks.
2. **Providers Tab**:
   - Individual enable/disable monitoring toggles for Codex, Claude Code, and Antigravity.
   - Default provider tab selection upon app launch.
3. **Notifications Tab (v1.1)**:
   - Master notifications enable/disable toggle.
   - Contextual system permission status indicator (`Authorized`, `Denied`, `Not Determined`) with direct link to macOS System Settings.
   - Quota alerts toggle: 15% and 5% threshold warnings.
   - Quota replenishment toggle: alerts upon verified window reset.
   - Session transition alerts: separately toggleable for `Waiting for Input`, `Session Finished`, and `Session Failed`.
   - Test Notification button for instant delivery verification.
   - Notification History log: view recent alerts with timestamps, provider, event type, and delivery status.
4. **Sessions & Retention Tab**:
   - Toggle inclusion of recent/finished sessions.
   - Configurable expiration window for completed sessions (`Never`, `1 hour`, `24 hours`, `7 days`).
5. **Storage Tab**:
   - On-demand scanning of local agent storage footprints with drill-down into directories and direct Finder reveal.
6. **Privacy Tab**:
   - **Hide Project Paths**: Masks filesystem paths and evidence in the UI, inspectors, tooltips, and system notifications while preserving Finder actions.

---

## Security & Privacy Non-Goals

Loom adheres to a strict read-only and local-first security contract:
- **No Cloud Services**: Zero external servers, user authentication, or data telemetry.
- **No Prompt Injection or Process Control**: Explicitly out of scope:
  - No `SIGKILL` or `SIGINT` process termination actions.
  - No automated prompt sending or agent orchestration.
  - No remote control or cloud synchronization.
  - No destructive cache pruning or log deletion.
  - No synthetic token-cost dashboards or unverified quota guesswork.

---

## Verification Strategy & Release Gates

1. **Deterministic Unit Test Suite**: Comprehensive portable tests covering process correlation, lifecycle reconciliation, quota threshold crossing, reset detection, deduplication, and settings persistence.
2. **Native Layout Probes**: Validates menu bar popover sizing, disclosure mechanics, and vertical height constraints across MacBook display configurations.
3. **Notification Delivery Verification**: Validates `UNUserNotificationCenter` payload generation, privacy masking, and deep-link routing.
4. **macOS Visual Quality Gate**: Real-device inspection of macOS 26+ Liquid Glass and macOS 14/15 material fallbacks in both Light and Dark appearances.
