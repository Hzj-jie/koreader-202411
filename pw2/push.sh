#!/bin/bash

if [ -z "$1" ]; then
  echo Need an address
  exit 1
fi

if [[ $1 == 192.* ]]; then
  TARGET=$1
elif [[ $1 == *.* ]]; then
  TARGET=192.168.$1
else
  TARGET=192.168.1.$1
fi

if [ -z "$(git status --porcelain)" ]; then
  ./clean.sh

  rsync -acvLK --no-o --no-g ../kindle/extensions/ root@$TARGET:/mnt/us/extensions/
  rsync -acvLK --no-o --no-g --exclude=lns.sh --exclude=push.sh --exclude=push-all.sh . root@$TARGET:/mnt/us/koreader/
else
  echo commit first
  git status
fi
