#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Selektos"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DMG_PATH="${1:-"$ROOT/dist/$APP_NAME-$VERSION.dmg"}"

if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "Set NOTARY_PROFILE to a notarytool keychain profile." >&2
    exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "Disk image not found: $DMG_PATH" >&2
    exit 1
fi

xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Notarized and stapled $DMG_PATH"
