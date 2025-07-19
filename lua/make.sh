#!/bin/bash

readonly VERSION=5.4.8

rm -rf lua-$VERSION lua-$VERSION-pw2 lua-$VERSION.tar.gz
wget "https://www.lua.org/ftp/lua-$VERSION.tar.gz"
tar xzf lua-$VERSION.tar.gz
rm lua-$VERSION.tar.gz
cp -r lua-$VERSION lua-$VERSION-pw2

pushd lua-$VERSION
make all test
popd

pushd lua-$VERSION-pw2
make PLAT="linux" \
     CC="arm-linux-gnueabihf-gcc -std=gnu99 -static" \
     AR="arm-linux-gnueabihf-ar rcu" \
     RANLIB="arm-linux-gnueabihf-ranlib" \
     MYCFLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=hard" \
     all
popd
