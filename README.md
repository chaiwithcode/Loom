# Loom

**Local-first mission control for AI coding agents on macOS.**

Loom is an open-source macOS menu bar app that gives developers one place to see what their local AI coding agents are doing across projects.

## V0

Support three providers:
- OpenAI Codex
- Anthropic Claude Code
- Google Antigravity

For each discovered session, show:
- Provider
- Project/repository
- Session state: working, waiting, finished, failed, idle/unknown
- Started/last activity time when available
- Git branch when available

Loom is read-only in V0. It does not approve commands, inject prompts, or modify agent sessions.

## Principles

- Native macOS / SwiftUI
- Local-first; no account or backend
- No telemetry by default
- Provider adapters are isolated from the UI
- Prefer documented/local interfaces; brittle parsing must stay behind provider adapters
- Never read secrets into logs

## Build & Run

### Prerequisites
- macOS 14.0 or newer
- Swift 5.9+ / Xcode 15+ toolchain

### Build & Test
```bash
# Build the LoomCore library and Loom executable
swift build

# Run unit tests
swift test
```

### Running Loom
```bash
# Run with default mock provider data (covers all 6 normalized states)
swift run Loom

# Run UI QA empty fixture
swift run Loom --demo-empty

# Run UI QA failure fixture
swift run Loom --demo-failure
```

### Package App Bundle
To package the native macOS `.app` bundle with `LSUIElement=true`:
```bash
# Package .build/Loom.app
./scripts/build-app.sh

# Launch the app bundle
open .build/Loom.app
```

## Non-goals for V0

- Usage/quota dashboard as the core product
- Remote access
- Agent-to-agent handoff
- Prompt orchestration
- Team/cloud dashboards
- Supporting every AI tool

## Proposed V1+

- Session actions and approvals where safe/supported
- Usage/quota as contextual metadata
- Notifications
- Git/test summaries
- Cross-agent handoff
- CLI
- Remote/iPhone companion

## Development

Open the project in Xcode (`open Package.swift`) or develop using `swift build`. See `AGENTS.md` and `docs/PRODUCT.md` before changing scope.
