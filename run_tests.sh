#!/usr/bin/env bash
# KOReader Test Suite Sandboxed Execution Entry.
# usage: ./run_tests.sh [platform_directory] [test_file]

set -eo pipefail

# Export the absolute path to the workspace root so sandboxed workers can resolve
# absolute paths to host resources (like linux/test_helper.lua).
export KO_WORKSPACE_DIR="$(pwd)"

# Unset developer-specific emulator and font environment variables to guarantee a
# standardized and deterministic test environment on all host workstations.
unset EMULATE_READER_W
unset EMULATE_READER_H
unset EMULATE_READER_DPI
unset EMULATE_READER_VIEWPORT
unset EMULATE_READER_FORCE_PORTRAIT
unset EMULATE_READER_FLASH
unset EMULATE_BW_SCREEN
unset EMULATE_BB_TYPE
unset DISABLE_TOUCH
unset EXT_FONT_DIR

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

# Clean up host screenshots directory from previous runs to prevent stale images
rm -rf "$PLATFORM_DIR/screenshots"

# Verify that the specified test file exists if provided
if [ -n "$TEST_FILE" ]; then
    if [ ! -e "$PLATFORM_DIR/$TEST_FILE" ]; then
        echo "[!] Error: Test file or directory '$TEST_FILE' does not exist inside $PLATFORM_DIR/."
        exit 1
    fi
fi

# Prepare and enter sandbox
source ./prepare_sandbox_env.sh "$PLATFORM_DIR"

# Run the test runner
export SDL_VIDEODRIVER=dummy
if [ -n "$TEST_FILE" ]; then
    ./luajit test_runner.lua "$TEST_FILE" || true
else
    exit_code=0
    start_time=$(date +%s)
    ./luajit test_runner.lua || exit_code=$?
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    echo "========================================================================="
    echo "    Total time:       ${elapsed}s"
    echo "========================================================================="
    exit $exit_code
fi
