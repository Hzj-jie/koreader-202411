# KOReader Plugin Import & Compatibility Guide

This guide details the steps and best practices for importing third-party plugins (e.g., from `koreader/contrib`) into the main KOReader codebase and making them fully compatible.

---

## 1. Import Steps Checklist

### [ ] Step 1: Copy Files & Disable by Default
- Copy the plugin directory (e.g., `my_plugin.koplugin/`) into `koreader/plugins/`.
- **Disable the plugin by default**: Add a versioned readme file matching `README.<git-branch>.md` (e.g. `README.koreader-202411.md`) in the plugin's root folder. Do NOT hardcode `disabled = true` in the plugin code itself. The core `pluginloader.lua` will dynamically detect this readme file and set `disabled = true` during registration.

### [ ] Step 2: Document Porting Changes
- Create the versioned readme file (e.g., `README.koreader-202411.md`) inside the plugin folder.
- Document:
  - Original source repository and commit hash.
  - Required installation steps (e.g., executing `./lns.sh`).
  - Modifications applied for compatibility with v2024.11 (e.g., settings changes, fallbacks).
  - Implicitly serving as the marker for the default disabled status.

### [ ] Step 3: Establish Platform Symlinks & Exclusions
- If the plugin needs to be excluded from specific target platforms (e.g., legacy DXG Kindle target `legacy/` due to the lack of touchscreen/Wi-Fi, or desktop binaries from embedded targets), open `lns.sh` and add the plugin to the corresponding exclude patterns variable (e.g., `LEGACY_EXCLUDES`, `PW2_EXCLUDES`, `KOBO_EXCLUDES`).
- From the root of the repository, execute the consolidated link script to link/exclude all plugin files (including the new README) to all platform directories:
  ```bash
  ./lns.sh
  ```
- This populates the platform-specific directories (`linux/`, `pw2/`, `legacy/`, `kobo/`) with symlinks pointing to the files in `koreader/`, respecting the exclusion lists.

### [ ] Step 4: Git Tracking of Symlinks
- Stage the new platform symlinks in git, but **exclude system/repository config files** from tracking to avoid repository pollution or index corruption:
  - **Exclude**: `.git/`, `.github/` workflows, `.gitmodules`, `.gitignore`, `.travis.yml`, `.travis.yaml`.
  - **Include**: All `.lua`, `.png`, `.svg`, `.json`, `.txt`, `.md`, `.mo` translation files, and platform-specific binaries/scripts (if any).

---

## 2. Refactoring Guidelines

### A. Settings Persistence (`LuaSettings`)
The active version of `LuaSettings` uses `read(key)` and `save(key, value)` instead of the deprecated `readSetting` and `saveSetting` APIs.

1. **Replacing `readSetting` / `saveSetting`**:
   - Convert all `settings:readSetting("key")` to `settings:read("key")`.
   - Convert all `settings:saveSetting("key", value)` to `settings:save("key", value)`.

2. **Handling Boolean Defaults (Critical)**:
   - Using standard Lua fallback `settings:read("key") or default_value` is **dangerous** for boolean settings where the default is `true`. If the setting is stored as `false`, `false or true` evaluates to `true` (overwriting the stored value).
   - **Rule**:
     - For **Boolean** settings: Use `settings:isTrueOr("key", default_value)`.
     - For **Non-Boolean** (numbers, strings, tables): Use `settings:read("key") or default_value`.

3. **Toggling Boolean Settings**:
   - `toggle()` is not supported by `LuaSettings`. Use `save` with the negation of `isTrue`:
     ```lua
     plugin.settings:save("my_setting", not plugin.settings:isTrue("my_setting"))
     ```

### B. UI Menu Registration
- Standardize placement of the plugin inside the menus (e.g., the `Games` sub-menu under `Tools`) by registering it with the `MenuSorter` using the appropriate `sorting_hint`:
  ```lua
  menu_items.my_plugin = {
      text = gettext("My Plugin"),
      sorting_hint = "games",
      callback = function() self:start() end,
  }
  ```

### C. Close Event Stack Overflow Prevention
During UIManager close operations, a `Close` event is broadcasted to the closing widget. If the widget's `onClose()` event handler internally calls `UIManager:close(self)`, it triggers an infinite recursion loop leading to a stack overflow.

- **Rule**: Keep `onClose()` strictly for cleaning up resources, stopping timers, and saving game state. Do not call `UIManager:close(self)` from inside it:
  ```lua
  -- Correct event handler
  function MyPluginUI:onClose()
      self:saveGame()
      self.timer:stop()
      return true
  end
  ```
- **Rule**: In the Close button or exit trigger callback, call `onClose()` followed by `UIManager:close(self)`:
  ```lua
  -- Correct callback
  callback = function()
      self:onClose()
      UIManager:close(self)
  end
  ```

### D. Function & Method Naming Conventions
To maintain clean semantics and avoid naming collisions with standard event handlers:
1. **Private/Internal Functions**: Prefix internally-used private class methods and helpers with an underscore `_` prefix (e.g. `_turnOnWifi`, `_saveSettings`).
2. **Non-Event Handler Functions**: Rename functions that are not actual event handlers to regular `verb + subject` names (e.g., rename `onSettingsChanged` to `updateSettings` if it doesn't handle a dispatched event) to prevent the event system from incorrectly invoking them.

---

## 3. Testing & Verification

### A. Integration Tests
Always add or update integration tests under the `linux/spec/` test suite to verify:
1. The plugin successfully registers in the menu hierarchy.
2. The plugin's UI can be instantiated.
3. The plugin closes cleanly without throwing stack overflow or nil-pointer exceptions.

### B. Running Tests
Run the test suite from the `linux/` directory:
```bash
./luajit test_runner.lua spec/unit/games_submenu_spec.lua spec/unit/menusorter_spec.lua
```

---

## 4. Localization (l10n) Guidelines

If the plugin contains user-facing strings, they must be localized to support KOReader's multilingual interface.

### A. Core Translation Catalog
If the plugin uses standard KOReader localization methods (i.e. `gettext("...")` or `_("...")`):
1. **Extract Strings**: Collect all translatable strings from the plugin source code.
2. **Merge with Main Catalogs**: Add translation entries for target languages (like `zh_CN` and `zh_TW`) to the respective translation file (e.g. `koreader/l10n/zh_CN/koreader.po`).
3. **Verify PO Format**: Run `msgfmt -c` to compile and verify there are no translation format or escape-character errors in the PO files.

### B. Self-Contained i18n Modules
If the plugin uses a self-contained translation module (such as `my_plugin_i18n.lua`):
1. **Define Mappings**: Define distinct translation tables for all languages/sub-locales you wish to support.
2. **Register Supported Languages**: Ensure the language codes are registered in the metadata lists and marked as supported.
3. **Proper Sub-Locale Detection (Critical)**:
   - When resolving the default system language, ensure you check for full/normalized locale matches (e.g., `zh_cn` or `zh_tw`) first before checking short prefixes (like `zh`). This avoids falling back to English or an incorrect sub-locale when sub-locales have significantly different writing systems (like Simplified vs Traditional Chinese).
   - **Correct Pattern**:
     ```lua
     function M.detectAuto()
       local lang = G_reader_settings:read("language") or "en"
       local norm = lang:lower():gsub("-", "_")
       if SUPPORTED[norm] then
         return norm
       end
       local short = norm:match("^([^_%-]+)")
       if short and SUPPORTED[short] then
         return short
       end
       return "en"
     end
     ```
