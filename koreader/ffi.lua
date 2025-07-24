if ffi ~= nil then
  -- Native ffi from luajit.
  return ffi
end
local ffi = package.loadlib("./ffi.so", "luaopen_ffi")()
function ffi.abi(param)
  return param == "32bit" or param == "le"
end
return ffi
