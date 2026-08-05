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
6. **Added library scanning feature (`Scan library for unsynced annotations`)**:
   - Implemented `SyncManager:scanLibraryForUnsyncedDocuments()` to scan KOReader's opened book history (`require("readhistory").hist`) across all four sidecar storage layouts (`doc` in book folder, `dir` in central `docsettings/`, `hash` in `docsettings/b3/`, and legacy `hist` in `history/`) for existing `.sdr` settings with annotations, queueing them into the pending sync list (`changed_documents.lua`).
   - Added a menu option `"Scan library for unsynced annotations"` with a confirmation dialog so users can populate pending syncs for existing annotated books without immediately uploading.
7. **Removed unsupported Reading Progress Sync features**:
   - Removed Reading Progress Sync menu options (`Enable Reading Progress Sync`, `Sync using last word of page`, `Sync every %1 pages`, `Push reading progress`, `Jump to device progress`) and the explanation popup (`Why are some options greyed out?`) because they rely on an unsupported upstream cloud storage API (`ui.cloudstorage`) in KOReader v2024.11.
   - Removed all unused backend reading progress sync methods, document hooks, Dispatcher actions, default settings, and obsolete progress sync unit tests (`progress_sync_integration_spec.lua`, `sync_service_silent_repro_spec.lua`).
8. **Replaced network-connected trigger with 1-minute timer incremental background sync (`onTimesChange_1M`)**:
   - Replaced `_onNetworkConnected` (which only fired on offline-to-online transitions) with periodic 1-minute checks (`onTimesChange_1M`).
   - Implemented private method `SyncManager:_syncPendingDocumentsBg()` to incrementally sync pending documents (up to 60 per minute) in their own `UIManager:nextTick` calls, preventing UI lag when syncing large numbers of annotated books in the background.
9. **Refactored internal helper methods to private and removed dead code**:
   - Prefixed internal `SyncManager` helper methods with an underscore (`_syncPendingDocumentsBg`, `_writeAnnotationsJSON`, `_writeChangedDocumentsFile`, `_writeLocalSettingValue`, `_removeFromChangedDocumentsFile`).
   - Removed dead code `SyncManager:checkPendingSync()`, which was only used by the removed reading progress sync feature.
10. **Skip uploading empty annotation JSON when remote file is missing**:
    - Updated `annotations.sync_callback` so that when a remote file is missing (`is_remote_missing` is true) and the local annotation list is empty (`next(local_map) == nil`), it avoids pushing empty JSON files to the server.
11. **Non-blocking "Sync All" execution using `Trapper`**:
    - Wrapped batch document syncing (`syncAllChangedDocuments`) in KOReader's background scheduler `require("ui/trapper"):wrap` coroutine.
    - Added live progress updates (`Syncing document X of Y...`), interactive pause dialogs, and cancellation handling to prevent UI freezes during large batch syncs.
12. **Simplified Chinese (`zh_CN`) and Traditional Chinese (`zh_TW`) i18n support**:
    - Added translation files (`l10n/zh_CN/annotation_sync.po` and `l10n/zh_TW/annotation_sync.po`) and generated platform symlinks across `linux`, `kobo`, and `pw2` build targets.
    - Updated `i18n_spec.lua` to test dynamic translation loading for both Chinese locales.
