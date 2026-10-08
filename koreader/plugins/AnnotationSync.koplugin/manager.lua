local DataStorage = require("datastorage")
local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local docsettings = require("frontend/docsettings")
local dump = require("dump")
local gettext = require("gettext")
local N_ = gettext.ngettext
local T = require("ffi/util").template
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local readhistory = require("readhistory")
local util = require("util")

local ReaderAnnotation = require("apps/reader/modules/readerannotation")
local annotations = require("plugins/AnnotationSync.koplugin/annotations")
local menus = require("plugins/AnnotationSync.koplugin/menus")
local remote = require("plugins/AnnotationSync.koplugin/remote")
local utils = require("plugins/AnnotationSync.koplugin/utils")

local ONLINE_RETRY_INTERVAL = 10

-- The file name of a book, for messages.
local function book_name(file)
  local _, name = util.splitFilePathName(file)
  return name
end

-- Background job callbacks and offline-queued syncs outlive the ReaderUI or
-- FileManager whose plugin queued them. Every plugin instance shares this
-- singleton table, and the latest plugin to init owns it.
local SyncManager = {
  running = nil,
  -- Books the user asked to sync: file -> "Manual Sync" or "Sync All". They
  -- run before the others, even with auto sync off. A request is used up
  -- when its job starts, or dropped when the book leaves the queue.
  requested = {},
}

function SyncManager:setPlugin(plugin)
  self.plugin = plugin
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

-- Manual Sync and "Sync now": queues the book first, its sync is forced.
function SyncManager:syncNow(file)
  self:_moveToFront(file)
  self.requested[file] = "Manual Sync"
  Notification:notify(
    T(gettext("Syncing in the background: %1"), book_name(file))
  )
  NetworkMgr:runWhenOnline(function()
    self:_dispatchNextSync()
  end)
end

-- Sync all changed documents listed in changed_documents.lua
function SyncManager:syncAllChangedDocuments()
  local total, changed_docs = self:getPendingChangedDocuments()
  if total == 0 then
    utils.show_msg("No changed documents to sync.")
    return
  end

  for _, file in ipairs(changed_docs) do
    -- Keep a Manual Sync request: it is forced.
    self.requested[file] = self.requested[file] or "Sync All"
  end
  Notification:notify(
    T(
      N_(
        "Syncing 1 book in the background",
        "Syncing %1 books one by one in the background",
        total
      ),
      total
    )
  )
  NetworkMgr:runWhenOnline(function()
    self:_dispatchNextSync()
  end)
end

function SyncManager:_loadChangedDocuments()
  local ok, docs = pcall(dofile, self:changedDocumentsFile())
  if not ok or type(docs) ~= "table" then
    return {}
  end
  if docs[1] == nil then
    -- Older versions wrote a map: { [file] = true }.
    local list = {}
    for file in pairs(docs) do
      table.insert(list, file)
    end
    return list
  end
  return docs
end

function SyncManager:_movePendingDocumentToBack(file)
  local list = self:_loadChangedDocuments()
  local idx = util.arrayContains(list, file)
  if idx then
    table.remove(list, idx)
    table.insert(list, file)
    self:_writeChangedDocumentsFile(list)
  end
end

function SyncManager:_moveToFront(file)
  local list = self:_loadChangedDocuments()
  local idx = util.arrayContains(list, file)
  if idx then
    table.remove(list, idx)
  end
  table.insert(list, 1, file)
  self:_writeChangedDocumentsFile(list)
end

