# Cache Architecture and Conventions

This document outlines the architectural role of KOReader's persistent cache directory, the rationale for preferring persistent storage over volatile `/tmp`, and the known causes of cache bloat.

---

## 1. Role: Persistent Auxiliary Storage vs. Volatile `/tmp`

*   **Derived, Recomputable Data**: The cache directory (`DataStorage:getCacheDir()`) contains no primary user state. Wiping the cache never causes loss of reading progress, settings, bookmarks, or annotations.
*   **Why Persistent Storage is Preferred**:
    *   **Expensive Recomputation Latency**: Heavy pre-computations (such as `cr3cache` DOM layout and pagination in `credocument.lua`, or font table parsing in `fontlist.lua`) can take 10–30+ seconds on low-power e-ink processors (800MHz–1GHz ARM). Persisting cache across reboots ensures fast book openings.
    *   **RAM Exhaustion on Low-Memory Devices**: `/tmp` is commonly mounted as `tmpfs` (RAM disk). Embedded devices (Kindle, Kobo) frequently operate with only 256MB–512MB of physical RAM. Storing 100MB+ of disk cache in `tmpfs` directly consumes physical RAM, leading to kernel OOM kills.
    *   **Multi-User & Desktop Isolation**: `/tmp` is globally shared and subject to permission collisions; `<data_dir>/cache` is scoped to the user's isolated configuration directory.
    *   **Android Sandboxing**: Standard Android apps cannot write to `/tmp` or `/data/local/tmp` due to SELinux restrictions.
*   **Role of `/tmp`**: Volatile storage (`DataStorage:getTmpDir()`) serves strictly as a runtime fallback when the primary storage is read-only (e.g. read-only SD cards or read-only network shares).

---

## 2. Root Causes of Cache Bloat

*   **High-Water Mark Retention**: Subsystems like `DocCache` and `cr3cache` implement LRU capacity evictions, but only evict when the cache is 100% full upon adding a new entry. When a user deletes books to free storage, the cache never shrinks downward; deleted books' cache entries remain until pushed out by new books.
*   **Disconnected Anonymous Hashes**: Cache filenames are anonymous hashes (MD5 or book hash). KOReader lacks a reverse index from book path to cache files, so deleting a book does not trigger cleanup of its cache entries.
*   **Fragmented Ownership**: No central manager enforces a global disk budget across the cache folder:
    *   `DocCache`: Page pixmaps in root `cache/` (~15–20MB LRU, ignores subdirectories).
    *   `cr3cache/`: C++ CREngine DOM layout cache (64MB default LRU).
    *   `bookinfo_cache.sqlite3`: CoverBrowser metadata DB (scales with library size, 20–80MB+).
    *   `cover_image.cache/`: Screensaver covers (5MB max).
    *   `fontlist/` & `calibre/`: Uncapped with no LRU.
*   **Orphan Residue (`tmpcr3cache`)**: CoverBrowser extracts covers in background subprocesses using `cache/tmpcr3cache`. If KOReader crashes, exits, or loses power during extraction, files in `tmpcr3cache` are never cleaned up because there is no LRU or startup cleanup for it.
