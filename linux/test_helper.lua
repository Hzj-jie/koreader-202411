-- Load the original loadlib helper first
dofile("ffi/loadlib.lua")

-- Intercept require globally to force-disable system fonts for all unit tests,
-- ensuring layout and font rendering determinism across different host workstations.
local orig_require = _G.require
_G.require = function(name)
    local res = orig_require(name)
    if name == "device" then
        if type(res) == "table" then
            res.hasSystemFonts = function() return false end
        end
    end
    return res
end

-- Safely deduplicate nested spy.on calls to prevent inner spy.revert() from destroying outer spies
pcall(function()
    local spy = require("luassert.spy")
    local orig_spy_on = spy.on
    spy.on = function(target, key)
        local current = target[key]
        if type(current) == "table" and current.revert then
            local existing_spy = current
            local orig_revert = existing_spy.revert
            existing_spy.revert = function() end
            if existing_spy.clear then
                existing_spy:clear()
            end
            return existing_spy
        end
        return orig_spy_on(target, key)
    end
end)

-- Helper stub for powerd: ensure PowerD:new clears prototype spy leakage and manages state
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
