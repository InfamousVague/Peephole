#!/usr/bin/env bash
# Builds a release binary and assembles Peephole.app — a menu-bar agent
# (LSUIElement, no Dock icon) that watches camera/mic access.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Peephole.app"
SRC_ICON="$ROOT/art/AppIcon-source.png"
VERSION="0.1.4"
# Same Developer ID as the sibling apps ("Matt Wisniewski, F6ZAL7ANAD").
# Override with SIGN_IDENTITY=- for an ad-hoc local build.
SIGN_IDENTITY="${SIGN_IDENTITY:-0948896DC970503ADEF5B5070E0BB3E9D9047757}"
DMG="$ROOT/Peephole-$VERSION.dmg"

echo "› swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "› assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# App icon: source PNG → .iconset → .icns (native sips + iconutil).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
  px="${spec%%:*}"; name="${spec##*:}"
  sips -z "$px" "$px" "$SRC_ICON" --out "$ICONSET/icon_${name}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Executable (single Mach-O; the menu-bar glyph is an SF Symbol).
cp "$BIN/Peephole" "$APP/Contents/MacOS/Peephole"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Peephole</string>
  <key>CFBundleDisplayName</key><string>Peephole</string>
  <key>CFBundleIdentifier</key><string>com.mattssoftware.peephole</string>
  <key>CFBundleExecutable</key><string>Peephole</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Peephole</string>
</dict>
</plist>
PLIST

# Sign with the Developer ID (hardened runtime, distribution-ready).
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  # Inside-out, no --deep.
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/Peephole"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=1 "$APP" && echo "✓ signed: $SIGN_IDENTITY"
else
  echo "⚠ signing identity $SIGN_IDENTITY not found — ad-hoc signing instead"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "✓ built $APP"

# Build a downloadable .dmg (Peephole.app + /Applications drop target).
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Peephole.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Peephole" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG" || true
fi
echo "✓ built $DMG"

# ── Notarize + staple (Developer ID builds only) ──────────────────
# Submits the signed .app, staples the ticket onto the .app itself
# (so the installed /Applications copy is Gatekeeper-trusted even
# offline) and onto the .dmg. Non-fatal: a creds-less or rejected
# build still completes, just signed-only. (Was dmg-only + would
# hard-abort the build under `set -e` on any notarization hiccup;
# this stapls the app too and degrades gracefully.)
NOTARY_PROFILE="${NOTARY_PROFILE:-Notary}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "› notarizing $APP (waits on Apple)…"
  NZIP="$(mktemp -d)/notarize.zip"
  ditto -c -k --keepParent "$APP" "$NZIP"
  if xcrun notarytool submit "$NZIP" \
       --keychain-profile "$NOTARY_PROFILE" --wait; then
    if xcrun stapler staple "$APP"; then
      if xcrun stapler validate "$APP"; then
        echo "✓ notarized + stapled $APP"
      else
        echo "⚠ staple validate failed for $APP"
      fi
      if [ -f "$DMG" ]; then
        if xcrun stapler staple "$DMG"; then echo "✓ stapled $DMG"; fi
      fi
    else
      echo "⚠ stapling failed for $APP"
    fi
  else
    echo "⚠ notarization skipped/failed — $APP signed but not notarized"
  fi
fi
