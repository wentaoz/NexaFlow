#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build --disable-sandbox --product IterationPilot

swift run --disable-sandbox IterationPilotRegressionTests

swift build --disable-sandbox -c release --product IterationPilot \
  --triple arm64-apple-macosx13.0 \
  --scratch-path .build/regression-arm64

swift build --disable-sandbox -c release --product IterationPilot \
  --triple x86_64-apple-macosx13.0 \
  --scratch-path .build/regression-x86_64

mkdir -p .build/regression-universal
lipo -create \
  .build/regression-arm64/arm64-apple-macosx/release/IterationPilot \
  .build/regression-x86_64/x86_64-apple-macosx/release/IterationPilot \
  -output .build/regression-universal/IterationPilot

ARCHS="$(lipo -archs .build/regression-universal/IterationPilot)"
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*)
    echo "Universal binary OK: $ARCHS"
    ;;
  *)
    echo "Universal binary missing expected architectures: $ARCHS" >&2
    exit 1
    ;;
esac
