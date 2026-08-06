#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP=".build/OpenNoteBatch.app"
BIN=".build/release/OpenNoteBatch"
SIGNING_IDENTITY="${OPENNOTE_BATCH_SIGNING_IDENTITY:-OpenNote Batch Development}"

login_keychain="$(security login-keychain | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
if ! security find-certificate -c "$SIGNING_IDENTITY" "$login_keychain" >/dev/null 2>&1 \
    || ! security find-key -l "$SIGNING_IDENTITY" -t private "$login_keychain" >/dev/null 2>&1; then
  echo "Signing identity not found: $SIGNING_IDENTITY" >&2
  echo "Run ./scripts/setup-local-signing.sh, or set OPENNOTE_BATCH_SIGNING_IDENTITY to an installed Apple signing identity." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/OpenNoteBatch"
cp "Support/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "Created $APP signed as $SIGNING_IDENTITY"
