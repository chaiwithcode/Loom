# Contributing to Loom

Useful contributions include reproducible discovery bugs, parser fixtures, clearer unknown/error states, accessibility improvements, and provider adapters built around local interfaces.

## Start small

Read the [product brief](docs/PRODUCT.md) and [architecture](docs/ARCHITECTURE.md). Describe the problem before a substantial change. Keep provider formats inside their adapter; UI and core consume normalized models. Discuss dependencies or expansion into remote control/cloud services first.

Use macOS 14+ and Swift 5.9+ / Xcode 15+. Build with `swift build`, or run the Loom scheme in `Loom.xcodeproj`. Package a local app with `bash scripts/build-app.sh`.

## Test behavior

The portable command used by CI is:

```bash
swift test --disable-sandbox --skip 'testRealAntigravityDiscoverySmokeTest'
```

The live Antigravity discovery smoke test (`testRealAntigravityDiscoverySmokeTest`) requires a local Antigravity installation and SQLite database, and is excluded in environments lacking local agent state. The SIGTERM-resistant cancellation regression test (`testDefaultCodexAppServerTransportSigtermResistantCancellation`) is verified passing and is included in portable test runs. Running `swift test` locally without skips executes the full test suite. Some live usage checks additionally require `ENABLE_LIVE_SMOKE_TESTS=1`; never describe a skipped check as a pass. Remote CI execution has not yet been verified.

For menu changes, run `bash scripts/verify-menu-sizing.sh`, then open the packaged app and inspect narrow layouts, long lists, empty/error states, tab switches and repeated refresh. Report what you actually ran and any gaps.

Parser changes should include synthetic fixtures proving normalization and malformed/missing data handling. Never commit real transcripts, account identifiers, credentials, databases, or full configuration files. Use generic paths and scrub screenshots. Preserve errors rather than suppressing them to make tests pass.

## Branching and release workflow

- **Main branch**: `main` is the stable release branch. There is no `develop` branch.
- **Short-lived branches**: Work in focused, short-lived branches (`feat/*`, `fix/*`, `docs/*`).
- **Pull requests**: Propose changes via pull requests targeting `main`. A pull request requires passing CI checks and a read-only review before merge.
- **Release tags**: Release tags are created only after code signing, notarization, and clean-Mac download verification checks have succeeded.

## Submit a reviewable change

Explain the concrete problem, resulting behavior and validation in the pull request. Keep changes focused and disclose known failures. Include UI screenshots when useful, with private project information removed.

Contributions are under Loom's [MIT License](LICENSE). Retain applicable notices and identify external code/assets with their licenses. No contributor agreement is required by this repository.
