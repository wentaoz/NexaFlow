#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/skills/nexaflow"
TARGET_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
DRY_RUN=1

if [[ "${1:-}" == "--apply" ]]; then
  DRY_RUN=0
fi

echo "Source: $SOURCE_DIR"
echo "Target: $TARGET_ROOT"

find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "_shared" | sort | while read -r skill_dir; do
  skill_name="$(basename "$skill_dir")"
  target_dir="$TARGET_ROOT/nexaflow-$skill_name"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] would install $skill_name -> $target_dir"
  else
    mkdir -p "$target_dir"
    rsync -a --delete "$skill_dir/" "$target_dir/"
    echo "installed $skill_name -> $target_dir"
  fi
done

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry run complete. Re-run with --apply to copy skills."
fi
