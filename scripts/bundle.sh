#!/bin/bash
set -euo pipefail

# Builds the Swift executable and assembles Micspresso.app.
#
# A real app bundle matters here: TCC tracks the microphone permission by
# bundle identifier + code signature, so upgrades keep their grant. Bare
# binaries get their permission orphaned whenever the binary path or
# signature changes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
RESOURCES_DIR="$PROJECT_DIR/Resources"

# Load .env (not committed) for signing config: TEAM_NAME, TEAM_ID
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/.env"
    set +a
fi

APP_NAME="Micspresso"
EXEC_NAME="micspresso"
BUILD_CONFIG="${1:-release}"

# When TEAM_NAME and TEAM_ID are both set, sign for distribution (hardened
# runtime + timestamp). Otherwise fall back to ad-hoc signing for local use.
SIGN_IDENTITY=""
if [[ -n "${TEAM_NAME:-}" && -n "${TEAM_ID:-}" ]]; then
    SIGN_IDENTITY="Developer ID Application: $TEAM_NAME ($TEAM_ID)"
fi

echo "Building $EXEC_NAME ($BUILD_CONFIG)..."
cd "$PROJECT_DIR"
swift build -c "$BUILD_CONFIG" --disable-sandbox

APP_BUNDLE="$BUILD_DIR/$BUILD_CONFIG/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DEST="$CONTENTS_DIR/Resources"

echo "Creating app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DEST"

cp "$BUILD_DIR/$BUILD_CONFIG/$EXEC_NAME" "$MACOS_DIR/$EXEC_NAME"
cp "$RESOURCES_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

# Stamp the version into the bundle. The binary reads it back at runtime
# (AppInfo.version), so CFBundleShortVersionString is the single source of
# truth for --version. Priority: $VERSION (set by release.sh from the tag),
# then git describe for traceable dev builds.
if [[ -z "${VERSION:-}" ]]; then
    VERSION="$(git -C "$PROJECT_DIR" describe --tags --always --dirty 2>/dev/null | sed 's/^v//')"
fi
VERSION="${VERSION:-0.0.0-dev}"
echo "Stamping version: $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS_DIR/Info.plist"

if [[ -f "$RESOURCES_DIR/AppIcon.icns" ]]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$RESOURCES_DEST/AppIcon.icns"
fi

echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

ENTITLEMENTS="$RESOURCES_DIR/Micspresso.entitlements"
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signing app bundle with: $SIGN_IDENTITY"
    # --options runtime + --timestamp are required for notarization; the
    # entitlements grant microphone access under the hardened runtime.
    codesign --force \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
    echo "Signing app bundle (ad-hoc, local use only)..."
    codesign --force \
        --entitlements "$ENTITLEMENTS" \
        --sign - \
        "$APP_BUNDLE"
fi

echo "App bundle created: $APP_BUNDLE"
