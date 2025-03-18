--[[--
BackgroundTaskPlugin creates a plugin with a switch to enable or disable it and executes a
background task.
See spec/unit/background_task_plugin_spec.lua for the usage.
]]

local PluginShare = require("pluginshare")
local SwitchPlugin = require("ui/plugin/switch_plugin")

local BackgroundTaskPlugin = SwitchPlugin:extend()

function BackgroundTaskPlugin:_start()
  assert(self.enabled)

  local start_settings_id = self.settings_id
  local enabled = function()
    if not self.enabled then
      return false
    end
    if start_settings_id ~= self.settings_id then
      return false
    end

    return true
  end

  table.insert(PluginShare.backgroundJobs, {
    when = self.when,
    repeated = enabled,
    executable = self.executable,
  })
  require("background_jobs_updated")()
end

return BackgroundTaskPlugin
