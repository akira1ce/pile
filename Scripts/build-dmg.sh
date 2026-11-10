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
SPARKLE_BIN="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin"
KEY_ACCOUNT="com.akira1ce.pile"
if [[ "$CONFIGURATION" == "release" ]]; then
    if [[ ! -x "$SPARKLE_BIN/generate_keys" ]]; then
        echo "Run ./Scripts/setup-updates.sh once before packaging a release." >&2
        exit 1
    fi
    EXPECTED_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Resources/Info.plist)"
    ACTUAL_KEY="$("$SPARKLE_BIN/generate_keys" --account "$KEY_ACCOUNT" -p)"
    if [[ "$ACTUAL_KEY" != "$EXPECTED_KEY" ]]; then
        echo "Sparkle key does not match Resources/Info.plist. Restore the original keychain key." >&2
        exit 1
    fi
fi
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

if [[ "$CONFIGURATION" == "release" ]]; then
    RELEASE_TAG="${PILE_RELEASE_TAG:-$VERSION}"
    if [[ "$RELEASE_TAG" != "$VERSION" && "$RELEASE_TAG" != "v$VERSION" ]]; then
        echo "PILE_RELEASE_TAG must be $VERSION or v$VERSION." >&2
        exit 1
    fi
    UPDATES_DIR="$PROJECT_ROOT/build/updates"
    rm -rf "$UPDATES_DIR"
    mkdir -p "$UPDATES_DIR"
    ditto "$DMG_PATH" "$UPDATES_DIR/pile-$VERSION.dmg"
    RELEASE_NOTES="$PROJECT_ROOT/docs/releases/$VERSION.md"
    if [[ -f "$RELEASE_NOTES" ]]; then
        cp "$RELEASE_NOTES" "$UPDATES_DIR/pile-$VERSION.md"
    fi
    "$SPARKLE_BIN/generate_appcast" \
        --account "$KEY_ACCOUNT" \
        --download-url-prefix "https://github.com/akira1ce/pile/releases/download/$RELEASE_TAG/" \
        --embed-release-notes \
        --maximum-deltas 0 \
        --link "https://akira1ce.github.io/pile/" \
        --full-release-notes-url "https://github.com/akira1ce/pile/releases/tag/$RELEASE_TAG" \
        "$UPDATES_DIR"
    python3 "$SCRIPT_DIR/validate-appcast.py" "$UPDATES_DIR/appcast.xml" "$DMG_PATH" >/dev/null
    "$SPARKLE_BIN/sign_update" --account "$KEY_ACCOUNT" --verify "$UPDATES_DIR/appcast.xml"
    echo "Staged signed update feed: $UPDATES_DIR/appcast.xml"
    echo "Upload $DMG_PATH to GitHub Release $RELEASE_TAG, then run ./Scripts/publish-updates.sh."
fi
