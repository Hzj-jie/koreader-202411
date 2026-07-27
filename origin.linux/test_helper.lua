-- Import the shared linux test helper to apply global mocks and helper stubs
local workspace = os.getenv("KO_WORKSPACE_DIR")
if workspace then
    dofile(workspace .. "/linux/test_helper.lua")
else
    dofile("../linux/test_helper.lua")
end
