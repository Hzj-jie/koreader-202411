--[[--
A lazy table whose properties are evaluated on demand and cached.

Example usage:
```lua
local CachedTable = require("cachedtable")

-- Properties are resolved only when an unpopulated field is accessed:
local t = CachedTable:new(function()
  return {
    file = "/path/to/file",
    dir = "/path/to/dir",
  }
end, { location = "hash" })

-- Statically pre-populated fields are accessed without triggering the resolver:
print(t.location) -- "hash" (resolver is NOT called)

-- Accessing an unpopulated field triggers the resolver:
print(t.file) -- "/path/to/file" (resolver called and values cached in table)
print(t.dir) -- "/path/to/dir" (cached, resolver NOT called again)
```
--]]

local logger = require("logger")

local CachedTable = {}

--- Checks whether a CachedTable has already been resolved.
-- @tparam table t The table to check.
-- @treturn bool True if the table has been resolved, false otherwise.
function CachedTable.isResolved(t)
  local mt = getmetatable(t)
  return mt and mt._is_resolved and mt._is_resolved() or false
end

--- Forces immediate evaluation of a CachedTable if it has not been resolved yet.
-- @tparam table t The table to resolve.
-- @treturn table The resolved table `t`.
function CachedTable.resolve(t)
  local mt = getmetatable(t)
  if mt and mt._resolve then
    mt._resolve(t)
  end
  return t
end

--- Iterates over key-value pairs of a CachedTable, resolving it first if needed.
-- @tparam table t The CachedTable instance.
-- @treturn function iterator
-- @treturn table t
-- @treturn nil
function CachedTable.pairs(t)
  CachedTable.resolve(t)
  return pairs(t)
end

--- Creates a new lazy-evaluated table.
-- @tparam function resolver A function returning a table of key-value pairs, or nil.
-- @tparam[opt] table initial_fields Statically initialized fields that can be read without triggering resolution.
-- @treturn table A table with lazy-evaluation behavior.
function CachedTable:new(resolver, initial_fields)
  assert(
    type(resolver) == "function",
    "CachedTable: resolver must be a function"
  )

  local obj = initial_fields or {}
  local resolved = false

  local function do_resolve(t)
    if not resolved then
      resolved = true
      local ok, data = pcall(resolver)
      if ok and data then
        for field, val in pairs(data) do
          if rawget(t, field) == nil then
            rawset(t, field, val)
          end
        end
      elseif not ok then
        logger.warn("CachedTable: resolver failed:", tostring(data))
      end
    end
  end

  local mt = {
    __index = function(t, k)
      do_resolve(t)
      return rawget(t, k)
    end,
    __pairs = function(t)
      do_resolve(t)
      return next, t, nil
    end,
    _resolve = do_resolve,
    _is_resolved = function()
      return resolved
    end,
  }

  return setmetatable(obj, mt)
end

return CachedTable
