local stub = require("luassert.stub")

describe("Screensaver module", function()
  local Screensaver

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    Screensaver = require("ui/screensaver")
  end)

  it("should calculate average time for pages", function()
    stub(Screensaver, "getAvgTimePerPage", function()
      return 60
    end)

    local sec = Screensaver:_calcAverageTimeForPages(5)
    assert.is_not_nil(sec)
    assert.is_string(sec)

    Screensaver.getAvgTimePerPage:revert()
  end)

  it("should handle N/A average time for pages when nil or nan", function()
    stub(Screensaver, "getAvgTimePerPage", function()
      return nil
    end)

    local sec = Screensaver:_calcAverageTimeForPages(5)
    assert.is_equal(sec, "N/A")

    Screensaver.getAvgTimePerPage:revert()
  end)

  it(
    "should expand special message format tokens when no lastfile setting exists",
    function()
      local message = "Title: %T, Battery: %b"
      local fallback = "Sleeping"

      local result = Screensaver:expandSpecial(message, fallback)
      assert.is_not_nil(result)
    end
  )

  it("should check if screensaver is excluded", function()
    local excluded = Screensaver:isExcluded()
    assert.is_boolean(excluded)
  end)

  it("should return default screensaver message when set", function()
    assert.is_not_nil(Screensaver.default_screensaver_message)
  end)

  describe("Special Token Expansion", function()
    it("should expand time and battery tokens", function()
      local template = "Battery: %b, Time: %c"
      local result = Screensaver:expandSpecial(template, "Sleeping")
      assert.is_string(result)
      assert.are.equal(result, "Sleeping")
    end)

    it("should handle custom title and author tokens", function()
      local template = "Book: %t by %a"
      local result = Screensaver:expandSpecial(template, "Sleeping")
      assert.is_string(result)
    end)

    it("should expand book info tokens when lastfile is set", function()
      G_reader_settings:save("lastfile", "/path/to/test.epub")
      local template = "%T - %A (Series: %S)"
      local result = Screensaver:expandSpecial(template, "Fallback")
      assert.is_string(result)
      G_reader_settings:delete("lastfile")
    end)
  end)

  describe("Screensaver Setup & Modes", function()
    it("should correctly evaluate mode predicates", function()
      Screensaver.screensaver_type = "cover"
      assert.is_true(Screensaver:modeIsImage())
      assert.is_true(Screensaver:modeExpectsPortrait())

      Screensaver.screensaver_type = "random_image"
      assert.is_true(Screensaver:modeIsImage())
      assert.is_true(Screensaver:modeExpectsPortrait())

      Screensaver.screensaver_type = "disable"
      assert.is_false(Screensaver:modeIsImage())
      assert.is_false(Screensaver:modeExpectsPortrait())

      Screensaver.screensaver_type = "message"
      assert.is_false(Screensaver:modeIsImage())
      assert.is_false(Screensaver:modeExpectsPortrait())

      Screensaver.screensaver_background = "black"
      assert.is_true(Screensaver:withBackground())
      Screensaver.screensaver_background = "none"
      assert.is_false(Screensaver:withBackground())
    end)

    it(
      "should handle getReaderProgress hook and progress screensaver mode",
      function()
        local orig_hook = Screensaver.getReaderProgress
        local mock_widget = { id = "mock_reading_progress" }
        Screensaver.getReaderProgress = function()
          return mock_widget
        end

        Screensaver:setup("readingprogress")
        Screensaver:show()
        assert.is_not_nil(Screensaver.screensaver_widget)
        Screensaver:cleanup()

        Screensaver.getReaderProgress = orig_hook
      end
    )

    it("should handle stretch limit configuration", function()
      local UIManager = require("ui/uimanager")
      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      local menu_updated = false
      local mock_menu = {
        updateItems = function()
          menu_updated = true
        end,
      }

      Screensaver:setStretchLimit(mock_menu)
      assert.is_not_nil(shown_widget)
      local spin = shown_widget

      -- ok callback
      spin.value = 15
      spin.callback(spin)
      assert.are.equal(
        15,
        G_reader_settings:read("screensaver_stretch_limit_percentage")
      )
      assert.is_true(G_reader_settings:isTrue("screensaver_stretch_images"))
      assert.is_true(menu_updated)

      -- extra callback (disable stretch)
      menu_updated = false
      spin.extra_callback()
      assert.is_false(G_reader_settings:isTrue("screensaver_stretch_images"))
      assert.is_true(menu_updated)

      -- option callback (full stretch)
      menu_updated = false
      spin.option_callback()
      assert.is_true(G_reader_settings:isTrue("screensaver_stretch_images"))
      assert.is_nil(
        G_reader_settings:read("screensaver_stretch_limit_percentage")
      )
      assert.is_true(menu_updated)

      UIManager.show = orig_show
    end)

    it(
      "should handle chooseFile, chooseFolder, and setMessage dialogs",
      function()
        local UIManager = require("ui/uimanager")
        local shown_dialog
        local orig_show = UIManager.show
        UIManager.show = function(self, w)
          shown_dialog = w
        end

        Screensaver:chooseFile()
        assert.is_not_nil(shown_dialog)

        Screensaver:chooseFolder()
        assert.is_not_nil(shown_dialog)

        Screensaver:setMessage()
        assert.is_not_nil(shown_dialog)
        if shown_dialog.callback then
          shown_dialog.callback("New Message")
          assert.are_equal(
            "New Message",
            G_reader_settings:read("screensaver_message")
          )
        end

        UIManager.show = orig_show
      end
    )

    it(
      "should handle show, close and cleanup routines with background and positions",
      function()
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        local orig_close = UIManager.close
        UIManager.show = function(self, w) end
        UIManager.close = function(self, w) end

        -- Disabled mode without message should return early
        G_reader_settings:save("screensaver_type", "disable")
        G_reader_settings:makeFalse("screensaver_show_message")
        Screensaver:setup()
        Screensaver:show()
        assert.is_nil(Screensaver.screensaver_widget)

        -- Show with message in middle and white background
        G_reader_settings:makeTrue("screensaver_show_message")
        G_reader_settings:save("screensaver_msg_background", "white")
        G_reader_settings:save("screensaver_message_position", "middle")
        G_reader_settings:save("screensaver_delay", "disable")
        Screensaver:setup()
        Screensaver:show()
        assert.is_not_nil(Screensaver.screensaver_widget)
        assert.is_true(Screensaver:close())

        -- Show with top message and black background
        G_reader_settings:save("screensaver_msg_background", "black")
        G_reader_settings:save("screensaver_message_position", "top")
        Screensaver:setup("poweroff", "Goodbye")
        Screensaver:show()
        assert.is_not_nil(Screensaver.screensaver_widget)
        Screensaver:cleanup()
        assert.is_nil(Screensaver.screensaver_widget)

        -- Show with bottom message and none background
        G_reader_settings:save("screensaver_msg_background", "none")
        G_reader_settings:save("screensaver_message_position", "bottom")
        Screensaver:setup()
        Screensaver:show()
        assert.is_not_nil(Screensaver.screensaver_widget)
        Screensaver:cleanup()

        -- Show with random image and auto-rotation
        G_reader_settings:save("screensaver_type", "random_image")
        G_reader_settings:makeTrue("screensaver_rotate_auto_for_best_fit")
        Screensaver:setup()
        Screensaver:show()
        assert.is_not_nil(Screensaver.screensaver_widget)

        -- Delayed close
        G_reader_settings:save("screensaver_delay", "3")
        Screensaver:close()
        assert.is_true(Screensaver.delayed_close)

        Screensaver:cleanup()
        assert.is_nil(Screensaver.delayed_close)
        assert.is_false(require("device").screen_saver_mode)

        UIManager.show = orig_show
        UIManager.close = orig_close
      end
    )
  end)
end)
