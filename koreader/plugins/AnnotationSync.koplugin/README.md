# AnnotationSync.koplugin

> **Sync your KOReader annotations everywhere!**
>
> Never lose a highlight, note, or bookmark again—AnnotationSync keeps your reading life in sync across all your devices.

## 🚀 Features

- **Cloud sync for KOReader annotations** (highlights, notes, bookmarks)
- **Settings Synchronization:** Synchronize your KOReader configuration settings (e.g., gesture configurations, page overlap styles) across all your devices selectively via your cloud storage.
- **Customizable Device Name:** Assign friendly custom names to your devices (e.g., "Bedside Kobo", "Phone") to easily identify them in sync menus.
- **Automatic background sync:** When enabled, books with changed annotations are queued and synced quietly in the background, one at a time, as soon as the device is online.
- **Core Cloud Storage Integration:** Integrates seamlessly with KOReader's built-in cloud storage (supporting Dropbox and WebDAV, and showing the active cloud configuration details directly in the settings menu).
- **Smart merging:** Resolves conflicts by comparing update timestamps to preserve your latest annotations.
- **Failsafe protection:** Prevents accidental remote data loss when setting up a fresh device.
- **Trash Bin & Restoration:** Easily view and undelete accidentally removed notes/highlights.
- **Configurable sync files:** Use hashes or actual filenames for sync storage.

## 📦 Installation

AnnotationSync ships with this KOReader build but is disabled by default:
1. Enable **Annotation Sync** in **Tools** -> **Plugin management**.
2. Restart KOReader.

## 🛠 Usage & Configuration

### ⚙️ Cloud Storage Setup

AnnotationSync integrates directly with KOReader's built-in cloud storage:
1. Ensure your cloud storage provider is configured in KOReader.
2. Go to **Settings** -> **Document** -> **Annotation Sync** -> **Settings** -> **Cloud settings**.
3. Select your desired cloud storage service.
4. Browse to the folder for the sync files, long-press **Long-press to choose current folder** and tap **Choose**.

*By default, sync files are named after a hash of the document content. To use actual filenames instead (useful if you organize files with Calibre):*
- **Settings** -> **Document** -> **Annotation Sync** -> **Settings** -> **Use filename instead of hash**

### ⚙️ Settings Synchronization

Keep your KOReader settings (e.g., gestures, page overlap style) synchronized across devices.

#### 1. Selecting Settings to Sync
1. Go to **Settings** -> **Document** -> **Annotation Sync** -> **Settings** -> **Show changed settings**.
2. This displays a hierarchical list of settings that differ from their default/vanilla configuration, categorized by domains (e.g., `[reader]`, `[defaults]`, `[settings/gestures]`).
3. Dictionary settings open submenus, and list arrays are compared as single entities.
4. Tap items to toggle their sync status. A checkmark `[✓]` indicates it will be synchronized:
   ```text
   [✓] [reader] page_overlap_style: default -> none
   [ ] [settings/gestures] gesture_reader >
   ```
5. You can use **Select All** or **Clear Selection** at any menu level to easily batch-configure settings. Your selections are automatically saved.

#### 2. Pushing Settings to the Cloud
1. Go to **Settings** -> **Document** -> **Annotation Sync** -> **Push settings to cloud**.
2. The selected settings will be uploaded, keyed by your device name (**Settings** -> **Document** -> **Annotation Sync** -> **Settings** -> **Device name**, which defaults to the hardware model name if left blank).

#### 3. Pulling Settings from the Cloud
1. Go to **Settings** -> **Document** -> **Annotation Sync** -> **Pull settings from cloud**.
2. Select the device whose settings you want to import from the list of available devices (showing their upload timestamps).
3. The plugin will display the differences between that device's settings and your local configuration.
4. Select which settings you want to import and select **Import Selected Settings**. The plugin will automatically update the corresponding configurations and apply them.

> [!IMPORTANT]
> **Exclusions & Failsafes**
> To prevent settings conflicts, credentials leaks, or infinite sync loops, the following settings are strictly excluded from synchronization:
> - **Private credentials and server configurations** (e.g., `cloud_server_object`, cloud storage / WebDAV passwords)
> - **Device-specific identifiers and paths** (e.g., `device_id`, `device_name`, `lastfile`, `home_dir`, font maps, cover caches)
> - **Core plugin settings** (e.g., `annotation_sync_plugin` and `AnnotationSync` preferences)
> - **Database and statistics logs** (e.g., battery stats, terminal configs, book statistics)

