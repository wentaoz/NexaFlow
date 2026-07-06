#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NexaFlow"
APP_BUNDLE="dist/$APP_NAME.app"
RELEASE_ROOT="artifacts/release"
DATE_DIR="$RELEASE_ROOT/$(date +%F)"
STAMP="$(date +%Y%m%d-%H%M%S)"
DMG_BASENAME="$APP_NAME-1.0-universal-$STAMP"
ALLOW_HYBRID="${ALLOW_HYBRID_DMG:-0}"
STANDARD_ONLY=0

if [[ "${1:-}" == "--standard-only" ]]; then
  STANDARD_ONLY=1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing $APP_BUNDLE. Build the app first with ./script/build_and_run.sh --verify." >&2
  exit 2
fi

if [[ ! -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]]; then
  echo "Missing executable: $APP_BUNDLE/Contents/MacOS/$APP_NAME" >&2
  exit 2
fi

mkdir -p "$DATE_DIR"

stage_dir="/private/tmp/nexaflow-dmg-stage-$STAMP"
standard_tmp="/private/tmp/$DMG_BASENAME.dmg"
standard_dmg="$DATE_DIR/$DMG_BASENAME.dmg"
hybrid_tmp_base="/private/tmp/$DMG_BASENAME-hybrid"
hybrid_dmg="$DATE_DIR/$DMG_BASENAME-hybrid.dmg"
zip_artifact="$DATE_DIR/$DMG_BASENAME.zip"

cleanup() {
  rm -rf "$stage_dir" "$standard_tmp" "$hybrid_tmp_base" "$hybrid_tmp_base.dmg"
}
trap cleanup EXIT

prepare_stage() {
  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"
  cp -R "$APP_BUNDLE" "$stage_dir/$APP_NAME.app"
  ln -s /Applications "$stage_dir/Applications"
}

write_terminal_launcher() {
  local launcher="$DATE_DIR/package_${APP_NAME}_standard_dmg_in_terminal.command"
  cat >"$launcher" <<EOF
#!/bin/zsh
set -euo pipefail
cd "$ROOT_DIR"
echo "Packaging $APP_NAME standard DMG outside Codex sandbox..."
./script/package_dmg.sh --standard-only
echo
echo "Done. Press any key to close this window."
read -k 1
EOF
  chmod +x "$launcher"

  local stable_launcher="$ROOT_DIR/script/package_standard_dmg_in_terminal.command"
  cat >"$stable_launcher" <<EOF
#!/bin/zsh
set -euo pipefail
cd "$ROOT_DIR"
echo "Packaging $APP_NAME standard DMG outside Codex sandbox..."
./script/package_dmg.sh --standard-only
echo
echo "Done. Press any key to close this window."
read -k 1
EOF
  chmod +x "$stable_launcher"
  echo "$launcher"
}

prepare_stage

echo "Packaging $APP_NAME DMG..."
hdiutil_log="/private/tmp/$DMG_BASENAME-hdiutil.log"
if hdiutil create -volname "$APP_NAME" -srcfolder "$stage_dir" -ov -format UDZO "$standard_tmp" >"$hdiutil_log" 2>&1; then
  mv "$standard_tmp" "$standard_dmg"
  echo "$standard_dmg"
  exit 0
fi

cat "$hdiutil_log" >&2
echo "warning: hdiutil create failed; standard compressed DMG was not produced." >&2
echo "warning: If this is running inside Codex sandbox, hdiutil cannot start the macOS DiskImages helper." >&2

if [[ "$STANDARD_ONLY" == "1" ]]; then
  echo "error: standard-only packaging failed. Run from a normal Terminal session, not inside Codex sandbox." >&2
  exit 1
fi

launcher_path="$(write_terminal_launcher)"
echo "warning: To produce a standard DMG, run this outside Codex sandbox:" >&2
echo "warning:   $launcher_path" >&2
echo "warning: or double-click:" >&2
echo "warning:   $ROOT_DIR/script/package_standard_dmg_in_terminal.command" >&2

if [[ "$ALLOW_HYBRID" != "1" ]]; then
  echo "Creating ZIP fallback instead of an incompatible hybrid .dmg..." >&2
  rm -f "$zip_artifact"
  ditto -c -k --keepParent "$APP_BUNDLE" "$zip_artifact"
  echo "$zip_artifact"
  exit 0
fi

echo "warning: ALLOW_HYBRID_DMG=1 set; creating hybrid DMG fallback." >&2

prepare_stage
hdiutil makehybrid -hfs -hfs-volume-name "$APP_NAME" -o "$hybrid_tmp_base" "$stage_dir"

if [[ -f "$hybrid_tmp_base.dmg" ]]; then
  mv "$hybrid_tmp_base.dmg" "$hybrid_dmg"
elif [[ -f "$hybrid_tmp_base" ]]; then
  mv "$hybrid_tmp_base" "$hybrid_dmg"
else
  found="$(ls "$hybrid_tmp_base"* 2>/dev/null | head -1 || true)"
  if [[ -z "$found" ]]; then
    echo "Failed to locate hybrid DMG output." >&2
    exit 1
  fi
  mv "$found" "$hybrid_dmg"
fi

echo "$hybrid_dmg"
