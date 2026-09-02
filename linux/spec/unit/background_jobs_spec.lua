describe("background_jobs", function()
  local background_jobs
  local mock_uimanager
  local mock_pluginshare
  local original_uimanager
  local original_pluginshare

  before_each(function()
    require("commonrequire")

    -- Save original loaded packages if any
    original_uimanager = package.loaded["ui/uimanager"]
    original_pluginshare = package.loaded["pluginshare"]

    -- Setup clean mock tables
    mock_pluginshare = {
      backgroundJobs = {},
    }
    mock_uimanager = {
      broadcastEvent = spy.new(function() end),
    }

    package.loaded["pluginshare"] = mock_pluginshare
    package.loaded["ui/uimanager"] = mock_uimanager

    -- Unload background_jobs to make sure it executes fresh loading code
    package.unload("background_jobs")
    background_jobs = require("background_jobs")
  end)

  after_each(function()
    -- Restore original loaded packages
    package.loaded["ui/uimanager"] = original_uimanager
    package.loaded["pluginshare"] = original_pluginshare
    package.unload("background_jobs")
  end)

  it("should insert 3 default background jobs on loading", function()
    assert.are.equal(3, #mock_pluginshare.backgroundJobs)

    local job1 = mock_pluginshare.backgroundJobs[1]
    local job2 = mock_pluginshare.backgroundJobs[2]
    local job3 = mock_pluginshare.backgroundJobs[3]

    assert.are.equal(60, job1.when)
    assert.is_true(job1.repeated)
    assert.is_function(job1.executable)

    assert.are.equal(300, job2.when)
    assert.is_true(job2.repeated)
    assert.is_function(job2.executable)

    assert.are.equal(900, job3.when)
    assert.is_true(job3.repeated)
    assert.is_function(job3.executable)
  end)

  it("should broadcast BackgroundJobsUpdated when jobs are loaded", function()
    -- During loading, 3 jobs were inserted. Each insert broadcasts the event.
    assert
      .spy(mock_uimanager.broadcastEvent).was
      .called_with(mock_uimanager, "BackgroundJobsUpdated")
    assert.spy(mock_uimanager.broadcastEvent).was.called(3)
  end)

  it(
    "should broadcast correct TimesChange events when default jobs are executed",
    function()
      local job1 = mock_pluginshare.backgroundJobs[1]
      local job2 = mock_pluginshare.backgroundJobs[2]
      local job3 = mock_pluginshare.backgroundJobs[3]

      -- Reset spy to check only execution broadcasts
      mock_uimanager.broadcastEvent:clear()

      job1.executable()
      assert
        .spy(mock_uimanager.broadcastEvent).was
        .called_with(mock_uimanager, "TimesChange_1M")

      job2.executable()
      assert
        .spy(mock_uimanager.broadcastEvent).was
        .called_with(mock_uimanager, "TimesChange_5M")

      job3.executable()
      assert
        .spy(mock_uimanager.broadcastEvent).was
        .called_with(mock_uimanager, "TimesChange_15M")
    end
  )

  it(
    "should allow inserting custom jobs using BackgroundJobs.insert",
    function()
      mock_uimanager.broadcastEvent:clear()
      local initial_count = #mock_pluginshare.backgroundJobs

      local custom_job = {
        when = 120,
        repeated = false,
        executable = function() end,
      }

      background_jobs.insert(custom_job)

      assert.are.equal(initial_count + 1, #mock_pluginshare.backgroundJobs)
      assert.are.equal(
        custom_job,
        mock_pluginshare.backgroundJobs[initial_count + 1]
      )

      assert
        .spy(mock_uimanager.broadcastEvent).was
        .called_with(mock_uimanager, "BackgroundJobsUpdated")
    end
  )

  describe("insertKeyed()", function()
    before_each(function()
      background_jobs.clearKeys()
    end)

    it("should raise error for nil or non-table job", function()
      assert.has_error(function()
        background_jobs.insertKeyed(nil)
      end)
      assert.has_error(function()
        background_jobs.insertKeyed("not-a-table")
      end)
    end)

    it("should raise error for repeated jobs", function()
      assert.has_error(function()
        background_jobs.insertKeyed({
          repeated = true,
          executable = "fork",
        })
      end)
    end)

    it("should raise error for any job.when field provided", function()
      assert.has_error(function()
        background_jobs.insertKeyed({
          when = "asap",
          executable = "fork",
        })
      end)
      assert.has_error(function()
        background_jobs.insertKeyed({
          when = 60,
          executable = "fork",
        })
      end)
      assert.has_error(function()
        background_jobs.insertKeyed({
          when = "best-effort",
          executable = "fork",
        })
      end)
      assert.has_error(function()
        background_jobs.insertKeyed({
          when = function()
            return true
          end,
          executable = "fork",
        })
      end)
    end)

    it("should raise error if custom key is provided", function()
      assert.has_error(function()
        background_jobs.insertKeyed({
          key = "custom-key",
          executable = "echo 1",
        })
      end)
      assert.has_error(function()
        background_jobs.insertKeyed({
          key = 12345,
          executable = "fork",
        })
      end)
    end)

    it("should raise error if key cannot be determined or is not a string", function()
      assert.has_error(function()
        background_jobs.insertKeyed({
          executable = 12345, -- not a string or function, no action
        })
      end)
    end)

    it(
      "should insert job, set when to asap, and track key when job is inserted",
      function()
        local callback_called = false
        local function action_fn()
          return true
        end
        local res = background_jobs.insertKeyed({
          executable = "fork",
          action = action_fn,
          callback = function(job)
            callback_called = true
          end,
        })

        local expected_key = require("util").functionFingerprint(action_fn)
        assert.is_true(res)
        assert.is_true(background_jobs.hasKey(expected_key))
        assert.are.equal(4, #mock_pluginshare.backgroundJobs)
        assert.are.equal("asap", mock_pluginshare.backgroundJobs[4].when)

        -- Simulate job completion via callback
        local job = mock_pluginshare.backgroundJobs[4]
        job.callback({ result = true })

        assert.is_true(callback_called)
        assert.is_false(background_jobs.hasKey(expected_key))
      end
    )

    it(
      "should filter out duplicate job while first is active",
      function()
        local res1 = background_jobs.insertKeyed({
          executable = "sync-command",
        })
        local res2 = background_jobs.insertKeyed({
          executable = "sync-command",
        })

        assert.is_true(res1)
        assert.is_false(res2)
        assert.are.equal(4, #mock_pluginshare.backgroundJobs)
      end
    )

    it(
      "should allow inserting new job with same executable after previous finishes",
      function()
        background_jobs.insertKeyed({
          executable = "reuse-command",
        })

        local job1 = mock_pluginshare.backgroundJobs[4]
        job1.callback({ result = "first" })

        local res2 = background_jobs.insertKeyed({
          executable = "reuse-command",
        })

        assert.is_true(res2)
        assert.are.equal(5, #mock_pluginshare.backgroundJobs)
      end
    )

    it(
      "should automatically derive key from action closure and filter duplicates",
      function()
        local function makeAction(doc)
          return function()
            return doc
          end
        end

        local action1 = makeAction("docA")
        local action2 = makeAction("docA")
        local action3 = makeAction("docB")

        local res1 = background_jobs.insertKeyed({
          executable = "fork",
          action = action1,
        })
        local res2 = background_jobs.insertKeyed({
          executable = "fork",
          action = action2,
        })
        local res3 = background_jobs.insertKeyed({
          executable = "fork",
          action = action3,
        })

        assert.is_true(res1)
        assert.is_false(res2)
        assert.is_true(res3)
        assert.are.equal(5, #mock_pluginshare.backgroundJobs)
      end
    )

    it(
      "should automatically derive key from string executable command and filter duplicates",
      function()
        local res1 = background_jobs.insertKeyed({
          executable = "tar -czf /tmp/backup.tar.gz /sdcard/books",
        })
        local res2 = background_jobs.insertKeyed({
          executable = "tar -czf /tmp/backup.tar.gz /sdcard/books",
        })
        local res3 = background_jobs.insertKeyed({
          executable = "tar -czf /tmp/other.tar.gz /sdcard/books",
        })

        assert.is_true(res1)
        assert.is_false(res2)
        assert.is_true(res3)
        assert.is_true(
          background_jobs.hasKey("tar -czf /tmp/backup.tar.gz /sdcard/books")
        )
        assert.is_true(
          background_jobs.hasKey("tar -czf /tmp/other.tar.gz /sdcard/books")
        )
      end
    )

    it(
      "should not use action for key calculation if executable is not fork",
      function()
        local action = function() end
        local res = background_jobs.insertKeyed({
          executable = "tar -czf /tmp/backup.tar.gz /sdcard/books",
          action = action,
        })
        assert.is_true(res)
        assert.is_true(
          background_jobs.hasKey("tar -czf /tmp/backup.tar.gz /sdcard/books")
        )
      end
    )

    it(
      "should automatically derive key from function executable and filter duplicates",
      function()
        local function makeFunc(tag)
          return function()
            return tag
          end
        end

        local fn1 = makeFunc("tagA")
        local fn2 = makeFunc("tagA")
        local fn3 = makeFunc("tagB")

        local res1 = background_jobs.insertKeyed({
          executable = fn1,
        })
        local res2 = background_jobs.insertKeyed({
          executable = fn2,
        })
        local res3 = background_jobs.insertKeyed({
          executable = fn3,
        })

        assert.is_true(res1)
        assert.is_false(res2)
        assert.is_true(res3)
      end
    )

    it(
      "should raise error if executable is fork but action is not a function",
      function()
        assert.has_error(function()
          background_jobs.insertKeyed({
            executable = "fork",
            action = "not-a-function",
          })
        end)
        assert.has_error(function()
          background_jobs.insertKeyed({
            executable = "fork",
          })
        end)
      end
    )

    it(
      "should handle job without callback and release key on completion",
      function()
        local res = background_jobs.insertKeyed({
          executable = "echo 1",
        })
        assert.is_true(res)
        assert.is_true(background_jobs.hasKey("echo 1"))

        local job = mock_pluginshare.backgroundJobs[#mock_pluginshare.backgroundJobs]
        assert.is_function(job.callback)
        job.callback({ result = 0 })

        assert.is_false(background_jobs.hasKey("echo 1"))
      end
    )

    it(
      "should track multiple concurrent keys independently",
      function()
        local res1 = background_jobs.insertKeyed({
          executable = "echo alpha",
        })
        local res2 = background_jobs.insertKeyed({
          executable = "echo beta",
        })

        assert.is_true(res1)
        assert.is_true(res2)
        assert.is_true(background_jobs.hasKey("echo alpha"))
        assert.is_true(background_jobs.hasKey("echo beta"))

        local job1 = mock_pluginshare.backgroundJobs[4]
        local job2 = mock_pluginshare.backgroundJobs[5]

        job1.callback({ result = 1 })
        assert.is_false(background_jobs.hasKey("echo alpha"))
        assert.is_true(background_jobs.hasKey("echo beta"))

        job2.callback({ result = 2 })
        assert.is_false(background_jobs.hasKey("echo beta"))
      end
    )
  end)
end)
