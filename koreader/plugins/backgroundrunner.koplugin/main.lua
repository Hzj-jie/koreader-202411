local Device = require("device")

-- disable on android, since it breaks expect behaviour of an activity.
-- it is also unused by other plugins.
-- See https://github.com/koreader/koreader/issues/6297
if Device:isAndroid() then
  return { disabled = true }
end

local CommandRunner = require("commandrunner")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")

-- BackgroundRunner is an experimental feature to execute non-critical jobs in
-- the background.
-- A job is defined as a table in PluginShare.backgroundJobs table.
-- It contains at least following items:
-- when: number, string or function
--   number: the delay in seconds
--   string: "best-effort" - the job will be started when there is no other jobs
--                           to be executed.
--           "idle"        - the job will be started when the device is idle.
--   function: if the return value of the function is true, the job will be
--             executed immediately.
--
-- repeated: boolean or function or nil or number
--   boolean: true to repeat the job once it finished.
--   function: if the return value of the function is true, repeat the job
--             once it finishes. If the function throws an error, it equals to
--             return false.
--   nil: same as false.
--   number: times to repeat.
--
-- executable: string or function
--   string: the command line to be executed. The command or binary will be
--           executed in the lowest priority. Command or binary will be killed
--           if it executes for over 1 hour.
--   function: the action to be executed. The execution cannot be killed, but it
--             will be considered as timeout if it executes for more than 1
--             second.
--   If the executable times out, the job will be blocked, i.e. the repeated
--   field will be ignored.
--
-- environment: table or function or nil
--   table: the key-value pairs of all environments set for string executable.
--   function: the function to return a table of environments.
--   nil: ignore.
--
-- callback: function or nil
--   function: the action to be executed when executable has been finished.
--             Errors thrown from this function will be ignored.
--   nil: ignore.
--
-- If a job does not contain enough information, it will be ignored.
--
-- Once the job is finished, several items will be added to the table:
-- result: number, the return value of the command. In general, 0 means
--         succeeded.
--         For function executable, 1 if the function throws an error.
--         For string executable, several predefined values indicate the
--         internal errors. E.g. 223: the binary crashes. 222: the output is
--         invalid. 127: the command is invalid. 255: the command timed out.
--         Typically, consumers can use following states instead of hardcodeing
--         the error codes.
-- exception: error, the error returned from function executable. Not available
--            for string executable.
-- timeout: boolean, whether the command times out.
-- bad_command: boolean, whether the command is not found. Not available for
--              function executable.
-- blocked: boolean, whether the job is blocked.
-- start_time: number, the time (fts) when the job was started.
-- end_time: number, the time (fts) when the job was stopped.
-- insert_time: number, the time (fts) when the job was inserted into queue.
-- (All of them in the monotonic time scale, like the main event loop & task
-- queue).
--
-- Since each time, the job table itself will be cloned, querying the results of
-- the inserted job may return inaccurate results, always use the parameter of
-- the callback function.

-- @return a string to represent the job for logging purpose.
local function _debugJobStr(job)
  return require("dump")(job)
end

local BackgroundRunner = {
  scheduled = false,
}

--- Copies required fields from |job|.
-- @return a new table with required fields of a valid job.
function BackgroundRunner:_clone(job)
  assert(job ~= nil)
  local result = {}
  result.when = job.when
  result.repeated = job.repeated
  result.executable = job.executable
  result.callback = job.callback
  result.environment = job.environment
  return result
end

function BackgroundRunner:_shouldRepeat(job)
  if type(job.repeated) == "nil" then
    return false
  end
  if type(job.repeated) == "boolean" then
    return job.repeated
  end
  if type(job.repeated) == "function" then
    local status, result = pcall(job.repeated)
    if status then
      return result
    end
    return false
  end
  if type(job.repeated) == "number" then
    job.repeated = job.repeated - 1
    return job.repeated > 0
  end

  return false
end

function BackgroundRunner:_finishJob(job)
  if type(job.executable) == "function" then
    local time_diff = job.end_time - job.start_time
    local threshold = time.s(1)
    if job.when == "best-effort" then
      threshold = threshold * 2
    elseif job.when == "idle" then
      threshold = threshold * 2
    end
    job.timeout = (time_diff > threshold)
  end
  job.blocked = job.timeout
  if job.blocked then
    logger.warn(
      "BackgroundRunner: job [",
      _debugJobStr(job),
      " will be blocked due to timeout @ ",
      os.time()
    )
  end
  if not job.blocked and self:_shouldRepeat(job) then
    self:_insert(self:_clone(job))
  end
  if type(job.callback) == "function" then
    pcall(job.callback, job)
  end
end

