--[[--
This module displays a PathChooser widget to choose a download directory.

It can be used as a callback on a button or menu item.

Example:
  callback = function()
    require("ui/downloadmgr"):new{
      title = gettext("Choose download directory"),
      onConfirm = function(path)
        logger.dbg("set download directory to", path)
        G_reader_settings:save("download_dir", path)
        UIManager:nextTick(function()
          -- reinitialize dialog
        end)
      end,
    }:chooseDir()
  end
]]

local Notification = require("ui/widget/notification")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local gettext = require("gettext")
local util = require("util")

local DownloadMgr = {
  onConfirm = function() end,
}

function DownloadMgr:new(from_o)
  local o = from_o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

--- Checks whether the download directory is valid and writable.
-- @tparam[opt] string dir directory to check, defaults to saved download_dir
-- @treturn bool true if directory exists and is writable
function DownloadMgr.isDownloadDirWritable(dir)
  if type(dir) == "table" then
    dir = nil
  end
  dir = dir
    or G_reader_settings:read("download_dir")
    or G_named_settings.lastdir()
  return util.isDirRW(dir, true)
end

--- Pre-flight check for download directory before starting a download.
-- If directory is read-only or unwritable, notifies the user and returns false.
-- @tparam[opt] string dir directory to check
-- @treturn bool true if download directory is writable
function DownloadMgr.checkDownloadDir(dir)
  if type(dir) == "table" then
    dir = nil
  end
  dir = dir
    or G_reader_settings:read("download_dir")
    or G_named_settings.lastdir()
  if not util.isDirRW(dir, true) then
    UIManager:show(Notification:new({
      text = gettext(
        "Download directory is read-only. Please choose a writable directory."
      ),
    }))
    return false
  end
  return true
end

--- Displays a PathChooser widget for picking a (download) directory.
-- @treturn string path chosen by the user
function DownloadMgr:chooseDir(dir)
  local path
  if dir then
    path = dir
  else
    local download_dir = G_reader_settings:read("download_dir")
    path = download_dir and ffiutil.realpath(download_dir .. "/..")
      or G_named_settings.lastdir()
  end
  local path_chooser = PathChooser:new({
    select_file = false,
    show_files = false,
    require_writable = true,
    path = path,
    onConfirm = function(dir_path)
      self.onConfirm(dir_path)
    end,
  })
  UIManager:show(path_chooser)
end

function DownloadMgr:chooseCloudDir()
  local cloud_storage = require("apps/cloudstorage/cloudstorage"):new({
    item = self.item,
    onConfirm = function(dir_path)
      self.onConfirm(dir_path)
    end,
  })
  UIManager:show(cloud_storage)
end

return DownloadMgr
