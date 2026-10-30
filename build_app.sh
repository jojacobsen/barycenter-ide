#!/bin/bash
# Baut Barycenter als echtes macOS .app-Bundle (Release) und signiert es ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"

APP="Barycenter.app"
BIN=".build/release/Barycenter"

echo "▸ Release bauen…"
swift build -c release

echo "▸ $APP zusammenbauen…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Barycenter"
cp Barycenter-Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM-Resource-Bundles (Highlightr: highlight.js + Themes, SwiftTerm) mitnehmen
for b in .build/release/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

# Lokalisierungen: jedes <lang>.lproj ins Bundle kopieren (für NSLocalizedString).
if [ -d Localization ]; then
  cp -R Localization/*.lproj "$APP/Contents/Resources/"
  echo "✓ $(ls -d Localization/*.lproj | wc -l | tr -d ' ') Lokalisierungen kopiert"
fi

echo "▸ Signieren (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ Fertig: $(pwd)/$APP"
