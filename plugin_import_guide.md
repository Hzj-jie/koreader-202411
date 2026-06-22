# KOReader Plugin Import & Compatibility Guide

This guide details the steps and best practices for importing third-party plugins (e.g., from `koreader/contrib`) into the main KOReader codebase and making them fully compatible.

---

## 1. Import Steps Checklist

### [ ] Step 1: Copy Files
- Copy the plugin directory (e.g., `my_plugin.koplugin/`) into `koreader/plugins/`.

### [ ] Step 2: Establish Platform Symlinks
- From the root of the repository, execute the consolidated link script:
  ```bash
  ./lns.sh
  ```
- This populates the platform-specific directories (`linux/`, `pw2/`, `legacy/`, `kobo/`) with symlinks pointing to the files in `koreader/`.

### [ ] Step 3: Git Tracking of Symlinks
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
