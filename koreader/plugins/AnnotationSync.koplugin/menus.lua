local ConfirmBox = require("ui/widget/confirmbox")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local gettext = require("gettext")
local T = require("ffi/util").template
local util = require("util")
local utils = require("plugins/AnnotationSync.koplugin/utils")

local M = {}

function M.show_deleted_annotations(plugin, document)
  local deleted = plugin.manager:getDeletedAnnotations(document)
  if #deleted == 0 then
    utils.show_msg(gettext("No deleted annotations found for this document."))
    return
  end

  local deleted_menu
  local function menu_items()
    local items = {}

    -- Add Restore All button at the top
    table.insert(items, {
      text = gettext("Restore All"),
      bold = true,
      keep_menu_open = true,
      callback = function()
        UIManager:show(ConfirmBox:new({
          text = T(
            gettext(
              "Are you sure you want to restore all %1 deleted annotations?"
            ),
            #deleted
          ),
          ok_text = gettext("Restore All"),
          ok_callback = function()
            plugin:restoreAnnotations(deleted, true) -- true = silent
            utils.show_msg(T(gettext("Restored %1 annotations."), #deleted))
            UIManager:close(deleted_menu)
          end,
        }))
      end,
      separator = true,
    })

    for i, ann in ipairs(deleted) do
      local text = ann.text or ann.note or gettext("Highlight")
      if text == "" then
        text = gettext("Highlight")
      end
      -- Truncate long text
      if #text > 50 then
        text = text:sub(1, 47) .. "..."
      end
      table.insert(items, {
        text = text,
        keep_menu_open = true,
        callback = function()
          UIManager:show(ConfirmBox:new({
            text = T(
              gettext("Do you want to restore this annotation?\n\nPage %1: %2"),
              ann.page,
              ann.text or ann.note or ""
            ),
            ok_text = gettext("Restore"),
            cancel_text = gettext("Close"),
            ok_callback = function()
              plugin:restoreAnnotation(ann)
              table.remove(deleted, i)
              if #deleted == 0 then
                UIManager:close(deleted_menu)
              else
                -- Item i + 1 follows the restored one (item 1 is Restore All),
                -- so the menu stays on the same page.
                deleted_menu:switchItemTable(nil, menu_items(), i + 1)
              end
            end,
          }))
        end,
      })
    end
    return items
  end

  deleted_menu = Menu:new({
    title = gettext("Deleted Annotations"),
    item_table = menu_items(),
  })
  UIManager:show(deleted_menu)
end

function M.show_devices_menu(plugin, settings_map)
  local menu_items = {}
  local devices_menu

  local current_device = plugin.manager:getDeviceName()

  -- Sort devices alphabetically by name
  local devices = {}
  for dev_id, data in pairs(settings_map) do
    if dev_id ~= current_device then
      table.insert(devices, { id = dev_id, data = data })
    end
  end
  table.sort(devices, function(a, b)
    return a.id < b.id
  end)

  for __, dev in ipairs(devices) do
    local timestamp = dev.data.timestamp or "unknown"
    local text = string.format("%s (%s)", dev.id, timestamp)
    table.insert(menu_items, {
      text = text,
      keep_menu_open = true,
      callback = function()
        M.show_differing_settings_menu(
          plugin,
          dev.id,
          dev.data.settings or {},
          devices_menu
        )
      end,
    })
  end

  if #menu_items == 0 then
    utils.show_msg(gettext("No other devices found in cloud settings."))
    return
  end

  devices_menu = Menu:new({
    title = gettext("Pull settings from cloud"),
    item_table = menu_items,
  })
  UIManager:show(devices_menu)
end

function M.show_differing_settings_menu(
  plugin,
  device_name,
  remote_settings,
  parent_menu
)
  local menu_items = {}
  local diff_menu

  -- Identify differing settings
  local differing = {}
  local caches = {}
  for key, r_val in pairs(remote_settings) do
    local l_val = plugin.manager:getLocalSettingValue(key, caches)
    if not util.tableEquals(l_val, r_val) then
      -- Format values for display
      local function format_val(val)
        if val == nil then
          return "nil"
        end
        if type(val) == "boolean" then
          return val and "true" or "false"
        end
        if type(val) == "table" then
          return "{...}"
        end
        return tostring(val)
      end
      table.insert(differing, {
        key = key,
        local_val_str = format_val(l_val),
        remote_val_str = format_val(r_val),
        remote_val = r_val,
      })
    end
  end

  -- Sort settings alphabetically by key
  table.sort(differing, function(a, b)
    return a.key < b.key
  end)

  if #differing == 0 then
    utils.show_msg(gettext("No differing settings found for this device."))
    return
  end

  -- Default all to checked
  local checked = {}
  for __, diff in ipairs(differing) do
    checked[diff.key] = true
  end

  -- Action item: Import Selected Settings
  table.insert(menu_items, {
    text = gettext("Import Selected Settings"),
    bold = true,
    keep_menu_open = true,
    callback = function()
      local count = 0
      for __, diff in ipairs(differing) do
        if checked[diff.key] then
          if
            plugin.manager:_writeLocalSettingValue(diff.key, diff.remote_val)
          then
            count = count + 1
          end
        end
      end
      if count > 0 then
        utils.show_msg(T(gettext("Successfully imported %1 settings."), count))
      else
        utils.show_msg(gettext("No settings imported."))
      end
      UIManager:close(diff_menu)
      if parent_menu then
        UIManager:close(parent_menu)
      end
    end,
  })

  table.insert(menu_items, {
    text = gettext("Select All"),
    keep_menu_open = true,
    callback = function()
      for __, diff in ipairs(differing) do
        checked[diff.key] = true
      end
      diff_menu:updateItems()
    end,
  })

  table.insert(menu_items, {
    text = gettext("Clear Selection"),
    keep_menu_open = true,
    callback = function()
      checked = {}
      diff_menu:updateItems()
    end,
    separator = true,
  })

  for __, diff in ipairs(differing) do
    local setting_id = diff.key
    local domain, full_key = setting_id:match("^([^:]+):(.*)$")
    table.insert(menu_items, {
      text_func = function()
        local is_checked = checked[setting_id]
        local prefix = is_checked and "[✓] " or "[ ] "
        return string.format(
          "%s[%s] %s: %s -> %s",
          prefix,
          domain or "unknown",
          full_key or setting_id,
          diff.local_val_str,
          diff.remote_val_str
        )
      end,
      keep_menu_open = true,
      callback = function()
        checked[setting_id] = not checked[setting_id]
        diff_menu:updateItems()
      end,
    })
  end

  diff_menu = Menu:new({
    title = T(gettext("Settings from %1"), device_name),
    item_table = menu_items,
  })
  UIManager:show(diff_menu)
end

function M.show_pending_documents(plugin)
  local total = plugin.manager:getPendingChangedDocuments()
  if total == 0 then
    utils.show_msg(gettext("No pending books."))
    return
  end

  local pending_menu
  local function menu_items()
    local _, changed_docs = plugin.manager:getPendingChangedDocuments()
    -- Sort the files alphabetically by their clean filename
    local files = {}
    for _, file in ipairs(changed_docs) do
      table.insert(files, file)
    end
    table.sort(files, function(a, b)
      local a_name = a:match("([^/]+)$") or a
      local b_name = b:match("([^/]+)$") or b
      return a_name:lower() < b_name:lower()
    end)

    local items = {}
    for i, file in ipairs(files) do
      local clean_filename = file:match("([^/]+)$") or file
      table.insert(items, {
        text = clean_filename,
        keep_menu_open = true,
        callback = function()
          UIManager:show(ConfirmBox:new({
            text = T(gettext("Sync this book now?\n\n%1"), clean_filename),
            ok_text = gettext("Sync"),
            cancel_text = gettext("Cancel"),
            ok_callback = function()
              plugin.manager:syncNow(file)
            end,
            other_buttons = {
              {
                {
                  text = gettext("Remove from list"),
                  callback = function()
                    plugin.manager:removeFromChangedDocumentsFileByPath(file)
                    utils.show_msg(
                      T(
                        gettext("Removed %1 from pending books."),
                        clean_filename
                      )
                    )
                    -- Item i is now the book after the removed one, so the
                    -- list stays on the same page.
                    pending_menu:switchItemTable(nil, menu_items(), i)
                  end,
                },
              },
            },
          }))
        end,
      })
    end
    return items
  end

  pending_menu = Menu:new({
    title = gettext("Pending books"),
    item_table = menu_items(),
  })
  UIManager:show(pending_menu)
end

return M
