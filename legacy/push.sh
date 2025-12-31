#!/bin/bash

pushd ..
./clean.sh
./update-git-rev.sh
popd

rsync -avL /media/hzj_jie/Kindle/koreader/ /media/hzj_jie/Kindle/koreader.old/
rsync -avL . /media/hzj_jie/Kindle/koreader/

git checkout ../koreader/git-rev
