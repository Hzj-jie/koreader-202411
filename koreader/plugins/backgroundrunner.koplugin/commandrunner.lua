local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local time = require("ui/time")

local MAX_JOBS = 10

local CommandRunner = {
  running_jobs = {},
}

function CommandRunner:_createEnvironmentFromTable(t)
  if t == nil then
    return ""
  end

  local r = ""
  for k, v in pairs(t) do
    r = r .. k .. "=" .. v .. " "
  end

  if string.len(r) > 0 then
    r = "export " .. r .. ";"
  end
  return r
end

function CommandRunner:_createEnvironment(job)
  local env_table = job and job.environment
  if type(env_table) == "table" then
    return self:_createEnvironmentFromTable(env_table)
  end
  if type(env_table) == "function" then
    local status, result = pcall(env_table)
    if status then
      return self:_createEnvironmentFromTable(result)
    end
  end
  return ""
end

function CommandRunner:canStart()
  return #self.running_jobs < MAX_JOBS
end

function CommandRunner:isJobSupported(job)
  if type(job.executable) ~= "string" then
    return false
  end
  if job.executable == "fork" and type(job.action) ~= "function" then
    return false
  end
  return true
end

function CommandRunner:start(job)
  assert(#self.running_jobs < MAX_JOBS, "CommandRunner limit reached")
  assert(type(job.executable) == "string")
  job.start_time = time.monotonic()

  local entry
  if job.executable == "fork" then
    assert(
      type(job.action) == "function",
      "CommandRunner fork mode requires job.action function"
    )
    local pid, parent_read_fd = ffiUtil.runInSubProcess(
      function(_pid, child_write_fd)
        local res = false
        local ok, ret = pcall(job.action)
        if ok then
          res = ret
        end
        -- TODO: Implement timeout in "fork" mode.
        local output = string.format(
          "return { result = %s, timeout = false }\n",
          tostring(res)
        )
        ffiUtil.writeToFD(child_write_fd, output, true)
      end,
      true
    )

    entry = {
      job = job,
      poll = function(self)
        return (ffiUtil.getNonBlockingReadSize(parent_read_fd) or 0) > 0
          or ffiUtil.isSubProcessDone(pid)
      end,
      readAll = function(self)
        return ffiUtil.readAllFromFD(parent_read_fd) or ""
      end,
      close = function(self)
        ffiUtil.isSubProcessDone(pid, true)
      end,
    }
  else
    local command = self:_createEnvironment(job)
      .. " "
      .. "sh plugins/backgroundrunner.koplugin/luawrapper.sh "
      .. '"'
      .. job.executable
      .. '"'
    logger.dbg("CommandRunner: Will execute command " .. command)
    local pio = io.popen(command)

    entry = {
      job = job,
      poll = function(self)
        return (ffiUtil.getNonBlockingReadSize(pio) or 0) > 0
      end,
      readAll = function(self)
        return pio:read("*a") or ""
      end,
      close = function(self)
        pio:close()
      end,
    }
  end

  if #self.running_jobs == 0 then
    UIManager:preventStandby()
  end
  table.insert(self.running_jobs, entry)
end

--- Polls the status of running jobs in self.running_jobs.
-- @return a table of completed jobs, or nil if no jobs completed.
function CommandRunner:poll()
  if #self.running_jobs == 0 then
    return nil
  end

  local completed = {}
  local i = 1
  while i <= #self.running_jobs do
    local entry = self.running_jobs[i]
    if entry:poll() then
      local output = entry:readAll()
      logger.dbg("CommandRunner: Receive output " .. output)
      local status, result = pcall(loadstring(output))
      if status and result ~= nil then
        for k, v in pairs(result) do
          entry.job[k] = v
        end
      else
        entry.job.result = 222
      end
      entry:close()
      entry.job.end_time = time.monotonic()
      table.insert(completed, entry.job)
      table.remove(self.running_jobs, i)
    else
      i = i + 1
    end
  end

  if #self.running_jobs == 0 then
    UIManager:allowStandby()
  end

  return #completed > 0 and completed or nil
end

--- Whether there are running jobs.
-- @treturn boolean
function CommandRunner:pending()
  return #self.running_jobs > 0
end

return CommandRunner
