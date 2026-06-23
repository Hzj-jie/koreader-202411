#!/usr/bin/env bash
# KOReader Pagination and Task Queue Benchmark Runner.
# usage: ./run_benchmarks.sh [platform_directory]

set -eo pipefail

PLATFORM_DIR="linux"

if [ -n "$1" ]; then
    if [ -d "$1" ]; then
        PLATFORM_DIR="$1"
    else
        echo "[!] Error: Selected platform environment directory '$1' does not exist."
        exit 1
    fi
fi

# Prepare and enter sandbox
source ./prepare_sandbox_env.sh "$PLATFORM_DIR"

benches=(
    "spec/unit/uimanager_bench.lua"
    "spec/unit/taskqueue_bench.lua"
    "spec/unit/benchmark.lua"
)

echo "================================================================================"
echo "          📊 RUNNING KOREADER BENCHMARKS"
echo "================================================================================"

results=()
durations=()
export SDL_VIDEODRIVER=dummy

for file in "${benches[@]}"; do
    echo "[*] Running $file..."
    start_time=$(date +%s.%N)
    set +e
    ./luajit test_runner.lua "$file"
    status=$?
    set -e
    end_time=$(date +%s.%N)
    elapsed=$(awk -v start="$start_time" -v end="$end_time" 'BEGIN { printf "%.3f", end - start }')
    echo "[+] Completed in $elapsed seconds"
    echo ""
    results+=("$status")
    durations+=("$elapsed")
done

echo "================================================================================"
echo "          📊 BENCHMARK SUMMARY"
echo "================================================================================"
printf "%-35s | %-15s | %-10s\n" "Benchmark File" "Time (seconds)" "Status"
echo "--------------------------------------------------------------------------------"
for i in "${!benches[@]}"; do
    file="${benches[$i]}"
    elapsed="${durations[$i]}"
    status_code="${results[$i]}"
    if [ "$status_code" -eq 0 ]; then
        status="SUCCESS"
    else
        status="FAILED"
    fi
    printf "%-35s | %-15s | %-10s\n" "$file" "$elapsed" "$status"
done
echo "================================================================================"
