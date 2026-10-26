assert(ffi == nil, "This file shouldn't be imported by luajit")

return assert(package.loadlib("./cffi.so", "luaopen_cffi"))()
