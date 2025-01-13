local dumpex = require("dumpex")

--[[--Serializes whatever is in `data` to a string that is parseable by Lua.

You can optionally specify a maximum recursion depth in `max_lv`.
@function dump
@param data the object you want serialized (table, string, number, boolean, nil)
@param max_lv optional maximum recursion depth
--]]
local function dump(data, max_lv, ordered)
    local pairs_func = ordered and require("ffi/util").orderedPairs or pairs
    return dumpex(data, max_lv, pairs_func)
end

return dump
