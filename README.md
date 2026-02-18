Tired of applying unnecessary changes introducing bugs, and removal of useful
features.

This repo is derived from the 2024-11 version with essential bug fixes only.

## Supported platforms

- kindle pw2 (pw2.tar.gz)
- kindle legacy (legacy.tar.gz)
- kobo (kobo.tar.gz)
- linux & wsl with ubuntu 24.04 or upper (linux.tar.gz)

Installation is very similar to the original koreader.

When running on the ebook devices, an easy approach is to follow the koreader
installation guide then replace the koreader folder with the files in the
cooresponding gz files from
https://github.com/Hzj-jie/koreader-202411/releases/latest.

When running on linux & wsl with ubuntu 24.04 or upper, unzip the linux.tar.gz
to any location, and run the run.sh file.

Since there isn't any native changes so far, replacing only the files from a
koreader installation with the lua files under koreader folder should also work.
But the combination was never tested.

After running stylua at
https://github.com/Hzj-jie/koreader-202411/commit/587d93fa241744aa8e03574bdcd3cf3dd92c3244,
diff against the baseline becomes pointless. But a copy of original files can
still be found under origin/ as the reference; or diff by

```
diff -rw koreader/ origin.stylua/
```

## Repo structure

Unlike the original koreader, building native binaries is not officially
supported, though it's possible to build in origin/ after running
install-deps.sh. Indeed the linux native binaries were rebuilt to support
the outdated Intel Core 2 Duo x64 processor on a Thinkpad X61t.

Instead, all the native files are placed in their corresponding platform
folders, e.g. pw2/ for kindle pw2, legacy/ for kindle legacy.

koreader/ includes all the lua, or platform independent files.

kindle/ includes the shared files across different kindle variants.

Multiple lns.sh scripts are used to symbol-link files from koreader/ to the
platform folder.

## Principle of changes

So far, all the changes are limited to lua files, there isn't a need of changing
anything native yet. Most of the changes fixed annoying bugs or usability
issues, but there are some slightly out of the scope, to improve the code
health, reduce the complexity, improve the user experience or reduce power
consumption.

Except for some repo setups, most of the changes can be mapped to one or more
issues to explain the motivations.

## Credits

KOReader 2024.11 "Slang", from
https://github.com/koreader/koreader/releases/tag/v2024.11. Source codes are all
coming from
https://github.com/koreader/koreader/archive/refs/tags/v2024.11.tar.gz,
including all the lua files. Native binaries are coming from the following
packages.

- pw2: https://github.com/koreader/koreader/releases/download/v2024.11/koreader-kindlepw2-v2024.11.zip
- legacy: https://github.com/koreader/koreader/releases/download/v2024.11/koreader-kindle-legacy-v2024.11.zip
- linux and origin.linux: originally from
  https://github.com/koreader/koreader/releases/download/v2024.11/koreader-linux-x86\_64-v2024.11.tar.xz,
  but rebuilt to run on outdated Intel Core 2 Duo x64.
- kobo: https://github.com/koreader/koreader/releases/download/v2024.11/koreader-kobo-v2024.11.zip

SortedIteration: ffi/SortedIteration.lua, from
http://lua-users.org/wiki/SortedIteration. It was previously used in koreader
as well, but embedded in ffi/util.lua. See the file itself contains the version
information and local changes.

stylua: stylua, from https://github.com/JohnnyMorganz/StyLua, current version is
2.1.0.

luacheck: luacheck, from https://github.com/lunarmodules/luacheck, current
version is 1.2.0.

dropbear: dropbearmulti 2024.85, from
https://github.com/ryanwoodsmall/static-binaries/blob/master/x86_64/dropbearmulti
official site: https://matt.ucc.asn.au/dropbear/dropbear.html. The downloaded
file is dropbearmulti, but renamed to dropbear to work as an ssh server.
