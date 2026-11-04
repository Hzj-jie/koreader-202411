#!/bin/bash
# Simple orchestrator delegating parameters to monkey_test.lua
cd linux
${LUA:-./luajit} tools/monkey_test.lua "$@"
