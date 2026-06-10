#!/usr/bin/env bash
#
# build.sh — full build of the MacPassHTTP plugin on modern Xcode (Apple Silicon).
#
# Orchestrates the whole chain and installs the plugin to
#   ~/Library/Application Support/MacPass/MacPassHTTP.mpplugin
#
#   1. MacPass (sibling repo) dependencies — the plugin compiles against MacPass
#      headers (HEADER_SEARCH_PATHS = ../MacPass/**) and links HNHUi/KeePassKit,
#      so MacPass's own Carthage deps must be checked out and built first.
#   2. MacPassHTTP's own Carthage deps — via ./build-deps.sh.
#   3. The plugin itself — xcodebuild, with the overrides explained below.
#   4. Embed KeePassHTTPKit's transitive frameworks (GCDWebServers, JSONModel)
#      into the installed plugin so it can load (see step 4 for why).
#   5. Code sign the bundle (inside-out) so MacPass will load it — MacPass runs
#      `codesign --verify` and refuses unsigned plugins (see step 5 for why).
#
# Requirements:
#   - Xcode + carthage installed.
#   - MacPass checked out as a sibling directory (../MacPass). Clone with:
#       git clone https://github.com/mstarke/MacPass ../MacPass
#
# Usage: ./build.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACPASS="$(cd "$ROOT/.." && pwd)/MacPass"
XCCONFIG="$ROOT/carthage-deployment-target.xcconfig"
CONFIG="Release"
PLUGIN="$HOME/Library/Application Support/MacPass/MacPassHTTP.mpplugin"
# Signing identity for the final codesign pass. Defaults to ad-hoc ("-"), which
# is enough for MacPass to load the plugin (it doesn't pin a signing anchor).
# Export CODESIGN_IDENTITY="Developer ID Application: ..." for a distributable build.
SIGN_ID="${CODESIGN_IDENTITY:--}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }

command -v carthage >/dev/null 2>&1 || die "carthage not found. See https://github.com/Carthage/Carthage#installing-carthage"
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found. Install Xcode and run xcode-select."
[ -f "$XCCONFIG" ] || die "missing $XCCONFIG"
[ -d "$MACPASS/.git" ] || die "MacPass not found at $MACPASS. Clone it: git clone https://github.com/mstarke/MacPass \"$MACPASS\""

# Delete shared schemes for platforms we don't build (iOS/tvOS/watchOS). These
# old projects ship several schemes that emit a same-named framework; Carthage
# builds them in parallel for --platform macOS and they race to write the same
# path in Carthage/Build/Mac, intermittently leaving an iOS or arm64-only build
# where the macOS framework should be. Removing them leaves one macOS scheme per
# framework. Re-run safe; runs again after each checkout restores the schemes.
prune_non_macos_schemes() {
  local checkouts="$1"
  log "pruning iOS/tvOS/watchOS schemes under $checkouts"
  find "$checkouts" -path "*/xcshareddata/xcschemes/*.xcscheme" \
    \( -iname "*iOS*" -o -iname "*tvOS*" -o -iname "*watchOS*" \) -print -delete || true
}

# ---------------------------------------------------------------------------
log "1/5  Building MacPass dependencies ($MACPASS)"
# Submodule (DDHotKey) + Carthage deps. We build only what the plugin needs
# (HNHUi, KeePassKit and its KissXML dep); TransformerKit fails to compile on a
# modern SDK (removed Darwin 'xlocale' module) and the plugin doesn't need it.
git -C "$MACPASS" submodule update --init --recursive
XCODE_XCCONFIG_FILE="$XCCONFIG" carthage checkout --project-directory "$MACPASS"
prune_non_macos_schemes "$MACPASS/Carthage/Checkouts"
XCODE_XCCONFIG_FILE="$XCCONFIG" carthage build HNHUi KeePassKit KissXML \
  --platform macOS --project-directory "$MACPASS"

# ---------------------------------------------------------------------------
log "2/5  Building MacPassHTTP dependencies"
"$ROOT/build-deps.sh"

