#!/bin/bash
set -euo pipefail

APP_NAME="Pastie"
CONFIG="release"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_BIN_DIR="${ROOT_DIR}/.build/${CONFIG}"
OUT_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${OUT_DIR}/${APP_NAME}.app"
ZIP_PATH="${OUT_DIR}/${APP_NAME}.app.zip"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT_DIR}/Resources/Info.plist")"
DMG_PATH="${OUT_DIR}/${APP_NAME}-${VERSION}.dmg"
DMG_STAGE="${OUT_DIR}/dmg-stage"

# Signing identity. Defaults to "-", an ad-hoc signature, which is what an unpaid
# developer can produce: it satisfies arm64's requirement that every binary be signed,
# but it is NOT a Developer ID, so Gatekeeper still blocks a downloaded copy until the
# user allows it in System Settings (see the README). Once an Apple Developer Program
# membership exists, set SIGN_IDENTITY to the "Developer ID Application: ..." identity
# and add a notarytool submission after this script.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "${ROOT_DIR}"
swift build -c "${CONFIG}"

rm -rf "${OUT_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_BIN_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

codesign --force --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
codesign --verify --verbose "${APP_BUNDLE}"

# ditto rather than zip: it preserves the bundle's symlinks, extended attributes and
# code signature, which a plain `zip` mangles badly enough to break the signature.
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

# The DMG is the primary download: open it, drag Pastie onto the Applications shortcut, eject.
# Staging a folder with the bundle plus a symlink to /Applications is what gives the Finder
# window its drag target. UDZO is the compressed read-only format every downloadable DMG uses.
# The staged copy is `ditto`'d rather than `cp -R`'d for the same reason the zip is: it keeps
# the signature intact.
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
ditto "${APP_BUNDLE}" "${DMG_STAGE}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGE}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGE}" -ov -format UDZO -quiet "${DMG_PATH}"
rm -rf "${DMG_STAGE}"

echo "Built ${APP_BUNDLE}"
echo "Packaged ${ZIP_PATH}"
echo "Packaged ${DMG_PATH}"
