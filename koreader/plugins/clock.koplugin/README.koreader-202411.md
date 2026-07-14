# Clock Compatibility for KOReader v2024.11

This folder contains the `Clock` (Analog Clock) plugin imported from the KOReader Contrib repository with modifications to make it work on KOReader v2024.11.

## Original Plugin Information
- **Source Repository:** [jperon/clock.koplugin](https://github.com/jperon/clock.koplugin)
- **Original Git Commit Hash:** `48c262c59c27816d8fdc54c52c9a2ddb00d78b47` (as referenced in `koreader/contrib`)

## Modifications Applied for Compatibility
1. **Pre-compiled Moonscript to Lua**:
   - The original upstream repository is written in Moonscript and relies on dynamic loading of `.moon` files at runtime.
   - For performance and dependency reasons, the plugin has been pre-compiled to standard Lua files (`main.lua` and `clockwidget.lua`).
2. **Localization API Adaptation**:
   - Replaced all calls of `_` shorthand to `gettext` to align with the core localization system.
3. **Widget Lifecycle adjustments**:
   - Renamed `onClose` callback hook inside `clockwidget` to `onCloseWidget` to align with the Widget container lifecycle changes.
4. **Optimized rendering & log verbose reduction**:
   - Removed performance clock ticks measurement logs (`elapsed_h`, `elapsed_m`, `total_elapsed`) from the hot rendering loop in `clockwidget.lua` to avoid log spamming in debug environments.
