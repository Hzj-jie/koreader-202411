#!/bin/sh

sudo apt install \
    gcc g++ make unzip meson ninja-build \
    gcc-arm-linux-gnueabi g++-arm-linux-gnueabi binutils-arm-linux-gnueabi \
    gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf binutils-arm-linux-gnueabihf \
    qemu-user
