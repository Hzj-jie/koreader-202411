#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPAT_H="$(realpath "$SCRIPT_DIR/../arm_glibc_compat.h")"
readonly LIBFFI_VERSION=3.4.5

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=("linux" "pw2" "kobo" "legacy")
fi

if [ ! -d "libffi-$LIBFFI_VERSION" ]; then
    rm -rf "libffi-$LIBFFI_VERSION" "libffi-$LIBFFI_VERSION.tar.gz"
    wget "https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION/libffi-$LIBFFI_VERSION.tar.gz"
    tar xzf "libffi-$LIBFFI_VERSION.tar.gz"
    rm "libffi-$LIBFFI_VERSION.tar.gz"
fi

for TARGET in "${TARGETS[@]}"; do
    echo "========================================="
    echo "Building libffi for target: $TARGET"
    echo "========================================="
    BUILD_DIR="libffi-$LIBFFI_VERSION/build-$TARGET"
    INSTALL_DIR="$SCRIPT_DIR/libffi-$LIBFFI_VERSION/install-$TARGET"

    rm -rf "$BUILD_DIR" "$INSTALL_DIR"
    mkdir -p "$BUILD_DIR"
    pushd "$BUILD_DIR"

    if [ "$TARGET" = "linux" ]; then
        ../configure --prefix="$INSTALL_DIR" --enable-static --disable-shared --with-pic
        make -j"$(nproc)"
        make install
        popd
        continue
    fi

    case "$TARGET" in
        pw2)
            HOST="arm-linux-gnueabi"
            CC="arm-linux-gnueabi-gcc"
            ARCH_FLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=softfp"
            ;;
        kobo)
            HOST="arm-linux-gnueabihf"
            CC="arm-linux-gnueabihf-gcc"
            ARCH_FLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=hard"
            ;;
        legacy)
            HOST="arm-linux-gnueabi"
            CC="arm-linux-gnueabi-gcc"
            ARCH_FLAGS="-march=armv6 -mfpu=vfp -mfloat-abi=softfp"
            ;;
        *)
            echo "Unknown target: $TARGET"
            exit 1
            ;;
    esac

    ../configure \
        --host="$HOST" \
        --prefix="$INSTALL_DIR" \
        --enable-static \
        --disable-shared \
        --with-pic \
        ac_cv_func_memfd_create=no \
        CC="$CC" \
        CFLAGS="$ARCH_FLAGS -O2 -U_TIME_BITS -U_FILE_OFFSET_BITS -include $COMPAT_H"

    make -j"$(nproc)"
    make install
    popd

    echo "Target $TARGET libffi built and installed to $INSTALL_DIR"
done
