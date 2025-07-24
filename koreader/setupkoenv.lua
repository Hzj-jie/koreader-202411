-- Set search path for `require()`.
package.path = "common/?.lua;frontend/?.lua;" .. package.path
package.cpath = "common/?.so;common/?.dll;/usr/lib/lua/?.so;" .. package.cpath
if jit == nil then
  -- For vanilla lua.
  jit = require("jit")
end
-- Setup `ffi.load` override and 'loadlib' helper.
require("ffi/loadlib")
