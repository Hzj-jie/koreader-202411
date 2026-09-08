-- need low-level mechanism to detect android to avoid recursive dependency
local isAndroid, android = pcall(require, "android")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local DataStorage = {}

local data_dir
local full_data_dir
local cache_dir
local is_storage_temporary = false
local is_storage_readonly = false
local storage_warning_shown = false

function DataStorage:isStorageTemporary()
  return is_storage_temporary == true
end

function DataStorage:isStorageReadOnly()
  return is_storage_readonly == true
end

-- For testing purposes only; do not use in production code.
-- Overrides the temporary storage flag to simulate fallback storage state.
function DataStorage:setStorageTemporary(val)
  is_storage_temporary = val
end

-- For testing purposes only; do not use in production code.
-- Overrides the read-only storage flag to simulate unwritable storage state.
function DataStorage:setStorageReadOnly(val)
  is_storage_readonly = val
end

-- For testing purposes only; do not use in production code.
-- Resets cached directories and storage state flags across test scenarios.
function DataStorage:reset()
  data_dir = nil
  full_data_dir = nil
  cache_dir = nil
  is_storage_temporary = false
  is_storage_readonly = false
  storage_warning_shown = false
end

local function getFallbackTmpDir()
  local ok, dev = pcall(require, "device")
  if ok and dev and dev.getTmpDir then
    local ok_tmp, tmp = pcall(dev.getTmpDir, dev)
    if ok_tmp and tmp and util.isDirRW(tmp, true) then
      return tmp
    end
  end
  local tmp = os.getenv("TMPDIR")
  if tmp and util.isDirRW(tmp, true) then
    return tmp
  end
  if util.isDirRW("/tmp", true) then
    return "/tmp"
  end
  if isAndroid and util.isDirRW("/data/local/tmp", true) then
    return "/data/local/tmp"
  end
  return nil
end

function DataStorage:getDataDir()
  if data_dir then
    return data_dir
  end

  local candidates = {}

  if isAndroid then
    table.insert(candidates, android.getExternalStoragePath() .. "/koreader")
  elseif os.getenv("UBUNTU_APPLICATION_ISOLATION") then
    local app_id = os.getenv("APP_ID")
    local package_name = app_id and app_id:match("^(.-)_")
    if package_name and os.getenv("XDG_DATA_HOME") then
      table.insert(
        candidates,
        string.format("%s/%s", os.getenv("XDG_DATA_HOME"), package_name)
      )
    end
  elseif
    os.getenv("APPIMAGE")
    or os.getenv("FLATPAK")
    or os.getenv("KO_MULTIUSER")
  then
    if os.getenv("XDG_CONFIG_HOME") then
      table.insert(
        candidates,
        string.format("%s/%s", os.getenv("XDG_CONFIG_HOME"), "koreader")
      )
    end
    if os.getenv("HOME") then
      local user_rw = string.format(
        "%s/%s",
        os.getenv("HOME"),
        jit.os == "OSX" and "Library/Application Support" or ".config"
      )
      table.insert(candidates, string.format("%s/%s", user_rw, "koreader"))
    end
  else
    table.insert(candidates, ".")
    if os.getenv("XDG_CONFIG_HOME") then
      table.insert(
        candidates,
        string.format("%s/%s", os.getenv("XDG_CONFIG_HOME"), "koreader")
      )
    end
    if os.getenv("HOME") then
      local user_rw = string.format(
        "%s/%s",
        os.getenv("HOME"),
        jit.os == "OSX" and "Library/Application Support" or ".config"
      )
      table.insert(candidates, string.format("%s/%s", user_rw, "koreader"))
    end
  end

  for _, cand in ipairs(candidates) do
    if cand and util.isDirRW(cand, true) then
      data_dir = cand
      return data_dir
    end
  end

  -- All standard candidates failed write check; fall back to temporary directory
  local tmp_dir = getFallbackTmpDir()
  if tmp_dir then
    local tmp_data_dir = tmp_dir .. "/koreader"
    if util.isDirRW(tmp_data_dir, true) then
      data_dir = tmp_data_dir
      is_storage_temporary = true
      return data_dir
    end
  end

  -- If even temporary storage is not writable, fall back to first candidate in read-only mode
  data_dir = candidates[1] or "."
  is_storage_readonly = true
  return data_dir
