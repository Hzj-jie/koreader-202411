local gettext = require("gettext")
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

local DEFAULT_DISABLED_PLUGINS = {
  AnnotationSync = true,
  checkers = true,
  game2048 = true,
  nonogram = true,
  slidepuzzle = true,
  sokoban = true,
  solitaire = true,
  sudoku = true,
}

local PluginLoader = {
  enabled_plugins = nil,
  disabled_plugins = nil,
  all_plugins = nil,
  plugins_disabled = nil,
  plugin_enabled = false,
  plugin_disabled = false,
}

function PluginLoader:pluginsDisabled()
  if not self.plugins_disabled then
    self.plugins_disabled = G_reader_settings:readTableRef("plugins_disabled")
  end
  return self.plugins_disabled
end

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

  for entry in pairs(INVISIBLE_PLUGINS) do
    self:pluginsDisabled()[entry] = false
  end
  for _, lookup_path in ipairs(lookup_path_list) do
    logger.info("Loading plugins from directory:", lookup_path)
    for entry in lfs.dir(lookup_path) do
      local plugin_root = lookup_path .. "/" .. entry
      local plugin_code_name = entry:sub(1, -10)
      -- valid koreader plugin directory
      if
        lfs.attributes(plugin_root, "mode") == "directory"
        and entry:find(".+%.koplugin$")
        and not OBSOLETE_PLUGINS[plugin_code_name]
      then
        local mainfile = plugin_root .. "/main.lua"
        local metafile = plugin_root .. "/_meta.lua"
        if self:pluginsDisabled()[plugin_code_name] == nil then
          if DEFAULT_DISABLED_PLUGINS[plugin_code_name] then
            self:pluginsDisabled()[plugin_code_name] = true
          end
        end
        local main_exists = lfs.attributes(mainfile, "mode") == "file"
        local meta_exists = lfs.attributes(metafile, "mode") == "file"

        if
          meta_exists
          and (self:pluginsDisabled()[plugin_code_name] or main_exists)
        then
          if self:pluginsDisabled()[plugin_code_name] then
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
            -- code_name: unique identifier matching the folder name (used for settings storage keys)
            -- name: internally-used Lua class/module name of the plugin instance
            plugin_module.code_name = plugin_code_name
            plugin_module.name = plugin_module.name or plugin_code_name
            if self:pluginsDisabled()[plugin_code_name] then
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
      code_name = plugin.code_name,
    })
  end
end

function PluginLoader:menuItem()
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
          plugin.enable = not plugin.enable
          local is_default_disabled = DEFAULT_DISABLED_PLUGINS[plugin.code_name]
          if plugin.enable then
            if is_default_disabled then
              self:pluginsDisabled()[plugin.code_name] = false
            else
              self:pluginsDisabled()[plugin.code_name] = nil
            end
            self.plugin_enabled = true
          else
            if is_default_disabled then
              self:pluginsDisabled()[plugin.code_name] = nil
            else
              self:pluginsDisabled()[plugin.code_name] = true
            end
            self.plugin_disabled = true
          end
        end,
        help_text = plugin.description,
      })
    end
  end

  return {
    text = gettext("Plugin management"),
    sub_item_table = plugin_table,
    onClose = function()
      if not self.plugin_enabled and not self.plugin_disabled then
        return
      end

      local msg
      if self.plugin_enabled and self.plugin_disabled then
        msg = gettext(
          "Newly enabled plugins may not work properly, and "
            .. "disabled plugins may still run in the background, until "
            .. "the current book is reloaded or KOReader is restarted. "
            .. "Do you want to restart now?"
        )
      elseif self.plugin_enabled then
        msg = gettext(
          "Newly enabled plugins may not work properly until "
            .. "the current book is reloaded or KOReader is restarted. "
            .. "Do you want to restart now?"
        )
      else
        msg = gettext(
          "Although disabled plugins are removed from the "
            .. "menu, they may still run in the background until the "
            .. "current book is reloaded or KOReader is restarted. "
            .. "Do you want to restart now?"
        )
      end

      self.plugin_enabled = false
      self.plugin_disabled = false
      require("ui/uimanager"):askForRestart(msg)
    end,
  }
end

return PluginLoader
