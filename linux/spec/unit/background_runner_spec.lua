describe("BackgroundRunner widget tests", function()
  local Device, PluginShare, MockTime, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    -- Device needs to be loaded before UIManager.
    Device = require("device")
    Device.input.waitEvent = function() end
    PluginShare = require("pluginshare")
    MockTime = require("mock_time")
    MockTime:install()
    UIManager = require("ui/uimanager")
    UIManager:setRunForeverMode()
    requireBackgroundRunner()
  end)

  teardown(function()
    MockTime:uninstall()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    stopBackgroundRunner()
  end)

  before_each(function()
    require("util").clearTable(PluginShare.backgroundJobs)
  end)

  after_each(function()
    requireBackgroundRunner():allowBlockingJobs(false)
  end)

  it("should start job", function()
    local executed = false
    table.insert(PluginShare.backgroundJobs, {
      when = 10,
      executable = function()
        executed = true
      end,
    })
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()
    assert.is_false(executed)
    MockTime:increase(9)
    UIManager:handleInput()
    assert.is_false(executed)
    MockTime:increase(2)
    UIManager:handleInput()
    assert.is_true(executed)
  end)

  it("should repeat job", function()
    local executed = 0
    table.insert(PluginShare.backgroundJobs, {
      when = 1,
      repeated = function()
        return executed < 10
      end,
      executable = function()
        executed = executed + 1
      end,
    })
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()

    for i = 1, 10 do
      MockTime:increase(2)
      UIManager:handleInput()
      assert.are.equal(i, executed)
    end
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(10, executed)
  end)

  it("should repeat job for predefined times", function()
    local executed = 0
    table.insert(PluginShare.backgroundJobs, {
      when = 1,
      repeated = 10,
      executable = function()
        executed = executed + 1
      end,
    })
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()

    for i = 1, 10 do
      MockTime:increase(2)
      UIManager:handleInput()
      assert.are.equal(i, executed)
    end
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(10, executed)
  end)

  it("should block long job", function()
    requireBackgroundRunner():allowBlockingJobs(true)
    local executed = 0
    local job = {
      when = 1,
      repeated = true,
      executable = function()
        executed = executed + 1
        MockTime:increase(2)
      end,
    }
    table.insert(PluginShare.backgroundJobs, job)
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(1, executed)
    assert.is_true(job.timeout)
    assert.is_true(job.blocked)
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(1, executed)
  end)

  it("should execute binary", function()
    local executed = false
    local job = {
      when = 1,
      executable = "ls | grep this-should-not-be-a-file",
      callback = function()
        executed = true
      end,
    }
    table.insert(PluginShare.backgroundJobs, job)
    notifyBackgroundJobsUpdated()

    while job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    -- grep should return 1 when there is no match.
    assert.are.equal(1, job.result)
    assert.is_false(job.timeout)
    assert.is_false(job.bad_command)
    assert.is_true(executed)
  end)

  it("should forward matching string environment to the executable", function()
    local job = {
      when = 1,
      repeated = false,
      executable = "echo $ENV1 | grep $ENV2",
      environment = {
        ENV1 = "yes",
        ENV2 = "yes",
      },
    }
    table.insert(PluginShare.backgroundJobs, job)
    notifyBackgroundJobsUpdated()

    while job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.are.equal(0, job.result)
    assert.is_false(job.timeout)
    assert.is_false(job.bad_command)
  end)

  it(
    "should forward non-matching string environment to executable without leaking to parent environment",
    function()
      local job = {
        when = 1,
        repeated = false,
        executable = "echo $ENV1 | grep $ENV2",
        environment = {
          ENV1 = "yes",
          ENV2 = "no",
        },
      }
      table.insert(PluginShare.backgroundJobs, job)
      notifyBackgroundJobsUpdated()

      while job.end_time == nil do
        MockTime:increase(2)
        UIManager:handleInput()
      end

      assert.are.equal(1, job.result)
      assert.is_false(job.timeout)
      assert.is_false(job.bad_command)
      assert.are.not_equal(os.getenv("ENV1"), "yes")
      assert.are.not_equal(os.getenv("ENV2"), "yes")
      assert.are.not_equal(os.getenv("ENV2"), "no")
    end
  )

  it(
    "should forward dynamic function environment to executable when matching",
    function()
      local job = {
        when = 1,
        repeated = false,
        executable = "echo $ENV1 | grep $ENV2",
        environment = function()
          return {
            ENV1 = "yes",
            ENV2 = "yes",
          }
        end,
      }
      table.insert(PluginShare.backgroundJobs, job)
      notifyBackgroundJobsUpdated()

      while job.end_time == nil do
        MockTime:increase(2)
        UIManager:handleInput()
      end

      assert.are.equal(0, job.result)
      assert.is_false(job.timeout)
      assert.is_false(job.bad_command)
    end
  )

  it(
    "should forward dynamic function environment to executable when non-matching",
    function()
      local job = {
        when = 1,
        repeated = false,
        executable = "echo $ENV1 | grep $ENV2",
        environment = function()
          return {
            ENV1 = "yes",
            ENV2 = "no",
          }
        end,
      }
      table.insert(PluginShare.backgroundJobs, job)
      notifyBackgroundJobsUpdated()

      while job.end_time == nil do
        MockTime:increase(2)
        UIManager:handleInput()
      end

      assert.are.equal(1, job.result)
      assert.is_false(job.timeout)
      assert.is_false(job.bad_command)
    end
  )

  it("should block long binary job", function()
    requireBackgroundRunner():allowBlockingJobs(true)
    local job = {
      when = 1,
      repeated = true,
      executable = "sleep 1h",
      environment = {
        TIMEOUT = 1,
      },
    }
    table.insert(PluginShare.backgroundJobs, job)
    notifyBackgroundJobsUpdated()

    while job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.are.equal(255, job.result)
    assert.is_true(job.timeout)
    assert.is_true(job.blocked)
  end)

  it("should execute callback", function()
    local executed = 0
    table.insert(PluginShare.backgroundJobs, {
      when = 1,
      repeated = 10,
      executable = function() end,
      callback = function()
        executed = executed + 1
      end,
    })
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()

    for i = 1, 10 do
      MockTime:increase(2)
      UIManager:handleInput()
      assert.are.equal(i, executed)
    end
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(10, executed)
  end)

  it("should execute all ready jobs in the same tick", function()
    local executed = 0
    table.insert(PluginShare.backgroundJobs, {
      when = 1,
      executable = function()
        executed = executed + 1
      end,
    })
    table.insert(PluginShare.backgroundJobs, {
      when = 1,
      executable = function()
        executed = executed + 1
      end,
    })
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(2, executed)
  end)

  it("should stop executing when suspending", function()
    local executed = 0
    local job = {
      when = 1,
      repeated = true,
      executable = function()
        executed = executed + 1
      end,
    }
    table.insert(PluginShare.backgroundJobs, job)
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(1, executed)
    -- Simulate a suspend event.
    requireBackgroundRunner():onSuspend()
    for i = 1, 10 do
      MockTime:increase(2)
      UIManager:handleInput()
      assert.are.equal(1, executed)
    end
    -- Simulate a resume event.
    requireBackgroundRunner():onResume()
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(1, executed)
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(2, executed)
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(3, executed)
  end)

  it("should not start multiple times after multiple onResume", function()
    local executed = 0
    local job = {
      when = 1,
      repeated = true,
      executable = function()
        executed = executed + 1
      end,
    }
    table.insert(PluginShare.backgroundJobs, job)
    notifyBackgroundJobsUpdated()

    for i = 1, 10 do
      requireBackgroundRunner():onResume()
    end

    MockTime:increase(2)
    UIManager:handleInput()
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(1, executed)
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(2, executed)
    MockTime:increase(2)
    UIManager:handleInput()
    assert.are.equal(3, executed)
  end)

  it("should support fork executable lambda in subprocess", function()
    local result_val
    local job = {
      when = 1,
      executable = "fork",
      action = function()
        return 0
      end,
      callback = function(j)
        result_val = j.result
      end,
    }
    table.insert(PluginShare.backgroundJobs, job)
    notifyBackgroundJobsUpdated()

    while job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.are.equal(0, result_val)
    assert.are.equal(0, job.result)
    assert.is_false(job.timeout)
  end)

  it("should support multiple concurrent background tasks", function()
    local done1, done2 = false, false
    local job1 = {
      when = 1,
      executable = "echo task1",
      callback = function()
        done1 = true
      end,
    }
    local job2 = {
      when = 1,
      executable = "echo task2",
      callback = function()
        done2 = true
      end,
    }
    table.insert(PluginShare.backgroundJobs, job1)
    table.insert(PluginShare.backgroundJobs, job2)
    notifyBackgroundJobsUpdated()

    while not (done1 and done2) do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.is_true(done1)
    assert.is_true(done2)
    assert.are.equal(0, job1.result)
    assert.are.equal(0, job2.result)
  end)

  it("should validate job support via CommandRunner:isJobSupported", function()
    local CommandRunner =
      require("plugins/backgroundrunner.koplugin/commandrunner")
    assert.is_true(
      CommandRunner:isJobSupported({ executable = "ping -c 1 www.google.com" })
    )
    assert.is_true(CommandRunner:isJobSupported({
      executable = "fork",
      action = function()
        return 0
      end,
    }))
    assert.is_false(CommandRunner:isJobSupported({ executable = "fork" }))
    assert.is_false(CommandRunner:isJobSupported({
      executable = "fork",
      action = "not_a_func",
    }))
    assert.is_false(
      CommandRunner:isJobSupported({ executable = function() end })
    )
  end)

  it("should handle error in fork action and return false result", function()
    local error_job = {
      when = 1,
      executable = "fork",
      action = function()
        error("something went wrong")
      end,
    }
    table.insert(PluginShare.backgroundJobs, error_job)
    notifyBackgroundJobsUpdated()

    while error_job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.is_false(error_job.result)
  end)

  it("should return integer result from fork action", function()
    local ret_val_job = {
      when = 1,
      executable = "fork",
      action = function()
        return 42
      end,
    }
    table.insert(PluginShare.backgroundJobs, ret_val_job)
    notifyBackgroundJobsUpdated()

    while ret_val_job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.are.equal(42, ret_val_job.result)
  end)

  it("should return boolean results from fork action", function()
    local false_job = {
      when = 1,
      executable = "fork",
      action = function()
        return false
      end,
    }
    local true_job = {
      when = 1,
      executable = "fork",
      action = function()
        return true
      end,
    }
    table.insert(PluginShare.backgroundJobs, false_job)
    table.insert(PluginShare.backgroundJobs, true_job)
    notifyBackgroundJobsUpdated()

    while false_job.end_time == nil or true_job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.is_false(false_job.result)
    assert.is_true(true_job.result)
  end)

  it("should support repeating fork mode jobs with cloned action", function()
    local callback_count = 0
    local job = {
      when = 1,
      repeated = 2,
      executable = "fork",
      action = function()
        return 0
      end,
      callback = function()
        callback_count = callback_count + 1
      end,
    }
    table.insert(PluginShare.backgroundJobs, job)
    notifyBackgroundJobsUpdated()

    while callback_count < 2 do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.are.equal(2, callback_count)
  end)

  it(
    "should respect MAX_JOBS capacity limit and keep excess jobs queued",
    function()
      local completed_count = 0
      local jobs = {}
      for i = 1, 12 do
        local j = {
          when = 1,
          executable = "fork",
          action = function()
            return 0
          end,
          callback = function()
            completed_count = completed_count + 1
          end,
        }
        table.insert(jobs, j)
        table.insert(PluginShare.backgroundJobs, j)
      end
      notifyBackgroundJobsUpdated()

      while completed_count < 12 do
        MockTime:increase(2)
        UIManager:handleInput()
      end

      assert.are.equal(12, completed_count)
    end
  )

  it(
    "should execute fork job in isolated subprocess and deliver result and timestamps to callback",
    function()
      local parent_state = "unmodified"
      local callback_job = nil

      local job = {
        when = 1,
        executable = "fork",
        action = function()
          parent_state = "modified_in_subprocess"
          return true
        end,
        callback = function(j)
          callback_job = j
        end,
      }
      table.insert(PluginShare.backgroundJobs, job)
      notifyBackgroundJobsUpdated()

      while callback_job == nil do
        MockTime:increase(2)
        UIManager:handleInput()
      end

      -- Memory in parent process is not modified by child
      assert.are.equal("unmodified", parent_state)
      -- Result was communicated through pipe
      assert.is_true(callback_job.result)
      assert.is_false(callback_job.timeout)
      assert.is_not_nil(callback_job.start_time)
      assert.is_not_nil(callback_job.end_time)
      assert.is_true(callback_job.end_time >= callback_job.start_time)
    end
  )

  it("should broadcast ForkedProcess event in subprocess", function()
    local Widget = require("ui/widget/widget")
    local Geom = require("ui/geometry")
    local device_fork_called = false
    local test_widget = Widget:extend({
      dimen = Geom:new({ w = 100, h = 100 }),
      onForkedProcess = function()
        device_fork_called = true
      end,
    })
    local widget_instance = test_widget:new({})
    UIManager:show(widget_instance)

    local child_saw_fork_called = false
    local job = {
      when = 1,
      executable = "fork",
      action = function()
        -- In the child subprocess, onForkedProcess was executed on widget
        return device_fork_called
      end,
      callback = function(j)
        child_saw_fork_called = j.result
      end,
    }
    table.insert(PluginShare.backgroundJobs, job)
    notifyBackgroundJobsUpdated()

    while job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.is_true(child_saw_fork_called)
    -- In parent, onForkedProcess was not called
    assert.is_false(device_fork_called)

    UIManager:close(widget_instance)
  end)

  it("should return string result from fork action", function()
    local str_job = {
      when = 1,
      executable = "fork",
      action = function()
        return "hello world"
      end,
    }
    table.insert(PluginShare.backgroundJobs, str_job)
    notifyBackgroundJobsUpdated()

    while str_job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.are.equal("hello world", str_job.result)
  end)

  it("should return table result from fork action", function()
    local tbl_job = {
      when = 1,
      executable = "fork",
      action = function()
        return { count = 5, status = "ok", items = { 1, 2, 3 } }
      end,
    }
    table.insert(PluginShare.backgroundJobs, tbl_job)
    notifyBackgroundJobsUpdated()

    while tbl_job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.are.same(
      { count = 5, status = "ok", items = { 1, 2, 3 } },
      tbl_job.result
    )
  end)

  it("should return nil result from fork action", function()
    local nil_job = {
      when = 1,
      executable = "fork",
      action = function()
        return nil
      end,
    }
    table.insert(PluginShare.backgroundJobs, nil_job)
    notifyBackgroundJobsUpdated()

    while nil_job.end_time == nil do
      MockTime:increase(2)
      UIManager:handleInput()
    end

    assert.is_nil(nil_job.result)
  end)

  it(
    "should handle invalid child output gracefully in CommandRunner",
    function()
      local CommandRunner =
        require("plugins/backgroundrunner.koplugin/commandrunner")
      UIManager:preventStandby()
      local mock_job = {
        executable = "mock",
      }
      table.insert(CommandRunner.running_jobs, {
        job = mock_job,
        poll = function()
          return true
        end,
        readAll = function()
          return "this is not valid lua code !!!"
        end,
        close = function() end,
      })

      local completed = CommandRunner:poll()
      assert.is_not_nil(completed)
      assert.are.equal(1, #completed)
      assert.are.equal(222, completed[1].result)
    end
  )
end)
