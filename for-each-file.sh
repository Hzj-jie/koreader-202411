#!/bin/bash

if [ -z "$2" ]; then
  VIM=vim
else
  VIM=view
fi

for i in $(grep -r "$1" | sed 's/:/\t/g' | cut -f 1 | sort | uniq); do
  $VIM $i
done
