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

