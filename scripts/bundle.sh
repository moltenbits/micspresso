#!/bin/bash
set -euo pipefail

# Builds the Swift executable and assembles the Micspresso app bundle.
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

EXEC_NAME="micspresso"
BUILD_CONFIG="${1:-release}"
if [[ "$BUILD_CONFIG" != "debug" && "$BUILD_CONFIG" != "release" ]]; then
    echo "Usage: $0 [debug|release]" >&2
    exit 1
fi

# Signing identity, in order of preference:
#   1. Developer ID (TEAM_NAME + TEAM_ID set) — distribution builds.
#   2. $SIGN_IDENTITY — explicit override.
#   3. A local dev certificate — keeps the dev build's code-signing identity
#      stable across rebuilds so the microphone TCC grant sticks. Ad-hoc
#      signatures reduce to the binary's cdhash, which changes every build
#      and re-prompts every time.
#   4. Ad-hoc — fresh machines and CI.
DISTRIBUTION_SIGNING=false
if [[ -n "${TEAM_NAME:-}" && -n "${TEAM_ID:-}" ]]; then
    SIGN_IDENTITY="Developer ID Application: $TEAM_NAME ($TEAM_ID)"
    DISTRIBUTION_SIGNING=true
elif [[ -z "${SIGN_IDENTITY:-}" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Micspresso Dev"'; then
        SIGN_IDENTITY="Micspresso Dev"
    elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"Spacebar Dev"'; then
        SIGN_IDENTITY="Spacebar Dev"
    else
        SIGN_IDENTITY="-"
    fi
fi

# Dev builds are a fully separate app from the notarized release: distinct
# bundle name ("Micspresso Dev.app"), bundle identifier (.dev), and therefore
# TCC records, settings domain, and Launch Services entry. Reusing one bundle
# id across different signatures (ad-hoc / dev cert / Developer ID) leaves
# stale mismatched TCC entries that suppress prompts or block launches.
if [[ "$DISTRIBUTION_SIGNING" == true ]]; then
    APP_NAME="Micspresso"
else
    APP_NAME="Micspresso Dev"
fi

# Distribution builds carry the tag-derived version in both fields. Dev
# builds keep the plain latest-release version (CFBundleShortVersionString)
# and put a build timestamp — <YY>.<MM>.<DD>.<minute of day> — in
# CFBundleVersion, so About shows e.g. "1.0.0 (26.08.09.896)".
if [[ -z "${VERSION:-}" ]]; then
    if [[ "$DISTRIBUTION_SIGNING" == true ]]; then
        VERSION="$(git -C "$PROJECT_DIR" describe --tags --always --dirty 2>/dev/null | sed 's/^v//')"
    else
        BASE_VERSION="$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
        MINUTE_OF_DAY=$((10#$(date +%H) * 60 + 10#$(date +%M)))
        VERSION="${BASE_VERSION:-0.0.0}"
        BUILD="$(date +%y.%m.%d).${MINUTE_OF_DAY}"
    fi
fi
VERSION="${VERSION:-0.0.0-dev}"
BUILD="${BUILD:-$VERSION}"

echo "Building $APP_NAME ($BUILD_CONFIG, version $VERSION, build $BUILD)..."
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
# truth for --version.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$CONTENTS_DIR/Info.plist"

if [[ "$DISTRIBUTION_SIGNING" != true ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.moltenbits.micspresso.dev" \
        "$CONTENTS_DIR/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Micspresso Dev" "$CONTENTS_DIR/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Micspresso Dev" "$CONTENTS_DIR/Info.plist"
fi

if [[ -f "$RESOURCES_DIR/AppIcon.icns" ]]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$RESOURCES_DEST/AppIcon.icns"
fi

echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

ENTITLEMENTS="$RESOURCES_DIR/Micspresso.entitlements"
if [[ "$DISTRIBUTION_SIGNING" == true ]]; then
    echo "Signing app bundle with Developer ID: $SIGN_IDENTITY"
    # --options runtime + --timestamp are required for notarization; the
    # entitlements grant microphone access under the hardened runtime.
    codesign --force --deep \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
elif [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Signing app bundle (ad-hoc — mic permission will re-prompt on every rebuild)..."
    codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
else
    echo "Signing app bundle with local identity: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
fi

# Keep the build product out of Launch Services: it exists to be run from here
# or copied by `make install`. If it stays registered, Spotlight and launchers
# can resolve stale .build copies with their own TCC attribution.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "App bundle created: $APP_BUNDLE"
