-- Mock of LuaJIT string.buffer for standard Lua using bitser
local bitser = require("ffi/bitser")

local M = {}

function M.encode(t)
    return bitser.dumps(t)
end

function M.decode(s)
    return bitser.loads(s)
end

function M.new()
    error("string.buffer.new() is not implemented in standard Lua mock!")
end

return M
