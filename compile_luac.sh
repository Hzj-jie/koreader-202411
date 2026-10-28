#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ] || [ -z "$1" ]; then
    echo "Usage: $0 <dest_dir> [<git_ref>]" >&2
    exit 1
fi

DEST="$1"
REF="${2:-HEAD}"

if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
    echo "Error: destination directory '$DEST' must be empty or not exist." >&2
    exit 1
fi

mkdir -p "$DEST"
DEST_ABS="$(cd "$DEST" && pwd)"

git archive "$REF" \
    run_tests.sh prepare_sandbox_env.sh .luacov \
    koreader linux origin/test origin.linux/data/tessdata \
    | tar -x -C "$DEST_ABS"

LUAC_BIN="$DEST_ABS/linux/luac"
if [ ! -x "$LUAC_BIN" ]; then
    echo "Error: luac binary not found or not executable at '$LUAC_BIN'." >&2
    exit 1
fi

echo "[*] Compiling koreader/ lua sources..."
(
    cd "$DEST_ABS/koreader"
    while IFS= read -r -d '' f; do
        # hello_spec.lua reads its source text via io.open and gsub
        if [ "$f" = "plugins/hello.koplugin/main.lua" ]; then
            continue
        fi
        "$LUAC_BIN" -o "$f" "$f"
    done < <(find . -type f -name '*.lua' -printf '%P\0')
)

echo "[*] Compiling linux/ lua sources..."
(
    cd "$DEST_ABS/linux"
    while IFS= read -r -d '' f; do
        # httpinspector's getFunctionInfo reads source lines of functions defined in spec
        if [ "$f" = "spec/unit/httpinspector_spec.lua" ]; then
            continue
        fi
        "$LUAC_BIN" -o "$f" "$f"
    done < <(find . -type f -name '*.lua' -printf '%P\0')
)

echo "[*] luac compilation complete at $DEST_ABS"
