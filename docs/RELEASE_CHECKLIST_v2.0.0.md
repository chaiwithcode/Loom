# Loom 2.0 release checklist

Release coordinates: **2.0.0**, build **5**, Apple Silicon (`arm64`), branch `2.0`, tag `v2.0.0`. Minimum supported macOS version is14. The final release verification record and checksums accompany the published assets; this checklist defines the required gates rather than asserting that unrun steps passed.

## Source and app checks

- Preserve staged and unstaged work before branch creation; review and commit the2.0 changes.
- Run `swift test --disable-sandbox --skip testRealAntigravityDiscoverySmokeTest`. The excluded smoke test depends on a local Antigravity installation and is not a portable release gate; no Antigravity agent is invoked.
- Run `swift test --disable-sandbox --filter 'LoomRegressionTests.*'`.
- Run `bash scripts/verify-notifications.sh`, including demo/production notification-state isolation.
- Run `bash scripts/verify-menu-sizing.sh` and `bash scripts/verify-settings.sh` against production views and supported640×460minimum Settings size.
- Run `bash scripts/verify-release-pipeline.sh` and `bash scripts/verify-pages-staging.sh`, including immutable asset refusal and missing/empty video rejection.
- Verify the final native trailer, poster, demo-data disclosure and music credits; keep quota support accurate for each provider.

## Distribution gates

- Run `bash scripts/release.sh --check`; resolve failures before preparation.
- Build and prepare from the clean release commit with `bash scripts/release.sh 2.0.0 --prepare`. Do not use `--skip-notarization` for public distribution.
- Verify app and widget version/build, embedded extension, App Group entitlements, arm64 architecture and Developer ID signatures with hardened runtime.
- Retain Apple's accepted notarization results; validate stapled app/DMG tickets and Gatekeeper assessment.
- Mount the final DMG and inspect the actual Finder window: approved background,640×420content canvas,96point Loom and Applications icons at their approved positions, `/Applications`symlink, and auto-open behavior. Metadata checks alone do not prove the visible layout.
- Compute final checksums only after signing/stapling; verify both the canonical ZIP and DMG. Do not mutate a published archive.
- Run `bash scripts/verify-widget-package.sh .build/Loom.app` and `bash scripts/test-sparkle-upgrade.sh`.

## GitHub and update channels

- Verify `origin` is exactly `chaiwithcode/Loom` and ensure the remote release tag resolves to the artifact source commit (peel annotated tags).
- Stage a draft release with `--verify-tag`; never replace assets with `--clobber`.
- Attach ZIP, DMG, checksums, signed appcast, verification record and current `Loom-Demo-16x9.mp4` / `Loom-Demo-9x16.mp4` media.
- Download the exact draft DMG and checksum files, compare against the local manifest and run `shasum -a256 -c`; also verify the canonical ZIP.
- Publish only after all readiness gates pass; validate the public asset URLs and the Pages/Sparkle deployment.
- Synchronize the Homebrew tap only through explicit `--sync`, using the canonical ZIP hash. Preparation must not push the tap.

## Recovery

Preserve previous app/artifacts and the original worktree snapshot. Do not reset user changes, force-push branches/tags, overwrite remote assets or delete a conflicting release. Stop at the failing gate and report its evidence.
