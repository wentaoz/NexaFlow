#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SWIFT_PRODUCT_NAME="IterationPilot"
APP_NAME="NexaFlow"
BUNDLE_ID="${ITERATIONPILOT_BUNDLE_ID:-com.williamchang.NexaFlow}"
MIN_SYSTEM_VERSION="13.0"
CONFIGURATION="${ITERATIONPILOT_CONFIGURATION:-release}"
ARCHS="${ITERATIONPILOT_ARCHS:-arm64 x86_64}"
CODESIGN_IDENTITY="${ITERATIONPILOT_CODESIGN_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
LAUNCH_ENV_KEYS=(
  NEXAFLOW_WORKSPACE_PATH
  NEXAFLOW_AI_ENDPOINT
  NEXAFLOW_AI_MODEL
  NEXAFLOW_AI_API_KEY
  NEXAFLOW_AI_SYSTEM_PROMPT
  NEXAFLOW_DEBUG_SNAPSHOT_DIR
  NEXAFLOW_DEBUG_SNAPSHOT_SCENARIOS
  NEXAFLOW_DEBUG_SNAPSHOT_RUN_ID
  NEXAFLOW_DEBUG_SNAPSHOT_DELAY_SECONDS
  NEXAFLOW_DEBUG_SNAPSHOT_WIDTH
  NEXAFLOW_DEBUG_SNAPSHOT_HEIGHT
  NEXAFLOW_DEBUG_SNAPSHOT_TERMINATE_AFTER_EXPORT
)

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "$SWIFT_PRODUCT_NAME" >/dev/null 2>&1 || true

rm -rf "$APP_BUNDLE"
if [[ "$SWIFT_PRODUCT_NAME" != "$APP_NAME" ]]; then
  rm -rf "$DIST_DIR/$SWIFT_PRODUCT_NAME.app"
fi
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

BUILT_BINARIES=()
for ARCH in $ARCHS; do
  TRIPLE="${ARCH}-apple-macosx${MIN_SYSTEM_VERSION}"
  SCRATCH_PATH="$ROOT_DIR/.build/$ARCH"
  echo "Building $SWIFT_PRODUCT_NAME for $ARCH ($CONFIGURATION)"
  if swift build --disable-sandbox -c "$CONFIGURATION" --triple "$TRIPLE" --scratch-path "$SCRATCH_PATH"; then
    BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --triple "$TRIPLE" --scratch-path "$SCRATCH_PATH" --show-bin-path)"
    BUILT_BINARIES+=("$BIN_DIR/$SWIFT_PRODUCT_NAME")
  else
    echo "warning: failed to build $ARCH; continuing with remaining architectures" >&2
  fi
done

if [[ "${#BUILT_BINARIES[@]}" -eq 0 ]]; then
  echo "No cross-architecture build succeeded; falling back to native build" >&2
  swift build --disable-sandbox -c "$CONFIGURATION"
  BUILT_BINARIES+=("$(swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)/$SWIFT_PRODUCT_NAME")
fi

if [[ "${#BUILT_BINARIES[@]}" -eq 1 ]]; then
  cp "${BUILT_BINARIES[0]}" "$APP_BINARY"
else
  lipo -create "${BUILT_BINARIES[@]}" -output "$APP_BINARY"
fi

chmod +x "$APP_BINARY"

if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_CONTENTS/PkgInfo"
xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F '"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE" >/dev/null 2>&1 || codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
else
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

