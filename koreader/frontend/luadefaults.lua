--[[--
Subclass of LuaSettings dedicated to handling the legacy global constants.
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local dump = require("dump")
local util = require("util")

local LuaDefaults = LuaSettings:extend({
  ro = nil, -- will contain the defaults.lua k/v pairs (const)
  rw = nil, -- will only contain non-defaults user-modified k/v pairs
})

--- Opens a settings file.
function LuaDefaults:open(path)
  local file_path = path or DataStorage:getDataDir() .. "/defaults.custom.lua"
  local new = LuaDefaults:extend({
    file = file_path,
  })
  new.rw = LuaSettings:load(file_path)

  -- The actual defaults file, on the other hand, is set in stone.
  new.ro = dofile("defaults.lua")

  return new
end

--- Reads a setting, optionally initializing it to a default.
function LuaDefaults:read(key, default)
  if not default then
    if self:hasBeenCustomized(key) then
      return self.rw[key]
    else
      return self.ro[key]
    end
  end

  if not self:hasBeenCustomized(key) then
    self.rw[key] = default
    return self.rw[key]
  end

  if self:hasBeenCustomized(key) then
    return self.rw[key]
  else
    return self.ro[key]
  end
end

--- Saves a setting.
function LuaDefaults:save(key, value)
  if util.tableEquals(self.ro[key], value, true) then
    -- Only keep actually custom settings in the rw table ;).
    return self:delete(key)
  else
    self.rw[key] = value
  end
  return self
end

--- Deletes a setting.
function LuaDefaults:delete(key)
  self.rw[key] = nil
  return self
end

--- Checks if setting exists.
function LuaDefaults:has(key)
  return self.ro[key] ~= nil
end

--- Checks if setting does not exist.
function LuaDefaults:hasNot(key)
  return self.ro[key] == nil
end

--- Checks if setting has been customized.
function LuaDefaults:hasBeenCustomized(key)
  return self.rw[key] ~= nil
end

--- Checks if setting has NOT been customized.
function LuaDefaults:hasNotBeenCustomized(key)
  return self.rw[key] == nil
end

--- Checks if setting is `true` (boolean).
function LuaDefaults:isTrue(key)
  if self:hasBeenCustomized(key) then
    return self.rw[key] == true
  else
    return self.ro[key] == true
  end
end

--- Checks if setting is `false` (boolean).
function LuaDefaults:isFalse(key)
  if self:hasBeenCustomized(key) then
    return self.rw[key] == false
  else
    return self.ro[key] == false
  end
end

--- Low-level API for filemanagersetdefaults
function LuaDefaults:getDataTables()
  return self.ro, self.rw
end

function LuaDefaults:readDefaultSetting(key)
  return self.ro[key]
end

-- NOP unsupported LuaSettings APIs
function LuaDefaults:reset() end

--- Writes settings to disk.
function LuaDefaults:flush()
  if not self.file then
    return
  end
  util.writeToFile(dump(self.rw), self.file, true)
  return self
end

return LuaDefaults
