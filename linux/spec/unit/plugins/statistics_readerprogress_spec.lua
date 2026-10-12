-- luacheck: ignore 122
describe("Statistics ReaderProgress widget module", function()
  local ReaderProgress, Screen, Geom

  setup(function()
    require("commonrequire")
    ReaderProgress = require("plugins/statistics.koplugin/readerprogress")
    Screen = require("device").screen
    Geom = require("ui/geometry")
  end)

  local function create_7day_dates()
    local dates = {}
    local now = os.time()
    for i = 1, 7 do
      local day_time = now - 86400 * (i - 1)
      table.insert(dates, {
        10 + i, -- pages
        1800 + i * 100, -- reading time in seconds
        os.date("%Y-%m-%d", day_time),
      })
    end
    return dates
  end

  describe("Progress widget initialization and layout", function()
    it(
      "initializes layout, font faces, and total stats with 7 days of data",
      function()
        local dates = create_7day_dates()
        local progress = ReaderProgress:new({
          current_pages = 25,
          today_pages = 10,
          session_time = 1200,
          today_time = 3600,
          dates = dates,
        })

        assert.is_table(progress)
        assert.is_table(progress.dimen)
        assert.are.equal(Screen:getWidth(), progress.dimen.w)
        assert.are.equal(Screen:getHeight(), progress.dimen.h)
        assert.are.equal("25", progress.current_pages)
        assert.are.equal("10", progress.today_pages)
      end
    )

    it("calculates total time and pages over requested days", function()
      local dates = create_7day_dates()
      local progress = ReaderProgress:new({
        current_pages = 0,
        today_pages = 0,
        session_time = 0,
        today_time = 0,
        dates = dates,
      })

      local total_time, total_pages = progress:getTotalStats(3)
      assert.are.equal(dates[1][1] + dates[2][1] + dates[3][1], total_pages)
      assert.are.equal(dates[1][2] + dates[2][2] + dates[3][2], total_time)
    end)

    it("generates day and week summaries", function()
      local dates = create_7day_dates()
      local progress = ReaderProgress:new({
        current_pages = 15,
        today_pages = 15,
        session_time = 900,
        today_time = 900,
        dates = dates,
      })

      local day_summary = progress:genSummaryDay(progress.screen_width)
      assert.is_table(day_summary)

      local week_summary = progress:genSummaryWeek(progress.screen_width)
      assert.is_table(week_summary)
    end)
  end)
end)
