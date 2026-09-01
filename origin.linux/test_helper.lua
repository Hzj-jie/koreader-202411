-- Dedicated test helper for origin.linux environment
-- Load the base test helper from linux/
local workspace = os.getenv("KO_WORKSPACE_DIR")
if workspace then
    dofile(workspace .. "/linux/test_helper.lua")
else
    dofile("../linux/test_helper.lua")
end

-- Unset KO_MULTIUSER in the C environment so origin's device/sdl/device detects Emulator instead of Desktop
local ffi = require("ffi")
pcall(function()
    ffi.cdef[[
        int unsetenv(const char *name);
    ]]
    ffi.C.unsetenv("KO_MULTIUSER")
end)

-- Ensure screenshots directory exists in sandbox
pcall(function()
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir("screenshots")
end)

-- Intercept require globally for origin/ unhardened codebase stubs
local orig_require = _G.require
_G.require = function(name)
    local res = orig_require(name)

    if name == "device" then
        if type(res) == "table" and res.getPowerDevice then
            local PowerD = res:getPowerDevice()
            if PowerD then
                PowerD.isCharging = function() return false end
                PowerD.isCharged = function() return false end
            end
        end
    elseif name == "document/credocument" then
        if type(res) == "table" and res.getPageFromXPointer and not res._patched_xpointer then
            res._patched_xpointer = true
            local original_getPageFromXPointer = res.getPageFromXPointer
            res.getPageFromXPointer = function(self, xp)
                if not self._document then
                    local l_ok, logger = pcall(orig_require, "logger")
                    if l_ok and logger and logger.warn then
                        logger.warn("getPageFromXPointer called on closed CreDocument")
                    end
                    return 1
                end
                return original_getPageFromXPointer(self, xp)
            end
        end
    elseif name == "device/generic/powerd" then
        if type(res) == "table" then
            if res.new and not res._orig_new then
                res._orig_new = res.new
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
                    local inst = res._orig_new(self, param)
                    rawset(inst, "frontlight_save", nil)
                    inst.frontlight_save = nil
                    return inst
                end
            end
            if res.setIntensity and not res._orig_setIntensity then
                res._orig_setIntensity = res.setIntensity
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
        end
    elseif name == "docsettings" then
        if type(res) == "table" and res.getSidecarDir and not res._orig_getSidecarDir then
            res._orig_getSidecarDir = res.getSidecarDir
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
                        local u_ok, util = pcall(orig_require, "util")
                        if u_ok and util and util.makePath then
                            util.makePath(sdr_dir)
                        else
                            local lfs_mod = package.loaded["libs/libkoreader-lfs"]
                            if lfs_mod and lfs_mod.mkdir then
                                lfs_mod.mkdir(sdr_parent)
                                lfs_mod.mkdir(sdr_dir)
                            end
                        end
                        return sdr_dir
                    end
                end
                return res._orig_getSidecarDir(self, doc_path, force_location)
            end
        end
    elseif name == "ffi/rtc" then
        if type(res) == "table" and not res._orig_secondsFromNowToEpoch then
            res._orig_secondsFromNowToEpoch = res.secondsFromNowToEpoch
            local fixed_now = 1700000000
            res.secondsFromNowToEpoch = function(self, seconds_from_now)
                return fixed_now + (seconds_from_now or 0)
            end
        end
    end

    return res
end

return {
    max_jobs = 1,
}
