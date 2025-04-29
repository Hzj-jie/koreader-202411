#!/bin/sh

for i in $(find ../koreader/ -type d | \
           sed 's/: /\t/g' | \
           cut -f 1 | \
           sed 's/..\/koreader\///g') ; do
  mkdir "$i" 2>/dev/null
done

for i in $(find ../koreader/ -type f -exec file {} \; | \
           grep -i -v elf | \
           sed 's/: /\t/g' | \
           cut -f 1 | \
           sed 's/..\/koreader\///g') ; do
  rm -f "$i"
  ln -rs "../koreader/$i" "$i"
done
