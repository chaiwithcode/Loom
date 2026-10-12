# Loom Release and Distribution Guide

This document describes the requirements, current build status, and official macOS signing and notarization workflow required before publishing public Loom binary releases.

## 1. System & Toolchain Requirements

- **Deployment Target**: macOS 14.0 or newer.
- **Build Toolchain**: Xcode 15+ / Swift 5.9+.
- **Architectures**: Apple Silicon (`arm64`) verified locally. Intel (`x86_64`) and universal binary packaging remain unverified and require dedicated build and runtime testing.

## 2. Current Development State & Honest Readiness

The local packaging script (`scripts/build-app.sh`) builds and packages `.build/Loom.app` for **local development only**. It does **not** produce a trusted public distribution artifact:

- **Ad-Hoc Signing**: Inspecting the packaged application (`codesign -dvv .build/Loom.app`) reveals:
  - `Signature=adhoc` (bundle ad-hoc signed with sealed `Info.plist` and resources, no longer linker-only).
  - `TeamIdentifier` is not set.
  - `flags=0x2(adhoc)` (Hardened Runtime is **disabled**).
- **Identity Inventory**: Running `security find-identity -p codesigning -v` on the primary development machine confirms that only **Apple Development** certificates are present. **No Developer ID Application identity** is installed.
- **Architecture**: The default build script compiles for the host architecture only (currently Apple Silicon `arm64`).
- **Gatekeeper**: Local ad-hoc trust is valid for execution on the local development machine without Developer ID, but if an ad-hoc signed build is downloaded from the internet, macOS Gatekeeper will block execution as an untrusted application from an unidentified developer.

**Status & Strategy**:
- **CI Development Artifacts vs. Public Releases**: Automated CI workflows build development bundles (`Loom-development-<arch>.zip`) with ad-hoc signing for build verification, automated testing, and developer inspection. These CI artifacts are **untrusted development builds**: Gatekeeper will block them on unconfigured machines because they lack Developer ID signatures and Apple notarization.
- **Candidate Release Preparation**: The release candidate pipeline packages the application bundle and validates portable integrity, but public binary publication is deferred until official Developer ID signing and Apple notarization credentials are fully in place.
- **Distribution Mode**: Loom remains source-distributed until Developer ID signing and notarization workflows are executed and validated on a clean macOS environment.

### Mac App Store Considerations & Distribution Route

Distributing via the Mac App Store is a fundamentally separate route from direct Developer ID distribution:
- **App Sandbox Requirement**: Mac App Store submission strictly requires the macOS App Sandbox.
- **Unverified Sandbox Compatibility**: Loom's current architecture relies on local agent discovery via process listing (`/bin/ps`), open file descriptor inspection (`lsof`), local provider CLI invocations, and reading external agent databases/transcripts (e.g. SQLite databases in `~/.gemini/` or session logs). These external process and data inspection capabilities have **not been verified** within the macOS App Sandbox, and standard sandbox containers typically restrict cross-process inspection and arbitrary filesystem access.
- **No Readiness Promise**: There is no promise of Mac App Store readiness at this time.
- **Recommended Path**: A direct Developer ID-signed, notarized beta release outside the App Store is recommended first. No personal signing identities, team IDs, or Apple account values should ever be committed to the repository.

## 3. Architecture Considerations

`scripts/build-app.sh` invokes `swift build -c release` for the host machine. Currently, only **`arm64`** (Apple Silicon) execution has been verified. Loom does not yet claim verified universal or Intel support.

To build a universal macOS binary using SwiftPM, the standard command pattern is:

```bash
# Unrun / unverified example (requires testing on Intel / Rosetta):
swift build -c release --arch arm64 --arch x86_64
```

Universal packaging and Intel compatibility remain unverified and require thorough build, test, and runtime verification before any claim of multi-architecture support.

## 4. Prerequisites for Public Distribution

Before creating a public release build:

