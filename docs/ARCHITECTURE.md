# Architecture

## System Overview & Layers

Loom is architected as a lightweight, local-only macOS application built with Swift 5.9+, SwiftUI, and native AppKit/UserNotifications frameworks. It monitors autonomous and interactive AI coding agents across four decoupled architectural layers:

```text
+-----------------------------------------------------------------------------------+
|                                UI & PRESENTATION LAYER                             |
|  - AppKit: StatusItemController (Dynamic Menu Bar Modes), DockController          |
|  - SwiftUI: MenuBarRootView (Liquid Glass Container, Segmented Navigation)         |
|             SessionFilterBar, SessionRowView, SessionActionsView, UsageBarView    |
|             DiagnosticsView, StorageView, SettingsView (NotificationsTab, etc.)    |
+-----------------------------------------------------------------------------------+
                                         ▲
                                         │ State Observation
+-----------------------------------------------------------------------------------+
|                                NOTIFICATION LAYER                                 |
|  - Coordinator: NotificationCoordinator (UNUserNotificationCenter Delivery)       |
|  - Policy: NotificationPolicy (Deduplication, Privacy Sanitization, Preferences)  |
|  - Evaluators: QuotaThresholdEvaluator, SessionTransitionDetector                 |
|  - Events: MonitoringEvent (Typed Quota & Transition Payloads)                    |
|  - History: NotificationHistoryStore (Bounded Local Audit Log in App Group)       |
+-----------------------------------------------------------------------------------+
                                         ▲
                                         │ Event Emission
+-----------------------------------------------------------------------------------+
|                                    CORE LAYER                                     |
|  - Store: SessionStore (Dual-Cadence Polling, State Management, Wake Sweep)       |
|  - Discovery: ProcessTree, WorkspaceResolver, SessionCorrelationEngine           |
|  - Lifecycle: SessionLifecycleReconciler (Transition Evidence, Stale Handling)    |
|  - Storage: StorageScanner (Non-blocking, Capped Local Directory Measurement)     |
|  - Models: AgentSession, AgentProcess, AgentUsage, ProviderAvailability           |
|  - Config: LoomSettings, SharedAppGroup (App Group Defaults Persistence)          |
+-----------------------------------------------------------------------------------+
                                         ▲
                                         │ Provider Protocols
+-----------------------------------------------------------------------------------+
|                                  PROVIDERS LAYER                                  |
|  - CodexProvider (CLI Process Tree, Git Metadata, stdio App-Server IPC)           |
|  - ClaudeProvider (CLI Process Tree, Transcript Discovery, Workspace Detection)   |
|  - AntigravityProvider (Language Server Process, Local Session DB, Loopback HTTPS) |
|  - MockAgentProvider (Fixture Scenarios: mock, empty, failure)                    |
+-----------------------------------------------------------------------------------+
```

### Module Boundaries

- **`LoomCore` Target**: Encapsulates models, discovery engines, lifecycle reconciliation, storage scanning, notification evaluation core, and provider adapters. Has zero third-party package dependencies.
- **`Loom` Executable Target**: Integrates the SwiftUI views, AppKit status item coordination, `UNUserNotificationCenter` desktop notification delivery, and official Sparkle 2 for signed local updates.
- **`LoomWidgets` Extension Target**: Standalone WidgetKit extension reading shared cached snapshots from `SharedAppGroup` to render desktop and Notification Center widgets without launching the main application process.

---

## Data Flow & Dual-Cadence Polling Architecture

```text
                                [ OS Process Table ]
                                         │
                   +---------------------+---------------------+
                   │                                           │
         (Fast ~5–10s Liveness)                      (Slow ~30–120s Quota/IPC)
                   │                                           │
         ProcessTree Inspection                      Provider Quota Fetcher
         - PID hierarchy & liveness                  - Codex stdio JSON-RPC
         - Parent / child correlation                - Antigravity Loopback HTTPS
         - CWD & Git repository detection            - Claude status verification
                   │                                           │
                   ▼                                           ▼
       WorkspaceResolver & Correlation                Usage Snapshot Parser
                   │                                           │
                   +---------------------+---------------------+
                                         │
                                         ▼
                           SessionLifecycleReconciler
                   - Truthful State Transitions (Working/Waiting/Finished)
                   - Wake-from-sleep reconciliation
                   - Inactivity timeout guards (No false "Waiting")
                                         │
                                         ▼
                                   SessionStore
                                         │
                   +---------------------+---------------------+
                   │                                           │
                   ▼                                           ▼
          MonitoringEvent Stream                      SwiftUI View Models
                   │                                  - MenuBarRootView
       +-----------+-----------+                      - SessionFilterBar
       │                       │                      - SessionRowView
       ▼                       ▼                      - UsageBarView
QuotaThresholdEvaluator  SessionTransitionDetector             │
 (15%, 5%, Resets)      (Waiting/Finished/Failed)              ▼
       │                       │                      StatusItemController
       +-----------+-----------+                      - Icon Only
                   │                                  - Active Sessions Count
                   ▼                                  - Lowest Quota %
           NotificationPolicy
         - Persistent Deduplication
         - Path Concealment Masking
                   │
                   ▼
         NotificationCoordinator
       - UNUserNotificationCenter
       - NotificationHistoryStore
```

