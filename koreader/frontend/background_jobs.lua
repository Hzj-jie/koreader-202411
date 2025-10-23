--[[--
Helper to manage background jobs.
--]]

BackgroundJobs = {}

function BackgroundJobs.insert(job)
  local jobs = require("pluginshare").backgroundJobs
  -- Do not require modules until it's really necessary.
  -- Note, the BackgroundJobs may be required before other modules.

  --[[
  -- Preserve for further debugging.
  -- Slightly perf optimization to avoid dumping job unnecessarily.
  if G_defaults:isTrue("DEV_MODE") then
    require("logger").info(
      "new background job ",
      require("dump")(job),
      ", in total ",
      #jobs + 1,
      " at ",
      debug.traceback()
    )
  end
  --]]
  table.insert(jobs, job)
  -- Raises an event to avoid depending on BackgroundRunner plugin directly.
  require("ui/uimanager"):broadcastEvent("BackgroundJobsUpdated")
end

BackgroundJobs.insert({
  when = 60,
  repeated = true,
  executable = function()
    require("ui/uimanager"):broadcastEvent("TimesChange_1M")
  end,
})

return BackgroundJobs
