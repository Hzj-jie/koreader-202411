local ConfirmBox = require("ui/widget/confirmbox")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local docsettings = require("frontend/docsettings")
local T = require("ffi/util").template
local DataStorage = require("datastorage")
local NetworkMgr = require("ui/network/manager")
local gettext = require("gettext")
local json = require("json")
local logger = require("logger")
local util = require("util")

local function isConnected()
  return NetworkMgr:isConnected()
end

local SettingsSelection =
  require("plugins/AnnotationSync.koplugin/settings_selection")
local SyncManager = require("plugins/AnnotationSync.koplugin/manager")
local annotations = require("plugins/AnnotationSync.koplugin/annotations")
local menus = require("plugins/AnnotationSync.koplugin/menus")
local utils = require("plugins/AnnotationSync.koplugin/utils")

local has_syncservice, SyncService =
  pcall(require, "apps/cloudstorage/syncservice")

local manual_sync_description =
  "Sync annotations and bookmarks of the active document."
local sync_all_description =
  "Sync annotations and bookmarks of all unsynced documents with pending modifications."

local AnnotationSyncPlugin = WidgetContainer:extend({
  -- see also: _meta.lua
  is_doc_only = false,

  settings = nil,
  manager = nil,
})

AnnotationSyncPlugin.default_settings = {
  last_sync = "Never",
  use_filename = false,
  network_auto_sync = false,
  device_name = "",
  selected_settings = {},
}

function AnnotationSyncPlugin:init()
  self.ui.menu:registerToMainMenu(self)

  -- Ensure the plugin is in the ReaderUI event chain
  local found = false
  for __, child in ipairs(self.ui) do
    if child == self then
      found = true
      break
    end
  end
  if not found then
    table.insert(self.ui, self)
  end

  utils.insert_after_statistics(self.plugin_id)
  self:onDispatcherRegisterActions()

  self.settings = G_reader_settings:readTableRef(
    self.plugin_id,
    util.tableDeepCopy(self.default_settings)
  )

  -- Fallback/migration for legacy cloud_server_object
  if not self.settings.sync_server then
    local server_json = G_reader_settings:read("cloud_server_object")
    if server_json and server_json ~= "" then
      local ok, server = pcall(json.decode, server_json)
      if ok and server then
        self.settings.sync_server = server
        self:saveSettings()
      end
    end
  end

  -- Sanitize corrupted settings
  self.manager = SyncManager:new(self)

  -- Migrate old annotation_sync_use_filename setting
  if G_reader_settings:has("annotation_sync_use_filename") then
    self.settings.use_filename =
      G_reader_settings:isTrue("annotation_sync_use_filename")
    G_reader_settings:delete("annotation_sync_use_filename")
  end

  self.settings_key = self.plugin_id

  if not gettext.loadPO then
    gettext.loadPO = function(po_path)
      local po = io.open(po_path, "r")
      if not po then
        return
      end

      local translation = gettext.translation
      local context = gettext.context

      local function addTranslation(msgctxt, msgid, msgstr)
        local unescaped =
          msgstr:gsub("\\n", "\n"):gsub('\\"', '"'):gsub("\\\\", "\\")
        if unescaped == "" then
          return
        end

        if msgctxt and msgctxt ~= "" then
          if not context[msgctxt] then
            context[msgctxt] = {}
          end
          context[msgctxt][msgid] = unescaped
        else
          translation[msgid] = unescaped
        end
      end

      local data = {}
      local fuzzy = false
      local what = nil

      while true do
        local line = po:read("*l")
        if line == nil or line == "" then
          if data.msgid and data.msgstr and data.msgstr ~= "" then
            addTranslation(data.msgctxt, data.msgid, data.msgstr)
          end
          if line == nil then
            break
          end
          data = {}
          what = nil
        else
          if not line:match("^#") then
            local w, s = line:match('^%s*([%a_%[%]0-9]+)%s+"(.*)"%s*$')
            if w then
              what = w
            else
              s = line:match('^%s*"(.*)"%s*$')
            end
            if fuzzy then
              if not (what and s == "") then
                fuzzy = false
              end
            elseif what and s then
              s = s:gsub("\\n", "\n")
              s = s:gsub('\\"', '"')
              s = s:gsub("\\\\", "\\")
              data[what] = (data[what] or "") .. s
            end
          elseif line:match("#, fuzzy") then
            fuzzy = true
          end
        end
      end
      po:close()
    end
  end

  -- Load plugin translations dynamically if available for the active locale
  local lang = gettext.current_lang
  if lang and lang ~= "C" and lang ~= "" then
    local path = self.path or "plugins/AnnotationSync.koplugin"
    local po_path = string.format("%s/l10n/%s/annotation_sync.po", path, lang)
    local f = io.open(po_path, "r")
    if f then
      f:close()
      gettext.loadPO(po_path)
    end
  end
