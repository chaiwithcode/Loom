# Interface polish and local storage

Loom displays subtle app version metadata in the menu bar footer alongside the update status (`Updated now • v1.0`), and detailed version information in About. The menu bar glyph and popover header remain uncluttered without redundant version toggles. The legacy persisted preference is retained for configuration compatibility.

Usage refresh failures show a short explanation and recovery guidance, with technical details behind disclosure. Cooperative cancellation preserves previous sessions and marks previous usage as saved data; it does not fabricate failed or finished sessions. Missing quota is never drawn as zero remaining.

On macOS 26 and later, header controls use native glass button styling. Older supported systems use borderless controls and semantic material. Reduce Transparency uses an opaque system background. Content cards do not stack glass effects.

## Storage

Settings → Storage measures allocated file bytes in explicitly listed provider data/cache roots. This is not the full size of installed applications. App binaries, projects and unlisted locations are excluded. Codex and Claude roots respect absolute CODEX_HOME and CLAUDE_CONFIG_DIR overrides. Antigravity only includes its own Gemini subfolders, not all Gemini data.

Scanning runs off the main actor when the tab opens or Rescan is selected. Each root is limited to five seconds and 100,000 visited entries, with cooperative cancellation on dismissal. The scanner never reads file contents, follows symbolic links, deletes files, or sends results elsewhere. Hard links are counted once per provider scan. Missing, inaccessible, linked and partially scanned roots are distinguished; partial totals are lower bounds. Finder reveal is available for measured roots. Hide project paths also hides the storage path text.

## Widgets

- **Loom Sessions**, Small and Medium: local activity and tracked counts. “Active” means working or starting; tracked counts can also include idle/recent sessions. Provider links in Medium retain the provider Settings context.
- **Loom Quotas**, Small, Medium, Large: remaining quota and reset times for local AI providers. By default tracks all enabled providers, or can be configured to focus on a specific provider (Codex, Claude Code, or Antigravity) via Edit Widget. Claude explicitly reports unsupported quota monitoring.
- **Loom Usage Overview**, Medium and Large: displays quota progress across all supported providers simultaneously without requiring provider switching. Medium offers a compact 3-column overview with remaining progress bars, reset countdowns, and `+N more` overflow. Large displays standard quota windows and additional granular model limits (e.g. GPT-4o, o1, Gemini 1.5 Pro), gracefully capping at visible capacity with `+N more limits` linking directly to Loom without scrolling.

All three widgets use the same monochrome woven Loom mark as the menu bar. Bars show remaining quota. Saved values use the original quota observation date, independently of when the overall snapshot is written. Snapshot fields are additive and old snapshots remain decodable; reopening Loom populates the new quota windows. WidgetKit owns the background and system appearance.
