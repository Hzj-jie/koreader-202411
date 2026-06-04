# KOReader Customization (2024.11 Derivative)

A focused, highly stabilized derivative of **KOReader 2024.11 "Slang"**, engineered to maintain core compatibility while delivering essential bug fixes, reducing structural bloat, and hardening the underlying execution framework against silent logic failures.

## 🎯 Core Philosophy
This repository is developed for users who value long-term stability over continuous downstream feature churn. It intentionally bypasses unnecessary modifications that introduce regressions or remove valuable workflows, preserving the high-fidelity E-Ink reading experience on targeted devices.

---

## 📦 Supported Platforms
Native binaries are isolated from the platform-independent Lua core and organized into dedicated deployment directories:
*   **Kindle Paperwhite 2**: `pw2/` (`pw2.tar.gz`)
*   **Kindle Legacy**: `legacy/` (`legacy.tar.gz`)
*   **Kobo Architecture**: `kobo/` (`kobo.tar.gz`)
*   **Linux & WSL (Ubuntu 24.04+)**: `linux/` (`linux.tar.gz`)

### Installation
Deploying this build closely mirrors the official KOReader setup workflow:
1.  **E-Ink Devices**: Complete the standard KOReader installation process on your device, then overwrite the base `koreader/` directory with the extracted contents of the corresponding platform release archive from the [Latest Release](https://github.com/Hzj-jie/koreader-202411/releases/latest).
2.  **Linux & WSL Environments**: Extract `linux.tar.gz` to your desired path and execute the bundled `run.sh` entry script.

> [!NOTE]
> Because this fork focuses on pure Lua enhancements, replacing just the source `.lua` files from an official installation with the contents of the active `koreader/` directory should functionally succeed, though complete integration testing across unverified configurations is highly recommended.

---

## 🏗️ Repository Architecture
To streamline maintenance and ensure reliable formatting, this repository adopts a strict structural separation:
*   `koreader/`: Contains all platform-independent Lua application source code and shared assets.
*   `kindle/`: Houses logic and scripts shared across various Kindle device models.
*   `origin/`: Retains pristine copies of upstream files to serve as an unformatted historical reference.
*   `origin.stylua/`: Contains pure source files formatted against the project's `StyLua` rules, establishing the formatting baseline.

To compare the active logic directly against the styled upstream baseline, execute:
```bash
diff -rw koreader/ origin.stylua/
```

*(Note: Native compilation is not officially supported directly inside this tree, though building within `origin/` after executing `install-deps.sh` remains possible. The bundled Linux binaries are specifically rebuilt to ensure backwards compatibility with legacy Intel Core 2 Duo architectures).*

---

## 🚀 Active Customizations & Fixes
Compared to the upstream baseline, this customized branch incorporates the following primary structural and logic modifications:

### ✏️ Core & UI Enhancements
Modifications across active Lua sources address specific application behavior, layout improvements, and advanced rendering logic:
*   **UI Manager Framework (PR #428)**: Deep architectural overhaul inside `uimanager.lua` that redesigned sub-widget rendering paths to completely eliminate unnecessary full-screen E-Ink flashes during highlights, footer updates, and chapter boundaries. It also introduces custom embedded OS confirmation dialogs (`askForReboot`, `askForPowerOff`) and powerful new framework operations (`keyEvents()`, `runWith()`).
*   **Event System Overhaul (PR #178)**: Refactored the event dispatching architecture to prefer `UIManager:broadcastEvent` and `UIManager:userInput` over direct `self.ui:handleEvent` calls. This ensures system events like `"Close"` and `"FlushSettings"` are correctly propagated down the widget hierarchy, enabling automated cleanup of child widgets and preventing resource leaks (e.g., lingering virtual keyboard instances).
*   **TouchMenu Keyboard Shortcuts (Commit 50e806cf)**: Introduced physical keyboard shortcut bindings for visible items in hierarchical touch menus, complete with visual key-hint overlays.
*   **Settings Framework Overhaul (Commit 7a0cc257, 452c9a04)**: Introduced a centralized `G_named_settings` abstraction layer to manage configuration defaults in one place, and upgraded `LuaSettings` to dynamically prevent the serialization of default values to disk, reducing settings file bloat.
*   **Centralized Activity Tracking & Hook Removal (Commit d8592e1b)**: Retired the legacy `event_hooks` (`HookContainer`) framework, eliminating potential memory leaks and dispatcher overhead. Replaced it with centralized user activity tracking inside `UIManager` (`timeSinceLastUserAction()`), simplifying idle-time logic across `AutoTurn`, `AutoSuspend`, `AutoDim`, and `ReaderRolling` modules.
*   **Reading History Filtering (Commits 4626678c, a59238de)**: Hardened the reading history manager (`readhistory.lua`) to ignore non-book items. It dynamically filters out crash logs (`crash.log`, `koreader.crash.*.log`), battery logs (`batterystat.log`), and helper HTMLs, and integrates with `FileChooser` rules to prevent system metadata (e.g., `.DS_Store`, calibre files) and settings directories (`.sdr`) from cluttering the history and statistics views.
*   **Background Task Plugin Framework (Commits 2a6c63a9, c7fbdc64, d8592e1b, d22a5a99)**: Introduced `BackgroundTaskPlugin` (extending `SwitchPlugin`) to unify and simplify plugins performing background work (like `AutoFrontlight`, `AutoTurn`, and `AutoDim`). By leveraging a centralized `BackgroundTaskRunner` instead of manual `UIManager:scheduleIn` timers, it decouples background tasks from UI widgets, centralizes user activity tracking via `UIManager:timeSinceLastUserAction()`, and improves overall system stability. Also resolved a critical framework issue (Commit d22a5a99) by ensuring task callbacks and environments are correctly propagated, which fixed silent timeout hangs in `ConnectivityChecker`.

### 📶 Network Management Component
Refined network state monitoring and wifi manager to simplify logic and prevent runtime crashes:
*   **Background Connection Checker (PR #216)**: Replaced synchronous blocking connection checks with an asynchronous background checker to monitor Wi-Fi status smoothly.
*   **Network Manager Rework (PR #144)**: Simplified the behavior of connection routines (`runWhen*` and `willRerunWhen*`) to prevent runtime crashes during state transitions.

### ➕ Added Capabilities
*   **Web Portal**: A browser-based remote control interface integrated under `web/`, allowing users to drive application actions and states directly over a regular browser.

### 🛡️ Stability & Hardening
Fixed numerous potential runtime crashes and logic errors across core modules to improve overall reliability:
*   **Input & Gestures**: Secured `GestureDetector` against missing event tables and added state healing guards; fixed `UIManager:handleInputEvent` crashes on malformed input arguments.
*   **UI Components**: Prevented crashes in `ImageView` (when not shown), `InputDialog` (during text search), and `BookMap`.
*   **Navigation & Documents**: Secured the `Table of Contents` module against missing TOC data and stabilized `UIManager` back-to-home navigation.
*   **Plugins & Network**: Resolved crashes in `KOSync` (during offline states and custom server lookups), `NetworkListener` (handling missing packet stats), and `statistics` (missing settings or page stats).
*   **Core Utilities**: Secured `datetime.stringToSeconds` against nil inputs/epoch overflows, fixed `readhistory` crashes on empty files, and resolved a double-free bug in `DictQuickLookup`.

---

## 📜 Credits & Upstream Sources
This build incorporates logic and binaries from the following critical upstream packages:
*   **KOReader 2024.11 "Slang"**: Base framework and source distributions from the [v2024.11 Release](https://github.com/koreader/koreader/releases/tag/v2024.11).
*   **Platform Distributions**: Bundled resources derived from official release packages (`koreader-kindlepw2-v2024.11.zip`, `koreader-kindle-legacy-v2024.11.zip`, `koreader-kobo-v2024.11.zip`).
*   **SortedIteration**: Embedded ordered traversal utilities sourced from [Lua-Users SortedIteration](http://lua-users.org/wiki/SortedIteration).
*   **Formatting & Linting**: Integration powered by **StyLua v2.1.0** and **Luacheck v1.2.0**.
*   **Embedded Server**: SSH server operations backed by **Dropbearmulti 2024.85** static binaries.
