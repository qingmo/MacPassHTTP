#!/usr/bin/env bash
#
# build-deps.sh — fetch and build MacPassHTTP's Carthage dependencies.
#
# Two problems make a plain `carthage bootstrap --platform macOS` fail with the
# pinned, ~2019-era dependencies on modern Xcode:
#
# 1. Deployment targets (macOS 10.7 / iOS 8.0) are below what modern Xcode
#    supports, so the link step fails with "SDK does not contain 'libarclite'"
#    (Apple removed libarclite_*.a in Xcode 14.3+). Fixed by
#    carthage-deployment-target.xcconfig, injected via XCODE_XCCONFIG_FILE,
#    which raises the targets to the supported minimums and pins ARCHS.
#
# 2. GCDWebServer and JSONModel each ship several shared schemes that build a
#    framework with the SAME product name (e.g. both "JSONModel" and
#    "JSONModel-mac" produce JSONModel.framework; "GCDWebServers (iOS)" and
#    "GCDWebServers (Mac)" produce GCDWebServers.framework). Carthage builds all
#    macOS-eligible schemes in parallel and they race to write the same path in
#    Carthage/Build/Mac. Depending on which build wins the race you intermittently
#    get an iOS framework ("building for macOS, but linking in dylib built for
#    iOS") or an arm64-only iOS-device slice (arch-mismatch link errors) in place
#    of the real macOS framework. We split bootstrap into checkout -> prune -> build
#    and delete the duplicate non-macOS schemes so exactly one scheme per
#    framework remains, making the build deterministic.
#
# Usage:
#   ./build-deps.sh            # checkout, prune duplicate schemes, build (macOS)
#   ./build-deps.sh update     # carthage update (re-resolve), then prune + build
#   ./build-deps.sh <args...>  # forwarded verbatim to carthage (with xcconfig)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XCCONFIG="$SCRIPT_DIR/carthage-deployment-target.xcconfig"
CHECKOUTS="$SCRIPT_DIR/Carthage/Checkouts"

if ! command -v carthage >/dev/null 2>&1; then
  echo "error: carthage not found. Install it: https://github.com/Carthage/Carthage#installing-carthage" >&2
  exit 1
fi
if [ ! -f "$XCCONFIG" ]; then
  echo "error: missing $XCCONFIG" >&2
  exit 1
fi

run_carthage() {
  echo "==> XCODE_XCCONFIG_FILE=$XCCONFIG"
  echo "==> carthage $*"
  XCODE_XCCONFIG_FILE="$XCCONFIG" carthage "$@"
}

# Keep exactly one macOS scheme per framework so Carthage's parallel builds can't
# race two same-named frameworks into Carthage/Build/Mac. Safe to re-run; missing
# files are ignored.
prune_duplicate_schemes() {
  echo "==> pruning duplicate non-macOS schemes from checkouts"
  local removed=0 f
  # JSONModel: keep JSONModel-mac, drop the iOS/tvOS/watchOS schemes.
  for f in "JSONModel" "JSONModel-tvOS" "JSONModel-watchOS"; do
    local p="$CHECKOUTS/jsonmodel/JSONModel.xcodeproj/xcshareddata/xcschemes/$f.xcscheme"
    if [ -f "$p" ]; then rm -f "$p"; echo "    removed jsonmodel scheme: $f"; removed=$((removed+1)); fi
  done
  # GCDWebServer: keep "GCDWebServers (Mac)", drop iOS/tvOS.
  for f in "GCDWebServers (iOS)" "GCDWebServers (tvOS)"; do
    local p="$CHECKOUTS/GCDWebServer/GCDWebServer.xcodeproj/xcshareddata/xcschemes/$f.xcscheme"
    if [ -f "$p" ]; then rm -f "$p"; echo "    removed GCDWebServer scheme: $f"; removed=$((removed+1)); fi
  done
  echo "    pruned $removed scheme(s)"
}

mode="${1:-bootstrap}"
case "$mode" in
  bootstrap)
    run_carthage checkout
    prune_duplicate_schemes
    run_carthage build --platform macOS
    ;;
  update)
    shift
    run_carthage update --no-build "$@"
    prune_duplicate_schemes
    run_carthage build --platform macOS
    ;;
  *)
    # Anything else: forward verbatim (still with the xcconfig).
    run_carthage "$@"
    ;;
esac
