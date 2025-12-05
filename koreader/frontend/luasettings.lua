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

--- Opens a settings file.
function LuaSettings:open(file_path)
  local new = LuaSettings:extend({
    file = file_path,
  })
  local ok, stored

  -- File being absent and returning an empty table is a use case,
  -- so logger.warn() only if there was an existing file
  local existing = lfs.attributes(new.file, "mode") == "file"

  ok, stored = pcall(dofile, new.file)
  if ok and stored then
    new.data = stored
  else
    if existing then
      logger.warn(
        "LuaSettings: Failed reading",
        new.file,
        "(probably corrupted)."
      )
    end
    -- Fallback to .old if it exists
    ok, stored = pcall(dofile, new.file .. ".old")
    if ok and stored then
      if existing then
        logger.warn("LuaSettings: read from backup file", new.file .. ".old")
      end
      new.data = stored
    else
      if existing then
        logger.warn(
          "LuaSettings: no usable backup file for",
          new.file,
          "to read from"
        )
      end
      new.data = {}
    end
  end

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
function LuaSettings:readTableOrNil(key)
  if self:has(key) then
    return self:readTableRef(key)
  end
end

--- Saves a setting.
function LuaSettings:save(key, value, default_value)
  -- Setting value to nil is same as self.delSetting(key), no reason to
  -- dump and compare the value in the case.
  if value == nil then
    return self:del(key)
  end
  if default_value == nil then
    if type(value) == "table" and value == self.data[key] then
      logger.info(
        "FixMe: LuaSettings:saveSetting ",
        key,
        " on a LuaSettings:readTableRef is not necessary, ",
        "unless a default_value is provided to remove the unnecessary setting.",
        debug.traceback()
      )
    else
      self.data[key] = value
    end
    return self
  end
  -- Should never happen.
  assert(type(value) == type(default_value))
  if type(value) == "table" then
    -- An easy optimization to avoid dumping.
    if
      util.tableSize(value) == util.tableSize(default_value)
      and (
        util.tableSize(value) == 0
        or dump(value, nil, true) == dump(default_value, nil, true)
      )
    then
      return self:del(key)
    end
  else
    if value == default_value then
      return self:del(key)
    end
  end
  self.data[key] = value
  return self
end

--- Deletes a setting.
function LuaSettings:del(key)
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
    self:del(key)
  end
  return self
end

--- Flips `nil` or `false` to `true`, and `true` to `nil`.
--- e.g., a setting that defaults to false.
function LuaSettings:flipNilOrFalse(key)
  if self:nilOrFalse(key) then
    self:save(key, true)
  else
    self:del(key)
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

function LuaSettings:backup(file)
  file = file or self.file
  local directory_updated
  if lfs.attributes(file, "mode") == "file" then
    -- As an additional safety measure (to the ffiutil.fsync* calls used in util.writeToFile),
    -- we only backup the file to .old when it has not been modified in the last 60 seconds.
    -- This should ensure in the case the fsync calls are not supported
    -- that the OS may have itself sync'ed that file content in the meantime.
    local mtime = lfs.attributes(file, "modification")
    if mtime < os.time() - 60 then
      os.rename(file, file .. ".old")
      directory_updated = true -- fsync directory content
    end
  end
  return directory_updated
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
  local directory_updated = self:backup()
  util.writeToFile(
    dump(self.data, nil, true),
    self.file,
    true,
    true,
    directory_updated
  )
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
