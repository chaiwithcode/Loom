# Changelog

All notable changes to Loom are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-10-13

### Fixed
- **Sparkle Update Delivery**: Embed release notes directly in `appcast.xml` via `--embed-release-notes` and link version history directly to GitHub Releases via `sparkle:fullReleaseNotesLink`.
- **Release Automation**: Guard against broken Pages markdown release-notes links in generated feeds and make release publishing idempotent for canonical assets.

## [0.1.0] - 2026-10-12

### Added
- **Native macOS Menu Bar App**: Built with Swift 5.9+ and SwiftUI for macOS 14+, utilizing `MenuBarExtra` for lightweight status monitoring.
- **Multi-Provider Session Discovery**: Local, read-only discovery of active coding sessions across OpenAI Codex, Anthropic Claude Code, and Google Antigravity.
- **Process Tree Correlation**: Groups parent processes, language servers, subagents, and child workers into a single logical session per repository task.
- **Normalized Lifecycle States**: Truthful state categorization (`starting`, `working`, `waiting`, `finished`, `failed`, `idle`, `unknown`) without synthetic state guessing.
- **Usage & Quotas Dashboard**: Polling snapshot tracking of remaining quota, reset timestamps, and model limits across supported providers.
- **Fixed Provider Navigation**: Fixed provider selector below the Sessions view showing live counts and guaranteeing direct reachability even with long session lists.
- **Settings Management**: Persisted preferences for enabling/disabling provider monitoring, default provider selection, session retention (active only vs keep recent, configurable expiration: Never, 1h, 24h, 7d; default Never), Dock visibility, and background refresh intervals.
- **Conservative Session Retention**: Sessions in uncertain or unknown states are conservatively retained and never filtered out by retention cutoffs solely due to unconfirmed state.
- **Privacy Protections**: "Hide project paths" toggle masks filesystem paths and evidence in the menu UI and inspector while preserving the "Reveal in Finder" disk action.
- **Local-First Architecture**: Strictly local operation with zero cloud backend, user accounts, analytics SDKs, or third-party package dependencies.
- **Atomic Local Packaging & App-Bundle Signing**: Replaces executables atomically using temporary siblings to preserve active running inodes and ad-hoc signs the full `.app` bundle, sealing `Info.plist` and resource assets for local development launch.
- **Provider Cancellation & Process Management**: Cooperative cancellation and robust subprocess lifecycle repair in `Foundation.waitUntilExit` using prelaunch `terminationHandler`, single Foundation reap ownership, bounded SIGTERM to SIGKILL escalation, and truthful error propagation during provider disablement and app lifecycle changes.
- **Verification Suite**: Comprehensive deterministic unit and integration test suite, SIGTERM-resistant cancellation regression tests, and native AppKit menu sizing probes.
