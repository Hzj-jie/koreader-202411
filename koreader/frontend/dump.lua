--[[--
A simple serialization function which won't do uservalues, functions, or loops.

If you need a more full-featured variant, serpent is available in ffi/serpent ;).
]]

local sorted_pairs = require("ffi/SortedIteration")
local insert = table.insert
local indent_prefix = "  "

local function _serialize(what, outt, indent, history)
  local datatype = type(what)
  assert(history ~= nil)
  if datatype == "table" then
    for up, item in ipairs(history) do
      if item == what then
        insert(outt, "nil --[[ LOOP:\n")
        insert(outt, string.rep(indent_prefix, indent - up))
        insert(outt, "^------- ]]")
        return
      end
    end
    local new_history = { what, unpack(history) }
    local didrun = false
    insert(outt, "{")
    for k, v in sorted_pairs(what) do
      insert(outt, "\n")
      insert(outt, string.rep(indent_prefix, indent + 1))
      insert(outt, "[")
      _serialize(k, outt, indent + 1, new_history)
      insert(outt, "] = ")
      _serialize(v, outt, indent + 1, new_history)
      insert(outt, ",")
      didrun = true
    end
    if didrun then
      insert(outt, "\n")
      insert(outt, string.rep(indent_prefix, indent))
    end
    insert(outt, "}")
  elseif datatype == "string" then
    insert(outt, string.format("%q", what))
  elseif datatype == "number" then
    insert(outt, tostring(what))
  elseif datatype == "boolean" then
    insert(outt, tostring(what))
  elseif datatype == "function" then
    insert(outt, tostring(what))
  elseif datatype == "nil" then
    insert(outt, "nil")
  end
end

--[[--Serializes whatever is in `data` to a string that is parseable by Lua.

@function dump
@param data the object you want serialized (table, string, number, boolean, nil)
--]]
local function dump(data)
  local out = {}
  _serialize(data, out, 0, {})
  return table.concat(out)
end

return dump
