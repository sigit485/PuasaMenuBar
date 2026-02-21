#!/usr/bin/env bash
set -euo pipefail

AGENT_LABEL="com.admin.PuasaMenuBar.autostart"
PLIST_PATH="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"

launchctl bootout "gui/$(id -u)" "${PLIST_PATH}" >/dev/null 2>&1 || true
launchctl disable "gui/$(id -u)/${AGENT_LABEL}" >/dev/null 2>&1 || true

if [[ -f "${PLIST_PATH}" ]]; then
  rm -f "${PLIST_PATH}"
fi

echo "Auto-start removed."
