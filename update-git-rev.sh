#!/bin/bash

echo v > git-rev-tmp
date '+%Y.%m-%d' >> git-rev-tmp
echo - >> git-rev-tmp
git show --summary  | head -n 1 | sed 's/commit //g' >> git-rev-tmp

cat git-rev-tmp | tr -d '\n' > koreader/git-rev
rm git-rev-tmp
