#!/bin/bash

export LUA_PATH="linux/luacov/?.lua;linux/luacov/?/init.lua;;$LUA_PATH"
./linux/luacov/bin/luacov "$@"
