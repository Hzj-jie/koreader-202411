local logger = require("logger")

local LibLipcs = {}

local haslipc, lipc = pcall(require, "liblipclua")

if not haslipc then
  logger.warn("Couldn't load liblipclua: ", lipc)
end

local Fake = {}
function Fake:get_string_property() end
function Fake:set_string_property() end
function Fake:get_int_property() end
function Fake:set_int_property() end
function Fake:access_hasharray_property() end
function Fake:new_hasharray() end
function Fake:register_int_property() end

function LibLipcs:supported()
  return haslipc
end

function LibLipcs:isFake(v)
  return v == Fake
end

function LibLipcs:of(serviceName)
  if not haslipc then return Fake end
  if not self[serviceName] then
    local v = lipc.init(serviceName)
    if v then
      assert(not self:isFake(v))
    else
      logger.warn("Couldn't get lipc handle")
      v = Fake
      assert(self:isFake(v))
    end
    self[serviceName] = v
  end
  return self[serviceName]
end

return LibLipcs
