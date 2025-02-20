#!/bin/bash
# A temporary script to replace G_reader_settings:readSetting("abc") or def to G_named_settings.abc

# first, replace the calls with "or"

for i in $(grep -r "G_reader_settings:readSetting(\"$1\")" | sed 's/:/\t/g' | cut -f 1 | sort | uniq); do
  sed -i "s/G_reader_settings:readSetting(\"$1\") or $2/G_named_settings.$1()/g" $i
done

# second, replace the calls without "or"

for i in $(grep -r "G_reader_settings:readSetting(\"$1\")" | sed 's/:/\t/g' | cut -f 1 | sort | uniq); do
  sed -i "s/G_reader_settings:readSetting(\"$1\")/G_named_settings.$1()/g" $i
done
