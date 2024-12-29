#!/bin/sh

wget -O - https://github.com/Hzj-jie/koreader-202411/archive/master.tar.gz | tar xz "koreader-202411-master/koreader"
cp -rl koreader-202411-master/koreader/ koreader/
rm -rf koreader-202411-master
