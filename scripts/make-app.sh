#!/usr/bin/env bash
# Builds a release binary and assembles Peephole.app — a menu-bar agent
# (LSUIElement, no Dock icon) that watches camera/mic access.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Peephole.app"
SRC_ICON="$ROOT/art/AppIcon-source.png"
VERSION="0.2.3"
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

# ── Embed + (below) sign the SuiteKit contract and this
# app's pane dylib so the MattsSoftware launcher can load
# the SAME code out of this installed .app. rpath lets the
# bundled exe find them under Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
cp "$BIN/libSuiteKit.dylib" "$APP/Contents/Frameworks/"
cp "$BIN/libPeepholePane.dylib" "$APP/Contents/Frameworks/"
if [ -d "$BIN/PeepholePane_PeepholePane.bundle" ]; then cp -R "$BIN/PeepholePane_PeepholePane.bundle" "$APP/Contents/Frameworks/"; fi
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Peephole" 2>/dev/null || true


# ── Widget extension (.appex) ─────────────────────────────────────
# Built by Xcode, not SwiftPM (SR-14944). Widget consumes
# PeepholeShared via local-package dep so it shares the App Group
# + SharedPeephole model with the host.
if [ "${SKIP_WIDGET:-0}" != "1" ]; then
  if command -v xcodegen >/dev/null; then
    ( cd "$ROOT/Widget" && xcodegen generate --quiet )
  fi
  echo "› xcodebuild PeepholeWidgets.appex"
  XCB_OUT="$ROOT/.build/xcode"
  xcodebuild \
    -project "$ROOT/Widget/PeepholeWidgets.xcodeproj" \
    -scheme PeepholeWidgets \
    -configuration Release \
    -derivedDataPath "$XCB_OUT" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    -quiet \
    build
  WIDGET_APPEX="$XCB_OUT/Build/Products/Release/PeepholeWidgets.appex"
  if [ -d "$WIDGET_APPEX" ]; then
    mkdir -p "$APP/Contents/PlugIns"
    rm -rf "$APP/Contents/PlugIns/PeepholeWidgets.appex"
    ditto "$WIDGET_APPEX" "$APP/Contents/PlugIns/PeepholeWidgets.appex"
    echo "✓ embedded $APP/Contents/PlugIns/PeepholeWidgets.appex"
  fi
fi

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

HOST_ENT="$ROOT/Peephole.entitlements"
WIDGET_ENT="$ROOT/Widget/Supporting Files/PeepholeWidgets.entitlements"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/libSuiteKit.dylib"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/libPeepholePane.dylib"
  if [ -d "$APP/Contents/PlugIns/PeepholeWidgets.appex" ]; then
    codesign --force --options runtime --timestamp \
      --entitlements "$WIDGET_ENT" \
      --sign "$SIGN_IDENTITY" \
      "$APP/Contents/PlugIns/PeepholeWidgets.appex/Contents/MacOS/PeepholeWidgets"
    codesign --force --options runtime --timestamp \
      --entitlements "$WIDGET_ENT" \
      --sign "$SIGN_IDENTITY" \
      "$APP/Contents/PlugIns/PeepholeWidgets.appex"
  fi
  codesign --force --options runtime --timestamp \
    --entitlements "$HOST_ENT" \
    --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/Peephole"
  codesign --force --options runtime --timestamp \
    --entitlements "$HOST_ENT" \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=1 "$APP" && echo "✓ signed: $SIGN_IDENTITY"
else
  echo "⚠ signing identity $SIGN_IDENTITY not found — ad-hoc signing instead"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "✓ built $APP"

# ── Notarize + staple the .app (Developer ID builds only) ─────────
# Runs BEFORE the .dmg is built so the disk image wraps an
# already-stapled app — the copy a user drags to /Applications is
# Gatekeeper-trusted even offline. We notarize the zipped app, so the
# ticket rides on the .app; the .dmg is signed but not stapled (its
# first mount does a one-time online check, fine for a freshly
# downloaded installer). Non-fatal: a creds-less or rejected build
# still completes, just signed-only.
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
    else
      echo "⚠ stapling failed for $APP"
    fi
  else
    echo "⚠ notarization skipped/failed — $APP signed but not notarized"
  fi
fi

# Build a downloadable .dmg from the (now-stapled) Peephole.app.
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