# ---------------------------------------------------------------------------
log "3/5  Building the MacPassHTTP plugin ($CONFIG)"
# Command-line settings (highest precedence) override the project's stale values:
#   MACOSX_DEPLOYMENT_TARGET=10.13  project sets 10.10, too low -> libarclite link error
#   ARCHS=arm64                     match the arm64-only Carthage frameworks
#   FRAMEWORK_SEARCH_PATHS += MacPass build dir, so <HNHUi/..>, <KeePassKit/..>
#                                   resolve to the built frameworks, not source headers
#   CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES
#                                   the recursive HEADER_SEARCH_PATHS=../MacPass/**
#                                   pulls source headers into framework modules, which
#                                   -Werror would otherwise reject
XCODE_XCCONFIG_FILE="$XCCONFIG" xcodebuild \
  -project "$ROOT/MacPassHTTP.xcodeproj" -scheme MacPassHTTP -configuration "$CONFIG" \
  MACOSX_DEPLOYMENT_TARGET=10.13 ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  "FRAMEWORK_SEARCH_PATHS=\$(inherited) \$(PROJECT_DIR)/../MacPass/Carthage/Build/Mac" \
  CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES

[ -d "$PLUGIN" ] || die "build reported success but $PLUGIN is missing"

# The project's "Versioning" build phase stamps CFBundleVersion from the git
# commit count, but on a clean build it runs before Info.plist exists in the
# output and silently no-ops, leaving the "UNKNOWN" placeholder. Stamp it here
# (same logic as the build phase: Release = commit count) so it's deterministic.
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLUGIN/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$PLUGIN/Contents/Info.plist" 2>/dev/null || true

# ---------------------------------------------------------------------------
log "4/5  Embedding transitive frameworks into the plugin"
# The project embeds only KeePassHTTPKit.framework, but it dynamically links
# GCDWebServers and JSONModel (@rpath). KeePassHTTPKit declares an rpath of
# @loader_path/Frameworks, so place its deps there; otherwise the plugin fails
# to load. HNHUi/KeePassKit are NOT embedded on purpose — they resolve from the
# host MacPass.app via @executable_path/../Frameworks.
NESTED="$PLUGIN/Contents/Frameworks/KeePassHTTPKit.framework/Versions/A/Frameworks"
mkdir -p "$NESTED"
for fw in GCDWebServers JSONModel; do
  rm -rf "$NESTED/$fw.framework"
  cp -R "$ROOT/Carthage/Build/Mac/$fw.framework" "$NESTED/"
done

# ---------------------------------------------------------------------------
log "5/5  Code signing the plugin (id: $SIGN_ID)"
# MacPass refuses to load plugins that fail `codesign --verify` (the UI shows
# "Plugin is not properly signed"; see MPPluginHost.m -_isSignedPluginURL:).
# xcodebuild leaves the bundle with only the arm64 linker's ad-hoc signature,
# which has no sealed resources, and the steps above (Info.plist edit, framework
# copy) would invalidate any real signature anyway — so we sign LAST, inside-out:
# nested frameworks deepest-first, then the outer bundle, which seals everything
# into Contents/_CodeSignature/CodeResources. MacPass doesn't pin a signing
# anchor, so an ad-hoc signature is accepted.
while IFS= read -r fw; do
  codesign --force --sign "$SIGN_ID" "$fw" || die "failed to sign $fw"
done < <(find "$PLUGIN/Contents/Frameworks" -name "*.framework" -depth)

codesign --force --sign "$SIGN_ID" "$PLUGIN" || die "failed to sign $PLUGIN"

# Verify exactly as MacPass does before it loads the plugin.
codesign --verify --verbose "$PLUGIN" || die "codesign --verify failed for $PLUGIN"

log "Done. Installed plugin:"
echo "    $PLUGIN"
echo "    arch:    $(lipo -info "$PLUGIN/Contents/MacOS/MacPassHTTP" 2>/dev/null | sed 's/.*: //')"
echo "    version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLUGIN/Contents/Info.plist" 2>/dev/null)"
echo "Restart MacPass to load it."
