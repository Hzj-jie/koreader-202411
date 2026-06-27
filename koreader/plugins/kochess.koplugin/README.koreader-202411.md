# SimpleUI Compatibility for KOReader v2024.11

This folder contains the compatibility record for the `SimpleUI` (Clean Homescreen / Launcher) plugin, which was imported from `https://github.com/doctorhetfield-cmd/simpleui.koplugin` with modifications to make it work on KOReader v2024.11.

## Original Modifications Applied for Compatibility
1. **LuaSettings API Alignment**:
   - Clean KOReader's `LuaSettings` class (in v2024.11) only defines `save`, `read`, and `delete` methods.
   - Refactored settings manager writes to use native methods.
   - Added a dynamic metatable patch in `main.lua` to alias all deprecated `readSetting`, `saveSetting`, and `delSetting` calls to their native counterparts for both module-level and global settings instances (`G_reader_settings` / `G_defaults`).
2. **Extension of Button and ButtonTable**:
   - Directly overriding original Button and ButtonTable is unacceptable. It introduces Top-Left Drawing Bug since it doesn't store the location of paintTo call.
