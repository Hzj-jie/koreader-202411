-- Dedicated test helper for origin.linux environment
-- Load the base test helper from linux/
local workspace = os.getenv("KO_WORKSPACE_DIR")
if workspace then
    dofile(workspace .. "/linux/test_helper.lua")
else
    dofile("../linux/test_helper.lua")
end

-- Helper stub for powerd in origin/ unhardened codebase
local intercepting = false
table.insert(package.loaders, 1, function(modname)
    if intercepting or modname ~= "device/generic/powerd" then
        return nil
    end
    intercepting = true
    local ok, res = pcall(require, modname)
    intercepting = false
    if ok and type(res) == "table" then
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
    end
    return function() return res end
end)

-- Helper stub for DocSettings in origin/ unhardened codebase:
-- Route test sample SDR directories to worker-isolated directories to prevent parallel worker collisions on shared spec/front/unit/data/
local intercepting_docsettings = false
table.insert(package.loaders, 1, function(modname)
    if intercepting_docsettings or modname ~= "docsettings" then
        return nil
    end
    intercepting_docsettings = true
    local ok, res = pcall(require, modname)
    intercepting_docsettings = false
    if ok and type(res) == "table" and res.getSidecarDir then
        local orig_getSidecarDir = res.getSidecarDir
        res.getSidecarDir = function(self, doc_path, force_location)
            local dir = orig_getSidecarDir(self, doc_path, force_location)
            local worker_config = os.getenv("XDG_CONFIG_HOME")
            if (force_location == nil or force_location == "doc") and worker_config and type(doc_path) == "string" then
                local test_subpath = doc_path:match("spec/front/unit/data/(.+)")
                    or doc_path:match("[%/]test/(.+)")
                    or doc_path:match("^test/(.+)")
                if test_subpath then
                    local sdr_parent = worker_config .. "/sdr"
                    local lfs = require("libs/libkoreader-lfs")
                    lfs.mkdir(sdr_parent)
                    local base_name = test_subpath:match("(.*)%.") or test_subpath
                    return sdr_parent .. "/" .. base_name .. ".sdr"
                end
            end
            return dir
        end
    end
    return function() return res end
end)

