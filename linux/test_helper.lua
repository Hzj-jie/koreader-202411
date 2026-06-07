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