function SyncManager:_startSync(file, trigger)
  if not util.fileExists(file) then
    logger.warn(
      "AnnotationSync: file missing, removing from sync list:",
      file
    )
    self:removeFromChangedDocumentsFileByPath(file)
    self.running = nil
    self:_dispatchNextSync()
    return
  end

  local _, pending_docs = self:getPendingChangedDocuments()
  if not util.arrayContains(pending_docs, file) then
    self.running = nil
    self:_dispatchNextSync()
    return
  end

  local ui_doc = self.plugin.ui.document
  local doc = (ui_doc and ui_doc.file == file) and ui_doc or file
  -- Manual Sync is forced, see annotations.merge.
  local force = trigger == "Manual Sync"
  assert(require("background_jobs").insertKeyed({
    executable = "fork",
    action = function()
      NetworkMgr:queryOnlineState()
      while not NetworkMgr:isOnline() do
        require("ffi/util").sleep(ONLINE_RETRY_INTERVAL)
        NetworkMgr:queryOnlineState()
      end

      local json_path = self:_writeAnnotationsJSON(doc)
      if not json_path then
        return { file = file, success = false }
      end
      local snapshot_path = json_path .. ".snapshot"
      local snapshot_content = assert(util.readFromFile(json_path, "r"))
      assert(util.writeToFile(snapshot_content, snapshot_path))

      local sync_success = false
      local uploaded = false
      local cached_path = self:getSyncCachePath(file)
      local ok, err = pcall(function()
        remote.sync_annotations(
          self.plugin,
          json_path,
          function(success, _, uploaded_json)
            sync_success = success
            if uploaded_json then
              uploaded = true
              assert(util.writeToFile(uploaded_json, json_path .. ".uploaded"))
            end
          end,
          force,
          cached_path
        )
      end)
      if not ok then
        logger.err("AnnotationSync: background sync failed for", file, err)
      end
      return {
        file = file,
        json_path = json_path,
        success = ok and sync_success == true,
        uploaded = uploaded,
      }
    end,
    callback = function(job)
      -- Was a Manual Sync asked for this book? One asked before this job
      -- started is in trigger (_dispatchNextSync moved requested[file] there),
      -- one asked while it ran is in requested[file]. Read it now: the queue
      -- update below can clear it.
      local asked = trigger == "Manual Sync"
        or self.requested[file] == "Manual Sync"
      local item = job.result
      if type(item) ~= "table" then
        logger.warn(
          "AnnotationSync: background sync returned invalid result for",
          file
        )
        item = { success = false }
      end
      if item.success then
        local snapshot_json =
          assert(util.readFromFile(item.json_path .. ".snapshot"))
        local uploaded_json = item.uploaded
            and assert(util.readFromFile(item.json_path .. ".uploaded"))
          or nil
        self:_applyBackgroundSync(
          file,
          snapshot_json,
          uploaded_json
        )
        self:_movePendingDocumentToBack(file)
        self:recordSyncState(trigger)
        logger.info(
          "AnnotationSync: background sync completed for",
          file
        )
      else
        self:_movePendingDocumentToBack(file)
      end
      if item.json_path then
        os.remove(item.json_path .. ".snapshot")
        os.remove(item.json_path .. ".uploaded")
      end
      self.running = nil
      -- A Manual Sync asked while this job ran is still requested if the book
      -- changed meanwhile or the job failed. The book's next job answers it.
      if asked and self.requested[file] ~= "Manual Sync" then
        if item.success then
          Notification:notify(T(gettext("Synced: %1"), book_name(file)))
        else
          utils.show_msg(T(gettext("Failed to sync %1."), book_name(file)))
        end
      end
      self:_dispatchNextSync(not item.success)
    end,
  }))
end

-- Starts the first book the user asked to sync. Without one, with auto sync
-- on and unless the last sync failed, starts the first book of the queue.
function SyncManager:_dispatchNextSync(failed)
  if self.running then
    return false
  end

  local list = self:_loadChangedDocuments()
  local file
  for _, f in ipairs(list) do
    if self.requested[f] then
      file = f
      break
    end
  end
  if not file and self.plugin.settings.network_auto_sync and not failed then
    file = list[1]
  end
  if not file then
    return false
  end

  local trigger = self.requested[file] or "Auto Sync"
  self.requested[file] = nil
  self.running = true
  NetworkMgr:willRerunWhenOnline(function()
    self:_startSync(file, trigger)
  end)
  return true
end

-- Applies a background sync that the forked child finished. The child merged
-- a snapshot of the book (snapshot_json) and uploaded the result
-- (uploaded_json, nil if there was nothing to upload). The book may have been
-- edited since the snapshot, so the upload can't replace it: run the same
-- 3-way merge again, with the book as it is now as the local side, the
-- snapshot as the base and the upload as the income.
function SyncManager:_applyBackgroundSync(
  file,
  snapshot_json,
  uploaded_json
)
  if not util.fileExists(file) then
    logger.warn(
      "AnnotationSync: file missing after background sync, skipping apply:",
      file
    )
    self:removeFromChangedDocumentsFileByPath(file)
    return
  end

  local document = { file = file }
  local ui_document = self.plugin.ui.document
  if ui_document and ui_document.file == file then
    document = ui_document
  end

  local book_now = self:getAnnotationsForDocument(document)
  -- Round trip through JSON so floating-point coordinates match the precision
  -- of snapshot_json and uploaded_json across comparisons and matching.
  local local_list = json.decode(json.encode(book_now))
  local base_list = json.decode(snapshot_json)

  local unchanged = util.tableEquals(local_list, base_list)

  if uploaded_json then
    local income_list = json.decode(uploaded_json)
    local _, active =
      annotations.merge(local_list, base_list, income_list, false)
    self.plugin:applySyncedAnnotations(document, active)
    self:_promoteSyncBase(file, uploaded_json)
  end

  if unchanged then
    self:removeFromChangedDocumentsFileByPath(file)
  end
end

-- Makes the uploaded list the merge base of `file`. Call it only after the
-- merge has reached the book: a base ahead of the book makes the next sync
-- read the remote additions as local deletions and tombstone them.
function SyncManager:_promoteSyncBase(file, uploaded_json)
  local cached_path = self:getSyncCachePath(file)
  local ok, err = util.writeToFile(uploaded_json, cached_path)
  if not ok then
    logger.warn(
      "AnnotationSync: Failed to write merge base:",
      cached_path,
      "(",
      tostring(err),
      ")"
    )
  end
end

