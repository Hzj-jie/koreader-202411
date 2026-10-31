# Core Subsystems and Architecture Conventions

This document outlines key conventions and architectural designs for core KOReader subsystems, including background job execution, atomic file persistence, and document settings (`DocSettings`) management.

---

## 1. Background Jobs and Process Scheduling

KOReader executes asynchronous and heavy operations (such as cloud synchronization, cover extraction, and network probes) via background runners to preserve UI responsiveness.

### Background Runners and Job Specifications
*   **Job Validation**: `BackgroundRunner` and `CommandRunner` (`MAX_JOBS = 10`) assert valid execution parameters (valid `executable` type and `when` scheduling trigger).
*   **Keyed Job Deduplication (`BackgroundJobs.insertKeyed`)**:
    *   To prevent duplicate background jobs from queueing concurrently (e.g. repeated user taps or recurring timer triggers), jobs are registered with unique keys.
    *   Dynamic closures can generate unique structural fingerprints using `util.functionFingerprint`.
    *   Subsystem state asserts active keys before clearing upon job completion to catch unbalanced lifecycle transitions.

### Forked Child UI Event Deferral (`NetworkMgr`)
*   When background subprocesses perform network requests, querying network status (such as `NetworkMgr:queryOnlineState()`) can detect state transitions.
*   **Defer Event Broadcasting via `UIManager:nextTick`**: In `NetworkMgr:_setOnlineState`, `NetworkOnline` and `NetworkOffline` events are broadcast to the application through `UIManager:nextTick` rather than called synchronously. This ensures that forked child processes executing network checks do not trigger UI event handlers designed exclusively for the main process loop.

---

## 2. Atomic File Persistence

All persistent file operations must guard against corrupted or partial writes caused by abrupt power loss, device reboots, or filesystem exhaustion.

### Write-Sync-Rename Protocol (`util.writeToFile` & `ffiUtil.copyFile`)
*   **Temporary Target Files**: Both `util.writeToFile` and `ffiUtil.copyFile` write output to a temporary `<target_path>.new` file on the same filesystem.
*   **Verification of All Steps**: Every intermediate step—file creation, data writes, `fsyncOpenedFile`, and `file:close()`—is checked.
*   **Atomic Directory Replacement**: Only upon completely successful write and flush is the temporary file atomically renamed over the destination using `os.rename`, followed by an `fsync` on the containing directory.
*   **Clean Failure Recovery**: If any step fails (e.g. `ENOSPC`), the `.new` file is cleaned up, the original file is left completely untouched, and callers display an error `Notification` or `InfoMessage` rather than crashing.

---

## 3. Document Settings (`DocSettings`) and Storage Fallbacks

`DocSettings` manages per-book settings, reading progress, and sidecar directories (`.sdr` folders) across multiple candidate storage locations.

### Candidate Search and Validation
*   `getCandidates(doc_path)` (module-local helper in `koreader/frontend/docsettings.lua`, called by `DocSettings:open`) asserts a valid, non-empty `doc_path` to prevent searches on invalid document handles.
*   Sidecar paths follow a prioritized candidate list (e.g., adjacent to document, alternate device storage, and local configuration cache).

### Safe Location Migration
*   When moving or updating sidecar assets (`DocSettings:flush` and `DocSettings.updateLocation`), associated files (such as book covers or custom metadata) are deleted from the source location only after `ffiUtil.copyFile` successfully copies them to the target.
*   If a copy fails, the cached location is marked `false` (rather than `nil`) to ensure that cleanup or purge routines do not accidentally delete the sole remaining copy at the source location.

### Storage Read-Only Warning (`DataStorage`)
*   `initDataDir()` (module-local function in `koreader/datastorage.lua`, executed on module load) checks directory creation status on primary storage.
*   If writable storage cannot be initialized (e.g. an SD card mounted read-only), `DataStorage:showStorageWarningIfNeeded()` surfaces a non-dismissable confirmation dialog once `UIManager` is ready, alerting the user before any reading session begins.
