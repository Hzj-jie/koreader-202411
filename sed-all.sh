#!/bin/sh

grep -r "$1" | sed s'/:/\t/g' | cut -f 1 | sort | uniq | xargs sed -i "s/$1/$2/g"
