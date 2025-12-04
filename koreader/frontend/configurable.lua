local ffiUtil = require("ffi/util")
local util = require("util")

local Configurable = {}

function Configurable:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function Configurable:hash(list)
  for key, value in ffiUtil.orderedPairs(self) do
    local value_type = type(value)
    if value_type == "number" or value_type == "string" then
      table.insert(list, value)
    end
  end
end

function Configurable:loadDefaults(config_options)
  local prefix = config_options.prefix .. "_"
  for i = 1, #config_options do
    local options = config_options[i].options
    for j = 1, #options do
      local key = options[j].name
      local default_value = options[j].default_value
      assert(default_value ~= nil, key)
      local settings_key = prefix .. key
      if G_reader_settings:has(settings_key) then
        if
          type(default_value) == "number"
          or type(default_value) == "string"
        then
          self[key] = G_reader_settings:readSetting(settings_key)
        elseif type(default_value) == "table" then
          self[key] = G_reader_settings:readTableSetting(settings_key)
        else
          assert(false)
        end
      else
        self[key] = default_value
      end
      assert(self[key] ~= nil)
    end
  end
  local defaults = util.tableDeepCopy(self)
  -- Avoid copying defaults again.
  self.defaults = defaults
end

function Configurable:loadSettings(settings, prefix)
  for key, value in pairs(self) do
    local settings_key = prefix .. key
    if settings:has(settings_key) then
      local value_type = type(value)
      if value_type == "number" or value_type == "string" then
        self[key] = settings:readSetting(settings_key)
      elseif value_type == "table" then
        self[key] = settings:readTableSetting(settings_key)
      else
        assert(false)
      end
    end
    assert(self[key] ~= nil)
  end
end

function Configurable:saveSettings(settings, prefix)
  for key, value in pairs(self) do
    local value_type = type(value)
    if
      value_type == "number"
      or value_type == "string"
      or value_type == "table"
    then
      settings:saveSetting(prefix .. key, value, self.defaults[key])
    else
      assert(false)
    end
  end
end

return Configurable
