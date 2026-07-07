#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"
echo "Packaging NexaFlow standard DMG outside Codex sandbox..."
./script/package_dmg.sh --standard-only
echo
echo "Done. Press any key to close this window."
read -k 1