1. **Apple Developer Account**: Active Apple Developer Program enrollment.
2. **Developer ID Application Certificate**: Obtain a valid **Developer ID Application** certificate and private key via Apple Developer account / Xcode Settings > Accounts, installed in the macOS Keychain.
3. **Hardened Runtime**: Mandatory for Apple notarization (`--options runtime`).
4. **Entitlements**: Start without additional entitlements and validate actual application subprocess execution and loopback communication behavior under Hardened Runtime before asserting that standard defaults are sufficient. Do not invent or add speculative entitlements without observed runtime failures.
5. **Notarization Profile**: Store Apple Notary credentials locally in the macOS Keychain using `notarytool`, omitting the `--password` flag so credentials are submitted securely via an interactive prompt rather than exposed in shell history:
   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD" \
     --apple-id "<your-apple-id>" \
     --team-id "<team-id>"
   ```
   > [!IMPORTANT]
   > Never commit signing certificates, private keys, app-specific passwords, or keychain profiles to this repository or CI workflows.

## 5. Step-by-Step Signing and Notarization Workflow

When a public release is prepared, follow this sequential procedure:

### Step 5.1: Package App Bundle
Compile the release binary and package the `.build/Loom.app` bundle with valid `Info.plist` and icon assets.

### Step 5.2: Code Sign with Hardened Runtime
Sign the application bundle directly with your Developer ID Application identity and a secure timestamp. **Do not use `--deep` for code signing**:
```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <Developer Name> (<TEAM_ID>)" \
  .build/Loom.app
```

> [!NOTE]
> Apple guidelines advise against `--deep` when signing. Because `.build/Loom.app` currently contains no nested frameworks or plugins, signing the bundle root directly is correct. If nested code (frameworks, helpers, or dylibs) is introduced later, each nested item must be signed individually from inside out before signing the outer application bundle.

### Step 5.3: Archive for Notarization Submission
Package the signed application into a zip archive using `ditto` to preserve code signing attributes and resource forks:
```bash
ditto -c -k --keepParent .build/Loom.app Loom-submission.zip
```

### Step 5.4: Submit to Apple Notary Service
Submit the archive to the Apple Notary Service and wait for processing:
```bash
xcrun notarytool submit Loom-submission.zip \
  --keychain-profile "AC_PASSWORD" \
  --wait
```

Review the submission outcome. When processing completes, examine the acceptance log:
```bash
xcrun notarytool log <submission-id> --keychain-profile "AC_PASSWORD"
```

### Step 5.5: Staple the Notarization Ticket to the App
> [!IMPORTANT]
> The notarization ticket must be stapled directly to the `.app` bundle, **not** to the zip archive:
```bash
xcrun stapler staple .build/Loom.app
```

### Step 5.6: Verify Strict Code Signing, Stapling, and Gatekeeper
Validate the stapled app bundle using strict verification commands:

```bash
# 1. Strict signature verification with deep traversal
codesign --verify --deep --strict --verbose=2 .build/Loom.app

# 2. Gatekeeper policy assessment (verifies policy acceptance)
spctl --assess -vv --type execute .build/Loom.app

# 3. Stapler ticket validation
xcrun stapler validate .build/Loom.app
```

Each verification tool reports distinct diagnostics:
- `codesign` verifies the seal is valid on disk and satisfies its Designated Requirement (`valid on disk`, `satisfies its Designated Requirement`).
- `spctl` evaluates Gatekeeper policy and must report `accepted` with `source=Notarized Developer ID`.
- `xcrun stapler validate` confirms the ticket is properly stapled (`The validate action worked!`).

### Step 5.7: Package and Code Sign Distributable DMG
Package the stapled `.app` bundle into a polished, read-only DMG with an `/Applications` shortcut and native Finder layout using `scripts/package-dmg.sh`:
```bash
SIGNING_IDENTITY="Developer ID Application: <Developer Name> (<TEAM_ID>)" \
  bash scripts/package-dmg.sh .build/Loom.app
