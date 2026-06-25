#!/bin/bash
# Simple orchestrator delegating parameters to monkey_test.lua
cd linux
./luajit tools/monkey_test.lua "$@"
