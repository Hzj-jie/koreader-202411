#!/bin/bash

wget --header="Accept: application/vnd.github+json" \
     --header="X-GitHub-Api-Version: 2022-11-28" \
     'https://api.github.com/repos/Hzj-jie/koreader-202411/issues?labels=fix-pending&per_page=100' \
     -O- 2>/dev/null \
     | grep -e html_url.*issues -e title \
     | sed 's/": "/\t/g' \
     | cut -f 2 \
     | sed 's/",$//g' \
     | sed 's/https/\nhttps/g'
