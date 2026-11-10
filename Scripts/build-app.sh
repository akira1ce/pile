#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${1:-debug}"
PILE_SIGN_IDENTITY="${PILE_SIGN_IDENTITY:-E4AA3D29A59D3306655EE1BCC796285EE8260AF2}"

case "$CONFIGURATION" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

cd "$PROJECT_ROOT"
if ! /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Resources/Info.plist >/dev/null 2>&1; then
    echo "Run ./Scripts/setup-updates.sh once to configure the Sparkle signing key." >&2
    exit 1
fi
mkdir -p ".build/clang-module-cache" ".build/swift-module-cache"
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
echo "Using macOS SDK: $MACOS_SDK_PATH"
BUILD_ARGS=(--disable-sandbox --sdk "$MACOS_SDK_PATH" -c "$CONFIGURATION" --product pile)
if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_ARGS+=(-debug-info-format none)
fi
CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-module-cache" \
SWIFT_MODULECACHE_PATH="$PROJECT_ROOT/.build/swift-module-cache" \
    swift build "${BUILD_ARGS[@]}"

APP_BUNDLE="$PROJECT_ROOT/build/pile.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp ".build/$CONFIGURATION/pile" "$APP_BUNDLE/Contents/MacOS/pile"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "Resources/PkgInfo" "$APP_BUNDLE/Contents/PkgInfo"
cp "icon/macos/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

SPARKLE_SOURCE="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_SOURCE" ]]; then
    echo "Sparkle framework not found after building: $SPARKLE_SOURCE" >&2
    exit 1
fi
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
ditto "$SPARKLE_SOURCE" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
SPARKLE_CONTENTS="$SPARKLE_FRAMEWORK/Versions/B"
# Sign inside out; retain Sparkle's helper entitlements.
for component in "$SPARKLE_CONTENTS/Autoupdate" "$SPARKLE_CONTENTS/Updater.app" "$SPARKLE_CONTENTS/XPCServices/"*.xpc; do
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$PILE_SIGN_IDENTITY" "$component"
done
codesign --force --options runtime --timestamp --sign "$PILE_SIGN_IDENTITY" "$SPARKLE_FRAMEWORK"
codesign --force --options runtime --timestamp --sign "$PILE_SIGN_IDENTITY" "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
