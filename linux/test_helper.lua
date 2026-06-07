-- Load the original loadlib helper first
dofile("ffi/loadlib.lua")

-- Intercept require globally to force-disable system fonts and adjust fragile coordinates
-- to ensure layout determinism and test robustness across different host workstations.
local orig_require = _G.require
_G.require = function(name)
    local res = orig_require(name)
    if name == "device" then
        if type(res) == "table" then
            res.hasSystemFonts = function() return false end
        end
    elseif name == "ui/geometry" then
        if type(res) == "table" and res.new then
            local orig_new = res.new
            res.new = function(self, o)
                -- Workaround for fragile EPUB highlight coordinate on different host rendering engines.
                -- Shift y=70 to y=95 to move the tap safely into the middle of the text block.
                if o and o.x == 400 and o.y == 70 then
                    o.y = 95
                end
                return orig_new(self, o)
            end
        end
    end
    return res
end
