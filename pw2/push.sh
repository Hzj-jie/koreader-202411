#!/bin/bash

if [ -z "$1" ]; then
  echo Need an address
  exit 1
fi

if [[ $1 == *.*.*.* ]]; then
  TARGET=$1
elif [[ $1 == *.* ]]; then
  TARGET=192.168.$1
else
  TARGET=192.168.1.$1
fi

if [ -z "$(git status --porcelain)" ]; then
  pushd ..
  ./clean.sh
  ./update-git-rev.sh
  popd

  rsync -acvLK --no-o --no-g ../kindle/extensions/ root@$TARGET:/mnt/us/extensions/
  rsync -acvLK --no-o --no-g --exclude=lns.sh --exclude=push*.sh . root@$TARGET:/mnt/us/koreader/

  ssh root@$TARGET rm -rf frontend/ui/data/onetime_migration.lua frontend/ui/data/settings_migration.lua frontend/ui/elements/avoid_flashing_ui.lua frontend/ui/elements/flash_keyboard.lua frontend/ui/elements/flash_ui.lua frontend/ui/elements/screen_notification_menu_table.lua frontend/ui/hook_container.lua frontend/ui/otamanager.lua frontend/ui/plugin/insert_menu.lua frontend/ui/widget/buttondialogtitle.lua frontend/userpatch.lua plugins/gestures.koplugin/migration.lua plugins/timesync.koplugin

  git checkout ../koreader/git-rev
else
  echo commit first
  git status
fi