> [!WARNING]
> **Security Warning**
> Synced settings are stored in cleartext (unencrypted JSON format) on your configured cloud storage destination under the `settings_sync.json` file. Avoid selecting or storing highly sensitive or private information in synced settings.

### 💾 Manual & Bulk Annotation Sync

- **Sync current book now:** Sync only the current document's annotations and bookmarks.
  - **Settings** -> **Document** -> **Annotation Sync** -> **Sync current book now**
- **Sync all pending books:** Mass-upload/download pending changes from all your offline reading sessions.
  - **Settings** -> **Document** -> **Annotation Sync** -> **Sync all pending books**
- **Automatic Syncing:** Automatically mass-sync all modified documents as soon as a network connection becomes available.
  - **Settings** -> **Document** -> **Annotation Sync** -> **Settings** -> **Sync pending books automatically**
- **Shortcuts:** You can bind "AnnotationSync: Sync current book now", "AnnotationSync: Sync all pending books", "AnnotationSync: Push settings to cloud" or "AnnotationSync: Pull settings from cloud" to any gesture or add them to a profile action list in KOReader.

### 🗑 Managing Deletions (Trash Bin)

AnnotationSync keeps track of deleted annotations so you can recover them:
- **Settings** -> **Document** -> **Annotation Sync** -> **Show deleted annotations**
- Tap on any deleted item to restore it, or use **Restore All** to recover everything.
- Restored items will be re-synced to the cloud on the next sync.

## 📦 Dropbox Setup

Setting up Dropbox on KOReader can be a little bit difficult. 
[This excellent post on the MobileRead forum](https://www.mobileread.com/forums/showthread.php?t=353670) explains the procedure in detail.

## 📦 Koofr (WebDAV) Setup

Koofr is a cloud storage provider that supports WebDAV. Connecting KOReader to Koofr via WebDAV requires a dedicated application password instead of your primary Koofr password.

### 1. Generate an Application Password on Koofr
1. Log in to the [Koofr Web App](https://app.koofr.net/).
2. Open your account menu and go to **Preferences**.
3. Select **Password** from the menu on the left.
4. Go to the **Generate new password** section, enter a name (e.g., `KOReader`), and click **Generate**.
5. Copy the generated password. *Note: You will not be able to see it again after leaving the page.*

### 2. Configure WebDAV in KOReader
1. Go to **Settings** -> **Document** -> **Annotation Sync** -> **Settings** -> **Cloud settings**.
2. If this is your first time, choose **Add service**, tap the **+** icon and choose **WebDAV**. Otherwise, select your existing WebDAV configuration and skip to step 5.
3. Fill in the following connection settings:
   - **Name**: `Koofr` (or any name of your choice)
   - **WebDAV address**: `https://app.koofr.net/dav/Koofr`
   - **Username**: Your Koofr account email address
   - **Password**: The application-specific password generated in Step 1 (do **not** use your primary Koofr login password)
   - **Start folder**: `/koreader` or `/AnnotationSync` (Recommended to keep sync files organized in a dedicated directory. Alternatively, you can use `/` for the root directory, but you must ensure any custom subfolders are created in Koofr beforehand.)
4. Tap **Save**, close the cloud storage list and select your new server.
5. Browse to the folder for the sync files, long-press **Long-press to choose current folder** and tap **Choose**.

## 🧪 Running Tests

The project includes a comprehensive test suite located under `linux/spec/unit/plugins/AnnotationSync.koplugin/`, plus `linux/spec/unit/plugins/annotationsync_spec.lua`. To run the tests from the `linux/` directory:

```bash
# Run all AnnotationSync unit and integration tests
./luajit test_runner.lua spec/unit/plugins/AnnotationSync.koplugin spec/unit/plugins/annotationsync_spec.lua
```

## 🤝 Contributing

Pull requests, feature suggestions, and bug reports are very welcome! Open an issue or submit a PR.

---

**AnnotationSync.koplugin**: Your reading notes, highlights, and bookmarks—always with you, always safe.
