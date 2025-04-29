#!/bin/sh

../lns.sh

mv plugins/README .
rm -rf plugins/*
mv README plugins/

rm -rf scripts
rm -rf settings
rm -rf web

