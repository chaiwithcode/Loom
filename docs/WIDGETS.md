# Loom widgets: build, install, and troubleshoot

Loom includes three native macOS desktop widgets provided by the `LoomWidgetExtension.appex` extension embedded inside `Loom.app`:

1. **Loom Sessions** (`com.chaiwithcode.loom.widget`):
   - **Supported Families**: Small (`.systemSmall`), Medium (`.systemMedium`)
   - **Purpose**: Displays active session counts, sessions needing attention, total tracked sessions, and per-provider lifecycle status.

2. **Loom Quotas** (`com.chaiwithcode.loom.quotas`):
   - **Supported Families**: Small (`.systemSmall`), Medium (`.systemMedium`), Large (`.systemLarge`)
   - **Purpose**: Tracks remaining quota and reset times for local AI providers. Configurable to display all enabled providers or filter to a specific provider (Codex, Claude Code, or Antigravity) via Edit Widget. Single-provider view presents full progress bars and reset countdowns; multi-provider view offers compact comparison across active tools.

3. **Loom Usage Overview** (`com.chaiwithcode.loom.usage-overview`):
   - **Supported Families**: Medium (`.systemMedium`), Large (`.systemLarge`)
   - **Purpose**: Displays quota progress across all supported providers simultaneously without requiring provider switching:
     - **Medium Layout**: 3 columns (one per provider: Codex, Claude Code, Antigravity) featuring provider names, compact quota rows, remaining progress bars, reset times, and `+N more` links when extra windows exist.
     - **Large Layout**: Comprehensive grouped view by provider displaying standard quota windows alongside specific model limits (e.g. GPT-4o, o1, Gemini 1.5 Pro). Content exceeding display capacity cleanly caps with `+N more limits` linking directly into Loom without scrolling.
     - **Truthful States**: Displays `Monitoring off` when disabled, `Quota not supported` for providers lacking usage APIs (e.g., Claude Code), `Quota unavailable` for missing values, and `Saved` / `Saved data` for cached observations.
     - **Remaining-Bar Direction**: Progress bars fill from the leading edge proportional to the remaining percentage, matching percentage text.

Package checks can verify that the extension is present and correctly described; they do not prove that macOS has registered it or that it appears in the Notification Center gallery. Gallery visibility must be checked on a Mac after installing and launching the app.

## Build and validate the package

From the repository root, build the local app bundle and run the structural checks:

```sh
bash scripts/build-app.sh
bash scripts/verify-widget-package.sh
# Check the installed copy explicitly:
bash scripts/verify-widget-package.sh /Applications/Loom.app
```

The verifier checks the embedded `.appex`, its executable and identifiers, its WidgetKit extension point, entitlements, app URL scheme, code signature, and the symbols and kinds for all three widgets (`com.chaiwithcode.loom.widget`, `com.chaiwithcode.loom.quotas`, and `com.chaiwithcode.loom.usage-overview`). A passing result is package evidence only; it does not test Launch Services/PlugInKit registration, gallery visibility, or an installed widget’s behavior.

## Install and verify in Notification Center

1. Move or copy `.build/Loom.app` to `/Applications` (or another stable Applications folder).
2. Launch Loom from that installed location at least once and allow it to finish launching.
3. Open Notification Center, choose **Edit Widgets**, and search for **Loom**.
4. Confirm all three widgets appear in the gallery: **Loom Sessions**, **Loom Quotas**, and **Loom Usage Overview**.
5. Add widgets to your desktop or Notification Center. Verify live data, remaining-bar fill direction, reset times, light/dark appearance, and deep link interactions (`loom://open`, `loom://quotas`, `loom://provider/<id>`).

If the gallery does not list Loom, confirm that the installed app contains `Contents/PlugIns/LoomWidgetExtension.appex`, launch that installed copy, and rerun the package verifier against the bundle being tested. Restarting Loom and reopening the gallery can help after replacing a bundle. If structural checks pass but Loom remains absent, capture the macOS version, app path, build/signing identity, verifier output, and relevant PlugInKit/system log evidence; a structural check alone cannot diagnose registration failure.

## App Group and development fallback

The app and widget use `group.com.chaiwithcode.loom`. For a signed distribution build, both targets must be signed by the same authorized Apple Developer team with that App Group enabled for their identifiers; valid entitlements in a bundle are not by themselves proof that the team is authorized to use the group.

When the App Group container cannot be resolved, `SharedAppGroup` falls back to Application Support. Sandboxed app and extension processes can have separate Application Support locations, so this fallback must not be treated as shared widget storage. It supports development/test degradation only. A widget showing “Launch Loom” or no data may therefore indicate that the two processes do not have a usable common App Group container, even when each process can use its own fallback path.

## Troubleshooting notes

- **Verifier passes, gallery entry missing:** structural validation succeeded; macOS registration is still unverified. Check the installed copy and inspect PlugInKit/system logs on the host Mac.
- **Gallery entry exists, but widget has no data:** launch Loom and refresh it. Check that both signed targets have the authorized App Group entitlement; separate fallback locations do not exchange snapshots.
- **Widget shows stale, unavailable, or error status:** these are intentional truthful states. Open Loom to inspect provider diagnostics and refresh.
- **Deep links do not behave as expected:** confirm Loom’s `loom://` URL scheme is present in the app bundle and that the installed app is the one being tested.

Do not claim desktop verification until the installed widget has been added from the gallery and its data and interactions have been checked on macOS.
