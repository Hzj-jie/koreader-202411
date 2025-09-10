#!/bin/bash

./compare-settings.sh $1 || { echo 'compare-settings.sh failed' ; exit 1; }

echo '*** WARNING ***'
echo Ensure the above diff is expected, except for certain fields, others
echo will all be overridden.
echo Press any key to continue.

read -n 1 -s

linux/luajit merge-settings.lua

echo '< new > device'
diff -w /tmp/settings.reader.new.lua /tmp/settings.reader.lua

echo '*** WARNING AGAIN ***'
echo Ensure the above diff is expected, right file will be overridden.
echo And shutdown koreader now, it overrides the settings during rebooting.
echo Press any key to continue.

read -n 1 -s

scp /tmp/settings.reader.new.lua root@192.168.1.$1:/mnt/us/koreader/settings.reader.lua
