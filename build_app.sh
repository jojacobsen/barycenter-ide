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

# SwiftPM-Resource-Bundles (Highlightr: highlight.js + Themes, SwiftTerm) mitnehmen
for b in .build/release/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

echo "▸ Signieren (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ Fertig: $(pwd)/$APP"
