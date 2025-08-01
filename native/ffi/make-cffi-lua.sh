#!/bin/bash

readonly CFFI_LUA_VERSION=9f2acc9a2a0c8e59dda35c0e11333d1b66296667
rm -rf cffi-lua-$CFFI_LUA_VERSION cffi-lua.zip
wget https://github.com/q66/cffi-lua/archive/$CFFI_LUA_VERSION.zip -O cffi-lua.zip
unzip cffi-lua.zip
rm cffi-lua.zip
pushd cffi-lua-$CFFI_LUA_VERSION
mkdir build
pushd build
meson -Dlua_version=5.4 ..
ninja all
popd
popd
