#!/usr/bin/env bash
set -eo pipefail

# Anchor execution context directly inside the native precompiled linux/ directory
cd "$(dirname "$0")"/linux

export TESSDATA_DIR="$PWD/data"

# Strictly enforce Lua 5.1 module paths and block host Lua 5.3 mixing
export LUA_PATH="./base/spec/unit/?.lua;./spec/unit/?.lua;../koreader/?.lua;../koreader/common/?.lua;../koreader/frontend/?.lua;./?.lua;./common/?.lua;./frontend/?.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="./?.so;../koreader/common/?.so;./libs/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;;"

cleanup() {
    echo "[*] Purging test execution residues..."
    rm -rf cache/ defaults.defaults_spec.lua docsettings/ docsettingspec/ help/ history.lua readerbookmark.pdf readerhighlight.pdf settings/ testdata/
}
# Guarantee cleanup executes upon script termination (regardless of exit status)
trap cleanup EXIT

echo "[*] Executing Base Framework Layer Suite..."
./luajit -e 'require "busted.runner" {standalone = false}' /dev/null \
    --exclude-tags=notest \
    --helper=../koreader/ffi/loadlib.lua \
    --output=gtest \
    --sort-files \
    base/spec/unit || true

echo "[*] Executing Frontend Application Suite..."
./luajit -e 'require "busted.runner" {standalone = false}' /dev/null \
    --exclude-tags=notest \
    --helper=../koreader/ffi/loadlib.lua \
    --output=gtest \
    --sort-files \
    spec/unit || true
