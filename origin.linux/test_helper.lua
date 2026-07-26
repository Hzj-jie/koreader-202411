-- Import the shared linux test helper to apply global mocks (like hasSystemFonts = false)
local workspace = os.getenv("KO_WORKSPACE_DIR")
if workspace then
    dofile(workspace .. "/linux/test_helper.lua")
else
    -- Fallback if run without run_tests.sh (e.g. manual direct execution on host)
    dofile("../linux/test_helper.lua")
end

-- Helper stub for origin.linux: ensure PowerD:new initializes frontlight hardware state
-- matching the requested fl_intensity, avoiding prototype inheritance leakage from PowerD prototype
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
        if res.turnOnFrontlight then
            local orig_turnOn = res.turnOnFrontlight
            res.turnOnFrontlight = function(self, done_callback)
                if not self.device:hasFrontlight() then return end
                if self:isFrontlightOn() then return false end
                if (self.fl_intensity or 0) <= (self.fl_min or 0) and not self.frontlight_save then
                    return false
                end
                return orig_turnOn(self, done_callback)
            end
        end
    end
    return function() return res end
end)


