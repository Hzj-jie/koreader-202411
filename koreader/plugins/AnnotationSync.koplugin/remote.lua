local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local json = require("json")
local T = require("ffi/util").template
local gettext = require("gettext")
local logger = require("logger")
local util = require("util")

local function isConnected()
  return require("ui/network/manager"):isConnected()
end

local annotations = require("plugins/AnnotationSync.koplugin/annotations")
local utils = require("plugins/AnnotationSync.koplugin/utils")

local has_syncservice, SyncService =
  pcall(require, "apps/cloudstorage/syncservice")

local M = {}

local function get_sync_provider(widget)
  if widget.ui.cloudstorage then
    return widget.ui.cloudstorage
  elseif has_syncservice then
    return SyncService
  end
  return nil
end

local function perform_sync(widget, json_path, sync_cb, is_silent, on_complete)
  local provider = get_sync_provider(widget)
  if not provider then
    if not is_silent then
      UIManager:show(InfoMessage:new({
        text = gettext("Cloud Storage plugin is not enabled or available."),
        timeout = 4,
      }))
    else
      logger.warn(
        "AnnotationSync: Cloud Storage plugin is not enabled or available."
      )
    end
    if on_complete then
      on_complete(false)
    end
    return
  end

  local server = widget.settings.sync_server
  if server then
    if widget.ui.cloudstorage then
      widget.ui.cloudstorage:sync(server, json_path, sync_cb, is_silent)
    else
      SyncService.sync(server, json_path, sync_cb, is_silent)
    end
  else
    if not is_silent then
      UIManager:show(InfoMessage:new({
        text = T(gettext("No cloud destination set in settings.")),
        timeout = 4,
      }))
    else
      logger.warn("AnnotationSync: No cloud destination set in settings.")
    end
    if on_complete then
      on_complete(false)
    end
  end
end

function M.sync_annotations(widget, document, json_path, on_complete, force)
  if not isConnected() then
    logger.dbg("AnnotationSync: remote sync skipped, network is offline")
    if on_complete then
      on_complete(false)
    end
    return
  end
  local sync_cb = function(local_file, cached_file, income_file)
    local success, merged_list = annotations.sync_callback(
      document,
      local_file,
      cached_file,
      income_file,
      force
    )
    if on_complete then
      -- This is a hacky to ignore both local and remote empty annotations.
      -- In the case, the sync won't happen (success == false), but shouldn't be
      -- treated as failure in the complete callback, i.e. the file shouldn't be
      -- retried.
      on_complete((success ~= false) or (merged_list ~= nil), merged_list)
    end
    return success
  end
  perform_sync(widget, json_path, sync_cb, not force, on_complete)
end

function M._sync_settings_callback(widget, local_file, _, income_file)
  local local_data = utils.read_json(local_file) or {}
  local income_data = utils.read_json(income_file) or {}

  -- Merge incoming settings from other devices
  for device_id, data in pairs(income_data) do
    if device_id ~= widget.manager:getDeviceName() then
      local_data[device_id] = data
    end
  end

  util.writeToFile(json.encode(local_data), local_file)
  return true, local_data
end

function M.sync_settings(widget, json_path, on_complete)
  local sync_cb = function(local_file, cached_file, income_file)
    local success, local_data =
      M._sync_settings_callback(widget, local_file, cached_file, income_file)
    if on_complete then
      on_complete(success, local_data)
    end
    return success
  end
  perform_sync(widget, json_path, sync_cb, false, on_complete)
end

return M
