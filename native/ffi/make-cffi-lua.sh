#!/bin/bash

readonly CFFI_LUA_VERSION=1fc4dc887ff6e5ee1e11acb293179b7ce08eb7d6
rm -rf cffi-lua-$CFFI_LUA_VERSION cffi-lua.zip
wget https://github.com/hzj-jie/cffi-lua/archive/$CFFI_LUA_VERSION.zip -O cffi-lua.zip
unzip cffi-lua.zip
rm cffi-lua.zip
pushd cffi-lua-$CFFI_LUA_VERSION
mkdir build
pushd build
meson -Dlua_version=5.4 ..
ninja all
cp cffi.so ../../../../linux/ffi.so
popd
popd
