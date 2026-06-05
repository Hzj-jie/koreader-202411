-- Load helper first (fallback to ffi/loadlib.lua if test_helper.lua does not exist or fails)
if not pcall(dofile, "test_helper.lua") then
    dofile("ffi/loadlib.lua")
end

-- Execute busted runner (which parses command line arguments in `arg`)
require("busted.runner")({ standalone = false })

-- HACK: Avoid exit-time segmentation faults by forcing a full garbage collection
-- sweep before shutting down. This collects and runs finalizers (__gc) for all
-- remaining FFI objects (like SDL contexts, FreeType faces) while the underlying
-- C shared libraries are still fully loaded in memory.
collectgarbage("collect")
collectgarbage("collect")
