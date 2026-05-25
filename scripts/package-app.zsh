#!/usr/bin/env zsh
set -euo pipefail

ROOT="${0:A:h}/.."
APP_NAME="CopyTranslator"
ZIP_PATH="$ROOT/dist/$APP_NAME.zip"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      ZIP_PATH="$2"
      shift 2
      ;;
    -h|--help)
      cat <<HELP
Usage: scripts/package-app.zsh [--output PATH]

Builds CopyTranslator.app and writes a zip archive.
Default output: dist/CopyTranslator.zip
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

rm -f "$ZIP_PATH"
mkdir -p "${ZIP_PATH:h}"
ditto -c -k --keepParent "$ROOT/dist/$APP_NAME.app" "$ZIP_PATH"

echo "Packaged: $ZIP_PATH"
