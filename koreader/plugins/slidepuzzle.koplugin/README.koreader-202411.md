# Slide Puzzle Compatibility for KOReader v2024.11

This folder contains the compatibility record and integration details for the `Slide Puzzle` plugin, which was imported from upstream `koreader/contrib` to run on KOReader v2024.11.

## Compatibility and Integration Status
- **Games Submenu Integration**: The game is integrated into the file manager under the `Tools` -> `Games` submenu.
- **Localization**: Slide Puzzle's internal localization catalog has been translated, and its language auto-detection has been updated to support full and normalized sub-locales (e.g. `zh_CN` / `zh_TW`).
- **Default State**: To maintain a minimal start-up performance footprint and keep the main launcher interface uncluttered, this plugin is disabled by default. It can be easily enabled via the KOReader Plugin Manager (`Tools` -> `Plugin Manager`).
