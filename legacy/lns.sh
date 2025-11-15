#!/bin/sh

../lns.sh

mv plugins/README .
mv plugins/backgroundrunner.koplugin .
rm -rf plugins/*
mv README plugins/
mv backgroundrunner.koplugin plugins/

ln -rs ../kindle/* .

rm -rf scripts
rm -rf settings
rm -rf web
rm -rf extensions

