#!/bin/bash

diff -rq . ../origin.stylua/  | \
  grep 'Only in ../origin.stylua/' | \
  grep '\.lua$' | \
  sed 's/origin.stylua\//\t/g' | \
  sed 's/: /\//g' | \
  cut -f 2
