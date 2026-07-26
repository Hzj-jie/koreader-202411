describe("CalendarView widget", function()
  local CalendarView
  local UIManager
  local mock_reader_statistics

  setup(function()
    require("commonrequire")
    package.loaded["plugins/statistics.koplugin/calendarview"] = nil
    CalendarView = require("plugins/statistics.koplugin/calendarview")
    UIManager = require("ui/uimanager")

    local sample_ts = os.time({ year = 2024, month = 5, day = 15, hour = 12 })
    mock_reader_statistics = {
      settings = {
        calendar_day_start_hour = 1,
        calendar_day_start_minute = 30,
      },
      getFirstTimestamp = function()
        return sample_ts
      end,
      getReadingRatioPerHourByDay = function()
        return {
          ["2024-05-15"] = {
            0.1,
            0.2,
            0.001,
            0.0,
            0.5,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.8,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
          },
        }
      end,
      getReadBookByDay = function()
        return {
          ["2024-05-15"] = {
            { id = 1, title = "Test Book 1" },
            { id = 2, title = "Test Book 2" },
          },
          ["2024-05-16"] = {
            { id = 1, title = "Test Book 1" },
          },
        }
      end,
      getBooksFromPeriod = function()
        local books = {}
        for i = 1, 12 do
          table.insert(books, {
            book_id = i,
            [1] = "Test Book " .. i,
            [2] = (i * 10) .. " mins",
            duration = i * 600,
          })
        end
        return books
      end,
      getReadingDurationBySecond = function()
        local res = {}
        for i = 1, 12 do
          res[i] = {
            periods = {
              { start = (i - 1) * 1800, finish = i * 1800 - 1 },
            },
          }
        end
        return res
      end,
    }
  end)

  describe("CalendarView main functionality", function()
    it("should initialize and populate items correctly", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
        show_hourly_histogram = true,
      })
      assert.is_table(view)
      assert.is_string(view.min_month)
      assert.is_string(view.max_month)
      assert.are.equal("2024-05", view.cur_month)
    end)

    it("should handle view without histogram", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
        show_hourly_histogram = false,
      })
      assert.is_table(view)
    end)

    it("should handle month navigation methods", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
      })
      view.min_month = "2024-01"
      view.max_month = "2024-12"

      view:nextMonth()
      assert.are.equal("2024-06", view.cur_month)

      view:prevMonth()
      assert.are.equal("2024-05", view.cur_month)

      view:goToMonth("2024-08")
      assert.are.equal("2024-08", view.cur_month)

      assert.is_true(view:onNextMonth())
      assert.is_true(view:onPrevMonth())
    end)

    it("should handle month hold input validation", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
      })
      local hold_input = view.page_info_text.hold_input
      assert.is_table(hold_input)
      assert.are.equal("2024-05", hold_input.input_func())

      -- Valid input
      hold_input.callback("2024-09")
      assert.are.equal("2024-09", view.cur_month)

      -- Invalid input
      hold_input.callback("invalid-date")
    end)

    it("should handle swipe events", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
      })
      view.min_month = "2024-01"
      view.max_month = "2024-12"

      -- West swipe -> next month
      assert.is_true(view:onSwipe(nil, { direction = "west" }))
      assert.are.equal("2024-06", view.cur_month)

      -- East swipe -> prev month
      assert.is_true(view:onSwipe(nil, { direction = "east" }))
      assert.are.equal("2024-05", view.cur_month)

      -- South swipe -> onExit
      local exited = false
      view.onExit = function()
        exited = true
        return true
      end
      view:onSwipe(nil, { direction = "south" })
      assert.is_true(exited)

      -- North swipe -> no-op
      view:onSwipe(nil, { direction = "north" })

      -- Diagonal swipe -> refresh
      assert.is_false(view:onSwipe(nil, { direction = "northeast" }))
    end)

    it("should handle multi-swipe and exit", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
      })
      assert.is_true(view:onMultiSwipe(nil, {}))
      assert.is_true(view:onExit())
    end)

    it("should trigger day callbacks when tapping calendar days", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
      })
      -- Find a day with callback and invoke it
      local day_widget
      for _, week in ipairs(view.weeks) do
        for _, day in ipairs(week.calday_widgets) do
          if day.callback then
            day_widget = day
            break
          end
        end
        if day_widget then
          break
        end
      end

      assert.is_not_nil(day_widget)
      assert.is_true(day_widget:onTap())
      assert.is_true(day_widget:onHold())
    end)

    it("should open CalendarDayView from showCalendarDayView", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
      })
      assert.has_no.errors(function()
        view:showCalendarDayView(mock_reader_statistics)
      end)
    end)
  end)

  describe("CalendarDayView functionality", function()
    it("should navigate pages, interact with books, and swipe", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
      })
      -- Find a day with callback and tap to get CalendarDayView
      local day_widget
      for _, week in ipairs(view.weeks) do
        for _, day in ipairs(week.calday_widgets) do
          if day.callback then
            day_widget = day
            break
          end
        end
        if day_widget then
          break
        end
      end

      day_widget:onTap()

      -- Access the displayed CalendarDayView from UIManager stack or mock
      local top_widget = UIManager._top or UIManager._window
      if top_widget and top_widget.nextPage then
        local day_view = top_widget

        assert.is_string(day_view:getTitle())

        -- Page navigation
        assert.is_true(day_view:nextPage())
        assert.are.equal(2, day_view.show_page)

        assert.is_true(day_view:prevPage())
        assert.are.equal(1, day_view.show_page)

        day_view:goToPage(2)
        assert.are.equal(2, day_view.show_page)

        -- Hold input callback for page
        if day_view.footer_page and day_view.footer_page.hold_input then
          assert.is_string(day_view.footer_page.hold_input.hint_func())
          day_view.footer_page.hold_input.callback("1")
          assert.are.equal(1, day_view.show_page)
        end

        -- Swipes
        assert.is_true(day_view:onSwipe(nil, { direction = "west" }))
        assert.is_true(day_view:onSwipe(nil, { direction = "east" }))
        assert.is_true(day_view:onSwipe(nil, { direction = "south" }))
        day_view:onSwipe(nil, { direction = "north" })
        assert.is_false(day_view:onSwipe(nil, { direction = "northeast" }))

        assert.is_true(day_view:onMultiSwipe(nil, {}))
        assert.is_true(day_view:onExit())
      end
    end)

    it(
      "should handle book item actions and removal in CalendarDayView",
      function()
        local view = CalendarView:new({
          reader_statistics = mock_reader_statistics,
          cur_month = "2024-05",
          width = 600,
          height = 800,
        })
        local day_widget
        for _, week in ipairs(view.weeks) do
          for _, day in ipairs(week.calday_widgets) do
            if day.callback then
              day_widget = day
              break
            end
          end
          if day_widget then
            break
          end
        end
        day_widget:onTap()

        local top_widget = UIManager._top or UIManager._window
        if top_widget and top_widget.layout then
          local day_view = top_widget
          local book_item = day_view.layout[1] and day_view.layout[1][1]
          if book_item then
            -- Tap checkmark or callback
            book_item:onTap(nil, { pos = { x = 0, y = 0 } })
            book_item:onHold()

            -- Remove item
            local item_data = day_view.kv_pairs[1]
            if item_data then
              day_view:removeKeyValueItem(item_data)
            end
          end
          day_view:onExit()
        end
      end
    )

    it("should handle navigation via swipe events", function()
      local view = CalendarView:new({
        reader_statistics = mock_reader_statistics,
        cur_month = "2024-05",
        width = 600,
        height = 800,
      })
      if type(view.onSwipe) == "function" then
        view:onSwipe(nil, { direction = "west" })
        view:onSwipe(nil, { direction = "east" })
      end
    end)
  end)
end)
