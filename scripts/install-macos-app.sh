#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD/.local/UtterLeaf.app"
DESTINATION="/Applications/UtterLeaf.app"
REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ ! -d "$SOURCE" ]; then
    printf 'Build the app with scripts/build-app.sh first.\n' >&2
    exit 1
fi
codesign --verify --deep --strict "$SOURCE"
if pgrep -f '/UtterLeaf.app/Contents/MacOS/UtterLeaf' >/dev/null; then
    printf 'Quit UtterLeaf before installing to avoid interrupting recording.\n' >&2
    exit 1
fi
STAGING="$(mktemp -d /Applications/.UtterLeaf-install.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
/usr/bin/ditto "$SOURCE" "$STAGING/UtterLeaf.app"
codesign --verify --deep --strict "$STAGING/UtterLeaf.app"
BACKUP=""
if [ -e "$DESTINATION" ]; then
    mkdir -p .local/install-backups
    BACKUP="$PWD/.local/install-backups/UtterLeaf-$(date +%Y%m%d-%H%M%S)-$$.app"
    "$REGISTER" -u "$DESTINATION" || true
    mv "$DESTINATION" "$BACKUP"
fi
if ! mv "$STAGING/UtterLeaf.app" "$DESTINATION"; then
    if [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then mv "$BACKUP" "$DESTINATION"; fi
    exit 1
fi
for OLD in "$SOURCE" "$PWD/.local/UtterLeaf.previous.app" "$PWD/.local/mac-cloud-profile-build/Build/Products/Release/CloudSigningHost.app"; do
    if [ -d "$OLD" ]; then "$REGISTER" -u "$OLD" || true; fi
done
"$REGISTER" -f "$DESTINATION"
printf 'Installed: %s\n' "$DESTINATION"
printf 'Launch this copy from Applications. Recording/history remain in Application Support/UtterLeaf.\n'
