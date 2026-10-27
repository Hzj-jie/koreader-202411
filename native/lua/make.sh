#!/bin/bash

readonly VERSION=a067bda2979a3b4642a812fe7bab264cc9a4f877

rm -rf lua-jit-5.5.1-$VERSION lua-jit-5.5.1-$VERSION-pw2 lua-jit-5.5.1.zip
wget "https://github.com/hzj-jie/lua-jit-5.5.1/archive/$VERSION.zip" -O lua-jit-5.5.1.zip
unzip lua-jit-5.5.1.zip
rm lua-jit-5.5.1.zip
cp -r lua-jit-5.5.1-$VERSION lua-jit-5.5.1-$VERSION-pw2

pushd lua-jit-5.5.1-$VERSION
make all
cp lua ../../../linux/lua
popd

pushd lua-jit-5.5.1-$VERSION-pw2
make CC="arm-linux-gnueabihf-gcc -std=gnu99 -static" \
     AR="arm-linux-gnueabihf-ar rcu" \
     RANLIB="arm-linux-gnueabihf-ranlib" \
     MYCFLAGS="-DLUA_USE_LINUX -march=armv7-a -mfpu=neon -mfloat-abi=hard" \
     all
popd
