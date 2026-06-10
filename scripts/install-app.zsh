#!/usr/bin/env zsh
set -euo pipefail

ROOT="${0:A:h}/.."
APP_NAME="CCTrans"
INSTALL_DIR="/Applications"
OPEN_AFTER_INSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --open)
      OPEN_AFTER_INSTALL=1
      shift
      ;;
    -h|--help)
      cat <<HELP
Usage: scripts/install-app.zsh [--install-dir PATH] [--open]

Builds CCTrans.app and installs it to PATH.
Default install directory: /Applications
HELP
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

"$ROOT/scripts/build-app.zsh"

APP_DIR="$ROOT/dist/$APP_NAME.app"
DEST="$INSTALL_DIR/$APP_NAME.app"

mkdir -p "$INSTALL_DIR"
rm -rf "$DEST"
ditto "$APP_DIR" "$DEST"

echo "Installed: $DEST"
echo "Open System Settings permissions if this is the first install on this Mac:"
echo '  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"'
echo '  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"'
echo '  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"'

if [[ "$OPEN_AFTER_INSTALL" == "1" ]]; then
  open "$DEST"
fi
