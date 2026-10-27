#!/bin/bash

readonly CFFI_LUA_VERSION=bc4e0558f89e6ef218452c5c90cbf39697c5bf14
rm -rf cffi-lua-$CFFI_LUA_VERSION cffi-lua.zip
wget https://github.com/hzj-jie/cffi-lua/archive/$CFFI_LUA_VERSION.zip -O cffi-lua.zip
unzip cffi-lua.zip
rm cffi-lua.zip
pushd cffi-lua-$CFFI_LUA_VERSION
mkdir build
pushd build
meson -Dlua_version=5.4 ..
ninja all
cp cffi.so ../../../linux/ffi.so
popd
popd
