#!/bin/sh

# stylua is downloaded from
# https://github.com/JohnnyMorganz/StyLua/releases/download/v2.1.0/stylua-linux-x86_64.zip

function run {
  ./stylua "$1"
  if [ -e "$1/jit/dump.lua" ]; then
    ./stylua --syntax Lua53 "$1/jit/dump.lua"
  fi
}

function run_twice {
  run "$@"
}

run_twice "koreader"
run_twice "origin/frontend.stylua"

# Run everything twice to avoid syntax breakages.
