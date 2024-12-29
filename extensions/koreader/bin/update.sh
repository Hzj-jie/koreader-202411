#!/bin/sh

pushd /mnt/us/
wget -O - https://github.com/Hzj-jie/koreader-202411/archive/master.tar.gz | tar xz
cp -rl koreader-202411-master/koreader/ /mnt/us/koreader/
cp -rl koreader-202411-master/extensions/koreader/ /mnt/us/extensions/koreader/
rm -rf koreader-202411-master
popd
