#!/bin/sh

../pw2/lns.sh

# no front light
rm -rf plugins/autodim.koplugin/
rm -rf plugins/autofrontlight.koplugin/

# kindle has built-in auto suspend
rm -rf plugins/autostandby.koplugin/
rm -rf plugins/autosuspend.koplugin/

# DXG has no wifi, may be enabled for kindle 4.
rm -rf plugins/calibre.koplugin/
rm -rf plugins/httpinspector.koplugin/
rm -rf plugins/kosync.koplugin/
rm -rf plugins/newsdownloader.koplugin/
rm -rf plugins/opds.koplugin/
rm -rf plugins/SSH.koplugin/
rm -rf plugins/wallabag.koplugin/
rm -rf plugins/weather.koplugin/

rm -rf settings/weather.lua
rm -rf web

# No touch screen
rm -rf plugins/gestures.koplugin/

# issue #323
rm -rf plugins/coverbrowser.koplugin/

# issue #325
rm -rf plugins/terminal.koplugin/