function SyncManager:getSyncCachePath(file)
  local sdr_dir = docsettings:getSidecarDir(file)
  if not sdr_dir or sdr_dir == "" then
    return nil
  end
  if not lfs.attributes(sdr_dir, "mode") then
    logger.info("AnnotationSync: creating missing sidecar directory:", sdr_dir)
    util.makePath(sdr_dir)
  end
  local filename = self:_getAnnotationFilename(file)
  return sdr_dir .. "/" .. filename .. ".sync"
end

-- Refreshes the local sync JSON file with latest memory/sidecar state in /tmp
function SyncManager:_writeAnnotationsJSON(document)
  local file = type(document) == "string" and document
    or (document and document.file)
  assert(file, "document and document.file must exist")

  local tmp_dir = DataStorage:getTmpDir()
  if not tmp_dir or tmp_dir == "" then
    return false
  end

  local filename = self:_getAnnotationFilename(file)
  return annotations.write_annotations_json(
    self:getAnnotationsForDocument(document),
    tmp_dir,
    filename
  )
end

function SyncManager:changedDocumentsFile()
  return DataStorage:getDataDir() .. "/changed_documents.lua"
end

function SyncManager:getPendingChangedDocuments()
  local list = self:_loadChangedDocuments()
  return #list, list
end

function SyncManager:addToChangedDocumentsFile(file)
  local list = self:_loadChangedDocuments()
  if not util.arrayContains(list, file) then
    table.insert(list, file)
    self:_writeChangedDocumentsFile(list)
  end
  self:_dispatchNextSync()
end

function SyncManager:removeFromChangedDocumentsFileByPath(file)
  -- A request lives only while its book is queued.
  self.requested[file] = nil
  local list = self:_loadChangedDocuments()
  local idx = util.arrayContains(list, file)
  if idx then
    table.remove(list, idx)
    self:_writeChangedDocumentsFile(list)
  end
end

function SyncManager:_writeChangedDocumentsFile(changed_docs)
  local track_path = self:changedDocumentsFile()
  local ok, err =
    util.writeToFile(dump(changed_docs), track_path, true)
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
    local list = self:_loadChangedDocuments()
    for _, item in ipairs(readhistory.hist) do
      if added_files[item.file] and not util.arrayContains(list, item.file) then
        table.insert(list, item.file)
      end
    end
    self:_writeChangedDocumentsFile(list)
    self:_dispatchNextSync()
  end

  return count, added_files
end

-- Get annotations associated with given document
function SyncManager:getAnnotationsForDocument(document)
  local file = type(document) == "string" and document
    or (document and document.file)
  -- Handle active document
  if document == self.plugin.ui.document then
    return self.plugin.ui.annotation.annotations
  end
  -- Handle inactive document
  local annotation_sidecar = docsettings:open(file)
  return ReaderAnnotation.loadFromSettings(annotation_sidecar)
end

-- Get only annotations marked as deleted in the sync cache JSON
function SyncManager:getDeletedAnnotations(document)
  local cached_path = self:getSyncCachePath(document.file)
  local map = cached_path and utils.read_json(cached_path)
  if not map then
    return {}
  end

  local active = self:getAnnotationsForDocument(document)
  local function is_active(item)
    for _, a in ipairs(active) do
      if ReaderAnnotation.doesMatch(item, a) then
        return true
      end
    end
    return false
  end

  local deleted = {}
  for _, v in pairs(map) do
    if v.deleted and not is_active(v) then
      table.insert(deleted, v)
    end
  end

  return annotations.sort(deleted)
end

function SyncManager:recordSyncState(descriptor)
  local parenthetical = ""
  if type(descriptor) == "string" and descriptor ~= "" then
    parenthetical = " (" .. descriptor .. ")"
  end
  self.plugin.settings.last_sync = os.date("%Y-%m-%d %H:%M:%S") .. parenthetical
  logger.dbg(
    "AnnotationSync: recordSyncState: updated at",
    self.plugin.settings.last_sync
  )
end

function SyncManager:_getAnnotationFilename(file)
  if self.plugin.settings.use_filename then
    local _, filename = util.splitFilePathName(file)
    return (filename ~= "" and filename or file) .. ".json"
  end
  local hash = util.partialMD5(file) or gettext("No hash")
  return hash .. ".json"
end

function SyncManager:cleanOrphanSyncFiles()
  local tmp_dir = DataStorage:getTmpDir()
  if not tmp_dir or lfs.attributes(tmp_dir, "mode") ~= "directory" then
    return
  end

  pcall(function()
    for entry in lfs.dir(tmp_dir) do
      if entry:match("%.json%.sync$") or entry:match("%.json%.temp$") then
        os.remove(tmp_dir .. "/" .. entry)
      end
    end
  end)
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
  local json_path = DataStorage:getDataDir() .. "/settings_sync.json"
  utils.show_msg(gettext("Fetching settings from cloud..."))
  remote.pull_settings(self.plugin, json_path, function(success, remote_data)
    if success then
      menus.show_devices_menu(self.plugin, remote_data)
    else
      utils.show_msg(gettext("Failed to fetch settings from cloud"))
    end
  end)
end

return SyncManager
