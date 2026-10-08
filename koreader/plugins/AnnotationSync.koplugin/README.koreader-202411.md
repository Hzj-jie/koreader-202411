# AnnotationSync Compatibility for KOReader v2024.11

This folder contains the `AnnotationSync` plugin imported into KOReader v2024.11 with necessary compatibility fixes to make the unit and integration tests run successfully on this version.

## Original Plugin Information
- **Source Repository:** [dani84bs/AnnotationSync.koplugin](https://github.com/dani84bs/AnnotationSync.koplugin)
- **Imported Version/Tag:** `v1.9.9`
- **Original Git Commit Hash:** `58edf0bea3ad096972031acba0b6b9026f1b5698`

## Modifications Applied for Compatibility

The following changes were made to resolve test failures, optimize runtime performance, and ensure API compatibility:

### New Features

1. **Fast background sync without opening books**:
   - Reads and writes annotations directly from sidecar metadata files, syncing in the background without needing to load document rendering engines or open heavy files into memory.
2. **Automatic background sync**:
   - When "Automatically Sync All when network becomes available" is on, books with changed annotations are queued and synced in the background one at a time, as soon as the device is online.
3. **Non-blocking manual sync with network prompts**:
   - "Manual Sync", "Sync now" in the pending documents list and "Sync All" queue their books for the background sync instead of freezing the user interface, and prompt to enable Wi-Fi when offline. A notification confirms each tap; after "Manual Sync" and "Sync now", another one tells when the book is synced, or a message says that its sync failed.
4. **Library-wide annotation discovery**:
   - Adds a "Scan library for unsynced annotations" feature to automatically discover and queue existing annotations across all previously read books.
5. **Localization & Chinese translation support**:
   - Integrated into KOReader's central `l10n/` catalog (including Simplified Chinese, Traditional Chinese, Italian, and Hungarian) for native gettext localization.

### Improvements & Bug Fixes

1. **Avoid empty cloud file uploads**:
   - Prevents uploading empty annotation files to cloud storage when no local annotations exist for a document.
2. **Instant menu responsiveness**:
   - Cloud sync menu options ("Push settings to cloud", "Pull settings from cloud", and "Manual Sync") immediately become available as soon as cloud storage is configured or a document is opened.
3. **Cleaned up deprecated features**:
   - Removed obsolete Reading Progress Sync options that depended on unsupported cloud APIs in KOReader v2024.11.
4. **v2024.11 API compatibility**:
   - Updated settings storage calls and utility functions to align with KOReader v2024.11 interfaces.
5. **Pagination accuracy**:
   - Aligned test expectations with KOReader v2024.11 pagination rendering engine.
6. **Clear pending documents upon sync completion**:
   - Prevents synced documents from being re-added to the pending list during post-sync UI refreshes, ensuring the pending documents list is cleanly cleared after "Sync All".
