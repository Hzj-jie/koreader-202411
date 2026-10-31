# Translation and Localization Workflow

This document outlines the workflow and conventions used to manage translations, update `.po` / `.pot` localization files, and maintain internationalization (i18n) hygiene in KOReader.

---

## 1. Overview of the Translation Process

KOReader uses GNU `gettext` tools for localization. Translatable strings are extracted from source files into a master template, synchronized across language catalogs, translated, and validated:

1.  **Extract Strings**: `xgettext` extracts translatable strings into `koreader/l10n/templates/koreader.pot`.
2.  **Merge Template**: `msgmerge` syncs the master template into individual catalogs (`koreader/l10n/*/koreader.po`).
3.  **Translate Strings**: Active translations are maintained for Simplified Chinese (`zh_CN`) and Traditional Chinese (`zh_TW`).
4.  **Validate Catalogs**: Catalogs are validated using `msgfmt -c -o /dev/null`.

---

## 2. Extraction and Template Update (`./update-po.sh`)

To extract new strings from Lua files and update translation catalogs:

```bash
# Run from repository root
./update-po.sh
```

### Extraction Scope and Keyword Rules
*   `xgettext` scans `reader.lua`, `datastorage.lua`, `frontend/`, `plugins/`, and `tools/` using `--from-code=utf-8 --no-location`.
*   Supported extraction keywords: `_` is supported by default in `xgettext`; `update-po.sh` configures additional keywords:
    *   `gettext`
    *   `C_:1c,2` (contextual / `pgettext`)
    *   `N_:1,2` (plural forms / `ngettext`)
    *   `NC_:1c,2,3` (contextual plural forms / `npgettext`)
    *   `T_N:1,2` and `gettext.T_N:1,2` (template plural forms)
*   **Variable Binding Requirement**: Source files must define `local gettext = require("gettext")` (typically at the top of the file, or as a local variable in scope) and call `gettext("...")`. Inline calls like `require("gettext")("...")` are ignored by `xgettext` and will fail localization extraction hygiene tests in `linux/spec/unit/gettext_spec.lua`.
*   **Dynamic Concatenation Forbidden**: Never concatenate runtime variables inside `gettext(...)` (e.g. `gettext("Page " .. p)`). Use formatting templates (`T(gettext("Page %1"), p)`).
*   **Template Plurals (`T_N`)**: Use `gettext.T_N(msgid, msgid_plural, n, ...)` or import `local T_N = require("gettext").T_N` to combine plural selection with template substitution.

### Location Suppression (`--no-location`)
*   On `master`, both `xgettext` and `msgmerge` invocations in `update-po.sh` use the `--no-location` flag to prevent code location comments (`#: filename:line`) from being generated in templates and `.po` catalogs. This avoids noisy diffs when code lines shift.

---

## 3. String Rules and PO File Formatting

When adding or updating entries in `.po` files, follow standard PO formatting rules:

### A. Escaping Quotes and Formatting
*   Inner double quotes inside `msgid` or `msgstr` must be escaped with a backslash:
    ```po
    msgid "Show \"Cover\" image"
    msgstr "显示\"封面\"图片"
    ```
*   Multi-line strings must begin with an empty string `""` on the first line:
    ```po
    msgid ""
    "This is a very long string\n"
    "that spans multiple lines."
    msgstr ""
    "这是一个非常长的字符串\n"
    "跨越了多行。"
    ```

### B. Plural Forms
*   Plural translations use `msgid_plural` with language-specific plural indices:
    ```po
    msgid "Delete %1 book"
    msgid_plural "Delete %1 books"
    msgstr[0] "删除 %1 本书"
    ```

### C. Language-Specific Conventions
*   **Simplified Chinese (`zh_CN`) & Traditional Chinese (`zh_TW`)**:
    *   For phrases involving background execution, `zh_TW` uses `後台` rather than `背景` (e.g. `正在後台同步` vs `正在后台同步`), except for pre-existing legacy UI rows such as "Background jobs" / "背景工作".
*   **English Catalogs**: Do not add dummy or fuzzy entries to `en_GB`.

---

## 4. Parser Invariants (`gettext.lua`)

KOReader's runtime translation parser (`koreader/frontend/gettext.lua`) relies on strict formatting invariants:

*   **Blank Line Delimiters**: `gettext.lua`'s `parseEntry` only commits an entry when it encounters an empty line (`""` or EOF). Every PO entry must be separated by at least one blank line; missing blank lines cause subsequent entries to be skipped.
*   **Obsolete Entry Boundaries**: On branches whose catalogs retain obsolete sections (`#~`), placing an active entry immediately after a fuzzy obsolete entry (`#, fuzzy` followed by `#~ msgid ...`) can cause `gettext.lua` to drop the active entry. Always insert new active entries in template order within the active section of the catalog, above any obsolete blocks.

---

## 5. Validation and Testing

### Syntax and Consistency Validation
Always pass `-o /dev/null` when running `msgfmt -c` to prevent an untracked `messages.mo` file from being created in the current working directory:

```bash
# Validate individual catalogs
msgfmt -c -o /dev/null koreader/l10n/zh_CN/koreader.po
msgfmt -c -o /dev/null koreader/l10n/zh_TW/koreader.po

# Validate all project catalogs
find koreader/l10n/ -name "*.po" -exec msgfmt -c -o /dev/null {} +
```

`msgfmt -c` validates syntax, formatting variables, escape sequences, and flags duplicate `(msgctxt, msgid)` entries.

### Runtime Unit Testing Pattern
When asserting translations in unit tests, test language switching explicitly and restore the locale in `after_each`:

```lua
local gettext = require("gettext")

describe("Localization checks", function()
    after_each(function()
        gettext.changeLang("C")
    end)

    it("translates expected strings in zh_CN and zh_TW", function()
        gettext.changeLang("zh_CN")
        assert.are.same("无法找到任何 Wi-Fi，请稍后重试。", gettext("Cannot find any Wi-Fi, please try again later."))

        gettext.changeLang("zh_TW")
        assert.are.same("找不到任何 Wi-Fi，請稍後重試。", gettext("Cannot find any Wi-Fi, please try again later."))
    end)
end)
```

---

## 6. Resolving Catalogs When Merging `master.hotfix` into `master`

`master.hotfix` retains line location comments (`#: file:line`), whereas `master` suppresses them with `--no-location`. When merging `master.hotfix` into `master`:

1.  Check out `master`'s version of the catalogs during the merge to preserve `--no-location`:
    ```bash
    git checkout --ours koreader/l10n/
    ```
2.  Run `./update-po.sh` on `master` to extract new strings and synchronize catalog keys.
3.  Merge in the translations added on `master.hotfix` using `msgmerge` with a compendium reference:
    ```bash
    msgmerge --update --backup=off --no-fuzzy-matching --no-location \
        -C <(git show master.hotfix:koreader/l10n/zh_CN/koreader.po) \
        koreader/l10n/zh_CN/koreader.po koreader/l10n/templates/koreader.pot

    msgmerge --update --backup=off --no-fuzzy-matching --no-location \
        -C <(git show master.hotfix:koreader/l10n/zh_TW/koreader.po) \
        koreader/l10n/zh_TW/koreader.po koreader/l10n/templates/koreader.pot
    ```
4.  Verify with `msgfmt -c -o /dev/null` across all modified catalogs before finalizing the merge.
