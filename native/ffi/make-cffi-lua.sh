#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPAT_H="$(realpath "$SCRIPT_DIR/../arm_glibc_compat.h")"
readonly LIBFFI_VERSION=3.4.5

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=("linux" "pw2" "kobo" "legacy")
fi

if [ ! -d "../lua/lua-jit-5.5.1-master" ]; then
    rm -rf "../lua/lua-jit-5.5.1-master" lua-jit-5.5.1.zip
    wget "https://github.com/hzj-jie/lua-jit-5.5.1/archive/master.zip" -O lua-jit-5.5.1.zip
    echo "Lua archive commit: $(unzip -z lua-jit-5.5.1.zip | tail -n 1)"
    unzip lua-jit-5.5.1.zip -d ../lua/
    rm lua-jit-5.5.1.zip
fi

rm -rf "cffi-lua-master" cffi-lua.zip
wget "https://github.com/hzj-jie/cffi-lua/archive/master.zip" -O cffi-lua.zip
echo "cffi-lua archive commit: $(unzip -z cffi-lua.zip | tail -n 1)"
unzip cffi-lua.zip
rm cffi-lua.zip

for TARGET in "${TARGETS[@]}"; do
    echo "========================================="
    echo "Building cffi-lua for target: $TARGET"
    echo "========================================="

    LIBFFI_A="$SCRIPT_DIR/libffi-$LIBFFI_VERSION/install-$TARGET/lib/libffi.a"
    if [ ! -f "$LIBFFI_A" ]; then
        ./make-libffi.sh "$TARGET"
    fi

    BUILD_DIR="$SCRIPT_DIR/cffi-lua-master/build-$TARGET"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    pushd "$BUILD_DIR"

    if [ "$TARGET" = "linux" ]; then
        CXXFLAGS="-I$(realpath "$SCRIPT_DIR/../lua/lua-jit-5.5.1-master") -I$(realpath "$SCRIPT_DIR/libffi-$LIBFFI_VERSION/install-linux/include")" \
        LDFLAGS="-Wl,--exclude-libs,ALL $(realpath "$SCRIPT_DIR/libffi-$LIBFFI_VERSION/install-linux/lib/libffi.a")" \
        meson setup -Dlua_version=custom -Dlua_path="$(realpath "$SCRIPT_DIR/../../linux/lua")" -Dlibffi=custom ..
        ninja all
        cp cffi.so "$SCRIPT_DIR/../../linux/ffi.so"
        popd
        continue
    fi

    case "$TARGET" in
        pw2)
            CC="arm-linux-gnueabi-gcc"
            CXX="arm-linux-gnueabi-g++"
            AR="arm-linux-gnueabi-ar"
            STRIP="arm-linux-gnueabi-strip"
            ARCH_FLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=softfp"
            CPU="armv7"
            SYSROOT="/usr/arm-linux-gnueabi"
            ;;
        kobo)
            CC="arm-linux-gnueabihf-gcc"
            CXX="arm-linux-gnueabihf-g++"
            AR="arm-linux-gnueabihf-ar"
            STRIP="arm-linux-gnueabihf-strip"
            ARCH_FLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=hard"
            CPU="armv7"
            SYSROOT="/usr/arm-linux-gnueabihf"
            ;;
        legacy)
            CC="arm-linux-gnueabi-gcc"
            CXX="arm-linux-gnueabi-g++"
            AR="arm-linux-gnueabi-ar"
            STRIP="arm-linux-gnueabi-strip"
            ARCH_FLAGS="-march=armv6 -mfpu=vfp -mfloat-abi=softfp"
            CPU="armv6"
            SYSROOT="/usr/arm-linux-gnueabi"
            ;;
        *)
            echo "Unknown target: $TARGET"
            exit 1
            ;;
    esac

    cat > cross.txt << EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'

[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = '$CPU'
endian = 'little'
EOF

    CXXFLAGS="$ARCH_FLAGS -O2 -U_TIME_BITS -U_FILE_OFFSET_BITS -include $COMPAT_H -I$(realpath "$SCRIPT_DIR/../lua/lua-jit-5.5.1-master") -I$(realpath "$SCRIPT_DIR/libffi-$LIBFFI_VERSION/install-$TARGET/include")" \
    LDFLAGS="$ARCH_FLAGS -Wl,--exclude-libs,ALL $(realpath "$LIBFFI_A")" \
    meson setup --cross-file cross.txt -Dlua_version=custom -Dtests=false -Dlibffi=custom ..
    ninja all
    cp cffi.so "$SCRIPT_DIR/../../$TARGET/ffi.so"
    popd

    # Fail-fast validation checks
    FFI_SO="$(realpath "$SCRIPT_DIR/../../$TARGET/ffi.so")"
    LUA_BIN="$(realpath "$SCRIPT_DIR/../../$TARGET/lua")"

    # 1. NEEDED checks (no libffi.so or libstdc++.so.6)
    if readelf -d "$FFI_SO" | grep -F "NEEDED" | grep -E -q "libffi|libstdc\+\+"; then
        echo "Error: Forbidden library found in NEEDED of $TARGET/ffi.so"
        exit 1
    fi

    # 2. Exported ffi_* symbols count check (must be 0)
    FFI_EXPORTS=$(nm -D --defined-only "$FFI_SO" | grep -c ' ffi_' || true)
    if [ "$FFI_EXPORTS" -ne 0 ]; then
        echo "Error: $FFI_EXPORTS exported ffi_* symbols found in $TARGET/ffi.so"
        exit 1
    fi

    # 3. Symbol versions check (GLIBC <= 2.4 and GCC <= 3.5)
    BAD_VERSIONS=$(readelf -V "$FFI_SO" | grep -oE 'Name: [^ ]+' | grep -vE '^Name: (GLIBC_2\.4|GCC_3\.[0-5])$' || true)
    if [ -n "$BAD_VERSIONS" ]; then
        echo "Error: Unexpected symbol versions found in $TARGET/ffi.so:"
        echo "$BAD_VERSIONS"
        exit 1
    fi

    # 4. QEMU smoke test
    LUA_CPATH="$SCRIPT_DIR/../../$TARGET/?.so;;" qemu-arm -L "$SYSROOT" "$LUA_BIN" \
        -e 'local ffi = require("ffi"); ffi.cdef("int getpid(void);"); assert(ffi.C.getpid() > 0); print("Target " .. "'"$TARGET"'" .. " FFI OK: " .. ffi.arch .. " " .. ffi.os)'
    echo "Target $TARGET cffi-lua built and verified successfully."
done
