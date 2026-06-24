#!/bin/bash
# Runner script for KOReader E2E Monkey Test

cd linux
./luajit tools/monkey_test.lua "$@"
