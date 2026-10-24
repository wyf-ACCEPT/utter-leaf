#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/module-cache .local/swift-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.local/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.local/module-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.local/swift-cache"
DESTINATION="$PWD/.local/UtterLeaf.app"
STAGING_DIR="$(mktemp -d "$PWD/.local/UtterLeaf-stage.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP="$STAGING_DIR/UtterLeaf.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/prompts"
cp .build/release/UtterLeaf "$APP/Contents/MacOS/UtterLeaf"
cp App/Info.plist "$APP/Contents/Info.plist"
cp prompts/cleanup-v6-spoken-symbols.txt prompts/cleanup-v5.txt "$APP/Contents/Resources/prompts/"
mkdir -p "$APP/Contents/Resources/ThirdPartyNotices"
cp App/ThirdPartyNotices/*.txt "$APP/Contents/Resources/ThirdPartyNotices/"
mkdir -p "$APP/Contents/Resources/Sounds"
cp -R App/Sounds/. "$APP/Contents/Resources/Sounds/"
cp assets/brand/UtterLeaf.icns "$APP/Contents/Resources/UtterLeaf.icns"
SIGNING_IDENTITY="${UTTERLEAF_SIGNING_IDENTITY:--}"
if [ "$SIGNING_IDENTITY" = "-" ] && [ -f .local/signing-identity ]; then
    IFS= read -r SIGNING_IDENTITY < .local/signing-identity
fi
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --sign - --identifier network.utterleaf.personal "$APP"
    printf 'Signing: ad-hoc; permission grants may need renewal after rebuild.\n'
else
    codesign --force --sign "$SIGNING_IDENTITY" --identifier network.utterleaf.personal --timestamp=none --options runtime --entitlements App/UtterLeaf.entitlements "$APP"
    printf 'Signing: configured local development identity.\n'
fi
codesign --verify --deep --strict "$APP"
# Preserve the inode backing a running process until that process exits.
# Never overwrite or re-sign the installed executable in place.
PREVIOUS="$PWD/.local/UtterLeaf.previous.app"
if [ -e "$PREVIOUS" ]; then rm -rf "$PREVIOUS"; fi
if [ -e "$DESTINATION" ]; then mv "$DESTINATION" "$PREVIOUS"; fi
if ! mv "$APP" "$DESTINATION"; then
    if [ -e "$PREVIOUS" ]; then mv "$PREVIOUS" "$DESTINATION"; fi
    exit 1
fi
printf 'Built: %s\n' "$DESTINATION"
