local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local FfiUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local socket = require("socket")
local socketutil = require("socketutil")
local logger = require("logger")
local gettext = require("gettext")
local C_ = gettext.pgettext
local T = FfiUtil.template

local Updater = {}

local function cleanupUpdateArtifacts(install_dir, include_staged)
  os.remove(install_dir .. ".update.tar.gz.part")
  os.remove(install_dir .. ".update.tar.gz")
  FfiUtil.purgeDir(install_dir .. ".update.tmp")
  if include_staged then
    FfiUtil.purgeDir(install_dir .. ".update")
  end
end

local function showFailure(install_dir, template_msg, reason, downloading_msg)
  UIManager:close(downloading_msg)
  cleanupUpdateArtifacts(install_dir, false)
  UIManager:show(InfoMessage:new({
    text = T(template_msg, reason or ""),
  }))
end

function Updater:getPackageName()
  local f = assert(io.open(lfs.currentdir() .. "/ko_update.sh", "r"))
  local content = f:read("*a")
  f:close()
  return ("\n" .. content):match('\n%s*PACKAGE="([%w_%-]+)"')
end

function Updater:_performUpdate(pkg)
  local install_dir = lfs.currentdir()
  cleanupUpdateArtifacts(install_dir, true)

  local _, free_bytes = FfiUtil.df(install_dir)
  if free_bytes < 160 * 1024 * 1024 then
    UIManager:show(InfoMessage:new({
      text = gettext("Not enough free space to download and unpack the update."),
    }))
    return
  end

  local downloading_msg = InfoMessage:new({
    text = gettext("Downloading may take several minutes…"),
  })
  UIManager:show(downloading_msg)

  UIManager:tickAfterNext(function()
    local part_path = install_dir .. ".update.tar.gz.part"
    local out_file, open_err = io.open(part_path, "wb")
    if not out_file then
      showFailure(
        install_dir,
        gettext("Failed to download update:\n%1"),
        open_err,
        downloading_msg
      )
      return
    end

    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, -1)
    local code, _, status = socket.skip(
      1,
      http.request({
        url = string.format(
          "https://github.com/Hzj-jie/koreader-202411/releases/latest/download/%s.tar.gz",
          pkg
        ),
        headers = {
          ["Accept-Encoding"] = "identity",
        },
        sink = function(chunk)
          if chunk then
            return out_file:write(chunk)
          end
          return 1
        end,
      })
    )
    socketutil:reset_timeout()
    local close_ok, close_err = out_file:close()

    if code ~= 200 or not close_ok then
      logger.warn("Updater: failed to download update:", status or code, close_err)
      showFailure(
        install_dir,
        gettext("Failed to download update:\n%1"),
        code ~= 200 and (status or code) or close_err,
        downloading_msg
      )
      return
    end

    local archive_path = install_dir .. ".update.tar.gz"
    local renamed, rename_err = os.rename(part_path, archive_path)
    if not renamed then
      showFailure(
        install_dir,
        gettext("Failed to download update:\n%1"),
        rename_err,
        downloading_msg
      )
      return
    end

    local tmp_update_dir = install_dir .. ".update.tmp"
    local mkdir_ok, mkdir_err = lfs.mkdir(tmp_update_dir)
    if not mkdir_ok then
      showFailure(
        install_dir,
        gettext("Failed to unpack update:\n%1"),
        mkdir_err,
        downloading_msg
      )
      return
    end

    local unpack_ok, unpack_err = Device:unpackArchive(archive_path, tmp_update_dir)
    os.remove(archive_path)
    if not unpack_ok then
      logger.warn("Updater: failed to unpack update:", unpack_err)
      showFailure(
        install_dir,
        gettext("Failed to unpack update:\n%1"),
        unpack_err,
        downloading_msg
      )
      return
    end

    local staged_ok, staged_err = os.rename(tmp_update_dir, install_dir .. ".update")
    if not staged_ok then
      showFailure(
        install_dir,
        gettext("Failed to unpack update:\n%1"),
        staged_err,
        downloading_msg
      )
      return
    end

    UIManager:close(downloading_msg)
    Device:install()
  end)
end

function Updater:update()
  local pkg = assert(self:getPackageName())

  NetworkMgr:runWhenConnected(function()
    local prompt = T(gettext("Download and unpack the latest update (%1)?"), pkg)
    if not NetworkMgr:isOnline() then
      prompt = gettext(
        "Network connection is offline or unstable. The update download may fail."
      )
        .. "\n\n"
        .. prompt
    end

    UIManager:show(ConfirmBox:new({
      text = prompt,
      ok_text = C_("Application update | Button", "Update"),
      ok_callback = function()
        self:_performUpdate(pkg)
      end,
    }))
  end)
end

return Updater
