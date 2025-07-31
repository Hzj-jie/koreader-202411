local ffi = require("ffi")

-- Handle arch-dependent typedefs...
if jit.arch == "x64" then
  require("ffi/posix_types_x64_h")
elseif jit.arch == "x86" then
  require("ffi/posix_types_x86_h")
elseif ffi.abi("64bit") then
  require("ffi/posix_types_64b_h")
else
  require("ffi/posix_types_def_h")
end

if ffi.arch ~= nil then
  require("ffi/posix_h_jit")
else
  require("ffi/posix_h_ffi")
end
