# Interface Polish, Notifications, and Local Storage

Loom balances native macOS desktop craft with strict local-first privacy. This document details the visual styling system, notification architecture and storage, menu bar status modes, and disk footprint scanning.

---

## 1. Visual Styling: Liquid Glass & Material Fallbacks

Loom’s popover interface is designed to feel like an integral part of macOS rather than a ported web dashboard or generic Electron utility.

```text
+---------------------------------------------------------------------------------+
| macOS 26+ Environment:                                                          |
|  - System Liquid Glass: .glassEffect() and GlassEffectContainer                 |
|  - Native glass-styled segmented navigation, header controls, and icon badges    |
|  - Standard content materials for data cards (no nested glass blur)             |
+---------------------------------------------------------------------------------+
| macOS 14 & 15 Fallback Environment:                                             |
|  - Semantic Materials: .ultraThinMaterial backing for popover root              |
|  - Native NSSegmentedControl and standard AppKit/SwiftUI borderless buttons     |
|  - Subtle hairline separators (.quaternary) and semantic fill colors            |
+---------------------------------------------------------------------------------+
| Accessibility Overrides:                                                        |
|  - Reduce Transparency: Replaces all glass/translucent materials with opaque    |
|    system background (NSColor.windowBackgroundColor)                            |
|  - Increase Contrast: High-contrast borders and elevated text contrast ratios   |
|  - VoiceOver: Semantic accessibility labels on all controls and status capsules  |
+---------------------------------------------------------------------------------+
```

### Liquid Glass Adoption Rules

1. **System-Provided Glass on macOS 26+**: Header chrome, navigation segment bars, and toolbar controls adopt native Liquid Glass styling via `.glassEffect()` where supported by the OS runtime.
2. **Graceful Fallbacks on macOS 14/15**: Availability guards (`@available(macOS 26.0, *)`) route older supported macOS versions to `.background(.ultraThinMaterial)` and native secondary fills.
3. **No Nested Glass Stacking**: Content cards (such as session cards and quota progress bars) use standard opaque or thin background fills. Stacking multiple translucent glass layers or placing translucent text on translucent backgrounds is strictly prohibited to prevent visual mush and contrast degradation.
4. **Restrained Color & Semantic Badges**:
   - **Needs Attention** (`waiting`, `failed`): High-visibility semantic amber (`Color.orange`) and red (`Color.red`).
   - **Active Execution** (`working`, `starting`): Crisp system accent blue or green.
   - **Idle & Unknown**: Low-emphasis secondary/tertiary grays.
   - **Quota Warning Thresholds**: 15% threshold uses warning amber; 5% threshold uses critical red.
5. **Accessibility Integrity**:
   - **Reduce Transparency**: When the user enables Reduce Transparency in macOS System Settings, all glass and material surfaces fall back immediately to solid, opaque system window fills.
   - **Full Keyboard Navigation & VoiceOver**: Every button, disclosure arrow, filter chip, and quick action provides descriptive `.accessibilityLabel` and `.accessibilityHint` traits.

---

## 2. Native Notifications & Storage Architecture

Loom integrates with `UNUserNotificationCenter` to deliver actionable system alerts while strictly guarding user privacy.

### User Notification Preferences

Configured under **Settings → Notifications**:

| Setting Key | Default | Description |
| :--- | :--- | :--- |
| `notificationsEnabled` | `true` | Master toggle. Existing opt-outs are preserved; macOS authorization is still required. |
| `quotaWarning15Percent` | `true` | Alerts when an enabled quota-capable provider's observed remaining quota crosses below 15% (Codex and Antigravity). |
| `quotaWarning5Percent` | `true` | Alerts when an enabled quota-capable provider's observed remaining quota crosses below 5% (Codex and Antigravity). |
| `quotaReplenishedAlert` | `true` | Alerts when a fresh observation confirms quota recovery to ~100% in a new window. |
| `sessionWaitingAlert` | `true` | Alerts when an agent session transitions to `waiting` (requiring user input/decision). |
| `sessionFinishedAlert` | `false` | Alerts when an active agent session concludes successfully and meets the observed Working duration. |
| `minimumWorkingDuration` | `300 seconds` | Finished alerts only: Always, 2, 5 or 10 minutes of observed Working time; waiting/failure alerts stay immediate. |
| `sessionFailedAlert` | `true` | Alerts when an agent process exits abnormally or encounters a fatal provider error. |

- **Quota Support**: Codex and Antigravity expose observed quota data for threshold alerts. Claude Code does not expose quota through its upstream local interface; Loom does not synthesize Claude quota values.
- **Permission Handling**: Notifications default to enabled. On normal launch, Loom requests macOS authorization only if notifications are enabled and permission has not been decided. Existing opt-outs and macOS denials remain unchanged; demo launches do not request permission. Enabling notifications in Settings can also request authorization.
- **System Settings Link**: If permissions are denied at the OS level, Settings displays an inline warning banner with a direct link to macOS System Settings.
- **Debug Test Notification**: Debug builds include **Send Test Notification** for manual development verification. Release builds exclude the button and test-alert implementation.

### Notification History Storage (`NotificationHistoryStore`)

Production quota threshold deduplication and window observations are persisted in UserDefaults across app restarts. Reset alerts require fresh, ordered observations crossing a known prior reset boundary and restoring at least 95% in a later window; a changed timestamp alone is insufficient. Upstream account/profile identity is not yet available for scoping this state.

To provide transparency and auditability, Loom maintains a bounded local history of queued, failed or suppressed notifications:

