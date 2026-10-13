# Loom Release and Distribution Guide

This document describes the production-grade direct distribution pipeline for **Loom**:

```text
macOS Keychain
├── Developer ID certificate (K9UNF256S9)
├── Sparkle EdDSA private key (ed25519)
├── Apple notarization profile (AC_PASSWORD)
└── GitHub CLI credentials (gh)
        │
        ▼
scripts/release.sh
        │
        ├── --check     (Non-destructive prerequisite preflight audit)
        │
        ├── --prepare   (Build .build/Loom.app -> Sign -> Notarize -> Staple ->
        │                Gatekeeper verify -> Package canonical ZIP ->
        │                Compute SHA-256 -> Generate Sparkle appcast.xml ->
        │                Stage Homebrew cask -> Pre-publish summary)
        │
        └── --publish   (Confirm -> Push Git tag vX.Y.Z -> Create GitHub Release ->
                         Verify uploaded checksum -> Synchronize Homebrew tap ->
                         Deploy Sparkle update feed to GitHub Pages)
```

---

## 1. Release Architecture & Immutability Contract

Loom enforces a strict release invariant:

> **Exactly one canonical signed and notarized ZIP (`Loom-X.Y.Z-macOS.zip`) is created per version.**
> That exact archive is shared across **GitHub Releases**, **Sparkle 2 appcasts**, and **Homebrew Cask**.
> Re-building or mutating a published release archive is strictly prohibited, as it invalidates SHA-256 checksums and Sparkle EdDSA signatures.

### Versioning Contract

| Component | Format | Example |
| :--- | :--- | :--- |
| **Git Tag** | `vX.Y.Z` | `v0.1.0` |
| **Marketing Version** (`CFBundleShortVersionString`) | `X.Y.Z` | `0.1.0` |
| **Bundle Version** (`CFBundleVersion`) | Monotonically increasing integer | `1`, `2`, `3` |
| **Release Artifact** | `Loom-X.Y.Z-macOS.zip` | `Loom-0.1.0-macOS.zip` |
| **Homebrew Cask Token** | `chaiwithcode-loom` | `Casks/chaiwithcode-loom.rb` |
| **Sparkle Feed URL** | Stable HTTPS GitHub Pages | `https://chaiwithcode.github.io/Loom/appcast.xml` |

---

## 2. Security Model: Keychain-Backed Local Release

To ensure maximum security and simplicity, **sensitive signing and notarization credentials never live in GitHub repository secrets**. Production builds, signing, and notarization are performed locally on the maintainer's trusted Mac.

### Credentials Summary

| Credential | Local Storage | Tool Usage |
| :--- | :--- | :--- |
| **Developer ID Application** | macOS login Keychain | `codesign --sign "Developer ID Application: ..."` (Auto-detected) |
| **Apple Notary Credentials** | Keychain profile `AC_PASSWORD` | `xcrun notarytool submit --keychain-profile "$NOTARY_PROFILE"` |
| **Sparkle EdDSA Private Key** | macOS Keychain account `ed25519` | `generate_appcast` (Auto-extracted from Keychain) |
| **GitHub Authentication** | GitHub CLI (`gh`) | `gh release create`, `gh repo ...` |

### Keychain Verification on Release Machine

1. **Apple Developer ID Certificate**:
   Ensure your Developer ID Application certificate and private key are installed in Keychain Access (auto-detected by release scripts).

2. **Apple Notary Profile**:
   The release pipeline uses the existing Keychain profile `AC_PASSWORD` by default (configurable via `NOTARY_PROFILE`).
   Validate it anytime with:
   ```bash
   xcrun notarytool history --keychain-profile "$NOTARY_PROFILE"
   ```

3. **Authenticate GitHub CLI**:
   Ensure `gh` is authenticated with repo write permissions:
   ```bash
   gh auth status
   ```

4. **Verify Sparkle Key**:
   The private EdDSA key is managed by Sparkle CLI tools in Keychain (service `https://sparkle-project.org`, account `ed25519`). Verify with:
   ```bash
   ./scripts/release.sh --check
   ```

---

## 3. Sparkle 2 Integration & Security

Loom integrates official **Sparkle 2.10.0** via Swift Package Manager.

