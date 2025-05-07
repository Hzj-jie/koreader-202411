Tired of applying unnecessary changes introducing bugs, and removal of useful
features.

This repo is derived from the 2024-11 version with essential bug fixes only.

## Supported platforms
- kindle pw2
- kindle legacy
- linux & wsl with ubuntu 24.04 or upper

## To be supported platforms
- kobo

After running stylua at
https://github.com/Hzj-jie/koreader-202411/commit/587d93fa241744aa8e03574bdcd3cf3dd92c3244,
diff against the baseline becomes pointless. But a copy of original files can
still be found under origin/ as the reference.

## Repo structure

Unlike the original koreader, building native binaries is not officially
supported, though it's possible to build in origin/ after running
install-deps.sh.

Instead, all the native files are placed in their corresponding platform
folders, e.g. pw2/ for kindle pw2, legacy/ for kindle legacy.

koreader/ includes all the lua, or platform independent files.

kindle/ includes the shared files across different kindle variants.

Multiple lns.sh scripts are used to symbol-link files from koreader/ to the
platform folder.

## Principle of changes

So far, all the changes are limited to lua files, there isn't a need of changing
anything native yet. Most of the changes fixed annoying bugs or usability
issues, but there are some slightly out of the scope, to improve the code health
, reduce the complexity, improve the user experience or reduce power
consumption.

Except for some repo setups, most of the changes can be mapped to one or more
issues to explain the motivation of the change.
