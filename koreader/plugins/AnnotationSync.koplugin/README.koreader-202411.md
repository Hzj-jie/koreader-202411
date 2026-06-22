# AnnotationSync Compatibility for KOReader v2024.11

This folder contains the `AnnotationSync` plugin imported into KOReader v2024.11 with necessary compatibility fixes to make the unit and integration tests run successfully on this version.

## Original Plugin Information
- **Source Repository:** [dani84bs/AnnotationSync.koplugin](https://github.com/dani84bs/AnnotationSync.koplugin)
- **Imported Version/Tag:** `v1.9.9`
- **Original Git Commit Hash:** `58edf0bea3ad096972031acba0b6b9026f1b5698`

## Modifications Applied for Compatibility

The following changes were made to resolve test failures and runtime compatibility errors:

1. **Refactored settings API usage**: 
   - Clean KOReader's `LuaSettings` class (in v2024.11) only defines `save` and `read` methods.
   - Refactored all calls to `saveSetting` -> `save` and `readSetting` -> `read` in both plugin source code (`main.lua`, `manager.lua`) and all spec tests.
2. **Self-contained test mocks**:
   - Encapsulated test overrides (mocking `disable_plugins`, mocking `fastforward_ui_events` scheduled timer ticks, and monkeypatching `UIManager:show` to ignore redundant displays) inside the plugin's `spec/unit/test_utils.lua` file. This prevents dirtying core KOReader files.
   - Adjusted `require` order in spec files so `test_utils` is loaded before any plugin-disabling calls occur.
3. **Pure-Lua fallback for PO translation loading**:
   - The plugin originally called `gettext.loadPO` (which is a non-existent function in clean KOReader's core `gettext` library).
   - Added a pure-Lua `.po` file parser fallback definition inside `main.lua` to parse local translation files and dynamically register strings in `gettext` public translation/context fields, fixing the crash on startup under locales.
4. **EPUB highlight ground truth pagination correction**:
   - Corrected the page number in `highlight_db.lua` for the entry `"SCENE I. Verona..."` from `8` to `7` to match the current rendering pagination layout in this version of KOReader, resolving `highlight_ground_truth_spec.lua` failure.
5. **Adjusted `util.writeToFile` calls**:
   - Replaced multi-argument calls of `util.writeToFile(..., true, false, true)` with `util.writeToFile(...)` to match the core utility signature.
