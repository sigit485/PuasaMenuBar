#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE_PATH="${1:-${PROJECT_ROOT}/PuasaMenuBar.app}"
AGENT_LABEL="com.admin.PuasaMenuBar.autostart"
PLIST_PATH="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"

if [[ ! -d "${APP_BUNDLE_PATH}" ]]; then
  echo "App bundle not found: ${APP_BUNDLE_PATH}" >&2
  echo "Build it first with: ${PROJECT_ROOT}/scripts/build_app_bundle.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "${PLIST_PATH}")"

cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${AGENT_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>${APP_BUNDLE_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "${PLIST_PATH}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}"
launchctl enable "gui/$(id -u)/${AGENT_LABEL}"
launchctl kickstart -k "gui/$(id -u)/${AGENT_LABEL}" >/dev/null 2>&1 || true

echo "Auto-start installed."
echo "LaunchAgent: ${PLIST_PATH}"
