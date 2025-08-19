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
function Fake:access_hash_property() end
function Fake:new_hasharray() end
function Fake:register_int_property() end
function Fake:close() end
-- Extensions
function Fake:read_hash_property() end

function LibLipcs:supported()
  return haslipc
end

function LibLipcs:isFake(v)
  return v == Fake
end

local Wrapper = {}

function Wrapper:new(l)
  local o = {
    l = l
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

function Wrapper:get_string_property(...)
  local r, o = pcall(self.l.get_string_property, self.l, ...)
  if r then return o end
  return nil
end

function Wrapper:set_string_property(...)
  pcall(self.l.set_string_property, self.l, ...)
end

function Wrapper:get_int_property(...)
  local r, o = pcall(self.l.get_int_property, self.l, ...)
  if r then return o end
  return nil
end

function Wrapper:set_int_property(...)
  pcall(self.l.set_int_property, self.l, ...)
end

function Wrapper:access_hash_property(...)
  local r, o = pcall(self.l.access_hash_property, self.l, ...)
  if r then return o end
  return nil
end

function Wrapper:new_hasharray(...)
  local r, o = pcall(self.l.new_hasharray, self.l, ...)
  if r then return o end
  return nil
end

function Wrapper:register_int_property(...)
  local r, o = pcall(self.l.register_int_property, self.l, ...)
  if r then return o end
  return nil
end

function Wrapper:close(...)
  pcall(self.l.close, self.l, ...)
end

-- Extensions
-- access_hash_property with empty input, and always returns to_table().
function Wrapper:read_hash_property(publisher, prop)
  local input = self:new_hasharray()
  if input == nil then
    return nil
  end
  local result = self:access_hash_property(publisher, prop, input)
  input:destroy()
  if result == nil then
    return nil
  end
  local t = result:to_table()
  result:destroy()
  return t
end

function LibLipcs:_check(v)
  if v then
    assert(not self:isFake(v))
    v = Wrapper:new(v)
  else
    logger.warn("Couldn't get lipc handle")
    v = Fake
    assert(self:isFake(v))
  end
  return v
end

function LibLipcs:accessor()
  if not haslipc then
    return Fake
  end
  if not self._ins then
    self._ins = self:_check(lipc.init("com.github.koreader"))
  end
  return self._ins
end

function LibLipcs:hash_accessor()
  if not haslipc then
    return Fake
  end
  if not self._no_name then
    self._no_name = self:_check(openlipc.open_no_name())
  end
  return self._no_name
end

return LibLipcs
