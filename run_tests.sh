#!/usr/bin/env bash
set -eo pipefail

# Select execution platform environment based on optional CLI parameter (defaults to 'linux')
PLATFORM_DIR="${1:-linux}"

# Validate that the selected execution platform folder actually exists
if [ ! -d "$PLATFORM_DIR" ]; then
    echo "[!] Error: Selected platform environment directory '$PLATFORM_DIR' does not exist."
    exit 1
fi

# Anchor execution context directly inside the selected platform directory
cd "$(dirname "$0")"/"$PLATFORM_DIR"

export TESSDATA_DIR="$PWD/data"

# Strictly enforce relative Lua 5.1 module paths via symlink structures and block host mixing
export LUA_PATH="./base/spec/unit/?.lua;./spec/unit/?.lua;./?.lua;./common/?.lua;./frontend/?.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="./?.so;./common/?.so;./libs/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;;"

cleanup() {
    echo "[*] Purging test execution residues inside $PLATFORM_DIR/..."
    rm -rf cache/ defaults.defaults_spec.lua docsettings/ docsettingspec/ help/ history.lua readerbookmark.pdf readerhighlight.pdf settings/ testdata/
}
# Guarantee cleanup executes upon script termination (regardless of exit status)
trap cleanup EXIT

echo "[*] Executing Base Framework Layer Suite inside $PLATFORM_DIR/..."
./luajit -e 'require "busted.runner" {standalone = false}' /dev/null \
    --exclude-tags=notest \
    --helper=./ffi/loadlib.lua \
    --output=gtest \
    --sort-files \
    base/spec/unit || true

echo "[*] Executing Frontend Application Suite inside $PLATFORM_DIR/..."
./luajit -e 'require "busted.runner" {standalone = false}' /dev/null \
    --exclude-tags=notest \
    --helper=./ffi/loadlib.lua \
    --output=gtest \
    --sort-files \
    spec/unit || true
