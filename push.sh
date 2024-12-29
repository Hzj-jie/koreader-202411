#!/bin/bash

if [ -z "$1" ]; then
  echo Need an address
  exit 1
fi

./clean.sh

rsync -acv --no-o --no-g --exclude='.*.un~' extensions/ root@192.168.1.$1:/mnt/us/extensions/
rsync -acv --no-o --no-g --exclude='.*.un~' koreader/ root@192.168.1.$1:/mnt/us/koreader/
