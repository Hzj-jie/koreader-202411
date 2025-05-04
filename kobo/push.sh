#!/bin/sh

rsync -acvLK --no-o --no-g --exclude=lns.sh . root@192.168.1.16:/mnt/onboard/.adds/koreader
