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

  ssh root@$TARGET rm -rf /mnt/us/koreader/frontend/ui/data/onetime_migration.lua /mnt/us/koreader/frontend/ui/data/settings_migration.lua /mnt/us/koreader/frontend/ui/elements/avoid_flashing_ui.lua /mnt/us/koreader/frontend/ui/elements/flash_keyboard.lua /mnt/us/koreader/frontend/ui/elements/flash_ui.lua /mnt/us/koreader/frontend/ui/elements/screen_notification_menu_table.lua /mnt/us/koreader/frontend/ui/hook_container.lua /mnt/us/koreader/frontend/ui/otamanager.lua /mnt/us/koreader/frontend/ui/plugin/insert_menu.lua /mnt/us/koreader/frontend/ui/widget/buttondialogtitle.lua /mnt/us/koreader/frontend/userpatch.lua /mnt/us/koreader/plugins/gestures.koplugin/migration.lua /mnt/us/koreader/plugins/timesync.koplugin

  git checkout ../koreader/git-rev
else
  echo commit first
  git status
fi
