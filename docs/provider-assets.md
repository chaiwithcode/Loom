# Provider Brand Assets & Provenance

This document records the origin, verification, and trademark ownership of third-party provider marks used in Loom to referentially identify supported AI coding assistants.

> [!IMPORTANT]
> Loom's source code is licensed under the MIT License. Third-party trademarks, product names, logos, and brand artwork remain the exclusive intellectual property of their respective owners. Loom's use of these marks is referential only, identifying local application data and processes, and does not imply sponsorship, affiliation, or endorsement.

---

## Asset Records

### 1. Codex

- **Provider**: OpenAI
- **Official Source**: Official OpenAI Codex desktop application for macOS (`com.openai.codex`, Team ID `2DC432GLL2`), version `26.928.31416` / build `12553`
- **Extracted From**: `Contents/Resources/app.asar` at `webview/assets/codex-app-ga-logo-3e5209898ca3.png`
- **Downloaded / Extracted Date**: 2026-10-17
- **Original Filename**: `codex-app-ga-logo-3e5209898ca3.png`
- **Local Filename**: `Resources/provider-codex.png`
- **Asset Format**: 104 × 104 RGBA PNG with alpha transparency
- **Transformation**: None. The original blue-to-purple gradient tile and white terminal glyph are preserved unmodified.
- **Rendering Style**: Original image rendering with subtle 3pt corner radius at 14–16pt scale.
- **SHA-256 Checksum**:
  `8e82b26c98a10e45798ce48124515720657f7735fb8d0853b3f087eaa8a6b74e`
- **Trademark Notice**: Codex and the Codex logo are trademarks of OpenAI OpCo, LLC.

---

### 2. Claude Code

- **Provider**: Anthropic
- **Official Source**: Anthropic brand guidelines and official Claude mark (`https://upload.wikimedia.org/wikipedia/commons/b/b0/Claude_AI_symbol.svg`)
- **Downloaded / Reviewed Date**: 2026-10-17
- **Original Filename**: `Claude_AI_symbol.svg`
- **Local Filename**: `Resources/provider-claude.png`
- **Asset Format**: 128 × 128 RGBA PNG with alpha transparency
- **Transformation**: Rendered as a clean high-resolution monochrome silhouette from the official 14-point sunburst vector path to support native macOS template rendering.
- **Rendering Style**: Template rendering (`.renderingMode(.template)`) adapting to light and dark appearance with native `.secondary` foreground emphasis.
- **SHA-256 Checksum**:
  `faf02d8efb01b5393706a5acc4cec50756c9469a60514b6e8d276b7785f2984c`
- **Trademark Notice**: Claude and the Claude logo are trademarks of Anthropic, PBC.

---

### 3. Antigravity

- **Provider**: Google DeepMind
- **Official Source**: Official Google Antigravity application for macOS (`/Applications/Antigravity.app/Contents/Resources/app.asar` -> `trayTemplate@2x.png`)
- **Downloaded / Reviewed Date**: 2026-10-17
- **Original Filename**: `trayTemplate@2x.png`
- **Local Filename**: `Resources/provider-antigravity.png`
- **Asset Format**: 44 × 44 RGBA PNG (template @2x)
- **Transformation**: Unmodified. The official monochrome arch template is used for native macOS menu-bar template presentation.
- **Rendering Style**: Template rendering (`.renderingMode(.template)`) adapting to light and dark appearance with native `.secondary` foreground emphasis.
- **SHA-256 Checksum**:
  `b7b65a06eb3a4e539f42f5f9ded84eb70df80d8e947346866a8b0ecaea064e13`
- **Trademark Notice**: Google, DeepMind, Antigravity, and the Antigravity mark are trademarks of Google LLC.