### 1. Separate Polling Cadences

Loom separates lightweight session monitoring from expensive usage/quota querying:
- **Fast Liveness Sweep (~5–10s)**:
  - Scans local running processes and child trees via low-overhead system calls.
  - Verifies whether previously tracked PIDs are still alive.
  - Fast-paths lifecycle state changes (`working` -> `finished` when processes terminate).
  - Operates completely in-memory without launching heavy child processes or running disk-intensive queries.
- **Slow Quota Polling (~30–120s, Configurable)**:
  - Communicates with provider daemon interfaces (Codex `stdio` app-server, Antigravity loopback HTTPS endpoint).
  - Parses rate-limit windows, remaining percentages, and reset deadlines.
  - Keeps quota querying bounded, cancellable, and non-blocking to preserve main thread responsiveness.
- **Wake Sweep**:
  - `SessionStore` listens for `NSWorkspace.didWakeNotification`.
  - Upon system wake, Loom immediately schedules an out-of-band fast liveness sweep followed by a quota refresh to clear stale sleep state.

---

## Notification Subsystem Architecture

The notification layer is designed to be deterministic, false-positive resistant, and privacy-respecting:

```text
[ SessionStore ]
       │ Emits MonitoringEvents
       ▼
+---------------------------------------------------------------------------------+
| MonitoringEvent Core                                                            |
|  - .quotaThresholdCrossed(provider:bucket:remainingPct:windowId:)               |
|  - .quotaReplenished(provider:bucket:windowId:)                                 |
|  - .sessionStateTransition(session:fromState:toState:evidence:)                 |
+---------------------------------------------------------------------------------+
       │
       ▼
+---------------------------------------------------------------------------------+
| Evaluation Layer                                                                |
|  - QuotaThresholdEvaluator:                                                     |
|      Tracks remaining quota crossing below 15% and 5%. Verifies recovery to     |
|      ~100% in a newly observed window before firing a replenishment alert.      |
|  - SessionTransitionDetector:                                                   |
|      Seeds initial discovered sessions on launch silently (no alert storm).     |
|      Emits events only on verified transitions:                                 |
|        * Working -> Waiting (requires explicit human input evidence)            |
|        * Working -> Finished (clean exit)                                       |
|        * Working -> Failed (abnormal exit / error code)                         |
+---------------------------------------------------------------------------------+
       │
       ▼
+---------------------------------------------------------------------------------+
| NotificationPolicy                                                              |
|  - Deduplication: Computes unique key: "<provider>:<bucket>:<windowId>:<rule>" |
|  - Persistence: Checks and updates deduplication records in SharedAppGroup     |
|  - Preferences: Evaluates user toggles (Master, 15%, 5%, Resets, Transitions)   |
|  - Privacy Filter: Masks project paths when `hideProjectPaths` is active        |
+---------------------------------------------------------------------------------+
       │
       ▼
+---------------------------------------------------------------------------------+
| Delivery & Audit                                                                |
|  - NotificationCoordinator: Dispatches to UNUserNotificationCenter              |
|  - Deep Linking: Routes user clicks directly to matching provider and session   |
|  - NotificationHistoryStore: Appends to bounded local ring buffer in defaults    |
+---------------------------------------------------------------------------------+
```

### Truthful Event Evaluation Rules

1. **Thresholds Represent Remaining Quota**: 15% and 5% alerts trigger when remaining quota falls below the threshold, not when 15% has been consumed.
2. **Window Identity Guard**: Deduplication is scoped to the provider's active quota window. A new window ID resets the deduplication state, enabling threshold alerts for the next cycle.
3. **No Countdown-Only Resets**: Quota replenishment is emitted *only* when a fresh observation confirms quota recovery to ~100% in a new window. Timers expiring without refreshed telemetry do not trigger alerts.
4. **No Initial Launch Alert Storm**: When Loom launches or wakes, existing running sessions seed the detector baseline without dispatching notifications.
5. **Inactivity Does Not Mean Waiting**: Inactivity timeouts never trigger a "Needs Input" notification. Waiting notifications require verifiable provider evidence (e.g., waiting on user confirmation or prompt input).
6. **Provider Failure Isolation**: If a provider fails to respond or crashes, active sessions do not generate `Finished` alerts; they are transitioned to `Unknown` or marked with provider error diagnostics.

