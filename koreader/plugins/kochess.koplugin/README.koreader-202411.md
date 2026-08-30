# KoChess Compatibility for KOReader v2024.11

This folder contains the compatibility record for the `KoChess` (Chess Game) plugin, which was imported from `https://github.com/Gyebro/kochess.koplugin` with modifications to make it work on KOReader v2024.11.

## Original Modifications Applied for Compatibility
1. **Focus and Layout Alignment (Button & ButtonTable inheritance)**:
   - Refactored custom `button.lua` and `buttontable.lua` in `KoChess` to extend KOReader's native `ui/widget/button` and `ui/widget/buttontable` classes, rather than redefining them from `WidgetContainer`.
2. **State Guarding**:
   - Added checks in the main execution paths to prevent crash conditions caused by repaint calls firing after the chess game dialog was closed.

## Removal Reason and Current Status
The plugin was removed from active development/run paths due to several compatibility issues with KOReader's layout and event models:
- **Top-Left Drawing Bug**: Sizing and location offsets in custom buttons did not correctly propagate layout coordinates, causing the chess board and UI buttons to occasionally render at the screen origin `(0, 0)`.
- **Event Leakage**: Unhandled tap events on the chess board/buttons leaked down to underlying reading view components.
- **Closure and Teardown Issues**: Disposing of the game context and stockfish chess engine child processes occasionally left dangling states.
- **Maintenance Overhead**: Fixing these issues required modifying core layout groups and event routing paths, making it impractical to support as a standalone plugin without risking master branch stability.
