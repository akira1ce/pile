#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${1:-release}"

case "$CONFIGURATION" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

cd "$PROJECT_ROOT"
"$SCRIPT_DIR/build-app.sh" "$CONFIGURATION"

APP_BUNDLE="$PROJECT_ROOT/build/pile.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")"
DMG_PATH="$PROJECT_ROOT/build/pile-$VERSION.dmg"
STAGING_DIR="$PROJECT_ROOT/build/dmg-root"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_BUNDLE" "$STAGING_DIR/pile.app"
ln -s /Applications "$STAGING_DIR/Applications"

if ! diskutil image create from \
    --volumeName "pile" \
    --format UDZO \
    "$STAGING_DIR" "$DMG_PATH" >/dev/null 2>&1; then
    echo "Failed to create $DMG_PATH" >&2
    exit 1
fi

rm -rf "$STAGING_DIR"

echo "Built $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