- **Storage Location**: Persisted in `UserDefaults` via `SharedAppGroup.suiteName` under `loom.notificationHistory`.
- **Bounded Retention**: Stored as a circular ring buffer capped at the last **100 events** to prevent unbounded disk growth.
- **Stored Data Schema**:
  - `id`: Unique UUID.
  - `timestamp`: ISO 8601 creation date.
  - `eventType`: `quota15`, `quota5`, `quotaReplenished`, `sessionWaiting`, `sessionFinished`, `sessionFailed`.
  - `providerID`: `codex`, `claude`, or `antigravity`.
  - `title`: Notification headline.
  - `subtitle`: Redacted summary text.
  - `delivered`: Boolean delivery status.

### Strict Privacy Guarantees

1. **No Sensitive Content Persistence**: The history store **never** records conversation transcripts, user prompts, shell commands, environment variables, API keys, or full error stack traces.
2. **Path Concealment (`hideProjectPaths`)**: When enabled:
   - File system paths (e.g. `/Users/deepak/Desktop/Projects/oss/Loom`) are masked in notification titles and bodies, showing only the sanitized repository name (e.g. `Loom`) or generic identifier.
   - Notification history entries sanitize all paths before writing to disk.
3. **Deep Linking Without Exposure**: Clicking a notification opens Loom, activates the relevant provider tab, and highlights the corresponding session via internal session UUIDs without passing filesystem paths through system notification payloads.

---

## 3. Menu Bar Status Modes & Footprint

To respect limited menu bar real estate—especially on notched MacBook displays—Loom provides three status modes in **Settings → General**:

```text
1. Icon Only (Default):
   [ ⎇ ]

2. Active Sessions Count:
   [ ⎇  2 ]

3. Lowest Quota Percentage:
   [ ⎇  18% ]
```

- **Icon Only**: Displays the canonical monochrome woven Loom glyph. Takes minimal width (~24pt).
- **Active Sessions Count**: Displays the glyph alongside an integer count of currently executing agents (`working` or `starting`). If zero sessions are active, displays the glyph alone.
- **Lowest Quota Percentage**: Displays the glyph alongside the lowest verified remaining quota across all monitored providers. Never displays `0%` for missing or unsupported quota data (such as Claude Code). Transitions to warning colors when crossing below 15%.
- **Safety Invariant**: Status bar strings are strictly bounded in width and truncated safely if screen constraints require it.

---

## 4. Session Productivity & Filters

The popover provides instant operational tools for active developers:

### Filter Chips & Real-Time Search

- **Filter Bar**: Positioned at the top of the Sessions view.
  - `All`: Unfiltered list of discovered sessions.
  - `Needs Attention`: Filters strictly to sessions in `waiting` or `failed` states.
  - `Working`: Filters strictly to sessions in `working` or `starting` states.
  - `Recent`: Filters to recently completed (`finished`) sessions.
- **Search Field**: Real-time filtering matching repository names, Git branches, host application names, or session identifiers without stalling background polling.

### Quick Actions (`SessionActionsView`)

Each session card exposes safe, non-destructive quick actions:
- **Focus Terminal / IDE**: Identifies the host application PID and brings its windows forward using `NSWorkspace.shared.runningApplications`.
- **Copy PID**: Copies the primary process PID to the clipboard.
- **Copy Repo Path**: Copies the project path (or masked name if privacy mode is active).
- **Copy Session ID**: Copies the provider session token.
- **Reveal in Finder**: Direct Finder navigation via `NSWorkspace.shared.activateFileViewerSelecting`.
- **Strict Read-Only Contract**: Loom does not provide `kill`, `SIGTERM`, or shell prompt execution affordances.

---

## 5. Local Storage Footprint Scanning

Configured in **Settings → Storage**:

- **Measured Directories**:
  - **OpenAI Codex**: Measures `~/.codex/sessions`, `~/.codex/cache`, and `~/.codex/logs` (respects `CODEX_HOME` override).
  - **Anthropic Claude Code**: Measures `~/.claude/state`, `~/.claude/transcripts`, and `~/.claude/config` (respects `CLAUDE_CONFIG_DIR` override).
  - **Google Antigravity**: Measures `~/.gemini/antigravity-cli/brain`, `~/.gemini/antigravity-cli/mcp`, and associated state files (excludes unrelated Gemini data).
- **Execution Safeguards**:
  - Scans off the main actor (`Task.detached` / background queue).
  - **Hard Bounds**: Execution is limited to a maximum of **5 seconds** and **100,000 entries** per provider root.
  - **Cooperative Cancellation**: Dismissing the popover or switching tabs cancels active scans immediately.
  - **Read-Only**: The scanner only reads file attributes (`fileSize`). It never inspects file contents, follows symlinks across filesystems, deletes files, or alters directory structures.
  - **Privacy**: If `hideProjectPaths` is active, storage path labels in the UI are redacted.

---

## 6. WidgetKit Integration

Loom provides three desktop and Notification Center widgets via `SharedAppGroup`:

1. **Loom Quotas** (Small, Medium, Large): Displays remaining quota percentages, countdowns to reset timestamps, and granular model limits. Configurable via widget intent to focus on a specific provider or show all.
2. **Loom Sessions** (Small, Medium): Glanceable count of active sessions and prominent alerts for sessions waiting for human input.
3. **Loom Usage Overview** (Medium, Large): Multi-provider comparison with progress bars and reset countdowns.

- **Data Invariants**: Widgets consume serialized snapshots from `LoomWidgetSnapshot`. Snapshots are written atomically upon store refresh. Saved timestamps use the original observation date, ensuring countdowns remain accurate even if Loom is idle.
