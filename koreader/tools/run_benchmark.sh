#!/bin/sh

CDPATH="" cd -- "$(dirname -- "$0")/.." || exit 1

BENCH_TMP_DIR="."
for _cand in "${TMPDIR:-}" /var/tmp /tmp ./tmp; do
    if [ -n "${_cand}" ] && [ -d "${_cand}" ] && [ -w "${_cand}" ]; then
        BENCH_TMP_DIR="${_cand%/}"
        break
    fi
done

BENCH_LUAJIT="${BENCH_TMP_DIR}/koreader-bench-luajit.$$.lua"
BENCH_LUA="${BENCH_TMP_DIR}/koreader-bench-lua.$$.lua"
BENCH_DATA_DIR="${BENCH_TMP_DIR}/koreader-bench-data.$$"
BENCH_LOG="benchmark.log"

trap 'rm -rf "${BENCH_LUAJIT}" "${BENCH_LUA}" "${BENCH_DATA_DIR}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
rm -rf "${BENCH_LUAJIT}" "${BENCH_LUA}" "${BENCH_DATA_DIR}"
mkdir -p "${BENCH_DATA_DIR}/koreader" || exit 1
if [ -f "./settings.reader.lua" ]; then
    cp "./settings.reader.lua" "${BENCH_DATA_DIR}/koreader/settings.reader.lua" || exit 1
fi
KO_MULTIUSER=1
XDG_CONFIG_HOME="${BENCH_DATA_DIR}"
export KO_MULTIUSER XDG_CONFIG_HOME

run_benchmark_vm() {
    _bench_label="${1}"
    _bench_bin="${2}"
    _bench_out="${3}"
    shift 3
    echo "Benchmarking ${_bench_label} . . ."
    if [ ! -x "./${_bench_bin}" ]; then
        echo "./${_bench_bin} not found or not executable"
        printf 'return { meta = { status = "MISSING", status_detail = "./%s not found or not executable" } }\n' "${_bench_bin}" >"${_bench_out}"
        return 1
    fi
    ./"${_bench_bin}" tools/ui_benchmark.lua run "${_bench_out}" "$@" >>crash.log 2>&1
    _bench_rc=$?
    if [ "${_bench_rc}" -ne 0 ]; then
        echo "${_bench_label} benchmark failed (exit ${_bench_rc})"
        printf 'return { meta = { status = "ERROR", status_detail = "exit code %s (see crash.log)" } }\n' "${_bench_rc}" >"${_bench_out}"
        return "${_bench_rc}"
    fi
    return 0
}

run_benchmark_vm "LuaJIT" "luajit" "${BENCH_LUAJIT}" "$@"
LUAJIT_RC=$?
run_benchmark_vm "Lua" "lua" "${BENCH_LUA}" "$@"
LUA_RC=$?

VIEWER_BIN=""
if [ -x "./luajit" ]; then
    VIEWER_BIN="luajit"
elif [ -x "./lua" ]; then
    VIEWER_BIN="lua"
fi

if [ -n "${VIEWER_BIN}" ]; then
    ./"${VIEWER_BIN}" tools/ui_benchmark.lua compare "${BENCH_LUAJIT}" "${BENCH_LUA}" "${BENCH_LOG}" >>crash.log 2>&1
    RETURN_VALUE=$?
    if [ "${RETURN_VALUE}" -eq 0 ]; then
        echo "Showing benchmark results . . ."
        ./"${VIEWER_BIN}" tools/ui_benchmark.lua show "${BENCH_LOG}" >>crash.log 2>&1
        RETURN_VALUE=$?
    else
        echo "Failed to compare benchmark results (exit ${RETURN_VALUE}, see crash.log)"
    fi
else
    echo "Neither ./luajit nor ./lua is executable!"
    printf "KOReader Benchmark Report\n\nError: neither ./luajit nor ./lua is executable.\n" >"${BENCH_LOG}"
    RETURN_VALUE=1
fi

if [ "${RETURN_VALUE}" -eq 0 ] && [ "${LUAJIT_RC}" -ne 0 ] && [ "${LUA_RC}" -ne 0 ]; then
    RETURN_VALUE=1
fi

exit "${RETURN_VALUE}"
