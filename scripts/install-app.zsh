#!/usr/bin/env zsh
set -euo pipefail

ROOT="${0:A:h}/.."
APP_NAME="CCTrans"
GITHUB_REPO="kargnas/cctrans"
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

# Best-effort GitHub star nudge for from-source installers. The install is
# already done at this point, and `set -e` is active, so every gh call must
# stay inside a condition to keep a gh/network hiccup from failing the script.
if [[ -t 0 ]] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  # GET user/starred/<repo> exits 0 only when the repo is already starred
  # (HTTP 204); 404 means not starred, so only then we prompt.
  if ! gh api "user/starred/$GITHUB_REPO" >/dev/null 2>&1; then
    if read -q "REPLY?Enjoying CCTrans? Star https://github.com/$GITHUB_REPO [y/N] "; then
      echo ""
      if gh api -X PUT "user/starred/$GITHUB_REPO" >/dev/null 2>&1; then
        echo "Starred $GITHUB_REPO. Thanks!"
      else
        echo "Could not star $GITHUB_REPO (gh api PUT failed; check token scopes)." >&2
      fi
    else
      echo ""
    fi
  fi
fi
