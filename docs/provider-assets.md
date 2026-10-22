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

- **Asset source**: [LobeHub Lobe Icons colour SVG](https://raw.githubusercontent.com/lobehub/lobe-icons/21b2144f4ebe87ead9b7c0e10067759ae261b03e/packages/static-svg/icons/claude-color.svg), a third-party icon collection; not an official brand asset distribution.
- **Revision**: `21b2144f4ebe87ead9b7c0e10067759ae261b03e`
- **Retrieved**: 2026-10-21
- **Source file**: `Resources/ProviderSources/claude.svg` (original SVG bytes retained)
- **App resource**: `Resources/provider-claude.pdf`
- **Transformation**: SVG exported to a transparent vector PDF with `rsvg-convert`; no recolouring or background tile added.
- **Rendering**: Original colours, not macOS template tinting. PDF is decoded by AppKit; SVG needs no runtime library.
- **SVG SHA-256**: `a3101f3047a119aa11825ad9369510f0c472428c8c52d420e31bc62db44a8364`
- **PDF SHA-256**: `4b07b198a53cfcd711b304a6129920fe7cd3028abee8eaa7211517ae1447bd9e`
- **Collection license**: MIT; notice preserved in `Resources/ProviderSources/LICENSE.lobehub`.
- **Trademark ownership**: Claude Code and its logo remain trademarks of Anthropic, PBC. Use identifies a supported provider and implies no affiliation or endorsement.

---

### 3. Antigravity

- **Asset source**: [LobeHub Lobe Icons colour SVG](https://raw.githubusercontent.com/lobehub/lobe-icons/21b2144f4ebe87ead9b7c0e10067759ae261b03e/packages/static-svg/icons/antigravity-color.svg), a third-party icon collection; not an official brand asset distribution.
- **Revision**: `21b2144f4ebe87ead9b7c0e10067759ae261b03e`
- **Retrieved**: 2026-10-21
- **Source file**: `Resources/ProviderSources/antigravity.svg` (original SVG bytes retained)
- **App resource**: `Resources/provider-antigravity.pdf`
- **Transformation**: SVG exported to a transparent vector PDF with `rsvg-convert`; no recolouring or background tile added.
- **Rendering**: Original colours, not macOS template tinting. PDF is decoded by AppKit; SVG needs no runtime library.
- **SVG SHA-256**: `652128cf55a28bb958563ee372d0bd00208d9e6fd446f523f77aafd811eef8ca`
- **PDF SHA-256**: `454e01c49d9f79b2c01b81ed5db719da452bff1c1505b349a54744f63715a8a4`
- **Collection license**: MIT; notice preserved in `Resources/ProviderSources/LICENSE.lobehub`.
- **Trademark ownership**: Antigravity and its logo remain trademarks of Google LLC. Use identifies a supported provider and implies no affiliation or endorsement.
