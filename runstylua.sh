#!/bin/bash

# stylua is downloaded from
# https://github.com/JohnnyMorganz/StyLua/releases/download/v2.1.0/stylua-linux-x86_64.zip

function run {
  # --verify crashes stylua.
  # thread '<unnamed>' panicked at src/verify_ast.rs:148:39:
  # internal error: entered unreachable code
  # note: run with `RUST_BACKTRACE=1` environment variable to display a
  # backtrace
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
