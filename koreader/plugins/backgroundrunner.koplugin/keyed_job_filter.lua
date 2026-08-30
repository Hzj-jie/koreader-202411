local BackgroundJobs = require("background_jobs")
local logger = require("logger")
local util = require("util")

local KeyedJobFilter = {
  active_keys = {},
}

function KeyedJobFilter:hasKey(key)
  return self.active_keys[key] == true
end

function KeyedJobFilter:insert(job)
  if not job then
    return false
  end

  local key = job.key
  if key == nil then
    if type(job.action) == "function" then
      key = util.functionFingerprint(job.action)
    elseif type(job.executable) == "function" then
      key = util.functionFingerprint(job.executable)
    end
  end

  if not key then
    BackgroundJobs.insert(job)
    return true
  end

  if self.active_keys[key] then
    logger.dbg("KeyedJobFilter: filtered out duplicate job with key:", key)
    return false
  end

  self.active_keys[key] = true

  local orig_callback = job.callback
  job.callback = function(res_job)
    self.active_keys[key] = nil
    if orig_callback then
      orig_callback(res_job)
    end
  end

  BackgroundJobs.insert(job)
  return true
end

if util.isTesting() then
  function KeyedJobFilter:clear()
    self.active_keys = {}
  end
end

return KeyedJobFilter
