#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PuasaMenuBar"
BUNDLE_ID="com.admin.PuasaMenuBar"
APP_BUNDLE_PATH="${PROJECT_ROOT}/${APP_NAME}.app"
RELEASE_BINARY_PATH="${PROJECT_ROOT}/.build/release/${APP_NAME}"
MODULE_CACHE_PATH="${PROJECT_ROOT}/.build/ModuleCache"

echo "Building ${APP_NAME} (release)..."
cd "${PROJECT_ROOT}"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_PATH}" \
SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_PATH}" \
swift build -c release

if [[ ! -f "${RELEASE_BINARY_PATH}" ]]; then
  echo "Release binary not found at ${RELEASE_BINARY_PATH}" >&2
  exit 1
fi

echo "Creating app bundle at ${APP_BUNDLE_PATH}..."
rm -rf "${APP_BUNDLE_PATH}"
mkdir -p "${APP_BUNDLE_PATH}/Contents/MacOS"

cp "${RELEASE_BINARY_PATH}" "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE_PATH}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>PuasaMenuBar membutuhkan lokasi untuk mengisi kota dan negara secara otomatis.</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  echo "Applying ad-hoc code signature..."
  codesign --force --deep --sign - "${APP_BUNDLE_PATH}" >/dev/null 2>&1 || true
fi

echo "Done."
echo "Open app with:"
echo "  open \"${APP_BUNDLE_PATH}\""
