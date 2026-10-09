# Architecture

## Layers

**Core** defines provider-neutral session/usage models, normalization, settings and refresh coordination. **Providers** own local detection, discovery, transport and provider parsing. **UI** consumes normalized state through SwiftUI menu, settings and About views.

SwiftPM exposes `LoomCore` from `Loom/Core` and `Loom/Providers`, and the `Loom` executable from `Loom/App` and `Loom/UI`. Xcode provides the shared Loom scheme. There are no third-party package dependencies.

## Data flow

```text
Local metadata / status interface
  -> provider discovery and parser
  -> normalized AgentSession / usage snapshot
  -> SessionStore
  -> SwiftUI Sessions / Usage
```

Do not leak raw provider JSON, logs or configuration into core/UI. Upstream formats change; parser fixtures and graceful failure belong at the adapter boundary. Missing evidence produces unknown metadata or state rather than a guess.

## Registration and refresh

Normal launch registers Codex and Antigravity. Explicit demo flags select mock, empty or failure fixtures; Claude's presence in fixtures is not a live implementation.

The store coordinates manual and periodic refresh (60 seconds by default, configurable). Cancellation and overlap handling prevent competing refreshes. Provider failures must not erase other providers' results. Retained successful usage snapshots must be identified as stale after errors.

## Local interfaces and privacy

Codex session discovery inspects running processes and resolves Git/project metadata; it reports Unknown state rather than inferring activity from process existence. Antigravity session discovery reads provider-local metadata. Codex usage uses a local app-server subprocess over standard input/output. Antigravity usage discovers a language-server port and queries it over loopback HTTPS with an ephemeral token.

Antigravity transport applies a TLS trust exception only to the discovered loopback host and port, and rejects redirects. This is not normal certificate-chain validation or proof that every loopback process is trustworthy. Provider credentials are not persisted by Loom; diagnostics must not expose them. See [SECURITY](../SECURITY.md).

Prefer documented local interfaces, then stable CLI output or metadata, with narrow tested fallbacks. Adapter failures must not block the app. Loom does not inject prompts or modify sessions.

## Presentation and verification

`MenuBarExtra` presents the primary window. Sessions/Usage retain independent state. Content measurement bounds the menu to available screen height; overflow scrolls rather than clipping. The full-color application icon is separate from the template monochrome glyph.

Parser/store tests cover normalized behavior; the native menu probe checks sizing and interactions. The [CI workflow](../.github/workflows/ci.yml) uses explicit portable test selection. Full-suite discovery and subprocess cancellation limitations are documented in [CONTRIBUTING](../CONTRIBUTING.md); excluded or unrun checks are not a full pass.