end

function AnnotationSyncPlugin:saveSettings()
  G_reader_settings:save(self.plugin_id, self.settings, self.default_settings)
end

function AnnotationSyncPlugin:deletePluginSettings()
  G_reader_settings:delete(self.plugin_id)
  G_reader_settings:delete("cloud_server_object")
  G_reader_settings:delete("cloud_download_dir")
  G_reader_settings:delete("cloud_provider_type")

  local track_path
  if self.manager then
    track_path = self.manager:changedDocumentsFile()
  else
    track_path = DataStorage:getDataDir() .. "/changed_documents.lua"
  end
  if track_path and util.fileExists(track_path) then
    os.remove(track_path)
  end
end

function AnnotationSyncPlugin:addToMainMenu(menu_items)
  menu_items.annotation_sync_plugin = {
    text = gettext("Annotation Sync"),
    sorting_hint = "tools",
    sub_item_table = {
      {
        text = gettext("Settings"),
        sub_item_table = {
          {
            text = gettext("Cloud settings"),
            enabled_func = function()
              return self.ui.cloudstorage ~= nil or has_syncservice
            end,
            callback = function()
              if self.ui.cloudstorage then
                self.ui.cloudstorage:onShowCloudStorageList(function(server)
                  self:onSyncServiceConfirm(server)
                end)
              elseif has_syncservice then
                local sync_service = SyncService:new({})
                sync_service.onConfirm = function(server)
                  self:onSyncServiceConfirm(server)
                end
                UIManager:show(sync_service)
              end
            end,
          },
          {
            text = gettext("Use filename instead of hash"),
            checked_func = function()
              return self.settings.use_filename
            end,
            callback = function()
              self.settings.use_filename = not self.settings.use_filename
              self:saveSettings()
              UIManager:close()
            end,
          },
          {
            text = gettext(
              "Automatically Sync All when network becomes available"
            ),
            checked_func = function()
              return self.settings.network_auto_sync
            end,
            callback = function()
              self.settings.network_auto_sync =
                not self.settings.network_auto_sync
              self:saveSettings()
              UIManager:close()
            end,
          },

          {
            text_func = function()
              local dev_name = self.settings.device_name
              if not dev_name or dev_name == "" then
                dev_name = require("device").model or "unknown"
              end
              return T(gettext("Device name: %1"), dev_name)
            end,
            enabled_func = function()
              return true
            end,
            callback = function()
              local default_dev_name = require("device").model or "unknown"
              local current_val = self.settings.device_name
              if not current_val or current_val == "" then
                current_val = default_dev_name
              end
              local input
              input = InputDialog:new({
                title = gettext("Set device name"),
                description = gettext(
                  "Leave empty to use the default device name."
                ),
                input = current_val,
                save_callback = function(val)
                  local dev_name = val:gsub("^%s*(.-)%s*$", "%1")
                  if dev_name == default_dev_name then
                    dev_name = ""
                  end
                  self.settings.device_name = dev_name
                  self:saveSettings()
                  if self.ui.menu and self.ui.menu.showMainMenu then
                    self.ui.menu:showMainMenu()
                  end
                  return true
                end,
              })
              UIManager:show(input)
            end,
          },
          {
            text = gettext("Show changed settings"),
            callback = function()
              self:showChangedSettings()
            end,
          },
          {
            enabled = false,
            text_func = function()
              local server = self.settings.sync_server
              local cloud_desc = (server and server.url) or gettext("None")
              return T(gettext("Current cloud: %1"), cloud_desc)
            end,
          },
        },
        separator = true,
      },
      {
        text = gettext("Push settings to cloud"),
        enabled = ((G_reader_settings:read("cloud_download_dir") or "") ~= ""),
        callback = function()
          self.manager:pushSettings()
        end,
      },
      {
        text = gettext("Pull settings from cloud"),
        enabled = ((G_reader_settings:read("cloud_download_dir") or "") ~= ""),
        callback = function()
          self.manager:pullSettings()
        end,
      },
      {
        text = gettext("Manual Sync"),
        enabled = ((G_reader_settings:read("cloud_download_dir") or "") ~= "")
          and ((self.ui and self.ui.document) ~= nil),
        hold_callback = function()
          utils.show_msg(manual_sync_description)
        end,
        callback = function()
          self:manualSync()
        end,
      },
      {
        text = gettext("Sync All"),
        enabled = true,
        hold_callback = function()
          utils.show_msg(sync_all_description)
        end,
        callback = function()
          self.manager:syncAllChangedDocuments()
        end,
        separator = true,
      },
      {
        text = gettext("Scan library for unsynced annotations"),
        enabled = true,
        callback = function()
          UIManager:show(ConfirmBox:new({
            text = gettext(
              "Scan your library for existing annotations and add them to the pending sync list?\n\nNote: This may take a long time depending on your library size."
            ),
            ok_text = gettext("Scan now"),
            cancel_text = gettext("Cancel"),
            ok_callback = function()
              utils.show_msg(gettext("Scanning library for annotations..."))
              UIManager:scheduleIn(0.1, function()
                utils.show_msg(
                  T(
                    gettext(
                      "Scan complete: added %1 books with annotations to sync list."
                    ),
                    self.manager:scanLibraryForUnsyncedDocuments()
                  )
                )
              end)
            end,
          }))
        end,
      },
      {
        text = gettext("Show pending/unsynced documents"),
        enabled = true,
        callback = function()
          menus.show_pending_documents(self)
        end,
      },
      {
        text = gettext("Show Deleted"),
        enabled = ((self.ui and self.ui.document) ~= nil),
        callback = function()
          self:showDeletedAnnotations()
        end,
        separator = true,
      },
      {
        enabled = false,
        text_func = function()
          return T(gettext("Last sync: %1"), self.settings.last_sync)
        end,
      },
      {
        text = T(gettext("Plugin version: %1"), self.version),
        keep_menu_open = true,
        callback = function()
          UIManager:show(InfoMessage:new({
            text = T(
              gettext("%1 (%4)\nVersion: %2\n\n%3"),
              self.fullname,
              self.version,
              self.description,
              self.plugin_id
            ),
          }))
        end,
      },
    },
  }
