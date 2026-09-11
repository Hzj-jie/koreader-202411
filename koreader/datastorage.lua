-- need low-level mechanism to detect android to avoid recursive dependency
local isAndroid, android = pcall(require, "android")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local DataStorage = {}

local data_dir
local full_data_dir
local cache_dir
local is_cache_dir_writable = false
local tmp_dir
local is_storage_temporary = false
local is_storage_readonly = false

-- For testing purposes only; do not use in production code.
-- Resets cached directories and storage state flags across test scenarios.
function DataStorage:reset()
  data_dir = nil
  full_data_dir = nil
  cache_dir = nil
  is_cache_dir_writable = false
  tmp_dir = nil
  is_storage_temporary = false
  is_storage_readonly = false
end

function DataStorage:getTmpDir()
  if tmp_dir then
    return tmp_dir
  end

  local candidates = {}
  local env_tmp = os.getenv("TMPDIR")
  if env_tmp then
    table.insert(candidates, env_tmp)
  end

  if isAndroid then
    table.insert(candidates, "/data/local/tmp")
  end
  table.insert(candidates, "/tmp")

  for _, cand in ipairs(candidates) do
    if util.isDirRW(cand, true) then
      tmp_dir = cand
      return tmp_dir
    end
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
    local package_name = app_id:match("^(.-)_")
    table.insert(
      candidates,
      string.format("%s/%s", os.getenv("XDG_DATA_HOME"), package_name)
    )
  end
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

  if
    not (
      os.getenv("APPIMAGE")
      or os.getenv("FLATPAK")
      or os.getenv("KO_MULTIUSER")
    )
  then
    table.insert(candidates, ".")
  end

  for _, cand in ipairs(candidates) do
    if cand and util.isDirRW(cand, true) then
      data_dir = cand
      return data_dir
    end
  end

  -- All standard candidates failed write check; fall back to temporary directory
  local fallback_tmp = self:getTmpDir()
  if fallback_tmp then
    local tmp_data_dir = fallback_tmp .. "/koreader"
    if util.isDirRW(tmp_data_dir, true) then
      data_dir = tmp_data_dir
      is_storage_temporary = true
      return data_dir
    end
  end

  -- If even temporary storage is not writable, fall back to first candidate in read-only mode
  data_dir = candidates[1]
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

-- Returns a writable cache directory, or nil if no writable cache directory exists.
function DataStorage:getCacheDirOrNil()
  if cache_dir then
    return is_cache_dir_writable and cache_dir or nil
  end

  local preferred = self:getDataDir() .. "/cache"
  if util.isDirRW(preferred, true) then
    cache_dir = preferred
    is_cache_dir_writable = true
    return cache_dir
  end

  local fallback_tmp = self:getTmpDir()
  if fallback_tmp then
    local tmp_cache = fallback_tmp .. "/koreader_cache"
    if util.isDirRW(tmp_cache, true) then
      cache_dir = tmp_cache
      is_cache_dir_writable = true
      return cache_dir
    end
  end

  cache_dir = preferred
  is_cache_dir_writable = false
  return nil
end

-- Returns a cache directory. Always returns a directory even if it is not writable.
-- Callers should take care of an unwritable directory themselves.
function DataStorage:getCacheDir()
  if not cache_dir then
    self:getCacheDirOrNil()
  end
  return cache_dir
end

function DataStorage:getFullDataDir()
  if full_data_dir then
    return full_data_dir
  end

  local dir = self:getDataDir()
  if string.sub(dir, 1, 1) == "/" then
    full_data_dir = dir
  else
    full_data_dir = (lfs.currentdir() .. "/" .. dir):gsub("/%.$", "")
  end

  return full_data_dir
end

function DataStorage:showStorageWarningIfNeeded()
  if not (is_storage_temporary or is_storage_readonly) then
    return
  end
  local UIManager = require("ui/uimanager")
  local gettext = require("gettext")

  local text
  if is_storage_readonly then
    text = gettext(
      "Storage is completely read-only. Settings and reading history cannot be saved to disk."
    )
  else
    text = gettext(
      "Primary storage is read-only. Settings will be saved to temporary storage and may be lost when the device is restarted."
    )
  end

  UIManager:show(require("ui/widget/confirmbox"):new({
    text = text,
    ok_text = gettext("Continue"),
    ok_callback = function() end,
    cancel_text = gettext("Quit"),
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
  if not is_storage_readonly then
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
