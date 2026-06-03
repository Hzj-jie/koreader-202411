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
*   **TouchMenu Keyboard Shortcuts (Commit 50e806cf)**: Introduced physical keyboard shortcut bindings (`Q`, `W`, `E`, `R`, `T`, `A`, `S`, `D`, `F`, `G`) for visible items in hierarchical touch menus, complete with visual key-hint overlays.
*   **Settings Framework Overhaul (Commit 7a0cc257, 452c9a04)**: Introduced a centralized `G_named_settings` abstraction layer to manage configuration defaults in one place, and upgraded `LuaSettings` to dynamically prevent the serialization of default values to disk, reducing settings file bloat.
*   **Background Task Plugin Framework (Commits 2a6c63a9, c7fbdc64, d8592e1b)**: Introduced `BackgroundTaskPlugin` (extending `SwitchPlugin`) to unify and simplify plugins performing background work (like `AutoFrontlight`, `AutoTurn`, and `AutoDim`). By leveraging a centralized `BackgroundTaskRunner` instead of manual `UIManager:scheduleIn` timers, it decouples background tasks from UI widgets, centralizes user activity tracking via `UIManager:timeSinceLastUserAction()`, and improves overall system stability.

### 📶 Network Management Component
Refined network state monitoring and wifi manager to simplify logic and prevent runtime crashes:
*   **Background Connection Checker (PR #216)**: Replaced synchronous blocking connection checks with an asynchronous background checker to monitor Wi-Fi status smoothly.
*   **Network Manager Rework (PR #144)**: Simplified the behavior of connection routines (`runWhen*` and `willRerunWhen*`) to prevent runtime crashes during state transitions.

---

## 📜 Credits & Upstream Sources
This build incorporates logic and binaries from the following critical upstream packages:
*   **KOReader 2024.11 "Slang"**: Base framework and source distributions from the [v2024.11 Release](https://github.com/koreader/koreader/releases/tag/v2024.11).
*   **Platform Distributions**: Bundled resources derived from official release packages (`koreader-kindlepw2-v2024.11.zip`, `koreader-kindle-legacy-v2024.11.zip`, `koreader-kobo-v2024.11.zip`).
*   **SortedIteration**: Embedded ordered traversal utilities sourced from [Lua-Users SortedIteration](http://lua-users.org/wiki/SortedIteration).
*   **Formatting & Linting**: Integration powered by **StyLua v2.1.0** and **Luacheck v1.2.0**.
*   **Embedded Server**: SSH server operations backed by **Dropbearmulti 2024.85** static binaries.
