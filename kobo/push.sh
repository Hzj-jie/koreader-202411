#!/bin/sh

export KOREADER_DIR=/mnt/onboard/.adds/koreader
rsync --rsync-path=$KOREADER_DIR -acvLK --no-o --no-g --exclude=lns.sh . root@192.168.1.16:$KOREADER_DIR
