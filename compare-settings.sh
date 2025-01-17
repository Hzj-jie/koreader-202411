#!/bin/bash

if [ -z "$1" ]; then
  echo Need an address
  exit 1
fi

scp root@192.168.1.$1:/mnt/us/koreader/settings.reader.lua /tmp/
echo '< local  > device'
diff settings.reader.lua /tmp/settings.reader.lua
