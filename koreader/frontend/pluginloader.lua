local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local DEFAULT_PLUGIN_PATH = "plugins"

-- plugin names that were removed and are no longer available.
local OBSOLETE_PLUGINS = {
  calibrecompanion = true,
  evernote = true,
  goodreads = true,
  kobolight = true,
  send2ebook = true,
  storagestat = true,
  zsync = true,
}

local INVISIBLE_PLUGINS = {
  backgroundrunner = true,
}

local PluginLoader = {
  show_info = true,
  enabled_plugins = nil,
  disabled_plugins = nil,
  all_plugins = nil,
}

function PluginLoader:loadPlugins()
  if self.enabled_plugins then
    return self.enabled_plugins, self.disabled_plugins
  end

  self.enabled_plugins = {}
  self.disabled_plugins = {}
  local lookup_path_list = { DEFAULT_PLUGIN_PATH }
  local data_dir = require("datastorage"):getDataDir()
  if data_dir ~= "." then
    local p = data_dir .. "/plugins/"
    if not util.arrayContains(lookup_path_list, p) then
      table.insert(lookup_path_list, p)
    end
  end
  local extra_paths = G_reader_settings:read("extra_plugin_paths")
  if extra_paths then
    if type(extra_paths) == "string" then
      extra_paths = { extra_paths }
    end
    if type(extra_paths) == "table" then
      for _, extra_path in ipairs(extra_paths) do
        if
          lfs.attributes(extra_path, "mode") == "directory"
          and not util.arrayContains(lookup_path_list, extra_path)
        then
          table.insert(lookup_path_list, extra_path)
        end
      end
    else
      logger.err("extra_plugin_paths config only accepts string or table value")
    end
  end

  local plugins_disabled = G_reader_settings:readTableRef("plugins_disabled")
  for entry in pairs(INVISIBLE_PLUGINS) do
    plugins_disabled[entry] = false
  end
  for _, lookup_path in ipairs(lookup_path_list) do
    logger.info("Loading plugins from directory:", lookup_path)
    for entry in lfs.dir(lookup_path) do
      local plugin_root = lookup_path .. "/" .. entry
      local mode = lfs.attributes(plugin_root, "mode")
      local plugin_name = entry:sub(1, -10)
      -- valid koreader plugin directory
      if
        mode == "directory"
        and entry:find(".+%.koplugin$")
        and not OBSOLETE_PLUGINS[plugin_name]
      then
        local mainfile = plugin_root .. "/main.lua"
        local metafile = plugin_root .. "/_meta.lua"
        local main_exists = lfs.attributes(mainfile, "mode") == "file"
        local meta_exists = lfs.attributes(metafile, "mode") == "file"
        if plugins_disabled[plugin_name] == nil then
          local readme = plugin_root .. "/README.koreader-202411.md"
          if lfs.attributes(readme, "mode") == "file" then
            plugins_disabled[plugin_name] = true
          end
        end
        if meta_exists and (plugins_disabled[plugin_name] or main_exists) then
          if plugins_disabled[plugin_name] then
            mainfile = metafile
          end

          local plugin_module = dofile(mainfile)
          assert(plugin_module ~= nil)
          assert(
            plugin_module.disabled == nil
              or type(plugin_module.disabled) == "boolean"
          )
          if not plugin_module.disabled then
            plugin_module.path = plugin_root
            plugin_module.name = plugin_module.name
              or plugin_root:match("/(.-)%.koplugin")
            if plugins_disabled[plugin_name] then
              table.insert(self.disabled_plugins, plugin_module)
            else
              local plugin_metamodule = dofile(metafile)
              assert(plugin_metamodule)
              for k, v in pairs(plugin_metamodule) do
                plugin_module[k] = v
              end
              table.insert(self.enabled_plugins, plugin_module)
            end
          else
            logger.dbg("Plugin", mainfile, "has been disabled.")
          end
        else
          logger.warn(
            "Plugin directory",
            entry,
            "is missing required files (main.lua or _meta.lua), skipping."
          )
        end
      end
    end
  end

  table.sort(self.enabled_plugins, function(v1, v2)
    return v1.path < v2.path
  end)

  return self.enabled_plugins, self.disabled_plugins
end

function PluginLoader:_addPluginsToMenu(plugins, enable)
  for _, plugin in ipairs(plugins) do
    table.insert(self.all_plugins, {
      name = plugin.name,
      fullname = plugin.fullname or plugin.name,
      description = plugin.description,
      enable = enable,
    })
  end
end

function PluginLoader:genPluginManagerSubItem()
  if not self.all_plugins then
    local enabled_plugins, disabled_plugins = self:loadPlugins()
    self.all_plugins = {}

    self:_addPluginsToMenu(enabled_plugins, true)
    self:_addPluginsToMenu(disabled_plugins, false)

    table.sort(self.all_plugins, function(v1, v2)
      return v1.fullname < v2.fullname
    end)
  end

  local plugin_table = {}
  for _, plugin in ipairs(self.all_plugins) do
    if not INVISIBLE_PLUGINS[plugin.name] then
      table.insert(plugin_table, {
        text = plugin.fullname,
        checked_func = function()
          return plugin.enable
        end,
        callback = function()
          local UIManager = require("ui/uimanager")
          local plugins_disabled =
            G_reader_settings:readTableRef("plugins_disabled")
          plugin.enable = not plugin.enable
          if plugin.enable then
            plugins_disabled[plugin.name] = false
          else
            plugins_disabled[plugin.name] = true
          end
          if self.show_info then
            self.show_info = false
            UIManager:askForRestart()
          end
        end,
        help_text = plugin.description,
      })
    end
  end
  return plugin_table
end

function PluginLoader:createPluginInstance(plugin, attr)
  return true, plugin:new(attr)
end

return PluginLoader
