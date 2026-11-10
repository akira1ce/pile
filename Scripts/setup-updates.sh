#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEY_ACCOUNT="com.akira1ce.pile"
SPARKLE_BIN="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin"

cd "$PROJECT_ROOT"
if [[ ! -x "$SPARKLE_BIN/generate_keys" ]]; then
    swift package resolve
fi

# generate_keys reuses an existing key; it never replaces it on subsequent runs.
"$SPARKLE_BIN/generate_keys" --account "$KEY_ACCOUNT" >/dev/null
PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" --account "$KEY_ACCOUNT" -p)"
python3 - "$PROJECT_ROOT/Resources/Info.plist" "$PUBLIC_KEY" <<'PY'
import base64
import pathlib
import plistlib
import sys

path = pathlib.Path(sys.argv[1])
key = sys.argv[2].strip()
if len(base64.b64decode(key, validate=True)) != 32:
    sys.exit("Invalid Sparkle public key")
with path.open("rb") as file:
    info = plistlib.load(file)
if info.get("SUPublicEDKey", key) != key:
    sys.exit("This machine's Sparkle key differs from the app's public key. Restore the original key; do not generate a replacement.")
info["SUPublicEDKey"] = key
with path.open("wb") as file:
    plistlib.dump(info, file, sort_keys=False)
PY

# The initial feed has no release items. Sign it so installed clients can check
# successfully before the first update is published. Never modify a live feed.
if python3 - "$PROJECT_ROOT/site/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
sys.exit(0 if not ET.parse(sys.argv[1]).findall("./channel/item") else 1)
PY
then
    "$SPARKLE_BIN/sign_update" --account "$KEY_ACCOUNT" "$PROJECT_ROOT/site/appcast.xml"
fi

echo "Sparkle public key configured in Resources/Info.plist."
echo "Private key stays in your login keychain (account: $KEY_ACCOUNT). Keep a secure backup of this key."
