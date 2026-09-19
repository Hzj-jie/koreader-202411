# UI Architecture and Conventions

This document outlines architectural patterns, widget sizing rules, and dialog handling conventions for developing UI components and plugins in KOReader.

---

## 1. Widget Sizing and Geometry

*   **Use `self.movable:getSize()`**: In KOReader UI containers and dialogs (e.g., `ButtonDialog`), always call `self.movable:getSize()` rather than directly reading `.dimen`.
*   **Avoid Premature `.dimen` Access**: Direct access to `.dimen` before rendering is incorrect because `.dimen` is only populated after a widget has been positioned and painted via `paintTo()`.
