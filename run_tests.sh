#!/usr/bin/env bash
set -eo pipefail

# Parse command line arguments to extract the target platform directory and optional test file/directory
PLATFORM_DIR="linux"
TEST_FILE=""

if [ -n "$1" ]; then
    if [ -d "$1" ]; then
        # First arg is a platform directory (e.g. ./run_tests.sh linux)
        PLATFORM_DIR="$1"
        if [ -n "$2" ]; then
            TEST_FILE="$2"
        fi
    else
        # First arg is not a directory. Maybe it's a file path like linux/spec/unit/device_spec.lua or spec/unit/device_spec.lua
        first_segment="${1%%/*}"
        if [ -d "$first_segment" ]; then
            PLATFORM_DIR="$first_segment"
            TEST_FILE="${1#$first_segment/}"
        else
            # No platform prefix, e.g. ./run_tests.sh spec/unit/device_spec.lua
            TEST_FILE="$1"
        fi
    fi
fi

# Validate that the selected execution platform folder actually exists
if [ ! -d "$PLATFORM_DIR" ]; then
    echo "[!] Error: Selected platform environment directory '$PLATFORM_DIR' does not exist."
    exit 1
fi

# Anchor execution context directly inside the selected platform directory
cd "$(dirname "$0")"/"$PLATFORM_DIR"

# Verify that the specified test file exists if provided
if [ -n "$TEST_FILE" ]; then
    if [ ! -e "$TEST_FILE" ]; then
        echo "[!] Error: Test file or directory '$TEST_FILE' does not exist inside $PLATFORM_DIR/."
        exit 1
    fi
fi



# Strictly enforce relative Lua 5.1 module paths via symlink structures and block host mixing
export LUA_PATH="./base/spec/unit/?.lua;./spec/unit/?.lua;./?.lua;./common/?.lua;./frontend/?.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="./?.so;./common/?.so;./libs/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;;"

cleanup() {
    echo "[*] Purging test execution residues inside $PLATFORM_DIR/..."
    rm -rf cache/ defaults.defaults_spec.lua docsettings/ docsettingspec/ dummy-test-file* dummy-luadata-file* batterystat.log file.sdr/ help/ history.lua ota/ readerbookmark.pdf readerbookmark.sdr/ readerhighlight.pdf readerhighlight.sdr/ readerhighlight.epub juliet.epub juliet.sdr/ screenshots/ settings/ styletweaks/ testdata/ this-is-not-a-valid-file* settings.tests.lua
}
# Guarantee cleanup executes upon script termination (regardless of exit status)
trap cleanup EXIT

if [ -n "$TEST_FILE" ]; then
    echo "[*] Executing specific test path '$TEST_FILE' inside $PLATFORM_DIR/..."
    ./luajit -e 'require "busted.runner" {standalone = false}' /dev/null \
        --exclude-tags=notest \
        --helper=./ffi/loadlib.lua \
        --output=gtest \
        "$TEST_FILE" || true
else
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
fi
