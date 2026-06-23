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
            backgroundJobs = {}
        }
        mock_uimanager = {
            broadcastEvent = spy.new(function() end)
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
        assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, "BackgroundJobsUpdated")
        assert.spy(mock_uimanager.broadcastEvent).was.called(3)
    end)

    it("should broadcast correct TimesChange events when default jobs are executed", function()
        local job1 = mock_pluginshare.backgroundJobs[1]
        local job2 = mock_pluginshare.backgroundJobs[2]
        local job3 = mock_pluginshare.backgroundJobs[3]

        -- Reset spy to check only execution broadcasts
        mock_uimanager.broadcastEvent:clear()

        job1.executable()
        assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, "TimesChange_1M")

        job2.executable()
        assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, "TimesChange_5M")

        job3.executable()
        assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, "TimesChange_15M")
    end)

    it("should allow inserting custom jobs using BackgroundJobs.insert", function()
        mock_uimanager.broadcastEvent:clear()
        local initial_count = #mock_pluginshare.backgroundJobs

        local custom_job = {
            when = 120,
            repeated = false,
            executable = function() end
        }

        background_jobs.insert(custom_job)

        assert.are.equal(initial_count + 1, #mock_pluginshare.backgroundJobs)
        assert.are.equal(custom_job, mock_pluginshare.backgroundJobs[initial_count + 1])

        assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, "BackgroundJobsUpdated")
    end)
end)
