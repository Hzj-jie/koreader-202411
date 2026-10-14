-- luacheck: ignore 122
describe("Statistics CalendarView widget module", function()
  local CalendarView, Screen, Geom

  setup(function()
    require("commonrequire")
    CalendarView = require("plugins/statistics.koplugin/calendarview")
    Screen = require("device").screen
    Geom = require("ui/geometry")
  end)

  before_each(function()
    package.loaded["plugins/statistics.koplugin/calendarview"] = nil
    CalendarView = require("plugins/statistics.koplugin/calendarview")
  end)

  local function create_mock_stats(first_ts)
    return {
      getFirstTimestamp = function()
        return first_ts
      end,
      getReadingRatioPerHourByDay = function()
        return {}
      end,
      getReadBookByDay = function()
        return {}
      end,
      settings = {},
    }
  end

  describe("CalendarView initialization and layout", function()
    it("initializes day widths, outer padding, and month labels", function()
      local now = os.time()
      local stats = create_mock_stats(now - 86400 * 30)
      local view = CalendarView:new({
        reader_statistics = stats,
        width = 600,
        height = 800,
      })

      assert.is_table(view)
      assert.is_number(view.day_width)
      assert.is_true(view.day_width > 0)
      assert.is_number(view.outer_padding)
      assert.is_string(view.min_month)
      assert.is_string(view.max_month)
      assert.are.equal(os.date("%Y-%m", now), view.max_month)
    end)

    it(
      "navigates across months with goToMonth, prevMonth, and nextMonth",
      function()
        local now = os.time()
        local stats = create_mock_stats(now - 86400 * 365 * 2)
        local view = CalendarView:new({
          reader_statistics = stats,
          width = 600,
          height = 800,
          cur_month = "2026-05",
          browse_future_months = true,
        })

        view:goToMonth("2026-07")
        assert.are.equal("2026-07", view.cur_month)

        view:prevMonth()
        assert.are.equal("2026-06", view.cur_month)

        view:nextMonth()
        assert.are.equal("2026-07", view.cur_month)
      end
    )
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes MIN_MONTH permanently cached when getFirstTimestamp initially returns nil",
      function()
        -- In calendarview.lua lines 1141 and 1212-1219:
        -- local MIN_MONTH = nil
        -- ...
        -- if not MIN_MONTH then
        --   local min_ts = self.reader_statistics:getFirstTimestamp()
        --   if not min_ts then min_ts = now_ts end
        --   MIN_MONTH = os.date("%Y-%m", min_ts)
        -- end
        -- self.min_month = MIN_MONTH
        --
        -- When a CalendarView is first created before any reading statistics exist,
        -- getFirstTimestamp() returns nil. MIN_MONTH is cached permanently to the current month.
        -- When a subsequent CalendarView instance is opened after statistics have been synced
        -- or recorded (e.g. from 2 years earlier), MIN_MONTH is not refreshed and remains
        -- locked to the current month, preventing the user from viewing earlier history.

        local empty_stats = create_mock_stats(nil)
        local view1 = CalendarView:new({
          reader_statistics = empty_stats,
          width = 600,
          height = 800,
        })
        assert.is_table(view1)
        assert.are.equal(os.date("%Y-%m"), view1.min_month)

        local earlier_ts = os.time() - 86400 * 365 * 2
        local expected_earlier_month = os.date("%Y-%m", earlier_ts)
        local populated_stats = create_mock_stats(earlier_ts)

        local view2 = CalendarView:new({
          reader_statistics = populated_stats,
          width = 600,
          height = 800,
        })
        assert.is_table(view2)

        -- Expected: view2.min_month reflects earlier_ts
        -- Defect: MIN_MONTH was permanently cached in the file-level upvalue, so view2.min_month
        -- is still locked to the current month.
        assert.are.equal(expected_earlier_month, view2.min_month)
      end
    )
  end)
end)
