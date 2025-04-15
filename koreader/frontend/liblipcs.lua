local logger = require("logger")

local LibLipcs = {}

local haslipc, lipc = pcall(require, "liblipclua")

if not haslipc then
  logger.warn("Couldn't load liblipclua: ", lipc)
end

local openlipc
if haslipc then
  openlipc = require("libopenlipclua")
end

local Fake = {}
function Fake:get_string_property() end
function Fake:set_string_property() end
function Fake:get_int_property() end
function Fake:set_int_property() end
function Fake:access_hasharray_property() end
function Fake:new_hasharray() end
function Fake:register_int_property() end
function Fake:close() end

function LibLipcs:supported()
  return haslipc
end

function LibLipcs:isFake(v)
  return v == Fake
end

function LibLipcs:_check(v)
  if v then
    assert(not self:isFake(v))
  else
    logger.warn("Couldn't get lipc handle")
    v = Fake
    assert(self:isFake(v))
  end
  return v
end

function LibLipcs:of(serviceName)
  if not haslipc then return Fake end
  if not self._ins then
    self._ins = self:_check(lipc.init("com.github.koreader"))
  end
  return self._ins
--[[
  if not self[serviceName] then
    self[serviceName] = self:_check(lipc.init(serviceName))
  end
  return self[serviceName]
]]--
end

function LibLipcs:no_name()
  if not haslipc then return Fake end
  if not self._no_name then
    self._no_name = self:_check(openlipc.open_no_name())
  end
  return self._no_name
end

return LibLipcs
