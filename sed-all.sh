#!/bin/sh

find . -name '*.lua' | xargs sed -i "s/$1/$2/g"
