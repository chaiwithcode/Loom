# Loom icon

Three agents. One Loom.

The approved Dock artwork follows the user-selected sculpted reference:
three upright amber, violet and cyan ribbons, a taller centre strand, clear
diagonal crossings and one substantial circular base viewed in perspective.
The dark charcoal rounded square and controlled highlights retain material
depth. The monochrome menu-bar glyph simplifies the same silhouette with a
transparent underpass and a substantial oval front band. The thicker ribbons
retain three distinct entries and the taller centre strand at menu-bar size.

`Resources/LoomIconMaster.png` is the 1254 px high-resolution transparent master.
It was refined from the user-provided October 4 brand presentation with the
built-in image generation tool. The exact brief is preserved in
`docs/ICON_PROMPT.md`. It is raster artwork; `docs/loom-app-icon.svg` is a
wrapper referencing that master, not an independent vector reconstruction.

Run `./scripts/export-icons.sh` to regenerate `loom-icon.png` and
`Resources/Loom.icns` using macOS `sips` and `iconutil`. It preserves the
previous exported assets in a temporary backup directory before replacing
them. Both Xcode and the SwiftPM bundle packager consume the same ICNS.

`docs/loom-icon.svg` and `Loom/UI/MenuBar/LoomIcon.swift` contain the matching
editable monochrome geometry. Keep their paths and transparent underpass
synchronized. The template draws at 18 pt for the menu bar and at the requested
point size for other monochrome consumers. App headers and About use the full-colour
application artwork, matching the Dock; they do not use the menu-bar template.

`docs/icon-preview.png` compares the unchanged Dock artwork with the refined
monochrome glyph at actual 18, 36 and 48 pixel resolutions on light and dark surfaces.
The enlarged 96 pixel mark makes its ribbon crossings and transparent gaps inspectable. See [ICON_PROMPT.md](ICON_PROMPT.md) for the icon design prompt.