end

function AnnotationSyncPlugin:onTimesChange_1M()
  if
    self.settings.network_auto_sync
    and isConnected()
    and self.manager
    and self.manager:hasPendingChangedDocuments()
  then
    logger.dbg("AnnotationSync: onTimesChange_1M triggered background sync")
    self.manager:_syncPendingDocumentsBg()
  end
end

function AnnotationSyncPlugin:applySyncedAnnotations(document, merged_list)
  if self.ui and self.ui.annotation and self.ui.document == document then
    -- 1. Sort for UI consistency
    table.sort(merged_list, function(a, b)
      local cmp = annotations.compare_positions(a.page, b.page, document)
      return (cmp or 0) > 0
    end)
    -- 2. Update active widget state
    self.ui.annotation.annotations = merged_list
    self.ui.annotation:onSaveSettings()

    -- 3. Notify system
    if #merged_list > 0 then
      UIManager:broadcastEvent(Event:new("AnnotationsModified", merged_list))
    end

    -- 4. Trigger Refreshes
    if not document.is_pdf then
      document:render()
      self.ui.view:recalculate()
      UIManager:setDirty(self.ui.view.dialog, "partial")
    end
  else
    -- Update sidecar directly for inactive document
    local annotation_sidecar = docsettings:open(document.file)
    annotation_sidecar:save("annotations", merged_list)
    annotation_sidecar:flush()
  end
end

function AnnotationSyncPlugin:onAnnotationSyncSyncAll()
  self.manager:syncAllChangedDocuments()
  return true
end

function AnnotationSyncPlugin:onAnnotationSyncManualSync()
  self:manualSync()
  return true
end

function AnnotationSyncPlugin:onAnnotationSyncPushSettings()
  self.manager:pushSettings()
  return true
end

function AnnotationSyncPlugin:onAnnotationSyncPullSettings()
  self.manager:pullSettings()
  return true
end

function AnnotationSyncPlugin:onDispatcherRegisterActions()
  Dispatcher:registerAction("annotation_sync_manual_sync", {
    category = "none",
    event = "AnnotationSyncManualSync",
    title = gettext("AnnotationSync: Manual Sync"),
    text = gettext(manual_sync_description),
    separator = true,
    reader = true,
  })
  Dispatcher:registerAction("annotation_sync_push_settings", {
    category = "none",
    event = "AnnotationSyncPushSettings",
    title = gettext("AnnotationSync: Push settings to cloud"),
    text = gettext("Push the selected settings to the cloud."),
    separator = true,
    general = true,
  })
  Dispatcher:registerAction("annotation_sync_pull_settings", {
    category = "none",
    event = "AnnotationSyncPullSettings",
    title = gettext("AnnotationSync: Pull settings from cloud"),
    text = gettext("Pull the selected settings from the cloud."),
    separator = true,
    general = true,
  })
  Dispatcher:registerAction("annotation_sync_sync_all", {
    category = "none",
    event = "AnnotationSyncSyncAll",
    title = gettext("AnnotationSync: Sync All"),
    text = gettext(sync_all_description),
    separator = true,
    general = true,
  })
