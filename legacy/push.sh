#!/bin/sh

../update-git-rev.sh
rm -rf /media/hzj_jie/Kindle/koreader.old/
mv /media/hzj_jie/Kindle/koreader /media/hzj_jie/Kindle/koreader.old
cp -rL . /media/hzj_jie/Kindle/koreader/
cp -r --update=none /media/hzj_jie/Kindle/koreader.old/* /media/hzj_jie/Kindle/koreader/
