#!/bin/bash

readonly CFFI_LUA_VERSION=68aa37f8bf9bd9ebcb21857902043c13d2aeb3d6
rm -rf cffi-lua-$CFFI_LUA_VERSION cffi-lua.zip
wget https://github.com/hzj-jie/cffi-lua/archive/$CFFI_LUA_VERSION.zip -O cffi-lua.zip
unzip cffi-lua.zip
rm cffi-lua.zip
pushd cffi-lua-$CFFI_LUA_VERSION
mkdir build
pushd build
meson -Dlua_version=5.4 ..
ninja all
popd
popd
