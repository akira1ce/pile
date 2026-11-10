#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPARKLE_BIN="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin"
KEY_ACCOUNT="com.akira1ce.pile"
APPCAST="$PROJECT_ROOT/build/updates/appcast.xml"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Resources/Info.plist")"
DMG_PATH="$PROJECT_ROOT/build/pile-$VERSION.dmg"

VALIDATED="$(python3 "$SCRIPT_DIR/validate-appcast.py" "$APPCAST" "$DMG_PATH")"
DOWNLOAD_URL="${VALIDATED%%$'\t'*}"
SIGNATURE="${VALIDATED#*$'\t'}"
"$SPARKLE_BIN/sign_update" --account "$KEY_ACCOUNT" --verify "$APPCAST"
"$SPARKLE_BIN/sign_update" --account "$KEY_ACCOUNT" --verify "$DMG_PATH" "$SIGNATURE"

# Verify the uploaded asset is exactly the archive we signed before announcing it.
REMOTE_DMG="$(mktemp "$PROJECT_ROOT/build/updates/.release-check.XXXXXX")"
trap 'rm -f "$REMOTE_DMG"' EXIT
curl --fail --location --silent --show-error "$DOWNLOAD_URL" --output "$REMOTE_DMG"
if ! cmp -s "$DMG_PATH" "$REMOTE_DMG"; then
    echo "The GitHub Release DMG differs from the signed local archive. Update feed was not published." >&2
    exit 1
fi

cp "$APPCAST" "$PROJECT_ROOT/site/appcast.xml"
echo "Updated site/appcast.xml for pile $VERSION. Commit and push it to deploy via GitHub Pages."
