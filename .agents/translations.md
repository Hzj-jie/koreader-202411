# Translation and Localization Workflow

This document outlines the workflow and tools used to manage translations, update `.po` / `.pot` localization templates, and merge translations for newly added plugins or core features in this workspace.

---

## Overview of the Translation Process

KOReader uses standard GNU `gettext` tools for localization. The process generally follows these steps:

1.  **Extract Strings**: Extract translatable strings (using `_("string")` or `_("string", ...)` functions) from source code into the master template (`koreader.pot`).
2.  **Merge Template**: Merge the updated `koreader.pot` template into the individual language catalogs (`koreader.po`).
3.  **Translate Strings**: Translate the new/empty keys. This can be done via automated helper scripts, translation dictionaries, or manual translation.
4.  **Validate syntax**: Validate the syntax of PO files using `msgfmt`.

---

## 1. Updating POT Template and PO Catalogs

To extract new strings from Lua files and update the translation template:

```bash
# Run the PO update script from the workspace root
./update-po.sh
```

This script:
*   Scans the codebase (`koreader/` directory) for translatable strings.
*   Updates `koreader/l10n/koreader.pot`.
*   Uses `msgmerge` to sync the updated keys into all target language directories (`koreader/l10n/*/koreader.po`), marking new additions as empty/untranslated.

---

## 2. Automated Translation and Merging

When importing third-party plugins (like `simpleui`), translations might be defined inline or in separate localization tables. We use scripts to merge these translations into the main PO catalogs.

### A. Python Helper Scripts

For bulk translation, we have developed several Python scripts located in the sandbox/scratch directory:

*   **`scratch/merge_plugin_translations.py`**:
    *   Iterates over all plugin-specific translations.
    *   Finds matching empty/fuzzy keys in individual `koreader.po` files.
    *   Applies the translations while preserving formatting (escaping double quotes, preserving newlines, and supporting plurals `msgstr[0]`/`msgstr[1]`).
*   **`scratch/apply_translations.py`**:
    *   Applies a mapping of translated strings directly to specified PO files.
    *   Translates default British English (`en_GB`) by copying `msgid` to `msgstr` and marking them as fuzzy (`#, fuzzy`).
*   **`scratch/manual_translate.py`**:
    *   Used to write targeted, user-provided dictionary overrides directly into the PO catalogs.

### B. Mappings & Conversions

*   **Simplified Chinese (`zh_CN`) & Traditional Chinese (`zh_TW`)**:
    *   For `zh_TW`, we use OpenCC (`opencc-purepy` library) to automatically convert Simplified Chinese translations to Traditional Chinese variants.
    *   We supplement this with custom dictionaries to handle region-specific phrasing (e.g. "folder" -> "資料夾", "file" -> "檔案").

---

## 3. String Rules and PO File Formatting

When editing PO files (manually or via scripts), adhere to the following rules:

### A. Escaping Quotes
*   Since PO entries are wrapped in double quotes, any inner double quotes in the translation text **must** be escaped with a backslash:
    ```po
    msgid "Show \"Cover\" image"
    msgstr "显示\"封面\"图片"
    ```

### B. Multi-line Strings
*   If a string spans multiple lines, split it into concatenated quoted strings:
    ```po
    msgid ""
    "This is a very long string\n"
    "that spans multiple lines."
    msgstr ""
    "这是一个非常长的字符串\n"
    "跨越了多行。"
    ```

### C. Plural Forms
*   Plural translations use `msgid_plural` and indices starting at `[0]` (depending on the language specification):
    ```po
    msgid "Delete %d book"
    msgid_plural "Delete %d books"
    msgstr[0] "删除 %d 本书"
    ```

---

## 4. Validation

Always validate the PO file syntax before committing changes. Syntactically invalid PO files will break localizations or fail compilation.

```bash
# Validate a specific PO file
msgfmt -c koreader/l10n/zh_CN/koreader.po

# Validate all PO files in the project
find koreader/l10n/ -name "*.po" -exec msgfmt -c {} \;
```

If there are syntax errors (e.g., mismatched variables, unclosed quotes, or bad escapes), `msgfmt` will output the file name and the exact line number of the failure. Make sure all validation warnings are resolved.
