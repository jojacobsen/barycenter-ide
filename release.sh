#!/bin/bash
# Builds a Developer ID–signed, Apple-notarized Barycenter.dmg ready for distribution.
#
#   ./release.sh
#
# Prerequisites (one-time):
#   - "Developer ID Application" certificate in the login keychain
#   - a notarytool credential profile. Reuse the existing one, or create:
#       xcrun notarytool store-credentials "barycenter-notary" \
#         --apple-id "<apple-id>" --team-id "BTZJHLR33N"
#     (same team as Kritz, so NOTARY_PROFILE=kritz-notary works too)
set -euo pipefail

APP_NAME="Barycenter"
SIGN_ID="Developer ID Application: Johannes Jacob (BTZJHLR33N)"
NOTARY_PROFILE="${NOTARY_PROFILE:-barycenter-notary}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
APP_DIR="$ROOT/$APP_NAME.app"
DMG="$ROOT/$APP_NAME.dmg"

# 1. Build the .app bundle (icon, resource bundles, ad-hoc signature).
./build_app.sh

# 2. Re-sign with Developer ID + Hardened Runtime + secure timestamp.
#    Sparkle's embedded framework must be signed inside-out FIRST (helpers, then the
#    framework), then the app last — otherwise notarization rejects unsigned nested code.
SPK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPK" ]; then
    echo "▶︎ codesign Sparkle (inside-out)"
    V="$SPK/Versions/B"
    for xpc in "$V/XPCServices/"*.xpc; do
        [ -e "$xpc" ] || continue
        # XPC services may be sandboxed -> keep their entitlements.
        codesign --force --options runtime --timestamp \
            --preserve-metadata=entitlements --sign "$SIGN_ID" "$xpc"
    done
    [ -e "$V/Autoupdate" ] && codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$V/Autoupdate"
    if [ -d "$V/Updater.app" ]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$V/Updater.app/Contents/MacOS/Updater"
        codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$V/Updater.app"
    fi
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$SPK"
fi

#    --entitlements: allow JIT for JavaScriptCore (Highlightr) / WebKit (Markdown preview).
echo "▶︎ codesign (Developer ID, hardened runtime)"
codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Barycenter.entitlements" \
    --sign "$SIGN_ID" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

# 3. Assemble the DMG (app + drag-to-Applications).
echo "▶︎ building DMG"
STAGE="$(mktemp -d)"
cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# 4. Notarize the DMG and wait for the result.
echo "▶︎ notarizing (this can take a few minutes) …"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# 5. Staple the ticket so it verifies offline.
echo "▶︎ stapling"
xcrun stapler staple "$DMG"

# 6. Verify Gatekeeper acceptance.
echo "▶︎ verifying"
spctl -a -t open --context context:primary-signature -v "$DMG" || true
stapler validate "$DMG"

echo "✓ Notarized DMG ready: $DMG"

# 7. Update the Sparkle appcast (only once a real signing key is configured).
#    DMGs are named per version and all live on one fixed "appcast" release, so a
#    single download-url-prefix is valid. generate_appcast signs each entry with the
#    private EdDSA key from your Keychain and writes the feed to docs/appcast.xml
#    (served via GitHub Pages at the SUFeedURL).
PUBKEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)"
GEN="$(find "$ROOT/.build" -path '*/Sparkle/bin/generate_appcast' 2>/dev/null | head -1)"
if [ -n "$GEN" ] && [ -n "$PUBKEY" ] && [ "$PUBKEY" != "REPLACE_WITH_PUBLIC_ED_KEY" ]; then
    VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
    DIST="$ROOT/dist"
    mkdir -p "$DIST"
    # Pull previously published DMGs so the appcast keeps older versions (ignore if none yet).
    gh release download appcast -D "$DIST" -p 'Barycenter-*.dmg' --clobber 2>/dev/null || true
    cp "$DMG" "$DIST/Barycenter-$VER.dmg"
    echo "▶︎ generating appcast"
    "$GEN" "$DIST" \
        --download-url-prefix "https://github.com/jojacobsen/barycenter-ide/releases/download/appcast/" \
        -o "$ROOT/docs/appcast.xml"
    echo "✓ appcast written: docs/appcast.xml"
    echo "  Publish it:  gh release upload appcast \"$DIST/Barycenter-$VER.dmg\" --clobber"
    echo "               git add docs/appcast.xml && git commit && git push   # updates GitHub Pages feed"
else
    echo "ℹ︎ Sparkle appcast skipped (set SUPublicEDKey in Barycenter-Info.plist to enable)."
fi
