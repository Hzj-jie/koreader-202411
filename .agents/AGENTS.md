# Project Rules

*   **Pre-commit Code Formatting**: Before committing any changes, run the `./runstylua.sh` script to ensure all modified Lua files conform to style guidelines.
*   **Static Code Analysis (Linter)**: Before committing any changes, run the `./runluacheck.sh` script to check for linter warnings or syntax errors. Ensure that no new linter warnings are introduced in the modified code.
*   **Clean Whitespace**: Always strip trailing whitespaces (including spaces on otherwise blank lines/lines with only spaces) from all modified files before committing changes. You can run `sed -i 's/[[:space:]]\+$//' <files>` or configure your editor to clean them up.
*   **Test Coverage for Code Changes**: Never change codebase logic or behavior without writing new tests or expanding existing unit tests to cover the modified/added paths.
*   **Pre-Refactor Testing**: If a large refactoring is planned or required, you must first add or verify baseline unit/integration tests that protect the existing behavior before changing the implementation.
*   **Issue Reference in Commit Messages**: In your commit messages, always reference Buganizer or GitHub issues using the following prefixes:
    *   Use `fix: #<issue-id>` if the change fully resolves the issue.
    *   Use `bug: #<issue-id>` if the change is related to, or a part of, the work for the issue.
*   **Plugin Development & Import Guidelines**: When importing new plugins, modifying existing ones, or handling target-specific exclusions/linking, you must read and adhere to the guidelines documented in [plugin_import_guide.md](file:///.agents/plugin_import_guide.md).
*   **Test Spec Files Location**: Never add test spec files into the `koreader/` directory, unless they are coming from external plugins. Add tests into the `linux/` folder instead.



