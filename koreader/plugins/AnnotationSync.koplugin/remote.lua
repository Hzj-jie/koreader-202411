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

local SyncService = require("apps/cloudstorage/syncservice")

local M = {}

local function perform_sync(widget, json_path, sync_cb, is_silent)
  local server = widget.settings.sync_server
  if not server then
    if not is_silent then
      UIManager:show(InfoMessage:new({
        text = T(gettext("No cloud destination set in settings.")),
        timeout = 4,
      }))
    else
      logger.warn("AnnotationSync: No cloud destination set in settings.")
    end
    return false
  end

  local sync_cb_invoked = false
  local wrapped_cb = function(...)
    sync_cb_invoked = true
    if sync_cb then
      return sync_cb(...)
    end
  end

  local res = SyncService.sync(server, json_path, wrapped_cb, is_silent)
  if res ~= nil then
    return res == true
  end
  return sync_cb_invoked
end

function M.sync_annotations(widget, json_path, on_complete, force, cached_path)
  local cleanup_tmp = function()
    os.remove(json_path)
    os.remove(json_path .. ".temp")
    os.remove(json_path .. ".sync")
  end
  if not isConnected() then
    logger.dbg("AnnotationSync: remote sync skipped, network is offline")
    cleanup_tmp()
    if on_complete then
      on_complete(false)
    end
    return
  end
  local captured_merged_list = nil
  local sync_cb_called = false
  local sync_cb_success = false

  local sync_cb = function(local_file, cached_file, income_file, code_response)
    sync_cb_called = true
    local actual_cached_file = cached_path or cached_file
    local success, merged_list = annotations.sync_callback(
      local_file,
      actual_cached_file,
      income_file,
      force,
      code_response
    )
    sync_cb_success = success
    captured_merged_list = merged_list
    return success
  end
  local ok, sync_success = pcall(function()
    return perform_sync(widget, json_path, sync_cb, not force)
  end)
  if sync_success and cached_path then
    local tmp_cached = json_path .. ".sync"
    local f = io.open(tmp_cached, "r")
    if f then
      f:close()
      local ffiutil = require("ffi/util")
      os.remove(cached_path)
      ffiutil.copyFile(tmp_cached, cached_path)
      os.remove(tmp_cached)
    end
  end
  cleanup_tmp()
  if not ok then
    if on_complete then
      on_complete(false)
    end
    error(sync_success)
  end

  if on_complete then
    -- Successful if sync succeeded, OR if both local and remote were empty
    -- (in which case sync_cb returned false and skipped upload, but captured_merged_list is empty table)
    local is_success = (sync_success == true)
      or (
        sync_cb_called
        and sync_cb_success == false
        and captured_merged_list ~= nil
      )
    on_complete(is_success, captured_merged_list)
  end
end

function M._sync_settings_callback(
  widget,
  local_file,
  _,
  income_file,
  code_response
)
  local is_not_found = code_response == 404
    or code_response == 409
    or (
      code_response == nil
      and (not income_file or not io.open(income_file, "r"))
    )

  local local_data = utils.read_json(local_file) or {}
  if is_not_found then
    util.writeToFile(json.encode(local_data), local_file)
    return true, local_data
  end

  local income_data = utils.read_json(income_file)
  if not income_data then
    logger.warn(
      "AnnotationSync: Failed to parse remote settings from server. Aborting sync."
    )
    return false
  end

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
  local final_local_data = nil
  local sync_cb = function(local_file, cached_file, income_file, code_response)
    local success, local_data = M._sync_settings_callback(
      widget,
      local_file,
      cached_file,
      income_file,
      code_response
    )
    final_local_data = local_data
    return success
  end
  local sync_success = perform_sync(widget, json_path, sync_cb, false)
  if on_complete then
    on_complete(sync_success == true, final_local_data)
  end
end

return M
