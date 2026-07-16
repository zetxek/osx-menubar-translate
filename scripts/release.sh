#!/usr/bin/env bash
#
# Build, notarize, staple and package a release build of Translate Menu.
#
# Usage:  scripts/release.sh 1.2.3            # signed + notarized (needs paid membership)
#         scripts/release.sh 1.2.3 --adhoc    # ad-hoc signed, NOT notarized
#
# Prerequisites for the default (notarized) path — see README "Cutting a release":
#   - An active Apple Developer Program membership
#   - A "Developer ID Application" certificate in the login keychain
#   - A notarytool keychain profile named "notary":
#       xcrun notarytool store-credentials notary --apple-id <you> --team-id <TEAM> --password <app-specific-password>
#
# --adhoc exists because the membership lapsed and notarization became
# impossible without it. An ad-hoc build is a real trade-off: Gatekeeper
# rejects it, so users must right-click -> Open the first time. It is how
# v1.2.1 and earlier shipped. Prefer the notarized path whenever the
# membership is active.
#
# Every flag below is load-bearing. See the comments before removing any.

set -euo pipefail

VERSION="${1:-}"
ADHOC=no
if [[ "${2:-}" == "--adhoc" ]]; then
    ADHOC=yes
fi

if [[ -z "$VERSION" ]]; then
    echo "usage: $0 <version> [--adhoc]   (e.g. $0 1.2.3)" >&2
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

if [[ "$ADHOC" == yes ]]; then
    SIGN_IDENTITY="-"
    # Hardened runtime is only meaningful alongside notarization, and enabling it
    # on an ad-hoc build buys nothing while risking launch failures.
    HARDENED=NO
    echo "==> Ad-hoc mode: the app will NOT be notarized."
    echo "    Gatekeeper will reject it and users must right-click -> Open the first"
    echo "    time. This matches how v1.2.1 shipped. Re-run without --adhoc once the"
    echo "    Apple Developer Program membership is active."
else
    SIGN_IDENTITY="Developer ID Application"
    HARDENED=YES
    echo "==> Checking for a Developer ID Application certificate"
    if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        echo "error: no 'Developer ID Application' certificate found in the keychain." >&2
        echo "       This needs an ACTIVE Apple Developer Program membership — an expired" >&2
        echo "       one drops you to a free 'Personal Team', which cannot create this" >&2
        echo "       certificate or notarize at all. Check developer.apple.com/account." >&2
        echo "" >&2
        echo "       To ship without notarization anyway (Gatekeeper will warn users):" >&2
        echo "           $0 $VERSION --adhoc" >&2
        exit 1
    fi
fi

echo "==> Building $VERSION (universal)"
# -destination 'generic/platform=macOS' is what makes this universal. Without it
# xcodebuild builds only the host architecture, which is how v1.2.1 shipped
# arm64-only and left Intel Macs unable to run it.
#
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO strips com.apple.security.get-task-allow,
# the debug entitlement that lets a debugger attach. v1.2.1 shipped with it.
# Notarization rejects hardened-runtime builds that carry it.
#
# ENABLE_HARDENED_RUNTIME=YES and --timestamp are both required by notarization.
# No `clean` action: CONFIGURATION_BUILD_DIR is a fresh mktemp dir every run, so
# the products are new by construction. Passing `clean` alongside -destination and
# a custom build dir also makes xcodebuild fail with "Supported platforms for the
# buildables in the current scheme is empty".
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    build \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ENABLE_HARDENED_RUNTIME="$HARDENED" \
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

if [[ "$ADHOC" == no ]]; then
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
else
    echo "==> Skipping notarization (--adhoc)"
    echo "    Recording what a user will actually hit, so it is not a surprise:"
    spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /' || true
fi

cp "$BUILD_DIR/$ZIP" "./$ZIP"
echo
echo "Done: ./$ZIP"
if [[ "$ADHOC" == yes ]]; then
    echo "NOTE: not notarized. Users must right-click -> Open the first time."
fi
echo "Attach it with:  gh release create v$VERSION ./$ZIP --title \"v$VERSION\" --notes-file <notes.md>"
