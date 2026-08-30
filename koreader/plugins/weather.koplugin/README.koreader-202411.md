# Weather Compatibility for KOReader v2024.11

This folder contains the `Weather` plugin imported from the KOReader Contrib repository with modifications to make it work on KOReader v2024.11.

## Original Plugin Information
- **Source Repository:** [roygbyte/weather.koplugin](https://github.com/roygbyte/weather.koplugin) (as referenced in `koreader/contrib`)
- **Original Git Commit Hash:** `72ea7451de8d571d625983df3dcd466d9b580cc5`

## Modifications Applied for Compatibility
1. **Refactored settings API usage**:
   - Clean KOReader's `LuaSettings` class (in v2024.11) only defines `save` and `read` methods.
   - Refactored all calls of `saveSetting` to `save` inside `main.lua`.
2. **Localization API Adaptation**:
   - Replaced all calls of `_` shorthand to `gettext` to align with the core localization system.
3. **Removed local settings definition file**:
   - Removed `weather.koplugin/settings.lua` (which was present in upstream `contrib`) to prevent settings conflict with the central KOReader settings manager.
