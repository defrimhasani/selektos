#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Selektos"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || printf '1')}"
ARCHS="${ARCHS:-$(uname -m)}"
CREATE_ARCHIVES="${CREATE_ARCHIVES:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
OUTPUT_DIR="${OUTPUT_DIR:-"$ROOT/dist"}"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_PATH="$APP_PATH/Contents"
EXECUTABLE_PATH="$CONTENTS_PATH/MacOS/$APP_NAME"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.zip"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "VERSION must contain two or three numeric components, such as 1.0.0." >&2
    exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "BUILD_NUMBER must be numeric, optionally with up to three components." >&2
    exit 1
fi

if [[ "$CREATE_ARCHIVES" != "0" && "$CREATE_ARCHIVES" != "1" ]]; then
    echo "CREATE_ARCHIVES must be 0 or 1." >&2
    exit 1
fi

if [[ ! -f "$ROOT/Distribution/Selektos.icns" ]]; then
    echo "Missing Distribution/Selektos.icns. Run 'make icon' first." >&2
    exit 1
fi

read -r -a requested_architectures <<< "$ARCHS"
if [[ ${#requested_architectures[@]} -eq 0 ]]; then
    echo "ARCHS must contain at least one architecture." >&2
    exit 1
fi

declare -a binaries=()
declare -a binary_directories=()

for architecture in "${requested_architectures[@]}"; do
    case "$architecture" in
        arm64|x86_64) ;;
        *)
            echo "Unsupported architecture: $architecture" >&2
            exit 1
            ;;
    esac

    triple="$architecture-apple-macosx"
    swift build \
        --package-path "$ROOT" \
        --configuration release \
        --product "$APP_NAME" \
        --triple "$triple"

    binary_directory="$(
        swift build \
            --package-path "$ROOT" \
            --configuration release \
            --triple "$triple" \
            --show-bin-path
    )"
    binary="$binary_directory/$APP_NAME"
    if [[ ! -x "$binary" ]]; then
        echo "Build did not produce $binary." >&2
        exit 1
    fi
    binaries+=("$binary")
    binary_directories+=("$binary_directory")
done

mkdir -p "$OUTPUT_DIR"
if [[ -e "$APP_PATH" ]]; then
    rm -rf -- "$APP_PATH"
fi
mkdir -p "$CONTENTS_PATH/MacOS" "$RESOURCES_PATH"

if [[ ${#binaries[@]} -eq 1 ]]; then
    /usr/bin/ditto "${binaries[0]}" "$EXECUTABLE_PATH"
else
    /usr/bin/lipo -create "${binaries[@]}" -output "$EXECUTABLE_PATH"
fi
chmod 755 "$EXECUTABLE_PATH"

/usr/bin/ditto "$ROOT/Distribution/Info.plist" "$CONTENTS_PATH/Info.plist"
/usr/bin/ditto "$ROOT/Distribution/Selektos.icns" "$RESOURCES_PATH/Selektos.icns"
/usr/bin/ditto "$ROOT/Distribution/PrivacyInfo.xcprivacy" "$RESOURCES_PATH/PrivacyInfo.xcprivacy"
printf 'APPL????' > "$CONTENTS_PATH/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_PATH/Info.plist"

while IFS= read -r -d '' bundle; do
    /usr/bin/ditto "$bundle" "$RESOURCES_PATH/$(basename "$bundle")"
done < <(find "${binary_directories[0]}" -maxdepth 1 -type d -name '*.bundle' -print0)

/usr/bin/plutil -lint "$CONTENTS_PATH/Info.plist" "$RESOURCES_PATH/PrivacyInfo.xcprivacy" >/dev/null

codesign_arguments=(--force --options runtime --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign_arguments+=(--timestamp=none)
else
    codesign_arguments+=(--timestamp)
fi
/usr/bin/codesign "${codesign_arguments[@]}" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

if [[ "$CREATE_ARCHIVES" == "1" ]]; then
    rm -f -- "$DMG_PATH" "$ZIP_PATH"
    (
        cd "$OUTPUT_DIR"
        /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$ZIP_PATH")"
    )

    staging_directory="$(mktemp -d "$OUTPUT_DIR/.Selektos-dmg.XXXXXX")"
    cleanup() {
        if [[ -n "${staging_directory:-}" && -d "$staging_directory" ]]; then
            rm -rf -- "$staging_directory"
        fi
    }
    trap cleanup EXIT

    /usr/bin/ditto "$APP_PATH" "$staging_directory/$APP_NAME.app"
    ln -s /Applications "$staging_directory/Applications"
    /usr/bin/hdiutil create \
        -volname "$APP_NAME $VERSION" \
        -srcfolder "$staging_directory" \
        -format UDZO \
        -ov \
        "$DMG_PATH" >/dev/null

    if [[ "$SIGNING_IDENTITY" != "-" ]]; then
        /usr/bin/codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
    fi
fi

echo "Created $APP_PATH"
if [[ "$CREATE_ARCHIVES" == "1" ]]; then
    echo "Created $DMG_PATH"
    echo "Created $ZIP_PATH"
fi
