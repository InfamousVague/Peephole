#!/usr/bin/env bash
# Builds a release binary and assembles Peephole.app — a menu-bar agent
# (LSUIElement, no Dock icon) that watches camera/mic access.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Peephole.app"
VERSION="0.1.0"
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

# Executable only — Peephole bundles no icon/resource assets, so there is no
# SwiftPM resource bundle to flatten (no Bundle.module usage).
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
