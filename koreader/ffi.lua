assert(ffi == nil, "This file shouldn't be imported by luajit")
--[[
ffi = package.loadlib("./ffi.so", "luaopen_ffi")()
function ffi.abi(param)
  return param == "32bit" or param == "le"
end
]]--

ffi = package.loadlib("./cffi.so", "luaopen_cffi")()

return ffi
