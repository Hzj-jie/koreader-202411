#!/bin/bash

git diff -w "$@" d7848ef99a53e99c9377d9d45f81cbd510fb4584 koreader/ ':(exclude)koreader/data/dict' ':(exclude)koreader/README.md' ':(exclude)koreader/jit/vmdef.lua' ':(exclude)koreader/fonts' ':(exclude)koreader/settings.reader.lua' ':(exclude)koreader/settings' ':(exclude)koreader/data/cr3.ini' | grep ''
git diff -w "$@" 231e6bd36634077930a8957d1656a83b2e022550 f29ec9e7e8c3b264a44d5c8dd42536a85d31df07 | grep ''
