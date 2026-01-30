#!/bin/bash

pushd ..
./clean.sh
./update-git-rev.sh
popd

rsync -acvLK --no-o --no-g --no-t --no-p --fsync --inplace /media/hzj_jie/Kindle/koreader/ /media/hzj_jie/Kindle/koreader.old/
rsync -acvLK --no-o --no-g --no-t --no-p --fsync --inplace . /media/hzj_jie/Kindle/koreader/

git checkout ../koreader/git-rev