---

## Liquid Glass UI & AppKit Status Bar Hierarchy

Loom adopts Apple's Liquid Glass visual language for macOS 26+ while providing high-craft material fallbacks on macOS 14/15:

```text
MenuBarRootView (SwiftUI)
│
├── LoomGlassStyles
│   ├── macOS 26+: .glassEffect() / GlassEffectContainer
│   └── macOS 14/15: .background(.ultraThinMaterial)
│
├── HeaderBarView
│   ├── Monochrome Loom Glyph & Title
│   ├── Activity & Attention Badges ("2 Active · 1 Needs Attention")
│   ├── Refresh Button (Native Glass Button)
│   ├── Settings Button (Native Glass Button)
│   └── Privacy Quick Toggle (hideProjectPaths)
│
├── NavigationBarView
│   └── NSSegmentedControl Bridge: [ Sessions | Usage | Storage ]
│
├── ContentContainerView
│   ├── SessionsView
│   │   ├── SessionFilterBar (Search Field + Filter Chips: All, Attention, Working, Recent)
│   │   ├── PrioritySectionView (Needs Attention: Waiting, Failed)
│   │   ├── ActiveSectionView (Working, Starting)
│   │   ├── IdleSectionView (Idle, Unknown)
│   │   └── CollapsibleSectionView (Recent Finished Sessions)
│   │       └── SessionRowView
│   │           ├── Repository Identity & Lifecycle Capsule
│   │           ├── Host App & Elapsed Time
│   │           ├── Expandable Process Tree & Diagnostics
│   │           └── SessionActionsView (Focus IDE, Copy PID, Copy Path, Finder Reveal)
│   │
│   ├── UsageView
│   │   ├── Provider Quota Windows & Pacing Velocity
│   │   ├── Granular Model Limits
│   │   └── UsageBarView with Truthful Missing/Stale Badges
│   │
│   └── StorageView
│       ├── Local Disk Footprint Proportions
│       └── Directory Detail Breakdown & Finder Navigation
│
├── ProviderSelectorView (Glanceable Codex, Claude, Antigravity Status)
└── FooterView (Freshness Timestamp, App Version, Global Health)
```

### StatusItemController (AppKit Bridge)

Loom is an `LSUIElement` application. The status bar item is managed by `StatusItemController`:
- **`iconOnly` Mode**: Displays the canonical monochrome template glyph.
- **`activeSessions` Mode**: Attaches a compact, secondary-styled integer label (e.g. `Loom 3`).
- **`lowestQuota` Mode**: Displays the glyph and the lowest verified remaining quota percentage (e.g. `Loom 14%`). Automatically highlights in amber/red when crossing notification thresholds.
- **Notch Safety**: Keeps status bar string lengths strictly bounded to prevent menu bar truncation on notched MacBook displays.

---

## Provider Registration & Lifecycle Contracts

In standard launch mode (`DemoFixture.standard`), Loom registers all three production providers:
1. **`CodexProvider`**: Inspects local CLI processes, resolves Git repository metadata, and interfaces with the local Codex app-server via `stdio`.
2. **`ClaudeProvider`**: Discovers running `claude` CLI processes, inspects transcript files, resolves active project directories, and truthfully marks quota monitoring as unsupported.
3. **`AntigravityProvider`**: Detects running language-server processes, reads local session SQLite databases in read-only mode (`?immutable=1&mode=ro`), and connects to local loopback HTTPS endpoints with ephemeral tokens.

### Health vs Session Lifecycle Separation

- **Provider Availability** (`ProviderAvailability`): Indicates tool installation, daemon liveness, and metadata availability (`.available`, `.degraded`, `.unavailable`, `.error`).
- **Session Lifecycle** (`AgentState`): Normalized project execution state (`.starting`, `.working`, `.waiting`, `.idle`, `.finished`, `.failed`, `.unknown`).

Optional metadata failures (such as SQLite WAL locks or transient timeouts) degrade provider health without terminating active sessions or claiming they have finished.

---

## Local-Only Security & Privacy Invariants

- **Read-Only Process Inspection**: Loom never executes `kill`, `SIGTERM`, or interactive shell commands against monitored agents.
- **No Cloud Synchronization**: All monitoring, quota tracking, storage analysis, and notification evaluation occurs entirely on the local Mac.
- **Path Concealment (`hideProjectPaths`)**: When enabled, masks absolute filesystem paths in the UI, tooltips, logs, and notification payloads while preserving Finder actions.
- **Ephemeral Token Handling**: Loopback communication tokens for Antigravity are kept in memory and never written to disk or logged.
- **Sanitized Diagnostics**: Provider diagnostics record counts, resolution ratios, and error categories without leaking source code, file contents, environment variables, or private auth keys.
