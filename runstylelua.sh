#!/bin/sh

# stylua is downloaded from
# https://github.com/JohnnyMorganz/StyLua/releases/download/v2.1.0/stylua-linux-x86_64.zip
./stylua koreader/
./stylua --syntax Lua53 koreader/jit/dump.lua

./stylua koreader/
./stylua --syntax Lua53 koreader/jit/dump.lua

# Run everything twice to avoid syntax breakages.
