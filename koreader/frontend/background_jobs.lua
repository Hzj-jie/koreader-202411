--[[--
Helper to manage background jobs.
--]]

BackgroundJobs = {}

function BackgroundJobs.insert(job)
  -- Do not require modules until it's really necessary.
  -- Note, the BackgroundJobs may be required before other modules.
  local Event = require("ui/event")
  local PluginShare = require("pluginshare")
  local UIManager = require("ui/uimanager")
  table.insert(PluginShare.backgroundJobs, job)
  -- Raises an event to avoid depending on BackgroundRunner plugin directly.
  UIManager:broadcastEvent(Event:new("BackgroundJobsUpdated"))
end

return BackgroundJobs
