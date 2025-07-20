#!/bin/bash

readonly LIBFFI_VERSION=3.4.5
rm -rf libffi-$LIBFFI_VERSION libffi-$LIBFFI_VERSION.tar.gz
wget https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION/libffi-$LIBFFI_VERSION.tar.gz
tar xzf libffi-$LIBFFI_VERSION.tar.gz
pushd libffi-$LIBFFI_VERSION
./configure
make
popd

readonly LUA_FFI_VERSION=1.1.0
rm -rf lua-ffi-$LUA_FFI_VERSION lua-ffi-$LUA_FFI_VERSION.tar.gz
wget https://github.com/zhaojh329/lua-ffi/releases/download/v$LUA_FFI_VERSION/lua-ffi-$LUA_FFI_VERSION.tar.gz
tar xzf lua-ffi-$LUA_FFI_VERSION.tar.gz
pushd lua-ffi-$LUA_FFI_VERSION
mkdir build
pushd build
cmake ..
make
popd
popd
