#!/bin/bash
set -euo pipefail

APP_NAME="Pastie"
CONFIG="release"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_BIN_DIR="${ROOT_DIR}/.build/${CONFIG}"
OUT_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${OUT_DIR}/${APP_NAME}.app"

cd "${ROOT_DIR}"
swift build -c "${CONFIG}"

rm -rf "${OUT_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_BIN_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

echo "Built ${APP_BUNDLE}"
