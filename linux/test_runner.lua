local original_os_exit = os.exit
os.exit = function(code, close)
    -- Intercept Busted's exit and force it to exit without running finalizers (close=false)
    -- to prevent exit-time FFI finalization race condition segfaults.
    original_os_exit(code or 0, false)
end

-- Load helper first (fallback to ffi/loadlib.lua if test_helper.lua does not exist or fails)
if not pcall(dofile, "test_helper.lua") then
    dofile("ffi/loadlib.lua")
end

-- Busted runner on Lua 5.1/LuaJIT throws error() on test failures instead of calling os.exit.
-- We wrap it in pcall to catch the failure path, then call original_os_exit safely.
local ok, err = pcall(function()
    require("busted.runner")({ standalone = false })
end)

if not ok then
    -- If Busted aborted with error() or threw a real runner crash, exit with failure code
    original_os_exit(1, false)
else
    -- Fallback exit code (though Busted's runner normally calls os.exit which is caught above)
    original_os_exit(0, false)
end
