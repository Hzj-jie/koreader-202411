-- Import the shared linux test helper to apply global mocks (like hasSystemFonts = false)
local workspace = os.getenv("KO_WORKSPACE_DIR")
if workspace then
    dofile(workspace .. "/linux/test_helper.lua")
else
    -- Fallback if run without run_tests.sh (e.g. manual direct execution on host)
    dofile("../linux/test_helper.lua")
end


