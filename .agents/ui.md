# UI Architecture and Conventions

This document outlines architectural patterns, widget sizing rules, and dialog handling conventions for developing UI components and plugins in KOReader.

---

## 1. Widget Sizing and Geometry

*   **Use `self.movable:getSize()`**: In KOReader UI containers and dialogs (e.g., `ButtonDialog`), always call `self.movable:getSize()` rather than directly reading `.dimen`.
*   **Avoid Premature `.dimen` Access**: Direct access to `.dimen` before rendering is incorrect because `.dimen` is only populated after a widget has been positioned and painted via `paintTo()`.

---

## 2. Dialogs and TitleBar Close Callbacks

*   **Immediate Close on TitleBar "X"**: In full-screen game and plugin screens, the TitleBar close button (`close_callback`), hardware back handlers, and close key handlers (`Escape`, `Close`, `Back`) should immediately invoke `UIManager:close(self)` without prompting through modal confirmation dialogs (`ConfirmBox`).
*   **Modal Dialog Trapping**: Attempting to display modal confirmation dialogs upon clicking "X" can cause modal layering conflicts, input traps, and unresponsiveness on touch or e-ink screens where dismissing the prompt returns to the view while tapping "X" repeatedly re-triggers the dialog.
