local original_os_exit = os.exit
local exit_code = 0
os.exit = function(code, close)
    -- Intercept Busted's exit call, record the exit code, and return.
    -- Busted will finish its execution flow and return to our script.
    exit_code = code or 0
end

-- Load helper first (fallback to ffi/loadlib.lua if test_helper.lua does not exist or fails)
if not pcall(dofile, "test_helper.lua") then
    dofile("ffi/loadlib.lua")
end

-- Busted runner on Lua 5.1/LuaJIT throws error() on test failures instead of calling os.exit.
-- We wrap it in pcall to catch the failure path, then handle exit safely.
local ok, err = pcall(function()
    require("busted.runner")({ standalone = false })
end)

if not ok then
    io.stderr:write("RUNNER ERROR: " .. tostring(err) .. "\n")
    exit_code = 1
end

-- Force a garbage collection sweep to finalize all unreachable test-created cdata/FFI objects
-- while C libraries are still loaded in memory. This will surface any real finalizer bugs
-- (like double-frees) during the test run instead of hiding them.
collectgarbage("collect")
collectgarbage("collect")

-- Exit cleanly without VM teardown to prevent exit-time finalization race conditions.
original_os_exit(exit_code, false)
