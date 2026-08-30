# Game 2048 Compatibility for KOReader v2024.11

This folder contains the compatibility record and integration details for the `Game 2048` plugin, which was imported from upstream `koreader/contrib` to run on KOReader v2024.11.

## Compatibility and Integration Status
- **Structure Refactoring**: Flattened the nested folder structure to match core KOReader plugin structure layout conventions.
- **Games Submenu Integration**: The game is integrated into the file manager under the `Tools` -> `Games` submenu.
- **Localization**: User interface text has been refactored to use KOReader's native `gettext` library and is fully localized for `zh_CN` (Simplified Chinese) and `zh_TW` (Traditional Chinese).
- **Default State**: To maintain a minimal start-up performance footprint and keep the main launcher interface uncluttered, this plugin is disabled by default. It can be easily enabled via the KOReader Plugin Manager (`Tools` -> `Plugin Manager`).
