#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${1:-debug}"

case "$CONFIGURATION" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

cd "$PROJECT_ROOT"
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
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
