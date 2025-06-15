--[[--
Helper to manage background jobs.
--]]

BackgroundJobs = {}

function BackgroundJobs.insert(job)
  -- Do not require modules until it's really necessary.
  -- Note, the BackgroundJobs may be required before other modules.
  require("logger").info("new background job ", require("dump")(job))
  table.insert(require("pluginshare").backgroundJobs, job)
  -- Raises an event to avoid depending on BackgroundRunner plugin directly.
  require("ui/uimanager"):broadcastEvent(
      require("ui/event"):new("BackgroundJobsUpdated"))
end

return BackgroundJobs
