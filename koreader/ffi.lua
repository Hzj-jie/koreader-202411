assert(ffi == nil, "This file shouldn't be imported by luajit")

local cffi = package.loadlib("./cffi.so", "luaopen_cffi")()

-- Define ffi.NULL for compatibility with LuaJIT code
cffi.NULL = cffi.nullptr

-- Wrap ffi.cast to return Lua nil instead of cdata NULL pointer
local orig_cast = cffi.cast
cffi.cast = function(...)
  local res = orig_cast(...)
  if type(res) == "userdata" and res == cffi.nullptr then
    return nil
  end
  return res
end

-- Wrap ffi.new to return Lua nil instead of cdata NULL pointer
local orig_new = cffi.new
cffi.new = function(...)
  local res = orig_new(...)
  if type(res) == "userdata" and res == cffi.nullptr then
    return nil
  end
  return res
end

-- Wrap ffi.cdef to ignore redefinition errors (matching LuaJIT behavior)
local orig_cdef = cffi.cdef
cffi.cdef = function(def)
  local ok, err = pcall(orig_cdef, def)
  if not ok then
    if not err:match("redefined") then
      error(err)
    end
  end
end

-- Wrap master cdata metatable to handle NULL pointer comparison/checks
local mt = debug.getmetatable(cffi.nullptr)
if mt then
  -- Wrap function calls to return Lua nil on NULL pointer return
  local orig_call = mt.__call
  if orig_call then
    mt.__call = function(func, ...)
      local res = orig_call(func, ...)
      if type(res) == "userdata" and res == cffi.nullptr then
        return nil
      end
      return res
    end
  end

  -- Wrap struct/array index to return Lua nil on NULL pointer read
  local orig_index = mt.__index
  if orig_index then
    mt.__index = function(obj, key)
      local res = orig_index(obj, key)
      if type(res) == "userdata" and res == cffi.nullptr then
        return nil
      end
      return res
    end
  end
end

ffi = cffi
return ffi
