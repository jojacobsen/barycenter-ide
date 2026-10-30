# Barycenter — Icon & Glyph Kit

Source assets for the Barycenter app icon and in-app glyphs. The motif is an
agent grid: a dark lattice of blue session tiles with a purple handler tile and
a central `>_` terminal pane.

## Contents

| Path | Purpose |
|------|---------|
| `svg/` | Master vector sources (`AppIcon-Default`, `-Light`, `-Tinted`, `-Small`). |
| `AppIcon.iconset/` | PNG renditions (16–512 @1x/@2x) for `iconutil`. |
| `AppIcon.appiconset/` | Xcode asset-catalog variant of the same renditions. |
| `AppIcon.icns` | Compiled icon shipped in the `.app` bundle. |
| `Appearances/` | macOS appearance variants (Default / Light / Tinted), 1024 px. |
| `InApp/` | In-app glyphs and menu-bar templates (idle + active, light/dark UI). |

## Rebuilding `AppIcon.icns`

```sh
iconutil -c icns AppIcon.iconset -o AppIcon.icns
cp AppIcon.icns ../AppIcon.icns   # used by build_app.sh / release.sh
```