open_app() {
  local open_env_args=()
  local key
  for key in "${LAUNCH_ENV_KEYS[@]}"; do
    if [[ ${!key+x} ]]; then
      open_env_args+=(--env "$key=${!key}")
    fi
  done
  if ((${#open_env_args[@]} > 0)); then
    /usr/bin/open -n "${open_env_args[@]}" "$APP_BUNDLE"
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}

wait_for_app_process() {
  for _ in {1..60}; do
    if pgrep -x "$APP_NAME" >/dev/null || pgrep -f "$APP_BINARY" >/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

app_has_visible_window() {
  APP_NAME="$APP_NAME" swift -e '
import CoreGraphics
import Foundation

let appName = ProcessInfo.processInfo.environment["APP_NAME"] ?? ""
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
let hasVisibleWindow = windows.contains { window in
    guard String(describing: window[kCGWindowOwnerName as String] ?? "") == appName else {
        return false
    }
    let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
    guard layer == 0 else { return false }
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else {
        return false
    }
    let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
    let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
    return width > 20 && height > 20
}
exit(hasVisibleWindow ? 0 : 1)
' >/dev/null 2>&1
}

wait_for_app_window() {
  for _ in {1..60}; do
    if app_has_visible_window; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

debug_snapshot_manifest_path() {
  printf '%s/%s/manifest.json' "$NEXAFLOW_DEBUG_SNAPSHOT_DIR" "$NEXAFLOW_DEBUG_SNAPSHOT_RUN_ID"
}

wait_for_debug_snapshot_manifest() {
  local manifest
  manifest="$(debug_snapshot_manifest_path)"
  for _ in {1..80}; do
    if [[ -s "$manifest" ]]; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

validate_debug_snapshot_manifest() {
  local manifest
  manifest="$(debug_snapshot_manifest_path)"
  python3 - "$manifest" <<'PY'
import json
import os
import sys

manifest_path = sys.argv[1]
with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

entries = manifest.get("entries", [])
failures = manifest.get("failures", [])
if failures:
    for failure in failures:
        print(f"snapshot failure: {failure.get('scenario')}: {failure.get('error')}", file=sys.stderr)
    sys.exit(1)
if not entries:
    print("snapshot manifest did not contain any entries", file=sys.stderr)
    sys.exit(1)

try:
    from PIL import Image, ImageStat
except Exception:
    Image = None
    ImageStat = None

for entry in entries:
    path = entry.get("path", "")
    scenario = entry.get("scenario", "unknown")
    if not os.path.exists(path):
        print(f"snapshot missing for {scenario}: {path}", file=sys.stderr)
        sys.exit(1)
    byte_count = os.path.getsize(path)
    if byte_count < 10_000:
        print(f"snapshot too small for {scenario}: {byte_count} bytes", file=sys.stderr)
        sys.exit(1)
    if entry.get("width", 0) < 300 or entry.get("height", 0) < 300:
        print(f"snapshot dimensions too small for {scenario}: {entry.get('width')}x{entry.get('height')}", file=sys.stderr)
        sys.exit(1)
    if Image is not None:
        with Image.open(path) as image:
            extrema = image.convert("RGB").getextrema()
            if all(high <= 8 for _, high in extrema):
                print(f"snapshot is black for {scenario}: {path}", file=sys.stderr)
                sys.exit(1)
            stat = ImageStat.Stat(image.convert("L"))
            if stat.stddev[0] < 1.0:
                print(f"snapshot has almost no visual variance for {scenario}: {path}", file=sys.stderr)
                sys.exit(1)

print(f"Debug snapshots OK: {len(entries)} file(s)")
for entry in entries:
    print(f"- {entry['scenario']}: {entry['path']}")
PY
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    export NEXAFLOW_DEBUG_SNAPSHOT_DIR="${NEXAFLOW_DEBUG_SNAPSHOT_DIR:-$HOME/.codex/nexaflow-previews}"
    export NEXAFLOW_DEBUG_SNAPSHOT_RUN_ID="${NEXAFLOW_DEBUG_SNAPSHOT_RUN_ID:-nexaflow-verify-$(date +%Y%m%d-%H%M%S)}"
    export NEXAFLOW_DEBUG_SNAPSHOT_SCENARIOS="${NEXAFLOW_DEBUG_SNAPSHOT_SCENARIOS:-current,analysis-session-normal,analysis-info-sidebar,analysis-evidence-trace}"
    export NEXAFLOW_DEBUG_SNAPSHOT_DELAY_SECONDS="${NEXAFLOW_DEBUG_SNAPSHOT_DELAY_SECONDS:-1.0}"
    rm -rf "$NEXAFLOW_DEBUG_SNAPSHOT_DIR/$NEXAFLOW_DEBUG_SNAPSHOT_RUN_ID"
    mkdir -p "$NEXAFLOW_DEBUG_SNAPSHOT_DIR"
    open_app
    if ! wait_for_app_process; then
      echo "$APP_NAME did not appear in the process list after launch." >&2
      exit 1
    fi
    if ! wait_for_app_window; then
      echo "$APP_NAME launched, but no visible main window appeared." >&2
      exit 1
    fi
    if ! wait_for_debug_snapshot_manifest; then
      echo "$APP_NAME launched, but did not export a debug snapshot manifest at $(debug_snapshot_manifest_path)." >&2
      exit 1
    fi
    validate_debug_snapshot_manifest
    echo "$APP_NAME launched with a visible window."
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
