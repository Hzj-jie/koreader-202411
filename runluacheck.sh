#!/bin/bash

# TODO: More folders
find koreader/frontend/ -name '*.lua' | xargs ./luacheck --std luajit
find koreader/plugins/ -name '*.lua' | xargs ./luacheck --std luajit
