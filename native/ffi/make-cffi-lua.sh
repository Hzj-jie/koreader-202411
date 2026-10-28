#!/bin/bash

# Requires native/lua/make.sh to have run first to build linux/lua and unpack
# lua-jit-5.5.1 headers.
readonly CFFI_LUA_VERSION=9d220712a072e293be6ff141a454ed4037e41fe5
readonly LUA_VERSION=48b78835287cf04bb9d323c92ea7a85ea6aeae66

if [ ! -d "../lua/lua-jit-5.5.1-$LUA_VERSION" ]; then
    wget "https://github.com/hzj-jie/lua-jit-5.5.1/archive/$LUA_VERSION.zip" -O lua-jit-5.5.1.zip
    unzip lua-jit-5.5.1.zip -d ../lua/
    rm lua-jit-5.5.1.zip
fi

rm -rf cffi-lua-$CFFI_LUA_VERSION cffi-lua.zip
wget "https://github.com/hzj-jie/cffi-lua/archive/$CFFI_LUA_VERSION.zip" -O cffi-lua.zip
unzip cffi-lua.zip
rm cffi-lua.zip

pushd cffi-lua-$CFFI_LUA_VERSION
mkdir build
pushd build
CXXFLAGS="-I$(realpath ../../../lua/lua-jit-5.5.1-$LUA_VERSION)" \
meson -Dlua_version=custom -Dlua_path="$(realpath ../../../../linux/lua)" ..
ninja all
cp cffi.so ../../../../linux/ffi.so
popd
popd
