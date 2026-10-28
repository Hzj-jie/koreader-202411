#!/bin/bash
set -euo pipefail

# Requires native/lua/make.sh to have run first to build linux/lua and unpack
# lua-jit-5.5.1 headers.
readonly CFFI_LUA_VERSION=9d220712a072e293be6ff141a454ed4037e41fe5
readonly LUA_VERSION=48b78835287cf04bb9d323c92ea7a85ea6aeae66
readonly LIBFFI_VERSION=3.4.5

if [ ! -d "../lua/lua-jit-5.5.1-$LUA_VERSION" ]; then
    wget "https://github.com/hzj-jie/lua-jit-5.5.1/archive/$LUA_VERSION.zip" -O lua-jit-5.5.1.zip
    unzip lua-jit-5.5.1.zip -d ../lua/
    rm lua-jit-5.5.1.zip
fi

if [ ! -f "libffi-$LIBFFI_VERSION/install/lib/libffi.a" ]; then
    ./make-libffi.sh
fi

rm -rf cffi-lua-$CFFI_LUA_VERSION cffi-lua.zip
wget "https://github.com/hzj-jie/cffi-lua/archive/$CFFI_LUA_VERSION.zip" -O cffi-lua.zip
unzip cffi-lua.zip
rm cffi-lua.zip

pushd cffi-lua-$CFFI_LUA_VERSION
mkdir build
pushd build
CXXFLAGS="-I$(realpath ../../../lua/lua-jit-5.5.1-$LUA_VERSION) -I$(realpath ../../libffi-$LIBFFI_VERSION/install/include)" \
LDFLAGS="-Wl,--exclude-libs,ALL $(realpath ../../libffi-$LIBFFI_VERSION/install/lib/libffi.a)" \
meson setup -Dlua_version=custom -Dlua_path="$(realpath ../../../../linux/lua)" -Dlibffi=custom ..
ninja all
cp cffi.so ../../../../linux/ffi.so
popd
popd
