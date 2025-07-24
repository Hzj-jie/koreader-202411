#!/bin/bash

readonly VERSION=1_8_0

rm -rf v$VERSION v$VERSOIN.tar.gz
wget "https://github.com/lunarmodules/luafilesystem/archive/refs/tags/v$VERSION.tar.gz"
tar xzf v$VERSION.tar.gz
rm v$VERSION.tar.gz

pushd luafilesystem-$VERSION
make LUA_VERSION=5.4
popd
