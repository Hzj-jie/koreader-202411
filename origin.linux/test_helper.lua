-- Dedicated test helper for origin.linux environment
-- Load the base test helper from linux/
local workspace = os.getenv("KO_WORKSPACE_DIR")
if workspace then
    dofile(workspace .. "/linux/test_helper.lua")
else
    dofile("../linux/test_helper.lua")
end

-- Ensure screenshots directory exists in sandbox
pcall(function()
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir("screenshots")
end)

-- Helper stubs for origin/ unhardened codebase
local intercepting = false
table.insert(package.loaders, 1, function(modname)
    if intercepting then
        return nil
    end

    if modname ~= "device/generic/powerd"
        and modname ~= "docsettings"
        and modname ~= "ffi/rtc"
        and modname ~= "ffi/SDL2_0"
        and modname ~= "device"
        and modname ~= "device/sdl/device"
        and modname ~= "document/credocument" then
        return nil
    end

    intercepting = true
    local ok, res = pcall(require, modname)
    intercepting = false

    if not ok then
        return nil
    end

    if type(res) == "table" then
        if modname == "ffi/SDL2_0" then
            if res.getPowerInfo then
                res.getPowerInfo = function(...)
                    -- Return deterministic power state: has battery, not charging, not plugged, 50% capacity
                    return true, false, false, 50
                end
            end
        elseif modname == "device" then
            if res.getPowerDevice then
                local PowerD = res:getPowerDevice()
                if PowerD then
                    PowerD.isCharging = function() return false end
                    PowerD.isCharged = function() return false end
                end
            end
        elseif modname == "device/sdl/device" then
            res.hasSystemFonts = function() return false end
            if not res.canSuspend or res.canSuspend() == false then
                res.canSuspend = function() return true end
                res.supportsScreensaver = function() return true end
            end
        elseif modname == "document/credocument" then
            if res.getPageFromXPointer then
                local original_getPageFromXPointer = res.getPageFromXPointer
                res.getPageFromXPointer = function(self, xp)
                    if not self._document then
                        require("logger").warn("getPageFromXPointer called on closed CreDocument")
                        return 1
                    end
                    return original_getPageFromXPointer(self, xp)
                end
            end
        elseif modname == "device/generic/powerd" then
            if res.new then
                local orig_new = res.new
                res.new = function(self, param)
                    if type(self.frontlightIntensityHW) == "table" and self.frontlightIntensityHW.clear then
                        self.frontlightIntensityHW:clear()
                    end
                    if type(self.setIntensityHW) == "table" and self.setIntensityHW.clear then
                        self.setIntensityHW:clear()
                    end
                    if type(self.turnOnFrontlightHW) == "table" and self.turnOnFrontlightHW.clear then
                        self.turnOnFrontlightHW:clear()
                    end
                    if type(self.turnOffFrontlightHW) == "table" and self.turnOffFrontlightHW.clear then
                        self.turnOffFrontlightHW:clear()
                    end
                    self.frontlight_save = nil
                    local inst = orig_new(self, param)
                    rawset(inst, "frontlight_save", nil)
                    inst.frontlight_save = nil
                    return inst
                end
            end
            if res.setIntensity then
                res.setIntensity = function(self, intensity)
                    local norm = self:normalizeIntensity(intensity)
                    if norm == rawget(self, "frontlight") then
                        return false
                    end
                    self.fl_intensity = norm
                    self:setIntensityHW(norm)
                    self:stateChanged()
                    return true
                end
            end
        elseif modname == "docsettings" then
            if res.getSidecarDir then
                local orig_getSidecarDir = res.getSidecarDir
                res.getSidecarDir = function(self, doc_path, force_location)
                    local worker_dir = os.getenv("XDG_CONFIG_HOME") or os.getenv("TMPDIR")
                    if (force_location == nil or force_location == "doc") and worker_dir and type(doc_path) == "string" then
                        local test_subpath = doc_path:match("spec/[%w/]*unit/data/(.+)")
                            or doc_path:match("spec/[^/]+/data/(.+)")
                            or doc_path:match("base/[^/]+/data/(.+)")
                            or doc_path:match("[%/]test/(.+)")
                            or doc_path:match("^test/(.+)")
                        if test_subpath then
                            local sdr_parent = worker_dir .. "/sdr"
                            local base_name = test_subpath:match("(.*)%.") or test_subpath
                            local sdr_dir = sdr_parent .. "/" .. base_name .. ".sdr"
                            local u_ok, util = pcall(require, "util")
                            if u_ok and util and util.makePath then
                                util.makePath(sdr_dir)
                            else
                                local l_ok, lfs_mod = pcall(require, "libs/libkoreader-lfs")
                                if l_ok and lfs_mod and lfs_mod.mkdir then
                                    lfs_mod.mkdir(sdr_parent)
                                    lfs_mod.mkdir(sdr_dir)
                                end
                            end
                            return sdr_dir
                        end
                    end
                    return orig_getSidecarDir(self, doc_path, force_location)
                end
            end
        elseif modname == "ffi/rtc" then
            local fixed_now = 1700000000
            res.secondsFromNowToEpoch = function(self, seconds_from_now)
                return fixed_now + (seconds_from_now or 0)
            end
        end
    end

    return function() return res end
end)

return {
    max_jobs = 1,
}


