#!/bin/bash
# Builds Barycenter as a real macOS .app bundle (release) and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")"

APP="Barycenter.app"
BIN=".build/release/Barycenter"

echo "▸ Building release…"
swift build -c release

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Barycenter"
cp Barycenter-Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Include the SwiftPM resource bundles (Highlightr: highlight.js + themes, SwiftTerm).
for b in .build/release/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

# Localizations: copy each <lang>.lproj into the bundle (for NSLocalizedString).
if [ -d Localization ]; then
  cp -R Localization/*.lproj "$APP/Contents/Resources/"
  echo "✓ Copied $(ls -d Localization/*.lproj | wc -l | tr -d ' ') localizations"
fi

# Embed Sparkle.framework (auto-updater) from the SwiftPM binary artifact.
SPARKLE_FW=$(find .build -type d -path '*/Sparkle.xcframework/macos-*/Sparkle.framework' 2>/dev/null | head -1)
if [ -n "$SPARKLE_FW" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
  cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
  echo "✓ Embedded Sparkle.framework"
else
  echo "⚠︎ Sparkle.framework not found in .build — run 'swift build' first" >&2
fi

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ Done: $(pwd)/$APP"
