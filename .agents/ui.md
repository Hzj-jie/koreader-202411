# UI Architecture and Conventions

This document outlines architectural patterns, widget sizing rules, and dialog handling conventions for developing UI components and plugins in KOReader.

---

## 1. Widget Sizing and Geometry

*   **Use `self.movable:getSize()`**: In KOReader UI containers and dialogs (e.g., `ButtonDialog`), always call `self.movable:getSize()` rather than directly reading `.dimen`.
*   **Avoid Premature `.dimen` Access**: Direct access to `.dimen` before rendering is incorrect because `.dimen` is only populated after a widget has been positioned and painted via `paintTo()`.

---

## 2. Modality (`modal = true`)

*   **Full-Screen Screens Must Not Be Modal**: Full-screen interactive application and game screens (extending `InputContainer` or `WidgetContainer`, such as `Game2048`, `SudokuScreen`, `MathPuzzleScreen`, etc.) must not declare `modal = true`. Marking a base screen as modal breaks `UIManager`'s window stack layering for non-modal sub-menus and causes `isShownModal()` to intercept and swallow unhandled gesture events.
*   **Modals Reserved for Popups & Dialogs**: The `modal = true` attribute is strictly reserved for transient overlays, dialogs, and popups (e.g., `ConfirmBox`, `InputDialog`, `VirtualKeyboard`) to ensure they stay on top of base screens and capture user focus.
