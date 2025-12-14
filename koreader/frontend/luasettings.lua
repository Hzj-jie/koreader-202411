--[[--
This module handles generic settings as well as KOReader's global settings system.
]]

local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local LuaSettings = {}

function LuaSettings:extend(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end
-- NOTE: Instances are created via open, so we do *NOT* implement a new method, to avoid confusion.

function LuaSettings:load(file_path)
  -- File being absent and returning an empty table is a use case,
  -- so logger.warn() only if there was an existing file
  local existing = lfs.attributes(file_path, "mode") == "file"
  if not existing then
    return {}, false
  end
  local ok, stored = pcall(dofile, file_path)
  if ok and stored then
    return stored, true
  end
  logger.warn("LuaSettings: Failed reading", file_path, ", probably corrupted.")
  return {}, false
end

--- Opens a settings file.
function LuaSettings:open(file_path)
  local new = LuaSettings:extend({
    file = file_path,
  })

  new.data = LuaSettings:load(file_path)
  return new
end

--[[-- Reads a setting or nil

@param key The setting's key
]]
function LuaSettings:read(key)
  local r = self.data[key]
  -- TODO: Should be an assertion.
  if type(r) == "table" then
    logger.info(
      "FixMe: LuaSettings:readSetting ",
      key,
      " returns a table and should use readTableRef instead.\n",
      debug.traceback()
    )
  end
  return r
end

--[[-- Reads a setting or creates an empty table, returned table can be directly
--     modified, and modifications would be preserved.

@param key The setting's key
]]
function LuaSettings:readTableRef(key, default)
  local v = self.data[key]
  if v ~= nil and type(v) ~= "table" then
    -- Should only happen during migrations.
    logger.warn(
      "LuaSetting ",
      key,
      " was not a table, override it with the default value ",
      dump(default or {})
    )
    v = nil
  end
  if v == nil then
    v = default or {}
    self.data[key] = v
  end
  return v
end

--[[-- Reads a setting but not creates an empty table, expects to call
       saveSetting or the setting will not be persisted.
]]
function LuaSettings:readTable(key)
  if self:has(key) then
    return self:readTableRef(key)
  end
end

--- Saves a setting.
function LuaSettings:save(key, value, default_value)
  -- Setting value to nil is same as self.delSetting(key), no reason to
  -- dump and compare the value in the case.
  if value == nil then
    return self:delete(key)
  end
  if default_value == nil then
    if type(value) == "table" and value == self.data[key] then
      logger.info(
        "FixMe: LuaSettings:saveSetting ",
        key,
        " on a LuaSettings:readTableRef is not necessary, unless a ",
        "default_value is provided to remove the unnecessary setting.\n",
        debug.traceback()
      )
    else
      self.data[key] = value
    end
    return self
  end
  -- Should never happen.
  if type(value) ~= type(default_value) then
    logger.info(
      "FixMe: LuaSettings:saveSetting ",
      key,
      " value type ",
      type(value),
      " unmatches default value type ",
      type(default_value),
      ", ignore default value ",
      default_value,
      " in favor of value ",
      value,
      "\n",
      debug.traceback()
    )
    self.data[key] = value
    return self
  end
  if type(value) == "table" then
    -- An easy optimization to avoid dumping.
    if
      util.tableSize(value) == util.tableSize(default_value)
      and (util.tableSize(value) == 0 or dump(value) == dump(default_value))
    then
      return self:delete(key)
    end
  else
    if value == default_value then
      return self:delete(key)
    end
  end
  self.data[key] = value
  return self
end

--- Deletes a setting.
function LuaSettings:delete(key)
  self.data[key] = nil
  return self
end

--- Checks if setting exists.
function LuaSettings:has(key)
  return self.data[key] ~= nil
end

--- Checks if setting does not exist.
function LuaSettings:hasNot(key)
  return self.data[key] == nil
end

--- Checks if setting is `true` (boolean).
function LuaSettings:isTrue(key)
  return self.data[key] == true
end

function LuaSettings:isTrueOr(key, default)
  if self:has(key) then
    return self:isTrue(key)
  end
  return default
end

--- Checks if setting is `false` (boolean).
function LuaSettings:isFalse(key)
  return self.data[key] == false
end

--- Checks if setting is `nil` or `true`.
function LuaSettings:nilOrTrue(key)
  return self:hasNot(key) or self:isTrue(key)
end

--- Checks if setting is `nil` or `false`.
function LuaSettings:nilOrFalse(key)
  return self:hasNot(key) or self:isFalse(key)
end

--- Flips `nil` or `true` to `false`, and `false` to `nil`.
--- e.g., a setting that defaults to true.
function LuaSettings:flipNilOrTrue(key)
  if self:nilOrTrue(key) then
    self:save(key, false)
  else
    self:delete(key)
  end
  return self
end

--- Flips `nil` or `false` to `true`, and `true` to `nil`.
--- e.g., a setting that defaults to false.
function LuaSettings:flipNilOrFalse(key)
  if self:nilOrFalse(key) then
    self:save(key, true)
  else
    self:delete(key)
  end
  return self
end

-- Unconditionally makes a boolean setting `true`.
function LuaSettings:makeTrue(key, default_value)
  self:save(key, true, default_value)
  return self
end

-- Unconditionally makes a boolean setting `false`.
function LuaSettings:makeFalse(key, default_value)
  self:save(key, false, default_value)
  return self
end

--- Replaces existing settings with table.
function LuaSettings:reset(table)
  self.data = table
  return self
end

--- Writes settings to disk.
function LuaSettings:flush()
  if not self.file then
    return
  end
  -- Do not save anything meaningless.
  if self.data == nil or next(self.data) == nil then
    return
  end
  util.writeToFile(dump(self.data), self.file, true)
  return self
end

--- Closes settings file.
function LuaSettings:close()
  self:flush()
end

--- Purges settings file.
function LuaSettings:purge()
  if self.file then
    os.remove(self.file)
  end
  return self
end

function LuaSettings:settingCount()
  return util.tableSize(self.data)
end

function LuaSettings:fileAttribute()
  if self.file then
    return lfs.attributes(self.file)
  end
  return nil
end

return LuaSettings
