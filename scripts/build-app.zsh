#!/usr/bin/env zsh
set -euo pipefail

ROOT="${0:A:h}/.."
APP_NAME="TransToast"
BUNDLE_ID="as.kargn.transtoast"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SIGN_IDENTITY="${TRANSTOAST_CODE_SIGN_IDENTITY:-}"
TAURI_HELPER_SOURCE="$ROOT/src-tauri/target/release/bundle/macos/TransToast.app"
TAURI_HELPER_DEST="$RESOURCES_DIR/TransToastTauri.app"

cd "$ROOT"
swift build -c release
npm run tauri -- build --bundles app >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
ditto "$TAURI_HELPER_SOURCE" "$TAURI_HELPER_DEST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.tauri-helper" "$TAURI_HELPER_DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName TransToastTauri" "$TAURI_HELPER_DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TransToastTauri" "$TAURI_HELPER_DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :LSUIElement" "$TAURI_HELPER_DEST/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$TAURI_HELPER_DEST/Contents/Info.plist"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$TAURI_HELPER_DEST" >/dev/null 2>&1 || true
cp "$ROOT/scripts/hy_mt2_translate.py" "$RESOURCES_DIR/hy_mt2_translate.py"
mkdir -p "$RESOURCES_DIR/runtimes"
cp "$ROOT"/scripts/runtimes/*.py "$RESOURCES_DIR/runtimes/"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
  <key>NSSupportsSuddenTermination</key>
  <false/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Sangrak</string>
</dict>
</plist>
PLIST

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/^ *[0-9]*) \([A-F0-9]\{40\}\) "Apple Development:[^"]*".*/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/^ *[0-9]*) \([A-F0-9]\{40\}\) "Developer ID Application:[^"]*".*/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

if ! codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null; then
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    echo "codesign with detected identity failed; falling back to ad-hoc signing." >&2
    SIGN_IDENTITY="-"
  else
    sleep 0.5
  fi
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
fi
codesign --verify --deep --strict "$APP_DIR"
echo "Signed with: $SIGN_IDENTITY"
echo "$APP_DIR"
