#!/bin/sh

export KOREADER_DIR=/mnt/onboard/.adds/koreader
rsync -e "ssh -o HostKeyAlgorithms=ecdsa-sha2-nistp256" --rsync-path=$KOREADER_DIR/rsync -acvLK --no-o --no-g --exclude=lns.sh . root@192.168.1.16:$KOREADER_DIR
