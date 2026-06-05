local original_os_exit = os.exit
local exit_code = 0
os.exit = function(code, close)
    -- Intercept Busted's exit call, record the exit code, and return.
    -- Busted will finish its execution flow and return to our script.
    exit_code = code or 0
end

-- 1. Configure relative module search paths directly in Lua to avoid global env dependencies
package.path = "./base/spec/unit/?.lua;./spec/unit/?.lua;./?.lua;./common/?.lua;./frontend/?.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua;;"
package.cpath = "./?.so;./common/?.so;./libs/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;;"

-- 2. Load framework unit test helpers
if not pcall(dofile, "test_helper.lua") then
    dofile("ffi/loadlib.lua")
end

-- 3. Reconstruct arguments list with default test runner options
local targets = {}
if #arg == 0 then
    targets = { "base/spec/unit", "spec/unit" }
else
    for i = 1, #arg do
        table.insert(targets, arg[i])
    end
end

_G.arg = {
    "--exclude-tags=notest",
    "--output=gtest",
    "--sort-files",
}
for _, target in ipairs(targets) do
    table.insert(_G.arg, target)
end

-- 4. Execute Busted runner
local ok, err = pcall(function()
    require("busted.runner")({ standalone = false })
end)

if not ok then
    io.stderr:write("RUNNER ERROR: " .. tostring(err) .. "\n")
    exit_code = 1
end

-- 5. Clean up and finalize all unreachable FFI objects while C dynamic libraries are still loaded
collectgarbage("collect")
collectgarbage("collect")

-- 6. Exit cleanly bypassing out-of-order VM teardown crashes
original_os_exit(exit_code, false)
