#!/bin/bash
# ==============================================================================
# 📊 KOReader comparative Pagination Benchmarking Suite (Automated Runner)
# ==============================================================================
# Runs whole-book sweeps consecutively on both Master and Baseline Upstream
# branches under forced headless configurations, presenting a clean aggregated
# metrics dashboard comparative summary.
# ==============================================================================

set -e


echo "================================================================================"
echo "          INITIATING CROSS-ENVIRONMENT COMPARATIVE BENCHMARKING SWEEP"
echo "================================================================================"
echo " Mode: Force Headless (Xvfb Virtual Framebuffer Software Rendering Overlay)"
echo " Scale: Full Traversal (Consecutive whole-book page counts pagination loops)"
echo " targets: juliet.epub, leaves.epub, sample.pdf, sample.txt"
echo "================================================================================"
echo ""

# Forceful deletion of global sandbox container to ensure absolute state isolation
echo "Wiping global sandbox config container (/tmp/koreader_benchmark/)..."
rm -rf /tmp/koreader_benchmark/
echo "Sandbox cleared completely."
echo ""

# 1. Sweep Pristine Upstream (origin.linux/)
echo "--------------------------------------------------------------------------------"
echo ">>> [1/2] RUNNING SWEEP: BASELINE PRISTINE UPSTREAM (origin.linux/)"
echo "--------------------------------------------------------------------------------"
pushd origin.linux > /dev/null
./luajit benchmark_paging.lua "$@" > /tmp/origin_benchmark_raw.txt 2>&1
popd > /dev/null
echo ">>> [1/2] Baseline pristine sweep completed successfully!"
echo ""

# 2. Sweep Developmental Branch (linux/)
echo "--------------------------------------------------------------------------------"
echo ">>> [2/2] RUNNING SWEEP: DEVELOPMENTAL BRANCH (linux/)"
echo "--------------------------------------------------------------------------------"
pushd linux > /dev/null
./luajit benchmark_paging.lua "$@" > /tmp/master_benchmark_raw.txt 2>&1
popd > /dev/null
echo ">>> [2/2] Developmental optimized sweep completed successfully!"
echo ""

# 3. Present Aggregated Dashboard summaries
echo "================================================================================"
echo "          📊 KOREADER CROSS-ENVIRONMENT PERFORMANCE COMPARATIVE SUMMARY"
echo "================================================================================"
echo ""

echo "--------------------------------------------------------------------------------"
echo " 1. PRISTINE BASELINE METRICS (origin)"
echo "--------------------------------------------------------------------------------"
sed -n '/KOREADER PAGINATION COMPARATIVE BENCHMARK HARNESS/,$p' /tmp/origin_benchmark_raw.txt
echo ""

echo "--------------------------------------------------------------------------------"
echo " 2. DEVELOPMENTAL OPTIMIZED METRICS (master)"
echo "--------------------------------------------------------------------------------"
sed -n '/KOREADER PAGINATION COMPARATIVE BENCHMARK HARNESS/,$p' /tmp/master_benchmark_raw.txt
echo ""

echo "================================================================================"
echo " comparative sweeps execution successfully completed!"
echo "================================================================================"

# Cleanup raw temp diagnostic trace files
rm -f /tmp/origin_benchmark_raw.txt /tmp/master_benchmark_raw.txt
