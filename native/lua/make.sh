#!/bin/bash

readonly VERSION=48b78835287cf04bb9d323c92ea7a85ea6aeae66

rm -rf lua-jit-5.5.1-$VERSION lua-jit-5.5.1-$VERSION-pw2 lua-jit-5.5.1.zip
wget "https://github.com/hzj-jie/lua-jit-5.5.1/archive/$VERSION.zip" -O lua-jit-5.5.1.zip
unzip lua-jit-5.5.1.zip
rm lua-jit-5.5.1.zip
cp -r lua-jit-5.5.1-$VERSION lua-jit-5.5.1-$VERSION-pw2

pushd lua-jit-5.5.1-$VERSION
make MYLDFLAGS="-Wl,-E -Wl,-rpath,'\$\$ORIGIN:\$\$ORIGIN/libs' -Wl,--disable-new-dtags" all
cp lua ../../../linux/lua
cp luac ../../../linux/luac
popd

pushd lua-jit-5.5.1-$VERSION-pw2
make CC="arm-linux-gnueabihf-gcc -std=gnu99 -static" \
     AR="arm-linux-gnueabihf-ar rcu" \
     RANLIB="arm-linux-gnueabihf-ranlib" \
     MYCFLAGS="-DLUA_USE_LINUX -march=armv7-a -mfpu=neon -mfloat-abi=hard" \
     all
popd
