local DataStorage = require("datastorage")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local NetworkMgr = require("ui/network/manager")
local gettext = require("gettext")
local json = require("json")
local logger = require("logger")
local util = require("util")
local T = require("ffi/util").template
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local docsettings = require("frontend/docsettings")
local lfs = require("libs/libkoreader-lfs")
local readhistory = require("readhistory")

local annotations = require("plugins/AnnotationSync.koplugin/annotations")
local menus = require("plugins/AnnotationSync.koplugin/menus")
local remote = require("plugins/AnnotationSync.koplugin/remote")
local utils = require("plugins/AnnotationSync.koplugin/utils")

local function isConnected()
  return NetworkMgr:isConnected()
end

local SyncManager = {}

function SyncManager:new(plugin)
  local o = {
    plugin = plugin,
    is_syncing = false,
    has_pending_sync = false,
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

function SyncManager:getDeviceName()
  if
    self.plugin.settings.device_name
    and self.plugin.settings.device_name ~= ""
  then
    return self.plugin.settings.device_name
  end
  return Device.model or "unknown"
end

-- Sync all changed documents listed in changed_documents.lua
function SyncManager:syncAllChangedDocuments()
  local total, changed_docs = self:getPendingChangedDocuments()
  if total == 0 then
    utils.show_msg("No changed documents to sync.")
    return
  end

  require("ui/trapper"):wrap(function()
    local Trapper = require("ui/trapper")
    Trapper:setPausedText(
      gettext(
        "Sync All paused.\nDo you want to continue or abort syncing documents?"
      )
    )
    local count = 0
    local failed_files = {}
    local current_idx = 0

    for file, _ in pairs(changed_docs) do
      current_idx = current_idx + 1
      local _, filename = util.splitFilePathName(file)
      if filename == "" then
        filename = file
      end

      local go_on = Trapper:info(
        T(
          gettext("Syncing document %1 of %2...\n%3"),
          current_idx,
          total,
          filename
        )
      )
      if not go_on then
        logger.info("AnnotationSync: Sync All aborted by user")
        break
      end

      local res = self:_syncFile(file)
      if res == true or res == "skip_upload" then
        count = count + 1
      elseif res == false then
        table.insert(failed_files, file)
      end
    end

    Trapper:reset()

    if count == 0 and #failed_files == 0 then
      utils.show_msg("Sync All cancelled.")
    elseif count == 0 then
      utils.show_msg("Unable to sync modified documents: " .. total)
    else
      self:updateLastSync("Sync All")
      utils.show_msg("Successfully synced modified documents: " .. count)
    end

    if #failed_files > 0 then
      local filenames = {}
      for _, file in ipairs(failed_files) do
        local _, name = util.splitFilePathName(file)
        table.insert(filenames, name ~= "" and name or file)
      end
      local ConfirmBox = require("ui/widget/confirmbox")
      local list_str = "- " .. table.concat(filenames, "\n- ")
      UIManager:nextTick(function()
        UIManager:show(ConfirmBox:new({
          text = T(
            gettext(
              "Unable to sync the following document(s):\n%1\n\nWould you like to open the pending documents manager?"
            ),
            list_str
          ),
          type = "yesno",
          ok_text = gettext("Open Manager"),
          ok_callback = function()
            menus.show_pending_documents(self.plugin)
          end,
          cancel_text = gettext("Close"),
        }))
      end)
    end
  end)
end

-- Incremental background sync of pending documents (up to 60 per minute) using nextTick
function SyncManager:_syncPendingDocumentsBg()
  if self.is_syncing_pending_bg then
    logger.dbg("AnnotationSync: background pending sync already in progress")
    return
  end

  local total, changed_docs = self:getPendingChangedDocuments()
  if total == 0 then
    return
  end

  local files_to_sync = {}
  for file, _ in pairs(changed_docs) do
    if #files_to_sync >= 60 then
      break
    end
    table.insert(files_to_sync, file)
  end

  self.is_syncing_pending_bg = true
  local count = 0

  local function sync_next(idx)
    if idx > #files_to_sync or not isConnected() then
      self.is_syncing_pending_bg = false
      if count > 0 then
        self:updateLastSync("Auto Sync (" .. count .. ")")
        logger.info(
          "AnnotationSync: background sync completed for",
          count,
          "document(s)"
        )
      end
      return
    end

    local file = files_to_sync[idx]
    UIManager:nextTick(function()
      if self:_syncFile(file) == true then
        count = count + 1
      end
      sync_next(idx + 1)
    end)
  end

  sync_next(1)
end

-- Helper to sync a single file by path, handling opening, temporary document closing, and cleanup.
-- Returns true on success, false on failure (file exists but sync failed), or nil if the file is missing.
function SyncManager:_syncFile(file)
  local ui_document = self.plugin.ui and self.plugin.ui.document
  local document = self:getDocumentByFile(file)
  if document then
    logger.info("AnnotationSync: syncing document:", file)
    local is_temporary = (document ~= ui_document)
    local ok, success = pcall(self.syncDocument, self, document, false)
    if not ok then
      logger.warn(
        "AnnotationSync: syncDocument CRASHED for",
        file,
        ":",
        tostring(success)
      )
    elseif not success then
      logger.warn("AnnotationSync: syncDocument failed for", file)
    end

    if is_temporary then
      logger.info("AnnotationSync: closing temporary document:", file)
      document:close()
    end
    return ok and success
  else
    if not util.fileExists(file) then
      logger.warn(
        "AnnotationSync: file missing, removing from sync list:",
        file
      )
      self:removeFromChangedDocumentsFileByPath(file)
      return nil
    else
      logger.warn("AnnotationSync: could not open document for sync:", file)
      return false
    end
  end
end

-- Orchestrates the sync process for a single document
function SyncManager:syncDocument(document, is_manual)
  if not isConnected() then
    logger.dbg("AnnotationSync: cannot sync document, network is offline")
    return false
  end

  local file = document and document.file
  if not file then
    return false
  end

  self:flushSettings()
  logger.dbg("AnnotationSync: syncing document:", file)

  local json_path = self:_writeAnnotationsJSON(document)
  if not json_path then
    return false
  end

  logger.dbg(
    "AnnotationSync: remote sync of",
    json_path,
    "(force=",
    is_manual,
    ")"
  )
  local sync_success = false
  remote.sync_annotations(
    self.plugin,
    document,
    json_path,
    function(success, merged_list)
      sync_success = success
      self:_onSyncComplete(document, success, merged_list)
    end,
    is_manual
  )
  return sync_success
end

-- Refreshes the local sync JSON file with latest memory/sidecar state
function SyncManager:_writeAnnotationsJSON(document)
  assert(document and document.file, "document and document.file must exist")
  local file = document.file

  local sdr_dir = docsettings:getSidecarDir(file)
  if not sdr_dir or sdr_dir == "" then
    return false
  end

  -- Fix for Issue #34: Ensure the local sidecar directory exists
  if not lfs.attributes(sdr_dir, "mode") then
    logger.info("AnnotationSync: creating missing sidecar directory:", sdr_dir)
    util.makePath(sdr_dir)
  end

  local filename = self:_getAnnotationFilename(file)
  return annotations.write_annotations_json(
    document,
    self:getAnnotationsForDocument(document),
    sdr_dir,
    filename
  )
end

function SyncManager:changedDocumentsFile()
  return DataStorage:getDataDir() .. "/changed_documents.lua"
end

function SyncManager:getPendingChangedDocuments()
  local count = 0
  local track_path = self:changedDocumentsFile()
  local ok, changed_docs = pcall(dofile, track_path)
  if ok and type(changed_docs) == "table" then
    for __ in pairs(changed_docs) do
      count = count + 1
    end
  end
  return count, changed_docs
end

function SyncManager:hasPendingChangedDocuments()
  local count, __ = self:getPendingChangedDocuments()
  return count > 0
end

function SyncManager:addToChangedDocumentsFile(file)
  local track_path = self:changedDocumentsFile()
  -- Load existing table or create new
  local changed_docs = {}
  local ok, loaded = pcall(dofile, track_path)
  if ok and type(loaded) == "table" then
    changed_docs = loaded
  end
  if file and type(file) == "string" then
    changed_docs[file] = true
    self:_writeChangedDocumentsFile(changed_docs)
  end
end

function SyncManager:removeFromChangedDocumentsFile(document)
  local file = document and document.file
  self:removeFromChangedDocumentsFileByPath(file)
end

function SyncManager:removeFromChangedDocumentsFileByPath(file)
  if not file then
    return
  end
  local track_path = self:changedDocumentsFile()
  local ok, changed_docs = pcall(dofile, track_path)
  if ok and type(changed_docs) == "table" and changed_docs[file] then
    changed_docs[file] = nil
    self:_writeChangedDocumentsFile(changed_docs)
  end
end

function SyncManager:_writeChangedDocumentsFile(changed_docs)
  local track_path = self:changedDocumentsFile()
  local ok, err =
    util.writeToFile(self:_serialize_table(changed_docs), track_path, true)
  if not ok then
    logger.warn(
      "AnnotationSync: Failed to write changed documents file:",
      track_path,
      "(",
      tostring(err),
      ")"
    )
  end
end

function SyncManager:scanLibraryForUnsyncedDocuments()
  local added_files = {}
  local count = 0

  if readhistory and type(readhistory.hist) == "table" then
    for _, item in ipairs(readhistory.hist) do
      if item and item.file and lfs.attributes(item.file, "mode") == "file" then
        if
          docsettings:hasSidecarFile(item.file) and not added_files[item.file]
        then
          added_files[item.file] = true
          count = count + 1
        end
      end
    end
  end

  if count > 0 then
    local track_path = self:changedDocumentsFile()
    local changed_docs = {}
    local ok, loaded = pcall(dofile, track_path)
    if ok and type(loaded) == "table" then
      changed_docs = loaded
    end
    for book_path in pairs(added_files) do
      changed_docs[book_path] = true
    end
    self:_writeChangedDocumentsFile(changed_docs)
  end

  return count, added_files
end

-- Get annotations associated with given document
function SyncManager:getAnnotationsForDocument(document)
  -- Handle active document
  if
    document == self.plugin.ui.document
    and self.plugin.ui.annotation
    and self.plugin.ui.annotation.annotations
  then
    return self.plugin.ui.annotation.annotations
  end
  -- Handle inactive document
  local annotation_sidecar = docsettings:open(document.file)
  local result = annotation_sidecar:read("annotations")
  return result or {}
end

-- Get only annotations marked as deleted in the local sync JSON
function SyncManager:getDeletedAnnotations(document)
  local file = document and document.file
  if not file then
    return {}
  end

  local sdr_dir = docsettings:getSidecarDir(file)
  if not sdr_dir or sdr_dir == "" then
    return {}
  end

  local filename = self:_getAnnotationFilename(file)
  local json_path = sdr_dir .. "/" .. filename

  local map = utils.read_json(json_path)
  if not map then
    return {}
  end

  local deleted = {}
  for _, v in pairs(map) do
    if v.deleted then
      table.insert(deleted, v)
    end
  end

  table.sort(deleted, function(a, b)
    local cmp = annotations.compare_positions(a.page, b.page, document)
    return (cmp or 0) > 0
  end)

  return deleted
end

-- Helper to get a document object by file path
function SyncManager:getDocumentByFile(file)
  if not file or not util.fileExists(file) then
    return nil
  end
  -- If the current document is available, return it if it matches.
  local ui_document = self.plugin.ui and self.plugin.ui.document
  if ui_document and ui_document.file == file then
    return ui_document
  end
  -- Otherwise open the document with the correct provider in order to use
  -- its `comparePositions()` function.
  local document
  local provider = DocumentRegistry:getProvider(file)
  if provider then
    logger.dbg("AnnotationSync: provider for", file, ":", provider.provider)
    document = DocumentRegistry:openDocument(file, provider)
    -- A document provided by crengine must be rendered in order to use
    -- any functions that rely on XPointers.
    if provider.provider == "crengine" then
      if document then
        logger.dbg("AnnotationSync: rendering:", file)
        document:render()
      end
    end
  end
  return document
end

function SyncManager:updateLastSync(descriptor)
  local parenthetical = ""
  if descriptor and type(descriptor) == "string" then
    parenthetical = " (" .. descriptor .. ")"
  end
  self.plugin.settings.last_sync = os.date("%Y-%m-%d %H:%M:%S") .. parenthetical
  logger.dbg(
    "AnnotationSync: updateLastSync: updated at",
    self.plugin.settings.last_sync
  )
end

function SyncManager:flushSettings()
  UIManager:broadcastEvent(Event:new("FlushSettings"))
end

function SyncManager:_getAnnotationFilename(file)
  if self.plugin.settings.use_filename then
    local _, filename = util.splitFilePathName(file)
    return (filename ~= "" and filename or file) .. ".json"
  end
  local hash = file and type(file) == "string" and util.partialMD5(file)
    or gettext("No hash")
  return hash .. ".json"
end

function SyncManager:_onSyncComplete(document, success, merged_list)
  if success then
    if merged_list then
      self.plugin:applySyncedAnnotations(document, merged_list)
    end
    self:removeFromChangedDocumentsFile(document)
  else
    logger.warn(
      "AnnotationSync: sync failed for",
      (document.file or "unknown"),
      ", keeping in changed list"
    )
  end
end

-- Helper to serialize a Lua table as code
function SyncManager:_serialize_table(tbl)
  local result = "{\n"
  for k, v in pairs(tbl) do
    result = result .. string.format("  [%q] = %s,\n", k, tostring(v))
  end
  result = result .. "}"
  return result
end

function SyncManager:getSelectedSettingsWithValues()
  local selected = self.plugin.settings.selected_settings or {}
  if not next(selected) then
    return nil
  end

  -- Load active reader settings
  local active_reader_path = DataStorage:getDataDir() .. "/settings.reader.lua"
  local ok_a, active_reader = pcall(dofile, active_reader_path)
  if not ok_a or type(active_reader) ~= "table" then
    active_reader = {}
  end

  -- Load active defaults settings
  local active_defaults_path = DataStorage:getDataDir()
    .. "/defaults.custom.lua"
  local ok_ad, active_defaults = pcall(dofile, active_defaults_path)
  if not ok_ad or type(active_defaults) ~= "table" then
    active_defaults = {}
  end

  -- Cache for loaded settings files in settings/ directory
  local settings_cache = {}

  local result = {}
  for key, is_selected in pairs(selected) do
    if is_selected then
      local domain, full_key = key:match("^([^:]+):(.*)$")
      if domain and full_key then
        local val
        if domain == "reader" then
          val = utils.get_nested_value(active_reader, full_key)
        elseif domain == "defaults" then
          val = utils.get_nested_value(active_defaults, full_key)
        elseif domain:match("^settings/") then
          local settings_name = domain:sub(10)
          if settings_cache[settings_name] == nil then
            local filepath = DataStorage:getSettingsDir()
              .. "/"
              .. settings_name
              .. ".lua"
            local ok_s, a_tbl = pcall(dofile, filepath)
            if ok_s and type(a_tbl) == "table" then
              settings_cache[settings_name] = a_tbl
            else
              settings_cache[settings_name] = false
            end
          end
          local tbl = settings_cache[settings_name]
          if tbl then
            val = utils.get_nested_value(tbl, full_key)
          end
        end
        result[key] = val
      end
    end
  end

  return result
end

function SyncManager:pushSettings()
  local selected_values = self:getSelectedSettingsWithValues()
  if not selected_values then
    utils.show_msg(
      gettext(
        "No settings are selected. Please select settings to sync in 'Show changed settings'."
      )
    )
    return
  end

  local device_id = self:getDeviceName()
  local local_data = {
    [device_id] = {
      settings = selected_values,
      timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    },
  }

  local json_path = DataStorage:getDataDir() .. "/settings_sync.json"
  local ok, err = util.writeToFile(json.encode(local_data), json_path)
  if not ok then
    logger.warn(
      "AnnotationSync: failed to write settings JSON:",
      json_path,
      "(",
      tostring(err),
      ")"
    )
    utils.show_msg(gettext("Failed to write settings to local storage."))
    return
  end

  logger.dbg("AnnotationSync: pushing settings to remote:", json_path)
  utils.show_msg(gettext("Pushing settings to cloud..."))
  remote.sync_settings(self.plugin, json_path, function(success)
    if success then
      logger.dbg("AnnotationSync: settings push successful")
    else
      logger.warn("AnnotationSync: settings push failed")
    end
  end)
end

function SyncManager:getLocalSettingValue(key, caches)
  caches = caches or {}
  local domain, full_key = key:match("^([^:]+):(.*)$")
  if not domain or not full_key then
    return nil
  end

  if domain == "reader" then
    if caches.reader == nil then
      local active_reader_path = DataStorage:getDataDir()
        .. "/settings.reader.lua"
      local ok, active_reader = pcall(dofile, active_reader_path)
      caches.reader = ok and active_reader or {}
    end
    return utils.get_nested_value(caches.reader, full_key)
  elseif domain == "defaults" then
    if caches.defaults == nil then
      local active_defaults_path = DataStorage:getDataDir()
        .. "/defaults.custom.lua"
      local ok, active_defaults = pcall(dofile, active_defaults_path)
      caches.defaults = ok and active_defaults or {}
    end
    return utils.get_nested_value(caches.defaults, full_key)
  elseif domain:match("^settings/") then
    local settings_name = domain:sub(10)
    if caches[settings_name] == nil then
      local filepath = DataStorage:getSettingsDir()
        .. "/"
        .. settings_name
        .. ".lua"
      local ok, a_tbl = pcall(dofile, filepath)
      caches[settings_name] = ok and a_tbl or false
    end
    local tbl = caches[settings_name]
    if tbl then
      return utils.get_nested_value(tbl, full_key)
    end
  end
  return nil
end

local function save_nested_setting(settings_obj, parts, value)
  if #parts == 1 then
    settings_obj:save(parts[1], value)
  else
    local top_key = parts[1]
    local top_val = settings_obj:read(top_key)
    if type(top_val) ~= "table" then
      top_val = {}
    end
    local new_tbl = util.tableDeepCopy(top_val)
    local current = new_tbl
    for i = 2, #parts - 1 do
      local part = parts[i]
      if type(current[part]) ~= "table" then
        current[part] = {}
      end
      current = current[part]
    end
    current[parts[#parts]] = value
    settings_obj:save(top_key, new_tbl)
  end
  settings_obj:flush()
end

function SyncManager:_writeLocalSettingValue(key, value)
  local domain, full_key = key:match("^([^:]+):(.*)$")
  if not domain or not full_key then
    return false
  end

  local LuaSettings = require("luasettings")
  local parts = {}
  for part in string.gmatch(full_key, "([^%.]+)") do
    table.insert(parts, part)
  end

  if domain == "reader" then
    save_nested_setting(G_reader_settings, parts, value)

    local filepath = DataStorage:getDataDir() .. "/settings.reader.lua"
    local settings_obj = LuaSettings:open(filepath)
    save_nested_setting(settings_obj, parts, value)
    return true
  elseif domain == "defaults" then
    local filepath = DataStorage:getDataDir() .. "/defaults.custom.lua"
    local settings_obj = LuaSettings:open(filepath)
    save_nested_setting(settings_obj, parts, value)
    return true
  elseif domain:match("^settings/") then
    local settings_name = domain:sub(10)
    local filepath = DataStorage:getSettingsDir()
      .. "/"
      .. settings_name
      .. ".lua"
    local settings_obj = LuaSettings:open(filepath)
    save_nested_setting(settings_obj, parts, value)
    return true
  end
  return false
end

function SyncManager:pullSettings()
  if not isConnected() then
    utils.show_msg(gettext("Network is disconnected, cannot pull settings"))
    return
  end

  local json_path = DataStorage:getDataDir() .. "/settings_sync.json"
  utils.show_msg(gettext("Fetching settings from cloud..."))
  remote.sync_settings(self.plugin, json_path, function(success, merged_data)
    if success and merged_data then
      menus.show_devices_menu(self.plugin, merged_data)
    else
      utils.show_msg(gettext("Failed to fetch settings from cloud"))
    end
  end)
end

return SyncManager
