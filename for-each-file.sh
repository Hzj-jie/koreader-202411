#!/bin/bash

for i in $(grep -r "$1" | sed 's/:/\t/g' | cut -f 1 | sort | uniq); do
  vim $i
done
