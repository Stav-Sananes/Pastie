#!/bin/bash
set -euo pipefail

APP_NAME="Pastie"
CONFIG="release"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_BIN_DIR="${ROOT_DIR}/.build/${CONFIG}"
OUT_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${OUT_DIR}/${APP_NAME}.app"
ZIP_PATH="${OUT_DIR}/${APP_NAME}.app.zip"

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

echo "Built ${APP_BUNDLE}"
echo "Packaged ${ZIP_PATH}"
