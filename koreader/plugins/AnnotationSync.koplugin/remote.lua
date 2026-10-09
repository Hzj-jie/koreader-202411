local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local json = require("json")
local T = require("ffi/util").template
local gettext = require("gettext")
local logger = require("logger")
local util = require("util")

-- SyncService runs exec synchronously only when online (Dropbox uses
-- runWhenOnline, WebDAV runWhenConnected, and isOnline() implies both). A
-- deferred exec would run after cleanup_tmp() has already deleted json_path.
local function isOnline()
  return require("ui/network/manager"):isOnline()
end

local annotations = require("plugins/AnnotationSync.koplugin/annotations")
local utils = require("plugins/AnnotationSync.koplugin/utils")

local SyncService = require("apps/cloudstorage/syncservice")

local M = {}

local function perform_sync(widget, json_path, sync_cb, is_silent, finish_cb)
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
    finish_cb(false)
    return
  end

  SyncService.sync(server, json_path, sync_cb, is_silent, finish_cb)
end

function M.sync_annotations(widget, json_path, on_complete, cached_path)
  local cleanup_tmp = function()
    os.remove(json_path)
    os.remove(json_path .. ".temp")
    os.remove(json_path .. ".sync")
  end
  if not isOnline() then
    logger.dbg("AnnotationSync: remote sync skipped, network is offline")
    cleanup_tmp()
    if on_complete then
      on_complete(false)
    end
    return
  end
  local captured_merged_list = nil

  local sync_cb = function(local_file, cached_file, income_file, code_response)
    local actual_cached_file = cached_path or cached_file
    local success, merged_list = annotations.sync_callback(
      local_file,
      actual_cached_file,
      income_file,
      code_response
    )
    captured_merged_list = merged_list
    return success
  end
  local finished, uploaded, uploaded_json = false, nil, nil
  local ok, err = pcall(function()
    -- Runs in the forked background job, so always silent.
    perform_sync(widget, json_path, sync_cb, true, function(result)
      finished, uploaded = true, result
    end)
    -- The isOnline() gate makes SyncService run exec before returning. A
    -- postponed exec would merge json_path after cleanup_tmp() removed it.
    assert(finished, "AnnotationSync: SyncService postponed the sync")
    if uploaded then
      -- sync_callback wrote the merged list into json_path for the upload.
      -- The caller makes it the merge base (cached_path) once the merge
      -- has reached the book.
      uploaded_json = assert(util.readFromFile(json_path, "r"))
    end
  end)
  cleanup_tmp()
  if not ok then
    if on_complete then
      on_complete(false)
    end
    error(err)
  end

  if on_complete then
    -- nil: nothing to upload (e.g. both sides empty), still in sync.
    on_complete(uploaded ~= false, captured_merged_list, uploaded_json)
  end
end

-- Uploads json_path, which holds this device's settings. sync_cb first copies
-- the other devices' entries from the cloud file into it, so the upload
-- replaces only this device's entry.
function M.push_settings(widget, json_path, on_complete)
  local sync_cb = function(local_file, _, income_file, code_response)
    if SyncService.notFound(code_response) then
      return true
    end

    local income_data = utils.read_json(income_file)
    if not income_data then
      logger.warn(
        "AnnotationSync: Failed to parse remote settings from server. Aborting sync."
      )
      return false
    end

    local local_data = utils.read_json(local_file)
    -- Merge incoming settings from other devices
    for device_id, data in pairs(income_data) do
      if device_id ~= widget.manager:getDeviceName() then
        local_data[device_id] = data
      end
    end

    util.writeToFile(json.encode(local_data), local_file)
    return true
  end
  perform_sync(widget, json_path, sync_cb, false, function(uploaded)
    on_complete(uploaded ~= false)
  end)
end

-- Downloads the cloud settings for the devices menu. sync_cb returns nil,
-- so SyncService uploads nothing.
function M.pull_settings(widget, json_path, on_complete)
  local remote_data = nil
  local sync_cb = function(_, _, income_file, code_response)
    if SyncService.notFound(code_response) then
      remote_data = {}
      return nil
    end
    remote_data = utils.read_json(income_file)
    if not remote_data then
      logger.warn(
        "AnnotationSync: Failed to parse remote settings from server."
      )
      return false
    end
    return nil
  end
  perform_sync(widget, json_path, sync_cb, false, function(result)
    on_complete(result ~= false, remote_data)
  end)
end

return M
