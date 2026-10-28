#!/bin/bash

readonly LIBFFI_VERSION=3.4.5
rm -rf libffi-$LIBFFI_VERSION libffi-$LIBFFI_VERSION.tar.gz
wget https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION/libffi-$LIBFFI_VERSION.tar.gz
tar xzf libffi-$LIBFFI_VERSION.tar.gz
rm libffi-$LIBFFI_VERSION.tar.gz
pushd libffi-$LIBFFI_VERSION
./configure
make
popd