--- Executes |job|.
-- @treturn boolean true if job is valid.
function BackgroundRunner:_executeJob(job)
  assert(not CommandRunner:pending())
  if job == nil then
    return false
  end
  if job.executable == nil then
    return false
  end

  if type(job.executable) == "string" then
    CommandRunner:start(job)
    return true
  end
  if type(job.executable) == "function" then
    job.start_time = os.time()
    local status, err = pcall(job.executable)
    if status then
      job.result = 0
    else
      logger.warn(
        "BackgroundRunner: _executeJob [",
        _debugJobStr(job),
        "] failed, ",
        err
      )
      job.result = 1
      job.exception = err
    end
    job.end_time = time.now()
    self:_finishJob(job)
    return true
  end
  return false
end

--- Polls the status of the pending CommandRunner.
function BackgroundRunner:_poll()
  assert(CommandRunner:pending())
  local result = CommandRunner:poll()
  if result == nil then
    return
  end

  self:_finishJob(result)
end

function BackgroundRunner:_executeRound(round)
  assert(round == 0 or round == 1 or round == 2)
  local executed_jobs = 0
  -- Change of #PluginShare.backgroundJobs during the loop is very rare, make it
  -- simple.
  for _ = 1, #PluginShare.backgroundJobs do
    local job = table.remove(PluginShare.backgroundJobs, 1)
    if job.insert_time == nil then
      -- Jobs are first inserted to jobs table from external users.
      -- So they may not have an insert field.
      job.insert_time = os.time()
    end
    local should_execute = false
    local should_ignore = false
    if type(job.when) == "function" then
      if round == 0 then
        local status, result = pcall(job.when)
        if status then
          should_execute = result
        else
          should_ignore = true
        end
      end
    elseif type(job.when) == "number" then
      if round == 0 then
        if job.when >= 0 then
          should_execute = (os.time() - job.insert_time >= time.s(job.when))
        else
          should_ignore = true
        end
      end
    elseif type(job.when) == "string" then
      --- @todo (Hzj_jie): Implement "idle" mode
      if job.when == "best-effort" then
        should_execute = (round == 1)
      elseif job.when == "idle" then
        should_execute = (round == 2)
      else
        should_ignore = true
      end
    else
      should_ignore = true
    end

    if should_execute then
      logger.dbg(
        "BackgroundRunner: run job ",
        _debugJobStr(job),
        " @ ",
        os.time()
      )
      assert(not should_ignore)
      self:_executeJob(job)
      executed_jobs = executed_jobs + 1
    elseif not should_ignore then
      table.insert(PluginShare.backgroundJobs, job)
    end
  end
  return executed_jobs
end

function BackgroundRunner:_execute()
  logger.dbg("BackgroundRunner: _execute() @ ", os.time())
  -- The BackgroundRunner always needs to be rescheduled after running an
  -- _execute.
  self.scheduled = false
  if PluginShare.stopBackgroundRunner == true then
    logger.dbg("BackgroundRunnerWidget: skip running @ ", os.time())
    return
  end
  if CommandRunner:pending() then
    self:_poll()
  else
    -- round == 0, when is number
    --          1, when is 'best-effort'
    --          2, when is 'idle'
    for round = 0, 2 do
      if self:_executeRound(round) > 0 then
        break
      end
    end
  end

  self:_schedule()
end

function BackgroundRunner:_schedule()
  if self.scheduled == false then
    if #PluginShare.backgroundJobs == 0 and not CommandRunner:pending() then
      logger.dbg("BackgroundRunnerWidget: no job, not running @ ", os.time())
    else
      logger.dbg("BackgroundRunnerWidget: start running @ ", os.time())
      self.scheduled = true
      UIManager:scheduleIn(2, function()
        self:_execute()
      end)
    end
  else
    logger.dbg("BackgroundRunnerWidget: a schedule is pending @ ", os.time())
  end
end

function BackgroundRunner:_insert(job)
  job.insert_time = os.time()
  table.insert(PluginShare.backgroundJobs, job)
end

local BackgroundRunnerWidget = WidgetContainer:extend({
  name = "backgroundrunner",
})

function BackgroundRunnerWidget:init()
  BackgroundRunner:_schedule()
end

function BackgroundRunnerWidget:onSuspend()
  logger.dbg("BackgroundRunnerWidget:onSuspend() @ ", os.time())
  PluginShare.stopBackgroundRunner = true
end

function BackgroundRunnerWidget:onResume()
  logger.dbg("BackgroundRunnerWidget:onResume() @ ", os.time())
  PluginShare.stopBackgroundRunner = false
  BackgroundRunner:_schedule()
end

function BackgroundRunnerWidget:onBackgroundJobsUpdated()
  logger.dbg("BackgroundRunnerWidget:onBackgroundJobsUpdated() @ ", os.time())
  PluginShare.stopBackgroundRunner = false
  BackgroundRunner:_schedule()
end

return BackgroundRunnerWidget
