local logger = require("logger")

local LibLipcs = {}

local haslipc, lipc = pcall(require, "liblipclua")

if not haslipc then
  logger.warn("Couldn't load liblipclua: ", lipc)
end

local Fake = { fake = true, }
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

function LibLipcs:of(serviceName)
  if not haslipc then return Fake end
  if not self[serviceName] then
    local v = lipc.init(serviceName)
    if not v then
      logger.warn("Couldn't get lipc handle")
      v = Fake
    end
    self[serviceName] = v
  end
  return self[serviceName]
end

function LibLipcs:no_name()
  if not haslipc then return Fake end
  if not self.no_name then
    local v = lipc.open_no_name()
    if not v then
      logger.warn("Couldn't open no name lipc handle")
      v = Fake
    end
    self.no_name = v
  end
  return self.no_name
end

return LibLipcs