end

function DataStorage:getHistoryDir()
  return self:getDataDir() .. "/history"
end

function DataStorage:getSettingsDir()
  return self:getDataDir() .. "/settings"
end

function DataStorage:getDocSettingsDir()
  return self:getDataDir() .. "/docsettings"
end

function DataStorage:getDocSettingsHashDir()
  return self:getDataDir() .. "/hashdocsettings"
end

function DataStorage:getCacheDir()
  if cache_dir then
    return cache_dir
  end

  local preferred = self:getDataDir() .. "/cache"
  if util.isDirRW(preferred, true) then
    cache_dir = preferred
    return cache_dir
  end

  local tmp = getFallbackTmpDir()
  if tmp then
    local tmp_cache = tmp .. "/koreader_cache"
    if util.isDirRW(tmp_cache, true) then
      cache_dir = tmp_cache
      return cache_dir
    end
  end

  cache_dir = preferred
  return cache_dir
end

function DataStorage:getFullDataDir()
  if full_data_dir then
    return full_data_dir
  end

  if string.sub(self:getDataDir(), 1, 1) == "/" then
    full_data_dir = self:getDataDir()
  elseif self:getDataDir() == "." then
    full_data_dir = lfs.currentdir()
  else
    full_data_dir = lfs.currentdir() .. "/" .. self:getDataDir()
  end

  return full_data_dir
end

function DataStorage:showStorageWarningIfNeeded()
  if storage_warning_shown then
    return
  end
  if not (self:isStorageTemporary() or self:isStorageReadOnly()) then
    return
  end
  local ok_uimgr, UIManager = pcall(require, "ui/uimanager")
  if not ok_uimgr or not UIManager or not UIManager.show then
    return
  end
  local ok_confirm, ConfirmBox = pcall(require, "ui/widget/confirmbox")
  if not ok_confirm or not ConfirmBox then
    return
  end
  local ok_gettext, gettext = pcall(require, "gettext")
  local _ = ok_gettext and gettext or function(s)
    return s
  end

  storage_warning_shown = true

  local text
  if self:isStorageReadOnly() then
    text = _(
      "Storage is completely read-only. Settings and reading history cannot be saved to disk."
    )
  else
    text = _(
      "Primary storage is read-only. Settings will be saved to temporary storage and may be lost when the device is restarted."
    )
  end

  UIManager:show(ConfirmBox:new({
    text = text,
    ok_text = _("Continue"),
    ok_callback = function() end,
    cancel_text = _("Quit"),
    cancel_callback = function()
      UIManager:quit()
    end,
  }))
end

local function initDataDir()
  local sub_data_dirs = {
    "cache",
    "clipboard",
    "data",
    "data/dict",
    "data/tessdata",
    -- "docsettings", -- created when needed
    -- "hashdocsettings", -- created when needed
    -- "history", -- legacy/obsolete sidecar files
    "ota",
    -- "patches", -- must be created manually by the interested user
    "plugins",
    "screenshots",
    "settings",
    "styletweaks",
    "tmp",
  }
  local datadir = DataStorage:getDataDir()
  if not DataStorage:isStorageReadOnly() then
    for _, dir in ipairs(sub_data_dirs) do
      local sub_data_dir = string.format("%s/%s", datadir, dir)
      if lfs.attributes(sub_data_dir, "mode") ~= "directory" then
        lfs.mkdir(sub_data_dir)
      end
    end
  end
end

initDataDir()

return DataStorage
