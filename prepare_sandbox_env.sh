# Sourced by run_tests.sh and run_benchmarks.sh to prepare the sandbox environment.
# Do not execute directly.

PLATFORM_DIR="$1"
if [ -z "$PLATFORM_DIR" ]; then
    PLATFORM_DIR="linux"
fi

if [ ! -d "$PLATFORM_DIR" ]; then
    echo "[!] Error: Platform environment directory '$PLATFORM_DIR' does not exist."
    return 1 2>/dev/null || exit 1
fi

PLATFORM_PATH="$(cd "$PLATFORM_DIR" && pwd)"
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

ln -s "$PLATFORM_PATH/test" "$SANDBOX_ROOT/test"

pushd "$SANDBOX_DIR" > /dev/null

cleanup() {
    echo "[*] Purging sandbox environment folder at $SANDBOX_ROOT..."
    popd > /dev/null 2>&1
    rm -rf "$SANDBOX_ROOT"
}
trap cleanup EXIT
