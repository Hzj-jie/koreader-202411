describe("ReadTimer plugin main module", function()
  local ReadTimer, time

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReadTimer = require("plugins/readtimer.koplugin/main")
    time = require("ui/time")
  end)

  describe("Initialization & Main Menu", function()
    it("should initialize ReadTimer plugin instance", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local rt = ReadTimer:new({
        ui = mock_ui,
      })
      assert.is_table(rt)
      assert.is_false(rt:scheduled())
      assert.are.equal(math.huge, rt:remaining())
    end)

    it("should populate main menu items", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local rt = ReadTimer:new({
        ui = mock_ui,
      })
      local menu_items = {}
      rt:addToMainMenu(menu_items)
      assert.is_table(menu_items.read_timer)
      assert.is_function(menu_items.read_timer.text_func)
      assert.is_function(menu_items.read_timer.checked_func)
      assert.is_false(menu_items.read_timer.checked_func())
    end)

    it("should handle scheduling and unscheduling timers", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local rt = ReadTimer:new({
        ui = mock_ui,
      })

      rt:rescheduleIn(300)
      assert.is_true(rt:scheduled())
      assert.is_number(rt:remaining())

      local hours, minutes, seconds = rt:remainingTime(1)
      assert.is_number(hours)
      assert.is_number(minutes)
      assert.is_number(seconds)

      rt:unschedule()
      assert.is_false(rt:scheduled())
    end)

    it("should test remaining time rounding modes", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local rt = ReadTimer:new({
        ui = mock_ui,
      })

      rt.time = time.monotonic() + time.s(3665) -- ~1 hour 1 minute 5 seconds

      local h, m, s = rt:remainingTime(-1) -- round down
      assert.is_number(h)
      assert.is_number(m)
      assert.is_number(s)

      h, m, s = rt:remainingTime(0) -- round nearest
      assert.is_number(h)
      assert.is_number(m)
      assert.is_number(s)

      h, m, s = rt:remainingTime(1) -- round up
      assert.is_number(h)
      assert.is_number(m)
      assert.is_number(s)

      rt:unschedule()
    end)

    it("should trigger alarm callback on expiration", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local rt = ReadTimer:new({
        ui = mock_ui,
      })

      rt.time = time.monotonic() + 10
      assert.is_function(rt.alarm_callback)
      rt.alarm_callback()
      assert.are.equal(0, rt.time)
      assert.is_false(rt:scheduled())
    end)

    it(
      "should support repeat in alarm_callback when last_interval_time is set",
      function()
        local shown_confirm
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        UIManager.show = function(self, widget)
          shown_confirm = widget
        end
        finally(function()
          UIManager.show = orig_show
        end)

        local mock_ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        }
        local rt = ReadTimer:new({
          ui = mock_ui,
        })

        rt.last_interval_time = 600
        rt.time = time.monotonic() + 10
        rt.alarm_callback()

        assert.is_not_nil(shown_confirm)
        assert.is_function(shown_confirm.ok_callback)
        assert.is_function(shown_confirm.cancel_callback)

        -- Ok callback repeats the interval
        shown_confirm.ok_callback()
        assert.is_true(rt:scheduled())

        -- Cancel callback clears interval and unschedules
        shown_confirm.cancel_callback()
        assert.are.equal(0, rt.last_interval_time)
        assert.is_false(rt:scheduled())
      end
    )

    it(
      "should broadcast UpdateHeader and UpdateFooter on onTimesChange_1M",
      function()
        local broadcasted = {}
        local UIManager = require("ui/uimanager")
        local orig_broadcast = UIManager.broadcastEvent
        UIManager.broadcastEvent = function(self, event)
          table.insert(broadcasted, event)
        end
        finally(function()
          UIManager.broadcastEvent = orig_broadcast
        end)

        local mock_ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        }
        local rt = ReadTimer:new({
          ui = mock_ui,
        })
        rt.show_value_in_header = true
        rt.show_value_in_footer = true
        rt.time = time.monotonic() + 120

        rt:onTimesChange_1M()
        local has_header = false
        local has_footer = false
        for _, ev in ipairs(broadcasted) do
          if ev == "UpdateHeader" then
            has_header = true
          elseif ev == "UpdateFooter" then
            has_footer = true
          end
        end
        assert.is_true(has_header)
        assert.is_true(has_footer)
      end
    )

    it(
      "should format header and footer text when timer is scheduled",
      function()
        local mock_ui = {
          menu = {
            registerToMainMenu = function() end,
          },
          view = {
            footer = {
              settings = {
                item_prefix = "icons",
              },
              addAdditionalFooterContent = function() end,
              removeAdditionalFooterContent = function() end,
            },
          },
        }
        local rt = ReadTimer:new({
          ui = mock_ui,
        })

        -- When not scheduled, both return nil
        assert.is_nil(rt.additional_header_content_func())
        assert.is_nil(rt.additional_footer_content_func())

        -- When scheduled
        rt.time = time.monotonic() + time.s(3600)
        local header_str = rt.additional_header_content_func()
        local footer_str = rt.additional_footer_content_func()
        assert.is_string(header_str)
        assert.is_string(footer_str)
        assert.is_true(footer_str:find("01:00") ~= nil)

        rt:unschedule()
      end
    )

    it(
      "reschedules active timer with remaining time on resume (fails: onResume reschedules for math.huge)",
      function()
        local mock_ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        }
        local rt = ReadTimer:new({
          ui = mock_ui,
        })

        -- Schedule timer for 300 seconds
        rt:rescheduleIn(300)
        assert.is_true(rt:scheduled())
        assert.is_true(rt:remaining() <= 300)

        -- When device resumes from sleep, onResume should reschedule for the remaining duration.
        -- In plugins/readtimer.koplugin/main.lua lines 400-406:
        --   self:unschedule()
        --   self:rescheduleIn(self:remaining())
        -- Because self:unschedule() sets self.time = 0, subsequent self:remaining() returns math.huge.
        -- As a result, rescheduleIn is called with math.huge, permanently losing the alarm.
        rt:onResume()

        assert.is_true(rt:scheduled())
        assert.are_not.equal(math.huge, rt:remaining())
        assert.is_true(rt:remaining() <= 300)
      end
    )
  end)
end)
