#!/bin/bash

if [ -z "$1" ]; then
  echo Need a target
  exit 1
fi

if [ -z "$2" ]; then
  echo Need a target folder
  exit 2
fi

for i in frontend/ui/data/onetime_migration.lua \
         frontend/ui/data/settings_migration.lua \
         frontend/ui/elements/avoid_flashing_ui.lua \
         frontend/ui/elements/flash_keyboard.lua \
         frontend/ui/elements/flash_ui.lua \
         frontend/ui/elements/screen_notification_menu_table.lua \
         frontend/ui/hook_container.lua \
         frontend/ui/otamanager.lua \
         frontend/ui/plugin/insert_menu.lua \
         frontend/ui/widget/buttondialogtitle.lua \
         frontend/userpatch.lua \
         plugins/gestures.koplugin/migration.lua \
         plugins/timesync.koplugin \
         plugins/weather.koplugin/settings.lua \
         zsync2 \
         spinning_zsync ; do
  echo "$2/koreader/$i"
done | xargs ssh root@$1 rm -rf

