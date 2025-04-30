#!/bin/bash

if [ -z "$1" ]; then
  echo Need an address
  exit 1
fi

if [ -z "$(git status --porcelain)" ]; then
  ./clean.sh

  rsync -acvLK --no-o --no-g extensions/ root@192.168.1.$1:/mnt/us/extensions/
  rsync -acvLK --no-o --no-g pw2/ root@192.168.1.$1:/mnt/us/koreader/
else
  echo commit first
  git status
fi
