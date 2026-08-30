#!/usr/bin/env bash
# KOReader Test Suite Repeat Execution Entry.
# Usage: ./repeat_run_tests.sh [run_tests.sh_args...]
# Repeats running ./run_tests.sh with all arguments ($*), displaying failure details when a run fails.

set -euo pipefail

RUN_COUNT=0
FAIL_COUNT=0

TMP_OUTPUT=$(mktemp)
trap 'rm -f "$TMP_OUTPUT"' EXIT

export TEST_BRIEF=1

echo "[*] Starting repeated execution of: ./run_tests.sh $*"
echo "[*] Press Ctrl+C to stop."

while true; do
    RUN_COUNT=$((RUN_COUNT + 1))

    if ./run_tests.sh "$@" > "$TMP_OUTPUT" 2>&1; then
        printf "\r[*] Run #%d: PASSED" "$RUN_COUNT"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo ""
        echo "========================================================================="
        echo "[!] FAILURE DETECTED on Run #$RUN_COUNT (Total Failures: $FAIL_COUNT)"
        echo "========================================================================="
        cat "$TMP_OUTPUT"
        echo "========================================================================="
    fi
done
