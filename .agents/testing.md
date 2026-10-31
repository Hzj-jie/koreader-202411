# Testing Guidelines

This document outlines key conventions, test execution environments, isolation practices, and mocking patterns for writing and running unit tests in KOReader.

---

## 1. Unit Test File Location

*   Never add test spec files into the `koreader/` directory, unless they are coming from external plugins. Add tests into the `linux/spec/unit/` folder instead (or plugin-specific spec directories under `linux/spec/unit/plugins/`).

---

## 2. Test Execution and Sandbox Architecture

### Running Unit Tests
Tests can be executed from the repository root using the sandbox wrapper or directly from the `linux/` platform directory:

```bash
# Run specific specs from repository root (paths relative to linux/)
./run_tests.sh spec/unit/input_spec.lua spec/unit/gettext_spec.lua

# Run directly using the platform runner from linux/
cd linux && ./luajit test_runner.lua spec/unit/input_spec.lua
```

*   **Inspect Summary Outputs**: Always inspect the final summary block and verify `Passed files/cases N/N` (and no `[  FAILED  ]` lines). Do not rely solely on the exit code of background runner processes.

### Sandbox Semantics and Path Resolution
*   `./run_tests.sh` prepares an isolated sandbox directory in `/tmp/koreader_sandbox_XXXXXX/run/context` with symlinks pointing back to `linux/`.
*   **Never Switch Branches While Tests Run**: Because sandbox symlinks resolve against the live working tree, switching git branches in your checkout while a test suite is running will produce mixed-state failures. For isolated background runs across multiple branch tips, use `git archive` copies.
*   **CWD-Relative Paths in Specs**: Inside the test sandbox, the working directory is the `linux/` platform mirror. Always access source files using cwd-relative paths (`frontend/`, `plugins/`, `tools/`, `reader.lua`, `datastorage.lua`, `resources/`). Never hardcode `../koreader/` paths, as `..` points outside the sandbox root.
*   **Anchoring Path Patterns**: When matching path patterns in mocks or string assertions (e.g. searching for `/tmp`), anchor patterns (e.g. `/tmp$`) to avoid false-matching temporary sandbox or worker prefixes such as `/tmp/koreader_sandbox_*` or `/tmp/.../worker_*`.

---

## 3. Test Isolation and State Teardown

### Settings Isolation (`LuaSettings`)
*   `LuaSettings:open` does not implement in-memory store semantics; passing `":memory:"` creates a literal file named `:memory:` in the current directory.
*   Always use `os.tmpname()` to generate an isolated temporary file path, and remove it unconditionally in `after_each`:

```lua
local settings_file

before_each(function()
    settings_file = os.tmpname()
end)

after_each(function()
    os.remove(settings_file)
end)
```

### Module State and Teardown Hygiene
*   **Restore Mocked Modules**: When stubbing `package.loaded` or mutating module upvalues, restore original values in `after_each` or a `finally` block.
*   **Teardown Input and Environment**: Tests that open devices or modify environment variables must clean up in `after_each` (e.g. `Input.opened_devices = {}`, `C.unsetenv(...)`, or calling `Input:UIManagerReady(require("ui/uimanager"))` to reset device state).
*   **Restore Locales**: Any test calling `gettext.changeLang("...")` must restore the default locale with `gettext.changeLang("C")` in `after_each`.

---

## 4. Assertions and Verification Principles

### UI Text Assertions
*   **Never Assert Untranslated English Literals**: Never compare UI text (`btn.text`, `widget.title`, `shown_widget.text`, or `Notification` / `InfoMessage` text) against hardcoded English strings. Always compare against `gettext(msgid)`:
    ```lua
    -- Correct:
    assert.are.same(gettext("Cannot find any Wi-Fi, please try again later."), widget.text)

    -- Incorrect:
    assert.are.same("Cannot find any Wi-Fi, please try again later.", widget.text)
    ```

### Red-Green Verification
*   Implement unit tests and production code in separate steps to avoid self-fulfilling tests.
*   Verify tests fail before applying the fix (red) and pass after the fix (green).
*   Assert end-to-end invariants directly rather than mocking out internal state by hand.

---

## 5. Mocking, FFI, and Lifecycle Gotchas

*   **`UIManager` Initialization Order**: `require("ui/uimanager")` triggers `UIManager:init()`, which in turn executes `Device:_UIManagerReady` and `Input:UIManagerReady`. If a test intends to mock device configuration or input devices, require `ui/uimanager` in `setup()` first before configuring test stubs.
*   **Stubbing `os.execute`**: Always stub `os.execute` whenever exercising code paths that invoke external commands (e.g. process termination via `pkill` or shell scripts) to prevent unintended side effects on the host machine.
*   **FFI C Symbols are Read-Only**: Symbols in `ffi.C` (such as `C.ioctl` or `C.kill`) cannot be replaced using Busted's `stub(ffi.C, ...)`. Drive FFI code paths using real system resources (e.g., standard pipe file descriptors created with `C.pipe` will return `ENOTTY` when passed to `EVIOCGRAB` `ioctl`s).
