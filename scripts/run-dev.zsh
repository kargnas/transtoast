#!/usr/bin/env zsh
set -euo pipefail

ROOT="${0:A:h}/.."
ROOT="${ROOT:A}"
APP_NAME="CopyTranslator"
APP_DIR="$ROOT/dist/$APP_NAME.app"
BUNDLE_ID="as.kargn.copy-translator"
APP_EXEC="$APP_DIR/Contents/MacOS/$APP_NAME"
DEBUG_EXEC="$ROOT/.build/arm64-apple-macosx/debug/$APP_NAME"
TAURI_SETTINGS_EXEC="$ROOT/src-tauri/target/debug/copy-translator-tauri"

cd "$ROOT"

# Build and run the signed app bundle in development so macOS TCC permissions
# use the stable bundle id instead of SwiftPM's ad-hoc debug executable id.
"$ROOT/scripts/build-app.zsh" >/dev/null
npm run tauri -- build --debug >/dev/null

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
while IFS= read -r pid; do
  kill "$pid" >/dev/null 2>&1 || true
done < <(pgrep -f "$APP_EXEC" || true)

if [[ -x "$DEBUG_EXEC" ]]; then
  while IFS= read -r pid; do
    parent_pid="$(ps -p "$pid" -o ppid= | tr -d ' ' || true)"
    kill "$pid" >/dev/null 2>&1 || true
    if [[ -n "$parent_pid" ]] && ps -p "$parent_pid" -o comm= 2>/dev/null | grep -q "debugserver"; then
      kill "$parent_pid" >/dev/null 2>&1 || true
    fi
  done < <(pgrep -f "$DEBUG_EXEC" || true)
fi

if [[ -x "$TAURI_SETTINGS_EXEC" ]]; then
  while IFS= read -r pid; do
    kill "$pid" >/dev/null 2>&1 || true
  done < <(pgrep -f "$TAURI_SETTINGS_EXEC" || true)
fi

open "$APP_DIR" --args --workspace-root "$ROOT" "$@"
echo "Opened: $APP_DIR"
