#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP=".build/OpenNoteBatch.app"
BIN=".build/release/OpenNoteBatch"
SIGNING_IDENTITY="${OPENNOTE_BATCH_SIGNING_IDENTITY:-OpenNote Batch Development}"
HELPER_NAME="OpenNoteBatchKeychain"
HELPER_SOURCE="Support/OpenNoteBatchKeychain.swift"
ICON_DOCUMENT="Support/AppIcon.icon"
HELPER_CACHE_DIR="${OPENNOTE_BATCH_HELPER_CACHE_DIR:-$HOME/Library/Application Support/OpenNoteBatch}"
HELPER_CACHE="$HELPER_CACHE_DIR/$HELPER_NAME"

login_keychain="$(security login-keychain | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
if ! security find-certificate -c "$SIGNING_IDENTITY" "$login_keychain" >/dev/null 2>&1 \
    || ! security find-key -l "$SIGNING_IDENTITY" -t private "$login_keychain" >/dev/null 2>&1; then
  echo "Signing identity not found: $SIGNING_IDENTITY" >&2
  echo "Run ./scripts/setup-local-signing.sh, or set OPENNOTE_BATCH_SIGNING_IDENTITY to an installed Apple signing identity." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenNoteBatch"
cp "Support/Info.plist" "$APP/Contents/Info.plist"
xcrun actool "$ICON_DOCUMENT" \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --output-partial-info-plist ".build/OpenNoteBatch-assetcatalog-info.plist" \
  --output-format human-readable-text \
  --warnings \
  --notices
ditto "$ICON_DOCUMENT" "$APP/Contents/Resources/AppIcon.icon"

if [[ -x "$HELPER_CACHE" ]] && codesign --verify --strict "$HELPER_CACHE" >/dev/null 2>&1; then
  cp "$HELPER_CACHE" "$APP/Contents/Helpers/$HELPER_NAME"
else
  swiftc -O -framework Security -o "$APP/Contents/Helpers/$HELPER_NAME" "$HELPER_SOURCE"
  codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/$HELPER_NAME"
  mkdir -p "$HELPER_CACHE_DIR"
  cp "$APP/Contents/Helpers/$HELPER_NAME" "$HELPER_CACHE"
fi

codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "Created $APP signed as $SIGNING_IDENTITY (stable Keychain helper: $HELPER_CACHE)"
