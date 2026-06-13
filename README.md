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
*   **Linux & WSL (Ubuntu 22.04+)**: `linux/` (`linux.tar.gz`)

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

### 🖼️ Improved Rendering Control
Redesigned the rendering and screen refresh paths to optimize display updates, significantly reducing screen refreshes and eliminating unnecessary display flickering (especially on E-Ink devices) ([PR #428](https://github.com/Hzj-jie/koreader-202411/pull/428)).

### 🖱️ Input & Gestures
*   **Accurate Gesture Handling**: Hardened touch and swipe detection to ensure malformed inputs or complex multi-finger taps are processed safely.
*   **Reliable Interface Navigation**: Refactored the window-level input loop to guarantee touch and key events are routed correctly down active layers. This prevents interface locking and resolves resource leaks (such as stuck virtual keyboards or persistent settings overlays) ([PR #178](https://github.com/Hzj-jie/koreader-202411/pull/178)).
*   **Background Interaction Protection**: Configured settings pages, input dialogs, and brightness sliders to block touch inputs from leaking through to the background view. This prevents accidental page turns, menu triggers, or text highlighting in the book reader when interacting with open popups.

### 🧱 Better UI Element Management
Centralized and hardened the user interface lifecycle to fix unexpected persistent UI elements (such as menus, search panels, and dialogs remaining on screen after closing their parent views) and eliminate associated memory leaks. By automatically tearing down child widgets when their parents exit, the interface remains clean and responsive ([Commit 74d4700a](https://github.com/Hzj-jie/koreader-202411/commit/74d4700a)).

### ✏️ Other Core & UI Enhancements
Modifications address specific application behavior, layout improvements, and advanced rendering logic:
*   **TouchMenu & InputBox Keyboard Shortcuts**: Introduced physical keyboard shortcuts for items in menus (with visual key-hint overlays) and optimized text input boxes so that system-wide keyboard shortcuts remain responsive even while typing ([Commit 50e806cf](https://github.com/Hzj-jie/koreader-202411/commit/50e806cf), [Commit 52d08951](https://github.com/Hzj-jie/koreader-202411/commit/52d08951) / [PR #428](https://github.com/Hzj-jie/koreader-202411/pull/428)).
*   **Centralized Activity Tracking ([Commit d8592e1b](https://github.com/Hzj-jie/koreader-202411/commit/d8592e1b))**: Introduced a centralized user activity tracker to simplify and improve the reliability of idle-time detection used by automatic page turning, automatic suspension, and screen dimming features.
*   **Consistent Page-Turn Tap Zones**: Updated dictionary popups, the page browser, and scrollable text/HTML views to respect the user's custom page-turn tap zones instead of forcing a hardcoded left/right split ([Commit d6e97f25](https://github.com/Hzj-jie/koreader-202411/commit/d6e97f25) / [Fix #139](https://github.com/Hzj-jie/koreader-202411/issues/139)). Additionally, simplified the tap zone configuration by removing the separate backward zone ratio setting, ensuring the entire screen is always utilized for either forward or backward page turns without leaving dead zones ([Commit 38fc7806](https://github.com/Hzj-jie/koreader-202411/commit/38fc7806) / [Fix #233](https://github.com/Hzj-jie/koreader-202411/issues/233), [#120](https://github.com/Hzj-jie/koreader-202411/issues/120)).
*   **Simplified Notification System**: Streamlined the notification system by removing complex source-filtering categories and past notification history, ensuring all notifications are displayed directly without background filtering overhead or settings menu clutter ([Commit 84fcc886](https://github.com/Hzj-jie/koreader-202411/commit/84fcc886), [Commit 52db342d](https://github.com/Hzj-jie/koreader-202411/commit/52db342d), [Commit d907be89](https://github.com/Hzj-jie/koreader-202411/commit/d907be89) / [Issue #252](https://github.com/Hzj-jie/koreader-202411/issues/252)).
*   **Kindle DX/DXG Keyboard Optimization**: Tailored the physical keyboard "Sym" key map for Kindle DX and DXG (which lack dedicated number keys) to map the top row of letter keys to numbers, making number entry more intuitive ([Commit deaf9ecc](https://github.com/Hzj-jie/koreader-202411/commit/deaf9ecc) / [Fix #370](https://github.com/Hzj-jie/koreader-202411/issues/370)).
*   **Reading History Filtering**: Filters out non-book files (like logs and settings folders) from the reading history manager to keep history and statistics views clean ([Commit 4626678c](https://github.com/Hzj-jie/koreader-202411/commit/4626678c), [Commit a59238de](https://github.com/Hzj-jie/koreader-202411/commit/a59238de)).
*   **Critical Battery Auto-Suspension**: Automatically suspends the device with a 3-second warning when the battery level drops below 5% to prevent complete battery depletion ([Commit c7dc3c29](https://github.com/Hzj-jie/koreader-202411/commit/c7dc3c29), [Commit 8174f417](https://github.com/Hzj-jie/koreader-202411/commit/8174f417) / [Issue #224](https://github.com/Hzj-jie/koreader-202411/issues/224)).
*   **Rich Book Information**: Displays extra details in the Book Info dialog for books with sidecar settings, including bookmarks count, saved settings count, and settings file size ([PR #298](https://github.com/Hzj-jie/koreader-202411/pull/298) / [Fix #282](https://github.com/Hzj-jie/koreader-202411/issues/282)).
*   **Visual Busy Feedback**: Shows an hourglass icon during long-running tasks like opening books or loading history to indicate the system is processing ([PR #298](https://github.com/Hzj-jie/koreader-202411/pull/298)).
*   **Page Button Tab Navigation**: Allows using physical Page Up / Page Down buttons to cycle through tabs in settings menus and configuration dialogs ([Commit 8c8e6f01](https://github.com/Hzj-jie/koreader-202411/commit/8c8e6f01), [Commit 8395a8b1](https://github.com/Hzj-jie/koreader-202411/commit/8395a8b1)).

### 🌐 Web-Based Remote Control
Provides a browser-based remote control interface, allowing users to drive application actions and states directly over a regular browser.

### 📶 Network Management Component
Refined network state monitoring and wifi manager to simplify logic and prevent runtime crashes:
*   **Network Manager Rework ([PR #144](https://github.com/Hzj-jie/koreader-202411/pull/144))**: Simplified network connection management to prevent crashes when transitioning between different network states (like connecting or disconnecting).
*   **Background Connection Checker ([PR #216](https://github.com/Hzj-jie/koreader-202411/pull/216))**: Replaced blocking network status checks with an asynchronous background checker to monitor Wi-Fi status smoothly without freezing the user interface.

### 🛡️ Stability & Hardening
Improvements to event handling, resource management, and core systems to ensure a more robust and responsive experience:
*   **Background Operations**: Refactored background operations ([Commit 2a6c63a9](https://github.com/Hzj-jie/koreader-202411/commit/2a6c63a9), [Commit c7fbdc64](https://github.com/Hzj-jie/koreader-202411/commit/c7fbdc64), [Commit d8592e1b](https://github.com/Hzj-jie/koreader-202411/commit/d8592e1b), [Commit d22a5a99](https://github.com/Hzj-jie/koreader-202411/commit/d22a5a99)) to use a unified task runner for automated jobs (such as automatic frontlight adjustments, clock updates, and network connectivity checks), separating background tasks from user interface elements to improve system responsiveness and reliability.
*   **Settings & Storage**: Upgraded the settings framework to improve storage efficiency and data safety, optimizing disk write operations to prevent configuration data loss or file corruption during saves ([Commit 7a0cc257](https://github.com/Hzj-jie/koreader-202411/commit/7a0cc257), [Commit 452c9a04](https://github.com/Hzj-jie/koreader-202411/commit/452c9a04)).
*   **Various crash preventions**: In components like image views, input dialogs, book map, Table of Contents navigation, synchronization, network listener, statistics plugin, date/time utility, reading history, and dictionary quick lookup.

### ⚡ Performance & Efficiency
Optimizations to reduce startup time, save battery, and extend device storage life:
*   **Optimized Storage Utilization**: Streamlined how configuration files are written to disk and saved, preventing redundant write operations and optimizing settings serialization to protect storage lifespan and reduce processing overhead ([Commit caa044c2](https://github.com/Hzj-jie/koreader-202411/commit/caa044c2) / [Fix #301](https://github.com/Hzj-jie/koreader-202411/issues/301), [PR #298](https://github.com/Hzj-jie/koreader-202411/pull/298)).
*   **Faster Startup & Plugin Loading**: Optimized the plugin loader to filter out obsolete plugins during the initial directory scan, reducing startup overhead ([Commit e6782844](https://github.com/Hzj-jie/koreader-202411/commit/e6782844)).

---

## 📜 Credits & Upstream Sources
This build incorporates logic and binaries from the following critical upstream packages:
*   **KOReader 2024.11 "Slang"**: Base framework and source distributions from the [v2024.11 Release](https://github.com/koreader/koreader/releases/tag/v2024.11).
*   **Platform Distributions**: Bundled resources derived from official release packages (`koreader-kindlepw2-v2024.11.zip`, `koreader-kindle-legacy-v2024.11.zip`, `koreader-kobo-v2024.11.zip`).
*   **SortedIteration**: Embedded ordered traversal utilities sourced from [Lua-Users SortedIteration](http://lua-users.org/wiki/SortedIteration).
*   **Formatting & Linting**: Integration powered by **StyLua v2.1.0** and **Luacheck v1.2.0**.
*   **Embedded Server**: SSH server operations backed by **Dropbearmulti 2024.85** static binaries.
