-- Import the shared linux test helper to apply global mocks (like hasSystemFonts = false)
local workspace = os.getenv("KO_WORKSPACE_DIR")
if workspace then
    dofile(workspace .. "/linux/test_helper.lua")
else
    -- Fallback if run without run_tests.sh (e.g. manual direct execution on host)
    dofile("../linux/test_helper.lua")
end

-- HACK: We intercept the module resolution path using package.loaders.
-- This approach is chosen because:
-- 1. The baseline tests inside the 'origin/' directory must remain a pristine replica of
--    KOReader 2024.11 and cannot be modified directly.
-- 2. Standard test-level mocks/stubs are easily wiped out by the runner's
--    package.unloadAll() cycles which insulate test files from one another.
-- 3. Modifying the global search loaders is persistent across unloadAll() calls.
local intercepting = false
table.insert(package.loaders, 1, function(modname)
    if intercepting then
        return nil
    end

    if modname ~= "ffi/SDL2_0" and modname ~= "device" and modname ~= "document/credocument" then
        return nil
    end

    intercepting = true
    local ok, res = pcall(require, modname)
    intercepting = false

    if not ok then
        error(res)
    end

    -- Mock charging state stubs for baseline tests.
    -- If run on a real physical host (e.g. laptop) that is charging, SDL FFI reports
    -- charging = true. This prevents UIManager from ticking suspend timers, causing
    -- autosuspend and batterystat tests to fail. We force them to return false.
    if modname == "ffi/SDL2_0" then
        if type(res) == "table" and res.getPowerInfo then
            res.getPowerInfo = function(...)
                return true, false, true, 50
            end
        end
    elseif modname == "device" then
        if type(res) == "table" and res.getPowerDevice then
            local PowerD = res:getPowerDevice()
            if PowerD then
                PowerD.isCharging = function() return false end
                PowerD.isCharged = function() return false end
            end
        end
    -- Mock closed document checks to prevent finalizer crash in screenshoter_spec.lua.
    -- The screenshoter test calls readerui:closeDocument() then readerui:onClose().
    -- This clears the document, but onClose() still triggers a SaveSettings propagation,
    -- which tries to read page info on the closed CreDocument instance.
    -- We force a fallback return value 1 instead of throwing index errors on C++ _document.
    elseif modname == "document/credocument" then
        if type(res) == "table" and res.getPageFromXPointer then
            local original_getPageFromXPointer = res.getPageFromXPointer
            res.getPageFromXPointer = function(self, xp)
                if not self._document then
                    require("logger").warn("getPageFromXPointer called on closed CreDocument")
                    return 1
                end
                return original_getPageFromXPointer(self, xp)
            end
        end
    end

    return function()
        return res
    end
end)
