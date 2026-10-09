# Loom — Product Brief

## Problem and thesis

Developers run independent AI coding agents across repositories. Sessions and quota information are fragmented across terminals and apps. Loom is a small native macOS surface that shows what is running, where it is working, what needs attention, and whether usage limits are approaching.

The core object is an agent session and its relationship to a project. Usage complements this context without replacing session monitoring.

## Current experience

- **Sessions:** provider availability and project sessions with normalized states. Expanded cards show available metadata and Finder reveal when a project path exists.
- **Usage:** quota remaining, reset times and additional model limits. Stale, unavailable and failed responses stay visible.

A shared header provides refresh and settings. Content determines menu height up to available screen space; longer content scrolls. Each text tab retains independent scroll and disclosure state.

## Integration status

Normal launch uses real Codex and Antigravity discovery and usage adapters. Codex discovers running processes and Git metadata, reporting Unknown state because process existence does not prove working/waiting status. Antigravity reads local session metadata. Claude Code exists in identities and demo fixtures; live support is planned, not shipped. Demo modes require explicit launch flags and are visibly labeled. Availability does not prove an installed CLI, authentication, an active session or a usable quota response.

## V0 acceptance criteria

- Native SwiftUI macOS 14+ menu bar presentation.
- Independent local discovery for implemented providers.
- Truthful project/state metadata, with unknown states when evidence is missing.
- Manual refresh and configurable periodic refresh without relaunching.
- Isolated provider failures and visibly stale retained usage snapshots.
- Read-only monitoring with no Loom backend, sign-in or telemetry pipeline.
- No persisted credentials or displayed secrets.

## Priorities

Reliable discovery and normalization come first. Next: a real Claude Code adapter, upstream compatibility, diagnostics and accessibility. Safe actions, notifications and richer repository context need separate product decisions. Remote control, cloud sync and orchestration are outside the current scope.

## Brand

Three vertical agent strands weave into one circular base. Preserve this approved silhouette, refined material colors and native macOS balance. Use the full-color icon for app identity and a simplified monochrome glyph for the menu bar. No vendor-specific logos belong in the core mark.
