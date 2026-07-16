#!/usr/bin/env bash
#
# Build, notarize, staple and package a release build of Translate Menu.
#
# Usage:  scripts/release.sh 1.2.3
#
# Prerequisites (one-time, see README "Cutting a release"):
#   - A "Developer ID Application" certificate in the login keychain
#   - A notarytool keychain profile named "notary":
#       xcrun notarytool store-credentials notary --apple-id <you> --team-id <TEAM> --password <app-specific-password>
#
# Every flag below is load-bearing. See the comments before removing any.

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: $0 <version>   (e.g. $0 1.2.3)" >&2
    exit 2
fi

PROJECT="Translate Menu.xcodeproj"
SCHEME="Translate Menu"
APP_NAME="Translate Menu.app"
BUILD_DIR="$(mktemp -d)"
ZIP="TranslateMenu-${VERSION}.zip"
KEYCHAIN_PROFILE="notary"

# This machine's xcode-select may point at CommandLineTools, where xcodebuild
# does not exist. Prefer a real Xcode if one is installed.
if [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "==> Checking the version in the project matches $VERSION"
PROJECT_VERSION=$(grep -m1 'MARKETING_VERSION' "$PROJECT/project.pbxproj" | sed 's/.*= *//; s/;//')
if [[ "$PROJECT_VERSION" != "$VERSION" ]]; then
    echo "error: MARKETING_VERSION is $PROJECT_VERSION but you asked for $VERSION." >&2
    echo "       Bump MARKETING_VERSION in both build configurations first." >&2
    exit 1
fi

echo "==> Checking for a Developer ID Application certificate"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "error: no 'Developer ID Application' certificate found in the keychain." >&2
    echo "       Without it the app is only ad-hoc signed and Gatekeeper will reject it" >&2
    echo "       on other people's Macs. Create one at developer.apple.com under" >&2
    echo "       Certificates > + > Developer ID Application, then download and open it." >&2
    exit 1
fi

echo "==> Building $VERSION (universal, hardened runtime)"
# -destination 'generic/platform=macOS' is what makes this universal. Without it
# xcodebuild builds only the host architecture, which is how v1.2.1 shipped
# arm64-only and left Intel Macs unable to run it.
#
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO strips com.apple.security.get-task-allow,
# the debug entitlement that lets a debugger attach. v1.2.1 shipped with it.
# Notarization rejects hardened-runtime builds that carry it.
#
# ENABLE_HARDENED_RUNTIME=YES and --timestamp are both required by notarization.
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    clean build \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    | tail -3

APP="$BUILD_DIR/$APP_NAME"

echo "==> Verifying the build before shipping it"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Translate Menu")
echo "    architectures: $ARCHS"
for required in x86_64 arm64; do
    if [[ "$ARCHS" != *"$required"* ]]; then
        echo "error: $required missing — this build is not universal." >&2
        exit 1
    fi
done

if codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - | grep -q "get-task-allow"; then
    echo "error: the app carries com.apple.security.get-task-allow (debug entitlement)." >&2
    echo "       Notarization will reject this. Is CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO set?" >&2
    exit 1
fi

BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
    echo "error: built app reports version $BUILT_VERSION, expected $VERSION." >&2
    exit 1
fi
echo "    version:       $BUILT_VERSION"
echo "    signature:     $(codesign -dv --verbose=2 "$APP" 2>&1 | grep '^Authority' | head -1 | sed 's/Authority=//')"

echo "==> Packaging"
# ditto, not `zip` — it preserves the bundle's symlinks and extended attributes.
( cd "$BUILD_DIR" && ditto -c -k --keepParent "$APP_NAME" "$ZIP" )

echo "==> Submitting to Apple for notarization (this usually takes 1-5 minutes)"
xcrun notarytool submit "$BUILD_DIR/$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "==> Stapling the notarization ticket to the app"
# Staple the .app, then re-zip: the ticket attaches to the bundle, not the zip,
# so the zip submitted above does not contain it.
xcrun stapler staple "$APP"
rm -f "$BUILD_DIR/$ZIP"
( cd "$BUILD_DIR" && ditto -c -k --keepParent "$APP_NAME" "$ZIP" )

echo "==> Verifying Gatekeeper accepts the stapled app"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"

cp "$BUILD_DIR/$ZIP" "./$ZIP"
echo
echo "Done: ./$ZIP"
echo "Attach it with:  gh release create v$VERSION ./$ZIP --title \"v$VERSION\" --notes-file <notes.md>"