end

function AnnotationSyncPlugin:onSyncServiceConfirm(server)
  self.settings.sync_server = server
  self:saveSettings()

  -- Keep G_reader_settings updated for legacy compatibility and menu enablement
  G_reader_settings:save("cloud_server_object", json.encode(server))
  G_reader_settings:save("cloud_download_dir", server.url)
  if server.type then
    G_reader_settings:save("cloud_provider_type", server.type)
  end

  UIManager:show(InfoMessage:new({
    text = T(
      gettext("Cloud destination set to:\n%1\nProvider: %2"),
      server.url,
      server.type or "unknown"
    ),
    timeout = 4,
  }))
  if self and self.ui and self.ui.menu and self.ui.menu.showMainMenu then
    self.ui.menu:showMainMenu()
  end
end

function AnnotationSyncPlugin:manualSync()
  local document = self.ui and self.ui.document
  local file = document and document.file
  if not file then
    utils.show_msg("A document must be active to do a manual sync.")
    return
  end
  self.manager:syncDocument(document, true)
  self.manager:updateLastSync("Manual Sync")
end

function AnnotationSyncPlugin:showDeletedAnnotations()
  local document = self.ui and self.ui.document
  if not document then
    return
  end
  menus.show_deleted_annotations(self, document)
end

function AnnotationSyncPlugin:restoreAnnotations(anns, silent)
  local document = self.ui and self.ui.document
  if not document or not anns or #anns == 0 then
    return
  end

  local now = os.date("%Y-%m-%d %H:%M:%S")
  local current = self.manager:getAnnotationsForDocument(document)

  for __, ann in ipairs(anns) do
    -- 1. Mark as not deleted and update timestamp
    ann.deleted = false
    ann.datetime_updated = now

    -- 2. Add back to current list
    table.insert(current, ann)
  end

  -- 3. Apply changes once (saves to sidecar and refreshes UI)
  self:applySyncedAnnotations(document, current)

  -- 4. Flush to local sync JSON immediately (Fix for Issue #39 delayed flush)
  self.manager:_writeAnnotationsJSON(document)

  if not silent then
    if #anns == 1 then
      utils.show_msg(gettext("Annotation restored."))
    else
      utils.show_msg(T(gettext("Restored %1 annotations."), #anns))
    end
  end
end

function AnnotationSyncPlugin:restoreAnnotation(ann, silent)
  self:restoreAnnotations({ ann }, silent)
end

function AnnotationSyncPlugin:onAnnotationsModified(modified_annotations)
  if not modified_annotations and type(modified_annotations) == "table" then
    logger.warn(
      "AnnotationSync: Document annotations modification detected, but could not process provided annotations payload (of type:",
      type(modified_annotations),
      ")"
    )
    return
  end

  -- only want to handle each changed file once, so let's keep track
  local changed_files = {}
  local unknown_file = "unknown_file"

  -- find changed files for payload annotations
  for __, annotation in ipairs(modified_annotations) do
    local changed_file = annotation.book_path
    -- AnnotationsModified event payload does not include book_path for an active document
    if not changed_file then
      changed_file = self.ui and self.ui.document and self.ui.document.file
    end
    if not changed_file then
      changed_file = unknown_file
    end
    local count = changed_files[changed_file]
    changed_files[changed_file] = (count and count + 1) or 1
  end

  -- handle changed files
  for changed_file, changes in pairs(changed_files) do
    if changed_file == unknown_file then
      if changes > 0 then
        logger.warn(
          "AnnotationSync: Document annotations modification detected, but could not determine file for",
          changes,
          "annotations"
        )
      end
    else
      logger.dbg(
        "AnnotationSync:",
        changes,
        "Document annotations modified:",
        changed_file
      )
      self.manager:addToChangedDocumentsFile(changed_file)
    end
  end
end

function AnnotationSyncPlugin:showChangedSettings()
  SettingsSelection.show(self)
end

return AnnotationSyncPlugin
