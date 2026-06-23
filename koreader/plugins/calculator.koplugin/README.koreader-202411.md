# Calculator Compatibility for KOReader v2024.11

This folder contains the `Calculator` plugin imported from the KOReader Contrib repository with modifications to make it work on KOReader v2024.11.

## Original Plugin Information
- **Source Repository:** [shuvashish76/calculator.koplugin](https://github.com/shuvashish76/calculator.koplugin)
- **Original Git Commit Hash:** `57971ab2ee084fa9439509fa6716fe005f2ea8ee` (as referenced in `koreader/contrib`)

## Modifications Applied for Compatibility
1. **Localization API Adaptation**:
   - Replaced all calls of `_` shorthand to `gettext` to align with the core localization system.
2. **Version Checker Removal**:
   - Removed the `getLatestVersion` network request check and `getCurrentVersion` verification since newer upstream versions of the calculator plugin do not work properly on older KOReader versions without extra tunings.
3. **Simplified Keyboards**:
   - Retained a stable 3-layer keyboard layout in `ui/keyboard_calc.lua` instead of the 4-layer layout found in the upstream repository, ensuring character set compatibility and layout stability on older screens.