```

The packager configures a native Finder installation surface:
- **Geometry**: 640×420 pt content bounds (outer bounds `{200, 120, 840, 572}` accommodating 32 pt macOS titlebar), 96 pt icons centered at `{180, 235}` (`Loom.app`) and `{460, 235}` (`/Applications`).
- **Background Artwork**: Minimal warm light-neutral canvas generated via native AppKit/CoreGraphics (`scripts/dmg/generate-background.swift`) with 1x/2x PNGs and multi-representation TIFF (`background.tiff`), featuring native system typography ("Loom" header at y62, "Monitor your local AI coding agents" tagline at y92, subtle directional arrow at y235, and "Drag Loom to Applications" at y340 clear of icon labels). Regenerate assets whenever geometry or renderer text is modified via `swift scripts/dmg/generate-background.swift scripts/dmg`.
- **Safety**: Preserves the sealed `.app` bundle via `ditto` without modifying bundle contents or deleting internal `.DS_Store` files. Calculates staging disk image size dynamically from the payload plus slack. Configures native Finder layout metadata or stages verified template `.DS_Store`, verifies staged background asset SHA-256 hashes against source, runs `scripts/dmg/verify-ds-store.swift` for on-disk `icvp` bplist metadata sanity checking (while relying on active reopened Finder assertions and mounted visual inspection for definitive layout proof), pre-computes checksums, backs up existing distribution artifacts (`.dmg`, `.dmg.sha256`, `SHA256SUMS.txt`) to `dist/backups/`, and atomically replaces the disk image file alongside separately staged checksum files with automatic recovery on failure.

This creates `dist/Loom-0.1.0.dmg`, signs the disk image, and generates `SHA256SUMS.txt`.

### Step 5.8: Notarize and Staple the DMG
Submit the DMG to Apple Notary Service so Gatekeeper assesses the disk image immediately on mount without requiring network lookup:
```bash
xcrun notarytool submit dist/Loom-0.1.0.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait

xcrun stapler staple dist/Loom-0.1.0.dmg
xcrun stapler validate dist/Loom-0.1.0.dmg
```

### Step 5.9: Gatekeeper & Clean Mac Download Verification
Verify Gatekeeper policy acceptance on both the disk image and installed application:
```bash
# Gatekeeper disk image check:
spctl --assess -vv --type open --context context:primary-signature dist/Loom-0.1.0.dmg

# Mount and inspect app under Gatekeeper:
hdiutil attach dist/Loom-0.1.0.dmg -mountpoint /Volumes/LoomStaging
spctl --assess -vv --type execute /Volumes/LoomStaging/Loom.app
hdiutil detach /Volumes/LoomStaging
```

Before distribution, test the artifact on a separate clean Mac that has never built the project or installed development certificates. Download the DMG through a real web browser to ensure genuine quarantine extended attributes (`com.apple.quarantine`) and Gatekeeper evaluation occur. Verify that Loom drags to Applications and launches cleanly without security prompts or developer trust blocks.

> [!CAUTION]
> Never provide security bypass instructions (such as `xattr -cr` or Gatekeeper overrides) to end users. If Gatekeeper blocks the app, resolve the code signing or notarization issue.

### Step 5.10: Checksum Verification
Confirm SHA-256 checksums in `dist/SHA256SUMS.txt`:
```bash
(cd dist && shasum -c SHA256SUMS.txt)
```

## 6. Manual Publication Policy

- **No Automated Publishing**: Release tagging and binary asset publication are intentionally manual actions executed by the repository owner after local verification.
- **Release Verification**: Do not tag a release in Git or attach binary archives to GitHub Releases until Developer ID signing, notarization, stapling, and clean-Mac testing are fully confirmed.

## 7. Official Apple Documentation References

- [Notarizing macOS Software Before Distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the Notarization Workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Developer ID Overview](https://developer.apple.com/developer-id/)
