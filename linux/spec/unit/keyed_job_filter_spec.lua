describe("KeyedJobFilter", function()
  local KeyedJobFilter, BackgroundJobs, PluginShare, UIManager

  before_each(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    BackgroundJobs = require("background_jobs")
    PluginShare = require("pluginshare")
    PluginShare.backgroundJobs = {}

    package.loaded["plugins/backgroundrunner.koplugin/keyed_job_filter"] = nil
    KeyedJobFilter =
      require("plugins/backgroundrunner.koplugin/keyed_job_filter")
    KeyedJobFilter:clear()
  end)

  it("should insert a job and track its key as active", function()
    local res = KeyedJobFilter:insert({
      key = "job_1",
      executable = function() end,
    })

    assert.is_true(res)
    assert.is_true(KeyedJobFilter:hasKey("job_1"))
    assert.is_equal(1, #PluginShare.backgroundJobs)
  end)

  it("should filter out duplicate job while key is active", function()
    local res1 = KeyedJobFilter:insert({
      key = "job_dedup",
      executable = function() end,
    })
    local res2 = KeyedJobFilter:insert({
      key = "job_dedup",
      executable = function() end,
    })

    assert.is_true(res1)
    assert.is_false(res2)
    assert.is_equal(1, #PluginShare.backgroundJobs)
  end)

  it(
    "should automatically derive key from action function and filter duplicates",
    function()
      local param = "doc1.epub"
      local function action_fn()
        return param
      end

      local res1 = KeyedJobFilter:insert({
        executable = "fork",
        action = action_fn,
      })
      local res2 = KeyedJobFilter:insert({
        executable = "fork",
        action = action_fn,
      })

      assert.is_true(res1)
      assert.is_false(res2)
      assert.is_equal(1, #PluginShare.backgroundJobs)
    end
  )

  it(
    "should allow distinct action closures capturing different parameters",
    function()
      local function make_action(p)
        return function()
          return p
        end
      end

      local res1 = KeyedJobFilter:insert({
        executable = "fork",
        action = make_action("book_a.epub"),
      })
      local res2 = KeyedJobFilter:insert({
        executable = "fork",
        action = make_action("book_b.epub"),
      })

      assert.is_true(res1)
      assert.is_true(res2)
      assert.is_equal(2, #PluginShare.backgroundJobs)
    end
  )

  it("should clear active key upon job callback completion", function()
    local callback_called = false
    KeyedJobFilter:insert({
      key = "job_lifecycle",
      executable = function() end,
      callback = function(job)
        callback_called = true
      end,
    })

    assert.is_true(KeyedJobFilter:hasKey("job_lifecycle"))

    local job = PluginShare.backgroundJobs[1]
    job.callback(job)

    assert.is_true(callback_called)
    assert.is_false(KeyedJobFilter:hasKey("job_lifecycle"))

    -- Now a new job with the same key should be accepted
    local res = KeyedJobFilter:insert({
      key = "job_lifecycle",
      executable = function() end,
    })
    assert.is_true(res)
  end)
end)
