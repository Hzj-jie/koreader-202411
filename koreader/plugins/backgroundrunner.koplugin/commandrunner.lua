local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local time = require("ui/time")
require("ffi/posix_h")

local MAX_JOBS = 10
local FORK_TIMEOUT = 3600

local CommandRunner = {
  running_jobs = {},
}

function CommandRunner:canStart()
  return #self.running_jobs < MAX_JOBS
end

function CommandRunner:isJobSupported(job)
  return job.executable == "fork" and type(job.action) == "function"
end

function CommandRunner:start(job)
  assert(#self.running_jobs < MAX_JOBS, "CommandRunner limit reached")
  assert(self:isJobSupported(job))
  job.start_time = time.monotonic()

  local pid, parent_read_fd =
    assert(ffiUtil.runInSubProcess(function(_pid, child_write_fd)
      local res = false
      local ok, ret = pcall(job.action)
      if ok then
        res = ret
      else
        logger.warn("CommandRunner: fork action failed:", ret)
      end
      local output = string.format(
        "return { result = %s, timeout = false }\n",
        require("dump")(res)
      )
      ffiUtil.writeToFD(child_write_fd, output, true)
    end, true, job.action))

  if #self.running_jobs == 0 then
    UIManager:preventStandby()
  end
  table.insert(self.running_jobs, {
    job = job,
    pid = pid,
    poll = function(self)
      return (ffiUtil.getNonBlockingReadSize(parent_read_fd) or 0) > 0
        or ffiUtil.isSubProcessDone(pid)
    end,
    readAll = function(self)
      local res = ffiUtil.readAllFromFD(parent_read_fd) or ""
      parent_read_fd = nil
      return res
    end,
    close = function(self)
      if parent_read_fd then
        ffi.C.close(parent_read_fd)
        parent_read_fd = nil
      end
      ffiUtil.terminateSubProcess(pid)
      ffiUtil.isSubProcessDone(pid, true)
    end,
  })
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
    elseif time.since(entry.job.start_time) >= time.s(FORK_TIMEOUT) then
      logger.warn(
        "CommandRunner: fork job timed out after " .. FORK_TIMEOUT .. "s"
      )
      entry:close()
      entry.job.result = 255
      entry.job.timeout = true
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

function CommandRunner:cleanup()
  for i = #self.running_jobs, 1, -1 do
    local entry = self.running_jobs[i]
    entry:close()
    table.remove(self.running_jobs, i)
  end
end

--- Whether there are running jobs.
-- @treturn boolean
function CommandRunner:pending()
  return #self.running_jobs > 0
end

return CommandRunner
