#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WRAP_C="$(realpath "$SCRIPT_DIR/../arm_glibc_wrap.c")"
readonly COMPAT_H="$(realpath "$SCRIPT_DIR/../arm_glibc_compat.h")"

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=("linux" "pw2" "kobo" "legacy")
fi

rm -rf "lua-jit-5.5.1-master" lua-jit-5.5.1.zip
wget "https://github.com/hzj-jie/lua-jit-5.5.1/archive/master.zip" -O lua-jit-5.5.1.zip
echo "Lua archive commit: $(unzip -z lua-jit-5.5.1.zip | tail -n 1)"
unzip lua-jit-5.5.1.zip
rm lua-jit-5.5.1.zip
make -C lua-jit-5.5.1-master fetch

for TARGET in "${TARGETS[@]}"; do
    echo "========================================="
    echo "Building lua for target: $TARGET"
    echo "========================================="
    BUILD_DIR="lua-jit-5.5.1-master-$TARGET"
    rm -rf "$BUILD_DIR"
    cp -a "lua-jit-5.5.1-master" "$BUILD_DIR"
    pushd "$BUILD_DIR"

    if [ "$TARGET" = "linux" ]; then
        make MYLDFLAGS="-Wl,-E -Wl,-rpath,'\$\$ORIGIN:\$\$ORIGIN/libs' -Wl,--disable-new-dtags" all
        cp lua ../../../linux/lua
        cp luac ../../../linux/luac
        popd

        # Fail-fast validation checks for linux
        LUA_BIN="$(realpath "$SCRIPT_DIR/../../linux/lua")"
        if readelf -d "$LUA_BIN" | grep -F "NEEDED" | grep -E "libffi|libstdc\+\+" > /dev/null; then
            echo "Error: Unexpected forbidden library in NEEDED for linux/lua"
            exit 1
        fi
        if [ "$(nm -D --defined-only "$LUA_BIN" | grep -cE ' (ffi_|_Z)')" -ne 0 ]; then
            echo "Error: Forbidden symbols exported in linux/lua"
            exit 1
        fi
        if ! nm -D --defined-only "$LUA_BIN" | grep "lua_newstate" > /dev/null; then
            echo "Error: lua_newstate not exported in linux/lua"
            exit 1
        fi
        "$LUA_BIN" -e "local ffi = require('ffi'); ffi.cdef('int getpid(void); int snprintf(char *s, size_t n, const char *fmt, ...);'); assert(ffi.C.getpid() > 0); local buf = ffi.new('char[32]'); ffi.C.snprintf(buf, 32, 'pid: %d', ffi.C.getpid()); assert(ffi.string(buf):find('^pid: ')); local cb = ffi.cast('int (*)(int, int)', function(a, b) return a + b end); assert(cb(10, 20) == 30); cb:free(); assert(ffi.cast('void (*)()', 0) == nil); assert(ffi.cast('void (*)()', 0) == ffi.nullptr)"
        echo "Target linux lua built and verified successfully."
        continue
    fi

    case "$TARGET" in
        pw2)
            CC="arm-linux-gnueabi-gcc"
            ARCH_FLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=softfp"
            INTERP="/lib/ld-linux.so.3"
            SYSROOT="/usr/arm-linux-gnueabi"
            ;;
        kobo)
            CC="arm-linux-gnueabihf-gcc"
            ARCH_FLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=hard"
            INTERP="/lib/ld-linux-armhf.so.3"
            SYSROOT="/usr/arm-linux-gnueabihf"
            ;;
        legacy)
            CC="arm-linux-gnueabi-gcc"
            ARCH_FLAGS="-march=armv6 -mfpu=vfp -mfloat-abi=softfp"
            INTERP="/lib/ld-linux.so.3"
            SYSROOT="/usr/arm-linux-gnueabi"
            ;;
        *)
            echo "Unknown target: $TARGET"
            exit 1
            ;;
    esac

    $CC -std=gnu99 -c $ARCH_FLAGS -fno-pie -O2 -U_TIME_BITS -U_FILE_OFFSET_BITS \
        -include "$COMPAT_H" "$WRAP_C" -o arm_glibc_wrap.o

    make CC="$CC -std=gnu99" \
         CXX="${CC%-gcc}-g++" \
         HOST="${CC%-gcc}" \
         AR="${CC%-gcc}-ar rcu" \
         RANLIB="${CC%-gcc}-ranlib" \
         FFI_CFLAGS="$ARCH_FLAGS -fno-pie -O2 -U_TIME_BITS -U_FILE_OFFSET_BITS -include $COMPAT_H" \
         MYCFLAGS="-DLUA_USE_LINUX $ARCH_FLAGS -fno-pie -U_TIME_BITS -U_FILE_OFFSET_BITS -include $COMPAT_H" \
         MYCXXFLAGS="$ARCH_FLAGS -fno-pie -U_TIME_BITS -U_FILE_OFFSET_BITS -include $COMPAT_H" \
         MYLDFLAGS="-Wl,-E -Wl,-rpath,'\$\$ORIGIN:\$\$ORIGIN/libs' -Wl,--disable-new-dtags -Wl,--wrap=__libc_start_main -Wl,--no-as-needed -no-pie" \
         MYLIBS="arm_glibc_wrap.o -l:libdl.so.2" \
         lua

    cp lua "../../../$TARGET/lua"
    popd

    # Fail-fast validation checks
    LUA_BIN="$(realpath "$SCRIPT_DIR/../../$TARGET/lua")"

    # 1. ELF type check (must be ET_EXEC for ARM targets to run safely on old kernels like Voyage 3.0.35)
    if ! readelf -h "$LUA_BIN" | grep -E "Type:[[:space:]]+EXEC" > /dev/null; then
        echo "Error: Expected ET_EXEC binary for $TARGET/lua"
        exit 1
    fi

    # 2. Interpreter check
    if ! readelf -l "$LUA_BIN" | grep -F "program interpreter" | grep "$INTERP" > /dev/null; then
        echo "Error: Interpreter check failed for $TARGET/lua. Expected $INTERP"
        exit 1
    fi

    # 3. NEEDED libdl.so.2 check
    if ! readelf -d "$LUA_BIN" | grep -F "NEEDED" | grep "\[libdl\.so\.2\]" > /dev/null; then
        echo "Error: libdl.so.2 missing from NEEDED in $TARGET/lua"
        exit 1
    fi

    # 4. Forbidden libraries check
    if readelf -d "$LUA_BIN" | grep -F "NEEDED" | grep -E "libffi|libstdc\+\+" > /dev/null; then
        echo "Error: Unexpected forbidden library in NEEDED for $TARGET/lua"
        exit 1
    fi

    # 5. RPATH check
    if ! readelf -d "$LUA_BIN" | grep -E "RPATH|RUNPATH" | grep "\[\\\$ORIGIN:\\\$ORIGIN/libs\]" > /dev/null; then
        echo "Error: Expected RPATH [$ORIGIN:$ORIGIN/libs] in $TARGET/lua"
        exit 1
    fi

    # 6. Symbol versions check (GLIBC <= 2.4 and GCC <= 3.5)
    BAD_VERSIONS=$(readelf -V "$LUA_BIN" | grep -oE 'Name: [^ ]+' | grep -vE '^Name: (GLIBC_2\.4|GCC_3\.[0-5])$' || true)
    if [ -n "$BAD_VERSIONS" ]; then
        echo "Error: Unexpected symbol versions found in $TARGET/lua:"
        echo "$BAD_VERSIONS"
        exit 1
    fi

    # 7. Exported symbols check
    if [ "$(nm -D --defined-only "$LUA_BIN" | grep -cE ' (ffi_|_Z)')" -ne 0 ]; then
        echo "Error: Forbidden symbols exported in $TARGET/lua"
        exit 1
    fi
    if ! nm -D --defined-only "$LUA_BIN" | grep "lua_newstate" > /dev/null; then
        echo "Error: lua_newstate not exported in $TARGET/lua"
        exit 1
    fi

    # 8. QEMU smoke test
    qemu-arm -L "$SYSROOT" "$LUA_BIN" -v
    qemu-arm -L "$SYSROOT" "$LUA_BIN" -e "local ffi = require('ffi'); ffi.cdef('int getpid(void); int snprintf(char *s, size_t n, const char *fmt, ...);'); assert(ffi.C.getpid() > 0); local buf = ffi.new('char[32]'); ffi.C.snprintf(buf, 32, 'pid: %d', ffi.C.getpid()); assert(ffi.string(buf):find('^pid: ')); local cb = ffi.cast('int (*)(int, int)', function(a, b) return a + b end); assert(cb(10, 20) == 30); cb:free(); assert(ffi.cast('void (*)()', 0) == nil); assert(ffi.cast('void (*)()', 0) == ffi.nullptr)"
    echo "Target $TARGET lua built and verified successfully."
done

rm -rf "lua-jit-5.5.1-master"*
