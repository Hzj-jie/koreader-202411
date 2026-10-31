# UI Architecture and Conventions

This document outlines architectural patterns, widget sizing rules, event loop lifecycles, and dialog handling conventions for developing UI components and plugins in KOReader.

---

## 1. Widget Sizing and Geometry

*   **Use `self.movable:getSize()`**: In KOReader UI containers and dialogs (e.g., `ButtonDialog`), always call `self.movable:getSize()` rather than directly reading `.dimen`.
*   **Avoid Premature `.dimen` Access**: Direct access to `.dimen` before rendering is incorrect because `.dimen` is only populated after a widget has been positioned and painted via `paintTo()`.

---

## 2. Modality (`modal = true`)

*   **Full-Screen Screens Must Not Be Modal**: Full-screen interactive application and game screens (extending `InputContainer` or `WidgetContainer`, such as `Game2048`, `SudokuScreen`, `MathPuzzleScreen`, etc.) must not declare `modal = true`. Marking a base screen as modal breaks `UIManager`'s window stack layering for non-modal sub-menus and causes `isShownModal()` to intercept and swallow unhandled gesture events.
*   **Modals Reserved for Popups & Dialogs**: The `modal = true` attribute is strictly reserved for transient overlays, dialogs, and popups (e.g., `ConfirmBox`, `InputDialog`, `VirtualKeyboard`) to ensure they stay on top of base screens and capture user focus.

---

## 3. Window Lifecycle and Clean Teardown

*   **Registration and Cleanup**: Windows registered with `UIManager` must use `Widget:showWidget` / `UIManager:show` for registration and `Widget:uimanagedCleanUp` / `onClose` for teardown.
*   **Assert Constructor Dependencies**: Widgets requiring `self.ui` or `self.ui.menu` (such as `BatteryStatWidget`, `AutoSuspend`, `ReaderMenu`) should assert those dependencies in `init()` rather than adding defensive nil checks throughout method bodies. Unit tests should pass a minimal stub `ui` object rather than relying on nil guards in production code.

---

## 4. `UIManager:setDirty` and Invariant Assertions

*   **Parameter Assertions**: `UIManager:setDirty(widget, refreshMode, region)` asserts that `refreshMode` is `nil`, a string, or a function, and that `region` is `nil` or a bounding table.
*   **Valid Window Widgets**: Methods such as `isWindowWidget` and `scheduleWidgetRepaint` enforce valid widget references via assertions to immediately surface invalid UI lifecycles.

---

## 5. Coroutine Error Propagation

*   **Propagate Coroutine Errors to Main Loop**: Unhandled coroutine exceptions must not be silently swallowed or merely logged. In `Trapper:wrap`, unhandled coroutine errors are re-raised on the main UI thread via `UIManager:nextTick` with full stack traces.
*   **Assert `coroutine.resume`**: Callers resuming coroutines should assert successful completion using `debug.traceback` to surface execution failures loudly.
