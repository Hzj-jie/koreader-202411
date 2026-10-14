#!/bin/bash
set -eo pipefail

if [ -z "$1" ]; then
  echo "Usage: $0 <target_host> <target_folder>"
  echo "Error: Missing target host."
  exit 1
fi

if [ -z "$2" ]; then
  echo "Usage: $0 <target_host> <target_folder>"
  echo "Error: Missing target folder."
  exit 2
fi

TARGET="$1"
TARGET_DIR="${2%/}"

REMOVED_FILES=(
  "frontend/ui/data/onetime_migration.lua"
  "frontend/ui/data/settings_migration.lua"
  "frontend/ui/elements/avoid_flashing_ui.lua"
  "frontend/ui/elements/flash_keyboard.lua"
  "frontend/ui/elements/flash_ui.lua"
  "frontend/ui/elements/screen_notification_menu_table.lua"
  "frontend/ui/hook_container.lua"
  "frontend/ui/otamanager.lua"
  "frontend/ui/plugin/insert_menu.lua"
  "frontend/ui/widget/buttondialogtitle.lua"
  "frontend/userpatch.lua"
  "plugins/gestures.koplugin/migration.lua"
  "plugins/timesync.koplugin"
  "plugins/weather.koplugin/settings.lua"
  "plugins/simpleui.koplugin"
  "plugins/kochess.koplugin"
  "zsync2"
  "spinning_zsync"
)

REMOTE_PATHS=()
for item in "${REMOVED_FILES[@]}"; do
  REMOTE_PATHS+=("${TARGET_DIR}/koreader/${item}")
done

ssh "root@${TARGET}" rm -rf -- "${REMOTE_PATHS[@]}"

