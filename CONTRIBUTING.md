# Contributing to Loom

Useful contributions include reproducible discovery bugs, parser fixtures, clearer unknown/error states, accessibility improvements, and provider adapters built around local interfaces.

## Start small

Read the [product brief](docs/PRODUCT.md) and [architecture](docs/ARCHITECTURE.md). Describe the problem before a substantial change. Keep provider formats inside their adapter; UI and core consume normalized models. Discuss dependencies or expansion into remote control/cloud services first.

Use macOS 14+ and Swift 5.9+ / Xcode 15+. Build with `swift build`, or run the Loom scheme in `Loom.xcodeproj`. Package a local app with `bash scripts/build-app.sh`.

## Test behavior

The portable command used by CI is:

```bash
swift test --disable-sandbox --skip 'testRealAntigravityDiscoverySmokeTest|testDefaultCodexAppServerTransportSigtermResistantCancellation'
```

These explicit exclusions are known limitations: the Antigravity smoke test requires a local database and can fail with SQLite error 14; the subprocess cancellation test has a known hang. `swift test` still includes both. Some live usage checks need `ENABLE_LIVE_SMOKE_TESTS=1`; never describe a skipped check as a pass. Remote CI execution has not yet been verified.

For menu changes, run `bash scripts/verify-menu-sizing.sh`, then open the packaged app and inspect narrow layouts, long lists, empty/error states, tab switches and repeated refresh. Report what you actually ran and any gaps.

Parser changes should include synthetic fixtures proving normalization and malformed/missing data handling. Never commit real transcripts, account identifiers, credentials, databases, or full configuration files. Use generic paths and scrub screenshots. Preserve errors rather than suppressing them to make tests pass.

## Submit a reviewable change

Explain the concrete problem, resulting behavior and validation in the pull request. Keep changes focused and disclose known failures. Include UI screenshots when useful, with private project information removed.

Contributions are under Loom's [MIT License](LICENSE). Retain applicable notices and identify external code/assets with their licenses. No contributor agreement is required by this repository.

## Source-file headers

All first-party Swift source and test files (`.swift`) in `Loom/` and `Tests/` must include the canonical license header:

```swift
//
//  <Filename>.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//
```

- Replace `<Filename>.swift` with the dynamic filename.
- `Package.swift` must begin with the `// swift-tools-version: 5.9` directive and does not take a header above it.
- Scripts in `scripts/` retain their shebang lines (`#!/usr/bin/env ...`).
- Third-party or vendored files retain their original headers.

