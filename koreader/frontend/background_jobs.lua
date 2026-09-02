--[[--
Helper to manage background jobs.
--]]

local BackgroundJobs = {}
local _active_keys = {}

-- For testing purposes only.
function BackgroundJobs.hasKey(key)
  return _active_keys[key] == true
end

-- For testing purposes only.
function BackgroundJobs.clearKeys()
  _active_keys = {}
end

local function calculateKey(job)
  local util = require("util")
  if job.executable == "fork" then
    if type(job.action) == "function" then
      return util.functionFingerprint(job.action)
    end
    return nil
  end
  if type(job.executable) == "string" then
    return job.executable
  end
  if type(job.executable) == "function" then
    return util.functionFingerprint(job.executable)
  end
  return nil
end

function BackgroundJobs.insertKeyed(job)
  assert(type(job) == "table", "BackgroundJobs.insertKeyed expects a table")
  assert(job.key == nil, "BackgroundJobs.insertKeyed does not support custom key")
  assert(job.repeated == nil, "BackgroundJobs.insertKeyed does not support repeated jobs")
  assert(job.when == nil, "BackgroundJobs.insertKeyed does not support custom when")

  job.when = "asap"

  local key = calculateKey(job)
  assert(type(key) == "string", "BackgroundJobs.insertKeyed expects a valid key")

  if _active_keys[key] then
    require("logger").dbg("BackgroundJobs: filtered duplicate job with key:", key)
    return false
  end

  _active_keys[key] = true

  local orig_callback = job.callback
  job.callback = function(res_job)
    _active_keys[key] = nil
    if orig_callback then
      orig_callback(res_job)
    end
  end

  BackgroundJobs.insert(job)
  return true
end

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

BackgroundJobs.insert({
  when = 300,
  repeated = true,
  executable = function()
    require("ui/uimanager"):broadcastEvent("TimesChange_5M")
  end,
})

BackgroundJobs.insert({
  when = 900,
  repeated = true,
  executable = function()
    require("ui/uimanager"):broadcastEvent("TimesChange_15M")
  end,
})

return BackgroundJobs
