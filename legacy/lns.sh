#!/bin/sh

../lns.sh

mv plugins/README .
rm -rf plugins/*
mv README plugins/

ln -rs ../kindle/* .

rm -rf scripts
rm -rf settings
rm -rf web
rm -rf extensions

