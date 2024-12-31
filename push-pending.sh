#!/bin/bash

if [ -z "$1" ]; then
  echo Need an address
  exit 1
fi

git diff origin/master --name-only | xargs -I{} scp -v {} root@192.168.1.$1:/mnt/us/{} 2>&1 | grep -v "debug1: "
