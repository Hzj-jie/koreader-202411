local ffi = require("ffi")

ffi.cdef[[
    int getpid(void);
]]

local parent_pid = ffi.C.getpid()
local original_os_exit = os.exit
local exit_code = 0

os.exit = function(code, close)
    local current_pid = ffi.C.getpid()
    if current_pid ~= parent_pid then
        -- We are inside a child process spawned via fork (e.g. util.runInSubProcess).
        -- We must exit immediately using the original os.exit to prevent the child
        -- from returning and leaking into the parent's test execution flow.
        original_os_exit(code or 0, false)
    else
        -- Parent process: Intercept Busted's exit call, record the exit code, and return.
        -- Busted will finish its execution flow and return to our script.
        exit_code = code or 0
    end
end

-- 1. Configure relative module search paths directly in Lua to avoid global env dependencies
package.path = "./base/spec/unit/?.lua;./spec/unit/?.lua;./?.lua;./common/?.lua;./frontend/?.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua;;"
package.cpath = "./?.so;./common/?.so;./libs/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;;"

-- 2. Load framework unit test helpers
if not pcall(dofile, "test_helper.lua") then
    dofile("ffi/loadlib.lua")
end

-- 3. Execute Busted runner (loads options automatically from .busted config file)
local ok, err = pcall(function()
    require("busted.runner")({ standalone = false })
end)

if not ok then
    io.stderr:write("RUNNER ERROR: " .. tostring(err) .. "\n")
    exit_code = 1
end

-- 4. Clean up and finalize all unreachable FFI objects while C dynamic libraries are still loaded
collectgarbage("collect")
collectgarbage("collect")

-- 5. Exit cleanly bypassing out-of-order VM teardown crashes
original_os_exit(exit_code, false)
