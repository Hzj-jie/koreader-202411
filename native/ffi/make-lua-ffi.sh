#!/bin/bash

readonly LUA_FFI_VERSION=1.1.0
rm -rf lua-ffi-$LUA_FFI_VERSION lua-ffi-$LUA_FFI_VERSION.tar.gz
wget https://github.com/zhaojh329/lua-ffi/releases/download/v$LUA_FFI_VERSION/lua-ffi-$LUA_FFI_VERSION.tar.gz
tar xzf lua-ffi-$LUA_FFI_VERSION.tar.gz
rm lua-ffi-$LUA_FFI_VERSION.tar.gz
pushd lua-ffi-$LUA_FFI_VERSION
mkdir build
pushd build
cmake -D USE_LUA54=true ..
make
popd
popd
