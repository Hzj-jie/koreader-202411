# SimpleUI Compatibility for KOReader v2024.11

This folder contains the compatibility record for the `SimpleUI` (Clean Homescreen / Launcher) plugin, which was imported from `https://github.com/doctorhetfield-cmd/simpleui.koplugin` with modifications to make it work on KOReader v2024.11.

## Original Modifications Applied for Compatibility
1. **LuaSettings API Alignment**:
   - The standard KOReader `LuaSettings` class in v2024.11 only defines `save`, `read`, and `delete` methods.
   - Refactored settings manager writes to use native methods.
   - Added a dynamic metatable patch in `main.lua` to alias all deprecated `readSetting`, `saveSetting`, and `delSetting` calls to their native counterparts for both module-level and global settings instances (`G_reader_settings` / `G_defaults`).
2. **Missing Core Dependency Fallback (`BookList` / `FileChooser`)**:
   - The plugin depends on the core `ui/widget/booklist` class, which is absent in this version of KOReader.
   - Patched `sui_patches.lua` to dynamically check for `ui/widget/booklist` and automatically fall back to patching `ui/widget/filechooser` instead.
3. **Removal of Silent Mode Support**:
   - Fully removed references and calls to `UIManager`'s non-existent silent mode functionality (e.g., `isInSilentMode` / `setSilentMode`) as it is not supported in the current `UIManager` implementation.

## Removal Reason and Current Status
The plugin was removed from active development/run paths due to structural incompatibilities with KOReader's layout model:
- **Layout and Alignment Issues**: SimpleUI's overridden `TouchMenu:updateItems()` custom layout does not match the native `_updateTimeInfo()` output formats. On clock tick updates, text length increases, causing the clock to overflow layout boundaries or align incorrectly due to parent container cached offsets.
- **Top-Left Drawing Bug**: Because SimpleUI's dynamic panels add rendering/loading overhead, the startup time gap allows the minute-tick clock update to fire *before* the first layout pass has positioned the widget. This triggers direct widget repainting while coordinates are still uninitialized, locking the widget's position to `(0, 0)` (top-left of the screen).
- **Maintenance Overhead**: Resolving these bugs required modifying and resetting core native widgets and layout groups (`HorizontalGroup` offsets / `TouchMenu` paint trees), defeating the purpose of a standalone plugin. Thus, the plugin was removed to preserve codebase stability.
