local ffi = require("ffi")

pcall(ffi.cdef, "typedef long time_t;")
pcall(ffi.cdef, "typedef long suseconds_t;")
pcall(
  ffi.cdef,
  [[
struct timeval {
  long int tv_sec;
  long int tv_usec;
};
]]
)
