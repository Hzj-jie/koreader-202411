-- Load the original loadlib helper first
require("ffi/loadlib")

-- Intercept require globally to ensure determinism across different host workstations
-- and avoid relying on physical hardware state (such as system fonts, battery charging state, etc.).
local orig_require = _G.require
_G.require = function(name)
    local res = orig_require(name)
    if name == "device" then
        if type(res) == "table" then
            res.hasSystemFonts = function() return false end
            if res.powerd then
                res.powerd.isChargingHW = function() return false end
                res.powerd.isChargedHW = function() return false end
                res.powerd.getCapacityHW = function() return 0 end
            end
        end
    elseif name == "ffi/SDL2_0" then
        if type(res) == "table" and res.getPowerInfo then
            res.getPowerInfo = function()
                -- Return deterministic power state: has battery, not charging, not plugged, 0% capacity
                return true, false, false, 0
            end
        end
    elseif name == "device/sdl/powerd" or name == "device/generic/powerd" then
        if type(res) == "table" then
            res.isChargingHW = function() return false end
            res.isChargedHW = function() return false end
            res.getCapacityHW = function() return 0 end
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

local max_jobs = 4
local nproc_p = io.popen("nproc 2>/dev/null")
if nproc_p then
    local cores = tonumber(nproc_p:read("*l"))
    nproc_p:close()
    if cores and cores > 0 then
        max_jobs = cores
    end
end

return {
    max_jobs = max_jobs,
}

