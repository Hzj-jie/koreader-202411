# Testing Guidelines

This document outlines key conventions, isolation practices, and mocking patterns for writing and running unit tests in KOReader.

---

## 1. Unit Test File Location

*   Never add test spec files into the `koreader/` directory, unless they are coming from external plugins. Add tests into the `linux/spec/unit/` folder instead.

---

## 2. Settings Isolation (`LuaSettings`)

*   **No In-Memory Store**: In KOReader unit tests, `LuaSettings:open` does not implement in-memory store semantics. Passing `":memory:"` (unlike SQLite) does not create an ephemeral memory-backed table; it creates or reads a literal file named `:memory:` in the working directory, leaving dirty state and side effects.
*   **Temporary Files for Isolation**: Any unit tests using `LuaSettings` must use `os.tmpname()` to generate an isolated temporary file path and clean it up via `os.remove()` in `after_each`.

```lua
local settings_file

before_each(function()
    settings_file = os.tmpname()
end)

after_each(function()
    if settings_file then
        os.remove(settings_file)
    end
end)
```
