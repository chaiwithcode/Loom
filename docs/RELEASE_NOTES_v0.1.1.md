## Loom v0.1.1

Maintenance and update-infrastructure release validating end-to-end Sparkle update delivery from v0.1.0.

### What's Changed

- **Sparkle Release Notes**: Release notes are now directly embedded in `appcast.xml` so update dialogs display formatted markdown notes reliably.
- **Version History Link**: Linked full release history to official GitHub Releases via `sparkle:fullReleaseNotesLink`.
- **Feed Generation & Validation**: Corrected appcast generation to prevent broken release-note links and validated feed metadata.

### Requirements

- macOS 14.0 Sonoma or later
- Apple Silicon (arm64)
- Hardened Runtime enabled, Developer ID signed, and notarized by Apple
