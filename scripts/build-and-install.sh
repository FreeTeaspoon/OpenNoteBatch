#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${OPENNOTE_BATCH_APPLICATIONS_DIR:-/Applications}"
APP_NAME="OpenNoteBatch.app"
BUILT_APP="$ROOT/.build/$APP_NAME"
TARGET_APP="$INSTALL_DIR/$APP_NAME"
BACKUP_DIR="$ROOT/.build/previous-installs"
STAGING_APP="$INSTALL_DIR/.OpenNoteBatch.app.install.$$"
BACKUP_APP=""

cleanup() {
    if [[ -n "$STAGING_APP" && ( -e "$STAGING_APP" || -L "$STAGING_APP" ) ]]; then
        rm -rf "$STAGING_APP"
    fi
}
trap cleanup EXIT

cd "$ROOT"

echo "Building and packaging OpenNote Batch..."
./scripts/package-app.sh

if [[ ! -d "$BUILT_APP" ]]; then
    echo "The package script did not create $BUILT_APP" >&2
    exit 1
fi

if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "Install directory does not exist: $INSTALL_DIR" >&2
    exit 1
fi

if [[ ! -w "$INSTALL_DIR" ]]; then
    echo "Install directory is not writable: $INSTALL_DIR" >&2
    echo "Set OPENNOTE_BATCH_APPLICATIONS_DIR to a writable Applications directory and try again." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"
rm -rf "$STAGING_APP"

echo "Copying the signed app to $INSTALL_DIR..."
ditto "$BUILT_APP" "$STAGING_APP"

if [[ -e "$TARGET_APP" || -L "$TARGET_APP" ]]; then
    BACKUP_APP="$BACKUP_DIR/OpenNoteBatch.app.$(date +%Y%m%d-%H%M%S)-$$"
    mv "$TARGET_APP" "$BACKUP_APP"
fi

if ! mv "$STAGING_APP" "$TARGET_APP"; then
    echo "Could not replace $TARGET_APP; restoring the previous app." >&2
    if [[ -n "$BACKUP_APP" && -d "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$TARGET_APP"
    fi
    exit 1
fi
STAGING_APP=""

if ! codesign --verify --deep --strict "$TARGET_APP"; then
    echo "The installed app failed signature verification; restoring the previous app." >&2
    rm -rf "$TARGET_APP"
    if [[ -n "$BACKUP_APP" && -d "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$TARGET_APP"
    fi
    exit 1
fi

echo "Installed: $TARGET_APP"
if [[ -n "$BACKUP_APP" ]]; then
    echo "Previous app backup: $BACKUP_APP"
fi
echo "Relaunch OpenNote Batch to use the new build."
