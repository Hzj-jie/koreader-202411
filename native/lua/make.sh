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

for TARGET in "${TARGETS[@]}"; do
    echo "========================================="
    echo "Building lua for target: $TARGET"
    echo "========================================="
    BUILD_DIR="lua-jit-5.5.1-master-$TARGET"
    rm -rf "$BUILD_DIR"
    cp -r "lua-jit-5.5.1-master" "$BUILD_DIR"
    pushd "$BUILD_DIR"

    if [ "$TARGET" = "linux" ]; then
        make MYLDFLAGS="-Wl,-E -Wl,-rpath,'\$\$ORIGIN:\$\$ORIGIN/libs' -Wl,--disable-new-dtags" all
        cp lua ../../../linux/lua
        cp luac ../../../linux/luac
        popd
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

    $CC -std=gnu99 -c $ARCH_FLAGS -O2 -U_TIME_BITS -U_FILE_OFFSET_BITS \
        -include "$COMPAT_H" "$WRAP_C" -o arm_glibc_wrap.o

    make CC="$CC -std=gnu99" \
         AR="${CC%-gcc}-ar rcu" \
         RANLIB="${CC%-gcc}-ranlib" \
         MYCFLAGS="-DLUA_USE_LINUX $ARCH_FLAGS -U_TIME_BITS -U_FILE_OFFSET_BITS -include $COMPAT_H" \
         MYLDFLAGS="-Wl,-E -Wl,-rpath,'\$\$ORIGIN:\$\$ORIGIN/libs' -Wl,--disable-new-dtags -Wl,--wrap=__libc_start_main -Wl,--no-as-needed" \
         MYLIBS="arm_glibc_wrap.o -l:libdl.so.2" \
         lua

    cp lua "../../../$TARGET/lua"
    popd

    # Fail-fast validation checks
    LUA_BIN="$(realpath "$SCRIPT_DIR/../../$TARGET/lua")"

    # 1. Interpreter check
    if ! readelf -l "$LUA_BIN" | grep -F "program interpreter" | grep -q "$INTERP"; then
        echo "Error: Interpreter check failed for $TARGET/lua. Expected $INTERP"
        exit 1
    fi

    # 2. NEEDED libdl.so.2 check
    if ! readelf -d "$LUA_BIN" | grep -F "NEEDED" | grep -q "\[libdl\.so\.2\]"; then
        echo "Error: libdl.so.2 missing from NEEDED in $TARGET/lua"
        exit 1
    fi

    # 3. RPATH check
    if ! readelf -d "$LUA_BIN" | grep -E "RPATH|RUNPATH" | grep -q "\[\\\$ORIGIN:\\\$ORIGIN/libs\]"; then
        echo "Error: Expected RPATH [$ORIGIN:$ORIGIN/libs] in $TARGET/lua"
        exit 1
    fi

    # 4. Symbol versions check (GLIBC <= 2.4 and GCC <= 3.5)
    BAD_VERSIONS=$(readelf -V "$LUA_BIN" | grep -oE 'Name: [^ ]+' | grep -vE '^Name: (GLIBC_2\.4|GCC_3\.[0-5])$' || true)
    if [ -n "$BAD_VERSIONS" ]; then
        echo "Error: Unexpected symbol versions found in $TARGET/lua:"
        echo "$BAD_VERSIONS"
        exit 1
    fi

    # 5. QEMU smoke test
    qemu-arm -L "$SYSROOT" "$LUA_BIN" -v
    echo "Target $TARGET lua built and verified successfully."
done
