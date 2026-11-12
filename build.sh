#!/usr/bin/env bash
# builds an unsigned OllieOS ipa (for Sideloadly / AltStore / SideStore / LiveContainer to sign)
#
# works on macOS (uses Xcode's toolchain and SDK) and Linux (clang + ld64.lld + an iPhoneOS SDK, see SDK_PATH)
#
# environment:
#   OLLIEOS_REF   upstream branch, tag or commit to build (default: main)
#   OLLIEOS_DIR   use an existing local ollieos checkout instead of cloning (its node_modules are used as-is)
#   OLLIEOS_REPO  upstream git url
#   BUNDLE_ID     app bundle identifier (default: codes.ollieg.ollieos)
#   SDK_PATH      linux only, path to iPhoneOS.sdk (default: ~/sdk/sdks/iPhoneOS16.5.sdk)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
UPSTREAM_DIR="$BUILD_DIR/ollieos"
WWW_STAGING_DIR="$BUILD_DIR/www"

OLLIEOS_REPO="${OLLIEOS_REPO:-https://github.com/obfuscatedgenerated/obfuscatedgenerated.github.io.git}"
OLLIEOS_REF="${OLLIEOS_REF:-main}"
BUNDLE_ID="${BUNDLE_ID:-codes.ollieg.ollieos}"
APP_NAME="OllieOS"
MIN_IOS="15.0"

FRAMEWORKS=(
    Foundation UIKit WebKit SafariServices CoreGraphics
    AVFoundation Contacts CoreLocation CoreMotion EventKit GameController LocalAuthentication
    Network PhotosUI Security UniformTypeIdentifiers UserNotifications
)

mkdir -p "$BUILD_DIR"

echo "==> fetching ollieos ($OLLIEOS_REF)"
if [ -n "${OLLIEOS_DIR:-}" ]; then
    rm -rf "$UPSTREAM_DIR"
    ln -sfn "$(cd "$OLLIEOS_DIR" && pwd)" "$UPSTREAM_DIR"
    if [ ! -d "$UPSTREAM_DIR/node_modules" ]; then
        (cd "$UPSTREAM_DIR" && npm ci --no-audit --no-fund)
    fi
else
    if [ ! -d "$UPSTREAM_DIR/.git" ]; then
        rm -rf "$UPSTREAM_DIR"
        git clone --quiet "$OLLIEOS_REPO" "$UPSTREAM_DIR"
    fi
    git -C "$UPSTREAM_DIR" fetch --quiet origin "$OLLIEOS_REF"
    git -C "$UPSTREAM_DIR" checkout --quiet --force FETCH_HEAD
    (cd "$UPSTREAM_DIR" && npm ci --no-audit --no-fund)
fi

VERSION="$(node -p "require('$UPSTREAM_DIR/package.json').version")"

echo "==> building upstream pages and assets (v$VERSION)"
(cd "$UPSTREAM_DIR" && npx webpack --mode=production && npm run generate-licenses)

echo "==> type checking app code"
node "$UPSTREAM_DIR/node_modules/typescript/bin/tsc" -p "$SCRIPT_DIR/web/tsconfig.json"

echo "==> bundling app boot entry"
rm -rf "$WWW_STAGING_DIR"
mkdir -p "$WWW_STAGING_DIR"
for page in index.html 404.html privacy.html LICENSE; do
    [ -f "$UPSTREAM_DIR/$page" ] && cp "$UPSTREAM_DIR/$page" "$WWW_STAGING_DIR/"
done
cp -r "$UPSTREAM_DIR/public" "$UPSTREAM_DIR/fsedit" "$UPSTREAM_DIR/recover_fs" "$WWW_STAGING_DIR/"

# replace upstream's scripts with the app's own build (main entry is ours, fsedit is upstream's)
rm -rf "$WWW_STAGING_DIR/public/script"
node "$UPSTREAM_DIR/node_modules/webpack-cli/bin/cli.js" \
    --config "$SCRIPT_DIR/web/webpack.config.js" \
    --env output_dir="$WWW_STAGING_DIR/public/script"
cp "$UPSTREAM_DIR/public/script/3rdpartylicenses.txt" "$WWW_STAGING_DIR/public/script/"
find "$WWW_STAGING_DIR" -name '*.map' -delete

echo "==> compiling native code"
APP_DIR="$BUILD_DIR/Payload/$APP_NAME.app"
rm -rf "$BUILD_DIR/Payload" "$BUILD_DIR/obj"
mkdir -p "$APP_DIR" "$BUILD_DIR/obj"

if [ "$(uname)" = "Darwin" ]; then
    SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
    CLANG=(xcrun --sdk iphoneos clang)
else
    SDK_PATH="${SDK_PATH:-$HOME/sdk/sdks/iPhoneOS16.5.sdk}"
    CLANG=(clang)
fi

OBJECT_FILES=()
for SOURCE_FILE in "$SCRIPT_DIR"/native/*.m; do
    OBJECT_FILE="$BUILD_DIR/obj/$(basename "${SOURCE_FILE%.m}").o"
    "${CLANG[@]}" -target "arm64-apple-ios$MIN_IOS" -isysroot "$SDK_PATH" \
        -fobjc-arc -fmodules -O2 -Wall -Wno-deprecated-declarations \
        -c "$SOURCE_FILE" -o "$OBJECT_FILE"
    OBJECT_FILES+=("$OBJECT_FILE")
done

FRAMEWORK_FLAGS=()
for FRAMEWORK in "${FRAMEWORKS[@]}"; do
    FRAMEWORK_FLAGS+=(-framework "$FRAMEWORK")
done

if [ "$(uname)" = "Darwin" ]; then
    "${CLANG[@]}" -target "arm64-apple-ios$MIN_IOS" -isysroot "$SDK_PATH" -dead_strip \
        "${OBJECT_FILES[@]}" "${FRAMEWORK_FLAGS[@]}" -o "$APP_DIR/$APP_NAME"
else
    LINKER="$(command -v ld64.lld-18 || command -v ld64.lld)"
    SDK_VERSION="$(basename "$SDK_PATH" | sed -E 's/[^0-9.]//g; s/\.$//')"
    "$LINKER" -arch arm64 -platform_version ios "$MIN_IOS" "${SDK_VERSION:-16.5}" \
        -syslibroot "$SDK_PATH" -dead_strip -lSystem -lobjc \
        "${OBJECT_FILES[@]}" "${FRAMEWORK_FLAGS[@]}" -o "$APP_DIR/$APP_NAME"
fi

echo "==> assembling app"
cp -r "$WWW_STAGING_DIR" "$APP_DIR/www"
cp "$SCRIPT_DIR/native/keyboard_accessory.js" "$APP_DIR/"
python3 "$SCRIPT_DIR/scripts/make_icons.py" "$UPSTREAM_DIR/public/logo.png" "$APP_DIR"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/g" -e "s/__MIN_IOS__/$MIN_IOS/" \
    "$SCRIPT_DIR/Info.plist" > "$APP_DIR/Info.plist"
printf 'APPL????' > "$APP_DIR/PkgInfo"

echo "==> packaging"
IPA_PATH="$BUILD_DIR/$APP_NAME-$VERSION.ipa"
rm -f "$IPA_PATH"
(cd "$BUILD_DIR" && zip -qr "$IPA_PATH" Payload)
echo "built $IPA_PATH"
