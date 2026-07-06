#!/bin/zsh
set -euo pipefail
cd "/Users/WilliamChang/Documents/Playground/IterationPilot"
echo "Packaging NexaFlow standard DMG outside Codex sandbox..."
./script/package_dmg.sh --standard-only
echo
echo "Done. Press any key to close this window."
read -k 1
