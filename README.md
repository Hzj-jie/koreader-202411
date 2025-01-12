Tired of applying unnecessary changes introducing bugs, and removal of useful
features.

This repo is derived from the 2024-11 version with essential bug fixes only. The
build works on kindle pw2 or upper only.

Diff against the baseline

```
git diff d7848ef99a53e99c9377d9d45f81cbd510fb4584 --stat | grep -v data/dict | grep -v screensaver | grep -v koreader/fonts
git diff 231e6bd36634077930a8957d1656a83b2e022550 f29ec9e7e8c3b264a44d5c8dd42536a85d31df07
```
