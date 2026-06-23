# SimpleUI Compatibility for KOReader v2024.11

This folder contains the `SimpleUI` (Clean Homescreen / Launcher) plugin imported from `https://github.com/doctorhetfield-cmd/simpleui.koplugin` with modifications to make it work on KOReader v2024.11.

## Installation & Linking
Since this is a new plugin, after importing it, you **must run** the linking script from the repository root:
```bash
./lns.sh
```
This ensures symlinks are correctly populated across all target platforms (`linux/`, `kobo/`, `legacy/`, `pw2/`).

## Default State
By default, this plugin is **disabled**. You can enable it from the plugin manager in the KOReader settings menu.

## Modifications Applied for Compatibility
1. **LuaSettings API Alignment**:
   - Clean KOReader's `LuaSettings` class (in v2024.11) only defines `save`, `read`, and `delete` methods.
   - Refactored settings manager writes to use native methods.
   - Added a dynamic metatable patch in `main.lua` to alias all deprecated `readSetting`, `saveSetting`, and `delSetting` calls to their native counterparts for both module-level and global settings instances (`G_reader_settings` / `G_defaults`).
2. **Missing Core Dependency Fallback (`BookList` / `FileChooser`)**:
   - The plugin depends on the core `ui/widget/booklist` class which is absent in this version of KOReader.
   - Patched `sui_patches.lua` to dynamically check for `ui/widget/booklist` and automatically fall back to patching `ui/widget/filechooser` instead.
