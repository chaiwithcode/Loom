# Loom 2.0 — Liquid Glass & Smarter Monitoring

Version **2.0.0**, build **5**.

## Interface

- Native Liquid Glass menu and Settings surfaces on macOS 26, with system-material fallbacks and accessibility adaptations on older supported macOS versions.
- Clearer session states, subordinate provider filters, search and attention/working/recent filters.
- Needs Attention remains first; Working/Starting and Idle precede Unknown sessions. Ordering is deterministic within each group.
- Multiple bare Unknown processes without a logical session or workspace collapse into an expandable unidentified-process group. Known sessions stay separate; details and actions remain accessible.
- Consistent Settings layout, fixed reset action, aligned controls and an About section with real project links.

## Monitoring and notifications

- Separate local lifecycle observation and slower quota polling, dynamic menu-bar status and expanded discovery diagnostics. Observed quota alerts support Codex and Antigravity; Claude Code does not expose quota through its upstream local interface.
- Production quota notification state uses persistent storage, preserving threshold deduplication across restarts. A reset alert requires fresh ordered observations crossing the previous known reset boundary and substantial quota restoration into a later window.
- Finished alerts have a minimum observed Working duration: Always, 2 minutes, **5 minutes by default**, or 10 minutes. This counts time observed while Loom monitors; it does not infer work from process age. Waiting and failure alerts remain immediate.
- Unknown transitions, provider failures and disabled providers are not treated as confirmed completion evidence for notification purposes. Further disappearance/correlation reliability work is tracked in the roadmap.
- Notifications default to enabled for new/missing preferences and Restore Defaults, preserving stored opt-outs and macOS permission choices. Normal launch requests permission only when undecided and enabled.
- Test-notification controls and sending code are compiled only into Debug builds.
- Bounded local notification history, privacy-aware content, Finder/copy/focus actions and observed quota consumption rate.

## Widgets

- App icon plus Sessions, Quotas or Overview headings; gallery names and widget configurations remain compatible.
- Full-width stacked Large quota rows, semantic warning colors matching the menu, and neutral cached data.
- Aggregate quota layouts omit providers with unsupported quota reporting; explicit provider selection retains its explanation. Claude remains represented in session counts.
- Medium Overview combines session activity and tightest known quotas, while Quotas retains per-window detail. Large views allocate a bounded six-row quota budget and retain honest overflow links.

## Compatibility and release verification

- macOS 14 or later. This release targets Apple Silicon.
- Existing preferences, explicit notification opt-outs, widget kinds and provider selections are retained. Missing completion-duration preferences default to five minutes.
- Release verification results are recorded in the [2.0 checklist](RELEASE_CHECKLIST_v2.0.0.md).
- Download links open the latest published release.
