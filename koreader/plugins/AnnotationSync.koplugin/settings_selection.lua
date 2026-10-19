local DataStorage = require("datastorage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local gettext = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local utils = require("plugins/AnnotationSync.koplugin/utils")
local SettingsSelection = {}

local excluded = {
    -- Global reader settings (settings.reader.lua)
    ["reader:device_id"] = true,
    ["reader:device_name"] = true,
    ["reader:lastfile"] = true,
    ["reader:home_dir"] = true,
    ["reader:fontmap"] = true,
    ["reader:color_rendering"] = true,
    ["reader:folder_shortcuts_settings"] = true,
    ["reader:cloud_server_object"] = true,
    ["reader:cloud_download_dir"] = true,
    ["reader:cloud_provider_type"] = true,
    ["reader:dict_presets"] = true,
    ["reader:dicts_disabled"] = true,
    ["reader:dicts_order"] = true,
    ["reader:input_ignore_gsensor"] = true,
    ["reader:input_lock_gsensor"] = true,
    ["reader:input_invert_page_turn_keys"] = true,
    ["reader:input_invert_left_page_turn_keys"] = true,
    ["reader:input_invert_right_page_turn_keys"] = true,
    ["reader:timezone"] = true,
    ["reader:annotation_sync_plugin"] = true,
    ["reader:sdl_window"] = true,

    -- Expanded Font and Path settings exclusions:
    ["reader:cre_font_family_fonts"] = true,
    ["reader:cre_fonts_recently_selected"] = true,
    ["reader:cover_image_cache_path"] = true,
    ["reader:cover_image_fallback_path"] = true,
    ["reader:document_metadata_folder"] = true,

    -- Plugin settings / databases / logs
    ["settings/cloudstorage"] = true,
    ["settings/battery_stats"] = true,
    ["settings/profiles"] = true,
    ["settings/terminal"] = true,
    ["settings/bookinfo_cache"] = true,
    ["settings/statistics"] = true,
    ["settings/vocabulary_builder"] = true,
  }

local function is_array(t)
  if type(t) ~= "table" then
    return false
  end
  local count = 0
  for __ in pairs(t) do
    count = count + 1
  end
  for i = 1, count do
    if t[i] == nil then
      return false
    end
  end
  return count > 0
end

local function format_val(val)
  if val == nil then
    return "nil"
  elseif type(val) == "boolean" then
    return val and "true" or "false"
  elseif type(val) == "table" then
    if next(val) == nil or is_array(val) then
      local parts = {}
      for _, v in ipairs(val) do
        table.insert(parts, format_val(v))
      end
      return "[" .. table.concat(parts, ", ") .. "]"
    else
      return "{dictionary}"
    end
  else
    return tostring(val)
  end
end

local function is_excluded(domain, path)
  if excluded[domain .. ":" .. utils.join_setting_path(path)] then
    return true
  end
  return false
end

local function build_diff_tree(domain, vanilla, active, path, parent_node)
  if is_excluded(domain, path) then
    return
  end

  local v_is_table = type(vanilla) == "table"
  local a_is_table = type(active) == "table"

  -- Case 1: Both are primitive values
  if not v_is_table and not a_is_table then
    if vanilla ~= active then
      table.insert(parent_node.children, {
        type = "leaf",
        domain = domain,
        key = path[#path],
        full_key = table.concat(path, "."),
        setting_id = domain .. ":" .. utils.join_setting_path(path),
        vanilla = format_val(vanilla),
        active = format_val(active),
      })
    end
    return
  end

  -- Case 2: One is a table and the other is not
  if v_is_table ~= a_is_table then
    if not a_is_table or is_array(active) then
      table.insert(parent_node.children, {
        type = "leaf",
        domain = domain,
        key = path[#path],
        full_key = table.concat(path, "."),
        setting_id = domain .. ":" .. utils.join_setting_path(path),
        vanilla = format_val(vanilla),
        active = format_val(active),
      })
    else
      local branch = {
        type = "branch",
        domain = domain,
        key = path[#path],
        full_key = table.concat(path, "."),
        children = {},
      }
      for k, v in pairs(active) do
        table.insert(path, k)
        build_diff_tree(domain, nil, v, path, branch)
        table.remove(path)
      end
      if #branch.children > 0 then
        table.insert(parent_node.children, branch)
      end
    end
    return
  end

  -- Case 3: Both are tables
  if is_array(vanilla) or is_array(active) then
    local v_str = format_val(vanilla)
    local a_str = format_val(active)
    if v_str ~= a_str then
      table.insert(parent_node.children, {
        type = "leaf",
        domain = domain,
        key = path[#path],
        full_key = table.concat(path, "."),
        setting_id = domain .. ":" .. utils.join_setting_path(path),
        vanilla = v_str,
        active = a_str,
      })
    end
    return
  end

  -- Both are dictionaries
  if next(active) == nil and next(vanilla) ~= nil then
    table.insert(parent_node.children, {
      type = "leaf",
      domain = domain,
      key = path[#path],
      full_key = table.concat(path, "."),
      setting_id = domain .. ":" .. utils.join_setting_path(path),
      vanilla = "{dictionary}",
      active = "{}",
    })
    return
  end

  local branch = {
    type = "branch",
    domain = domain,
    key = path[#path],
    full_key = table.concat(path, "."),
    children = {},
  }

  for k, v in pairs(active) do
    table.insert(path, k)
    build_diff_tree(domain, vanilla[k], v, path, branch)
    table.remove(path)
  end

  if #branch.children > 0 then
    table.insert(parent_node.children, branch)
  end
end

local function compare_settings_file(
  domain,
  vanilla_path,
  active_path,
  parent_node
)
  local ok_v, vanilla_tbl = pcall(dofile, vanilla_path)
  local ok_a, active_tbl = pcall(dofile, active_path)

  if not ok_a or type(active_tbl) ~= "table" then
    return
  end
  for k, v in pairs(active_tbl) do
    build_diff_tree(
      domain,
      ok_v and vanilla_tbl and vanilla_tbl[k],
      v,
      { k },
      parent_node
    )
  end
end

local function get_all_leaf_keys(n, keys)
  keys = keys or {}
  for __, child in ipairs(n.children) do
    if child.type == "branch" then
      get_all_leaf_keys(child, keys)
    else
      table.insert(keys, child.setting_id)
    end
  end
  return keys
end

function SettingsSelection.build_tree(plugin)
  local root = {
    type = "branch",
    children = {},
  }

  -- 1. Compare settings.reader.lua
  G_reader_settings:flush()
  compare_settings_file(
    "reader",
    plugin.path .. "/defaults/settings.reader.lua",
    DataStorage:getDataDir() .. "/settings.reader.lua",
    root
  )

  -- 2. Compare defaults.custom.lua
  G_defaults:flush()
  compare_settings_file(
    "defaults",
    plugin.path .. "/defaults/defaults.custom.lua",
    DataStorage:getDataDir() .. "/defaults.custom.lua",
    root
  )

  -- 3. Compare files in settings/ directory
  local vanilla_settings_dir = plugin.path .. "/defaults/settings"
  local active_settings_dir = DataStorage:getSettingsDir()
  if lfs.attributes(vanilla_settings_dir, "mode") == "directory" then
    for entry in lfs.dir(vanilla_settings_dir) do
      if entry ~= "." and entry ~= ".." then
        local filepath = vanilla_settings_dir .. "/" .. entry
        if lfs.attributes(filepath, "mode") == "file" and entry:match("%.lua$") then
          local name = entry:gsub("%.lua$", "")
          local domain = "settings/" .. name
          if not excluded[domain] then
            local file_branch = {
              type = "branch",
              domain = domain,
              key = name,
              full_key = name,
              children = {},
            }

            compare_settings_file(
              domain,
              filepath,
              active_settings_dir .. "/" .. entry,
              file_branch
            )

            if #file_branch.children > 0 then
              table.insert(root.children, file_branch)
            end
          end
        end
      end
    end
  end

  return root
end

function SettingsSelection.prune_selected_settings(plugin, root)
  root = root or SettingsSelection.build_tree(plugin)
  local valid_keys = {}
  for _, key in ipairs(get_all_leaf_keys(root)) do
    valid_keys[key] = true
  end

  local selected = plugin.settings.selected_settings

  local pruned = false
  for key in pairs(selected) do
    if not valid_keys[key] then
      selected[key] = nil
      pruned = true
    end
  end

  if pruned then
    plugin:saveSettings()
  end
end

local function show_node_menu(node, title, plugin, parent_refresh)
  assert(parent_refresh)
  local menu_items = {}
  local submenu

  table.sort(node.children, function(a, b)
    if a.type ~= b.type then
      return a.type == "branch"
    end
    return a.key < b.key
  end)

  if #node.children > 0 then
    table.insert(menu_items, {
      text = gettext("Select All"),
      keep_menu_open = true,
      callback = function()
        for __, key in ipairs(get_all_leaf_keys(node)) do
          plugin.settings.selected_settings[key] = true
        end
        plugin:saveSettings()
        submenu:updateItems()
        parent_refresh()
      end,
    })
    table.insert(menu_items, {
      text = gettext("Clear Selection"),
      keep_menu_open = true,
      callback = function()
        for __, key in ipairs(get_all_leaf_keys(node)) do
          plugin.settings.selected_settings[key] = nil
        end
        plugin:saveSettings()
        submenu:updateItems()
        parent_refresh()
      end,
      separator = true,
    })
  end

  for __, child in ipairs(node.children) do
    if child.type == "branch" then
      table.insert(menu_items, {
        text_func = function()
          local any_selected = false
          for ___, key in ipairs(get_all_leaf_keys(child)) do
            if plugin.settings.selected_settings[key] then
              any_selected = true
              break
            end
          end
          return string.format(
            "%s[%s] %s >",
            any_selected and "[✓] " or "[ ] ",
            child.domain,
            child.full_key
          )
        end,
        keep_menu_open = true,
        callback = function()
          show_node_menu(child, child.full_key, plugin, function()
            submenu:updateItems()
            parent_refresh()
          end)
        end,
      })
    else
      local setting_id = child.setting_id
      table.insert(menu_items, {
        text_func = function()
          return string.format(
            "%s[%s] %s: %s -> %s",
            plugin.settings.selected_settings[setting_id] and "[✓] " or "[ ] ",
            child.domain,
            child.full_key,
            child.vanilla,
            child.active
          )
        end,
        keep_menu_open = true,
        callback = function()
          plugin.settings.selected_settings[setting_id] = not plugin.settings.selected_settings[setting_id]
            or nil
          plugin:saveSettings()
          local idx = 1
          for i, item in ipairs(menu_items) do
            if item.setting_id == setting_id then
              idx = i
              break
            end
          end
          submenu:updateItems(idx - (submenu.page - 1) * submenu.perpage, true)
          parent_refresh()
        end,
        setting_id = setting_id,
      })
    end
  end

  if #menu_items == 0 then
    table.insert(menu_items, {
      text = gettext("No changed settings found."),
      enabled = false,
    })
  end

  submenu = Menu:new({
    title = title,
    item_table = menu_items,
  })
  UIManager:show(submenu)
end

function SettingsSelection.show(plugin)
  local root = SettingsSelection.build_tree(plugin)
  SettingsSelection.prune_selected_settings(plugin, root)
  show_node_menu(root, gettext("Changed Settings"), plugin, function() end)
end

return SettingsSelection
