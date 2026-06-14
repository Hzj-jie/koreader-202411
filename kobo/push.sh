#!/bin/bash

pushd ..
./update-git-rev.sh
popd

export STORAGE_DIR=/mnt/onboard/.adds
export KOREADER_DIR=$STORAGE_DIR/koreader
rsync -e "ssh -o HostKeyAlgorithms=ecdsa-sha2-nistp256" --rsync-path=$KOREADER_DIR/rsync -acvLK --no-o --no-g --exclude=lns.sh . root@192.168.1.16:$KOREADER_DIR

../remove-removed-files.sh 192.168.1.16 $STORAGE_DIR

git checkout ../koreader/git-rev