### Isolation & Lifecycle
- Sparkle APIs are isolated under `Loom/Update/` (`UpdateController.swift`, `CheckForUpdatesView.swift`).
- A single long-lived `@MainActor` singleton (`UpdateController.shared`) manages the `SPUStandardUpdaterController` lifecycle across the full app run.
- Update checks respect `updater.canCheckForUpdates` to prevent invalid states.

### EdDSA Keypair Management
Sparkle archive validation uses the **EdDSA (Ed25519)** algorithm.
- **Public Key**: Embedded in `Resources/Info.plist` and `scripts/build-app.sh`:
  ```xml
  <key>SUFeedURL</key>
  <string>https://chaiwithcode.github.io/Loom/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>jFxPCf9cSvpmuEc6U4EdjWlYwMzMVlTd6M8wPlvLZsE=</string>
  ```
- **Private Key**: Kept exclusively in macOS Keychain. Never committed to Git or CI secrets.

---

## 4. Local Release Execution Workflow

The canonical entry point for all releases is `scripts/release.sh`.

### Step 1: Preflight Audit
Verify your system toolchain, Keychain credentials, and Git status:
```bash
./scripts/release.sh --check
```

### Step 2: Prepare Release
Compiles release binary, signs inside-out with Developer ID and Hardened Runtime, submits for Apple notarization, staples the ticket, packages the canonical ZIP, generates SHA-256 checksums, signs `appcast.xml`, and stages the Homebrew cask:
```bash
./scripts/release.sh 0.2.0 --prepare
```
*(For local testing without Apple notarization credentials, append `--skip-notarization`)*.

### Step 3: Publish Release
Reviews artifact hashes, prompts for confirmation, creates & pushes git tag `v0.2.0`, uploads assets to GitHub Releases, verifies remote checksum, synchronizes `chaiwithcode/homebrew-tap`, and deploys the Sparkle feed to GitHub Pages:
```bash
./scripts/release.sh 0.2.0 --publish
```

---

## 5. GitHub Workflows Architecture

Loom uses a clean, zero-secret CI/CD model:

1. **`.github/workflows/ci.yml`**:
   - Runs tests and builds on pull requests and pushes to `main`.
   - Never touches release credentials or distribution pipelines.

2. **`.github/workflows/pages.yml`**:
   - Deploys `appcast.xml` to GitHub Pages (`https://chaiwithcode.github.io/Loom/appcast.xml`).
   - Automatically triggered when a GitHub Release is published (`release: [published]`).
   - Uses standard `GITHUB_TOKEN` (`permissions: pages: write`). **Zero secrets required**.

---

## 6. Homebrew Tap Maintenance

### Cask Specification
The official cask token is:
```text
chaiwithcode-loom
```

### Installation Command
```bash
brew install --cask chaiwithcode/tap/chaiwithcode-loom
```

### Automated Updates
The release orchestrator automatically updates `chaiwithcode/homebrew-tap` with the exact version and canonical SHA-256 during the `--publish` step:
```bash
./scripts/release.sh <version> --publish
```
Or independently via:
```bash
./scripts/update-homebrew-tap.sh <version> [sha256] --sync
```

---

## 7. Verification Tooling & Regression Checks

Loom includes automated scripts to test each phase of the distribution pipeline:

| Script | Purpose |
| :--- | :--- |
| `scripts/release.sh --check` | Preflight audit of Keychain, tools, versions, and git hygiene. |
| `scripts/fetch-sparkle-tools.sh` | Downloads and verifies pinned Sparkle CLI tools (`generate_appcast`, `generate_keys`). |
| `scripts/generate-appcast.sh` | Generates and cryptographically validates `appcast.xml` item attributes. |
| `scripts/test-sparkle-upgrade.sh` | **End-to-end upgrade test**: spins up local HTTP server, tests update discovery, verifies EdDSA signature, downloads and extracts payload, and asserts tampered payload rejection. |
| `scripts/update-homebrew-tap.sh` | Generates verified Homebrew Cask ruby file and handles tap synchronization. |
| `scripts/verify-settings.sh` | Standalone probe verifying Settings UI, General/About tabs, and Sparkle update controls. |
| `scripts/verify-menu-sizing.sh` | Standalone probe verifying native menu sizing and layout constraints. |
| `swift test` | Full test suite across providers, models, UI state, and transport isolation. |
