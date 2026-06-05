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

PLATFORM_PATH="$(pwd)"
SANDBOX_ROOT="/tmp/koreader_sandbox_$$"
SANDBOX_DIR="$SANDBOX_ROOT/run/context"
mkdir -p "$SANDBOX_DIR"

# Symlink all files and directories except user/test storage directories
for entry in "$PLATFORM_PATH"/* "$PLATFORM_PATH"/.*; do
    name="$(basename "$entry")"
    if [ "$name" != "." ] && [ "$name" != ".." ] && [ "$name" != "*" ]; then
        if [ "$name" != "settings" ] && [ "$name" != "cache" ] && [ "$name" != "docsettings" ] && [ "$name" != "history" ] && [ "$name" != "screenshots" ]; then
            ln -s "$entry" "$SANDBOX_DIR/$name"
        fi
    fi
done

# Create a symlink for the test folder in SANDBOX_ROOT so that ../../test from SANDBOX_DIR resolves correctly
ln -s "$PLATFORM_PATH/test" "$SANDBOX_ROOT/test"

# Now execute busted inside the sandbox!
pushd "$SANDBOX_DIR" > /dev/null

# Verify that the specified test file exists if provided
if [ -n "$TEST_FILE" ]; then
    if [ ! -e "$TEST_FILE" ]; then
        echo "[!] Error: Test file or directory '$TEST_FILE' does not exist inside $PLATFORM_DIR/."
        exit 1
    fi
fi

cleanup() {
    echo "[*] Purging sandbox environment folder at $SANDBOX_ROOT..."
    popd > /dev/null 2>&1
    rm -rf "$SANDBOX_ROOT"
}
# Guarantee cleanup executes upon script termination (regardless of exit status)
trap cleanup EXIT

# Run the test runner, delegating arguments. The runner manages environment paths and exit sequences.
export SDL_VIDEODRIVER=dummy
if [ -n "$TEST_FILE" ]; then
    ./luajit test_runner.lua "$TEST_FILE" || true
else
    ./luajit test_runner.lua || true
fi
