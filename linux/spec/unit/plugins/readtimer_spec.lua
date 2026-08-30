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
  end)
end)
