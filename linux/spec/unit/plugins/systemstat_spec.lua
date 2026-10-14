local spy = require("luassert.spy")

describe("systemstat plugin", function()
  local SystemStatWidget
  local SystemStat
  local orig_uimanager_show
  local shown_widgets

  setup(function()
    require("commonrequire")

    shown_widgets = {}
    local Device = require("device")
    Device.model = "TestEreader"

    local UIManager = require("ui/uimanager")
    orig_uimanager_show = UIManager.show
    UIManager.show = function(self, widget)
      table.insert(shown_widgets, widget)
    end

    SystemStatWidget = dofile("plugins/systemstat.koplugin/main.lua")
    -- Access internal SystemStat singleton through widget execution or environment
    local dummy_menu = { registerToMainMenu = function() end }
    local w = SystemStatWidget:new({ ui = { menu = dummy_menu } })
    w:onShowSysStatistics()
    -- KeyValuePage was shown; find SystemStat from package/dofile
    -- SystemStat is a local in main.lua, but methods on SystemStatWidget call it
  end)

  teardown(function()
    local UIManager = require("ui/uimanager")
    UIManager.show = orig_uimanager_show
  end)

  before_each(function()
    shown_widgets = {}
  end)

  describe("SystemStatWidget lifecycle and actions", function()
    it("registers dispatcher action on init", function()
      local Dispatcher = require("dispatcher")
      local registered_actions = {}
      local orig_registerAction = Dispatcher.registerAction
      Dispatcher.registerAction = function(self, name, action)
        registered_actions[name] = action
      end
      finally(function()
        Dispatcher.registerAction = orig_registerAction
      end)

      local registered_menu = false
      local mock_menu = {
        registerToMainMenu = function(self, widget)
          registered_menu = true
        end,
      }
      local widget = SystemStatWidget:new({
        ui = { menu = mock_menu },
      })
      widget:init()

      assert.is_true(registered_menu)
      assert.is_not_nil(registered_actions["system_statistics"])
      assert.are.equal(
        "ShowSysStatistics",
        registered_actions["system_statistics"].event
      )
      assert.are.equal(
        "System statistics",
        registered_actions["system_statistics"].title
      )
    end)

    it("adds system_statistics item to main menu", function()
      local menu_items = {}
      local widget = SystemStatWidget:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })
      widget:addToMainMenu(menu_items)

      assert.is_not_nil(menu_items.system_statistics)
      assert.are.equal("System statistics", menu_items.system_statistics.text)
      assert.is_true(menu_items.system_statistics.keep_menu_open)
      assert.is_function(menu_items.system_statistics.callback)

      menu_items.system_statistics.callback()
      assert.are.equal(1, #shown_widgets)
      assert.are.equal("System statistics", shown_widgets[1].title)
    end)

    it("handles onResume and onNotCharging events", function()
      local widget = SystemStatWidget:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })

      widget:onResume()
      widget:onNotCharging()

      widget:onShowSysStatistics()
      assert.are.equal(1, #shown_widgets)
      local page = shown_widgets[1]
      local found_wakeups = false
      local found_discharge = false
      for _, pair in ipairs(page.kv_pairs) do
        if pair[1] and pair[1]:find("Wake%-ups") then
          found_wakeups = true
          assert.is_true(tonumber(pair[2]) >= 1)
        elseif pair[1] and pair[1]:find("Discharge cycles") then
          found_discharge = true
          assert.is_true(tonumber(pair[2]) >= 1)
        end
      end
      assert.is_true(found_wakeups)
      assert.is_true(found_discharge)
    end)
  end)

  describe("pending network jobs callback", function()
    it("shows countsOfPendingJobs in kv_pairs", function()
      local networklistener = require("ui/network/networklistener")
      local orig_counts = networklistener.countsOfPendingJobs
      networklistener.countsOfPendingJobs = function()
        return 7
      end
      finally(function()
        networklistener.countsOfPendingJobs = orig_counts
      end)

      local widget = SystemStatWidget:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })
      widget:onShowSysStatistics()

      local page = shown_widgets[1]
      local pending_item
      for _, pair in ipairs(page.kv_pairs) do
        if pair[1] and pair[1]:find("Pending network jobs") then
          pending_item = pair
          break
        end
      end
      assert.is_not_nil(pending_item)
      assert.are.equal(7, pending_item[2])
    end)

    it(
      'displays InfoMessage with pending job keys when jobs exist (fails: line 276 inverted msg == "" check)',
      function()
        local networklistener = require("ui/network/networklistener")
        local orig_pendingJobKeys = networklistener.pendingJobKeys
        networklistener.pendingJobKeys = function()
          return { "kosync_push_progress" }, { "weather_fetch_forecast" }
        end
        finally(function()
          networklistener.pendingJobKeys = orig_pendingJobKeys
        end)

        local widget = SystemStatWidget:new({
          ui = { menu = { registerToMainMenu = function() end } },
        })
        widget:onShowSysStatistics()

        local page = shown_widgets[1]
        local pending_item
        for _, pair in ipairs(page.kv_pairs) do
          if pair[1] and pair[1]:find("Pending network jobs") then
            pending_item = pair
            break
          end
        end
        assert.is_not_nil(pending_item)
        assert.is_function(pending_item.callback)

        shown_widgets = {}
        pending_item.callback()

        -- When pending jobs exist, InfoMessage should be shown with job details.
        -- However, main.lua line 276 checks:
        --   if msg == "" then UIManager:show(InfoMessage:new({ text = msg })) end
        -- which inverts the logic and suppresses the message when msg is non-empty.
        assert.are.equal(1, #shown_widgets)
        local info = shown_widgets[1]
        assert.is_not_nil(info)
        assert.is_not_nil(info.text)
        assert.is_true(info.text:find("kosync_push_progress") ~= nil)
        assert.is_true(info.text:find("weather_fetch_forecast") ~= nil)
      end
    )
  end)
end)
