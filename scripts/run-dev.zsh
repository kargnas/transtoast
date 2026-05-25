#!/usr/bin/env zsh
set -euo pipefail

cd "${0:A:h}/.."

if [[ -f .env.local ]]; then
  set -a
  source .env.local
  set +a
fi

swift run CopyTranslator
