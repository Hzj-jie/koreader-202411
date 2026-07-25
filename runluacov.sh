#!/bin/bash
# KOReader Test Suite Code Coverage Entry.
# usage: ./runluacov.sh [platform_directory] [test_file]

set -eo pipefail

export KO_WORKSPACE_DIR="$(pwd)"

rm -f luacov.stats.out luacov.report.out

export LUA_PATH="luacov/?.lua;luacov/?/init.lua;./luacov/?.lua;./luacov/?/init.lua;${KO_WORKSPACE_DIR}/linux/luacov/?.lua;${KO_WORKSPACE_DIR}/linux/luacov/?/init.lua;;$LUA_PATH"
export LUAFLAGS="-joff -lluacov"

echo "[*] Running unit test suite with LuaCov coverage instrumentation..."
./run_tests.sh "$@"

echo ""
echo "[*] Generating coverage report..."
if [ -f "luacov.stats.out" ]; then
    # Normalize relative paths in stats output from sandbox (frontend/ -> koreader/frontend/)
    sed -i 's#\(^\|:\)frontend/#\1koreader/frontend/#g; s#\(^\|:\)plugins/#\1koreader/plugins/#g' luacov.stats.out 2>/dev/null || true
fi

./linux/luacov/bin/luacov

if [ -f "luacov.report.out" ]; then
    echo "[*] Coverage report generated: luacov.report.out"
    echo "========================================================================="
    tail -n 25 luacov.report.out
    echo "========================================================================="
fi
