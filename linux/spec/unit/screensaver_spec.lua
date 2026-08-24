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
      "should setup screensaver state for suspend, poweroff, and reboot",
      function()
        G_reader_settings:save("screensaver_type", "disable")
        G_reader_settings:save("screensaver_show_message", true)

        Screensaver:setup()
        assert.are.equal("disable", Screensaver.screensaver_type)
        assert.is_true(Screensaver.show_message)

        Screensaver:setup("poweroff", "Shutting down...")
        assert.are.equal("poweroff_", Screensaver.prefix)
        assert.are.equal("Shutting down...", Screensaver.event_message)

        Screensaver:setup("reboot", "Restarting...")
        assert.are.equal("reboot_", Screensaver.prefix)
        assert.are.equal("Restarting...", Screensaver.event_message)
      end
    )

    it("should fallback to random_image or koreader.png when needed", function()
      G_reader_settings:save("screensaver_type", "random_image")
      Screensaver:setup()
      assert.are.equal("random_image", Screensaver.screensaver_type)
      assert.is_not_nil(Screensaver.image_file)
    end)

    it("should handle chooseFolder and chooseFile dialogs", function()
      local filemanagerutil = require("apps/filemanager/filemanagerutil")
      local orig_show_choose = filemanagerutil.showChooseDialog
      local passed_title, passed_cb

      filemanagerutil.showChooseDialog = function(title, cb, path, ext, filter)
        passed_title = title
        passed_cb = cb
        if filter then
          assert.is_boolean(filter("test.epub"))
        end
      end

      Screensaver:chooseFolder()
      assert.is_not_nil(passed_title)
      passed_cb("/path/to/folder")
      assert.are.equal(
        "/path/to/folder",
        G_reader_settings:read("screensaver_dir")
      )

      Screensaver:chooseFile()
      assert.is_not_nil(passed_title)
      passed_cb("/path/to/cover.png")
      assert.are.equal(
        "/path/to/cover.png",
        G_reader_settings:read("screensaver_document_cover")
      )

      filemanagerutil.showChooseDialog = orig_show_choose
    end)

    it("should handle setMessage input dialog", function()
      local UIManager = require("ui/uimanager")
      local shown_widget
      local orig_show = UIManager.show
      local orig_close = UIManager.close
      UIManager.show = function(self, w)
        shown_widget = w
      end
      UIManager.close = function(self, w) end

      Screensaver:setMessage()
      assert.is_not_nil(shown_widget)
      local input_dlg = shown_widget
      local cancel_btn = input_dlg.buttons[1][1]
      local ok_btn = input_dlg.buttons[1][2]

      cancel_btn.callback()

      input_dlg.getInputText = function()
        return "Custom Sleep Message"
      end
      ok_btn.callback()
      assert.are.equal(
        "Custom Sleep Message",
        G_reader_settings:read("screensaver_message")
      )

      UIManager.show = orig_show
      UIManager.close = orig_close
    end)

    it("should handle setStretchLimit spin widget callbacks", function()
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

    it("should handle show, close and cleanup routines", function()
      local UIManager = require("ui/uimanager")
      local shown_widget
      local orig_show = UIManager.show
      local orig_close = UIManager.close
      UIManager.show = function(self, w)
        shown_widget = w
      end
      UIManager.close = function(self, w) end

      -- Disabled mode without message should return early
      G_reader_settings:save("screensaver_type", "disable")
      G_reader_settings:makeFalse("screensaver_show_message")
      Screensaver:setup()
      Screensaver:show()
      assert.is_nil(Screensaver.screensaver_widget)

      -- Show with message in middle
      G_reader_settings:makeTrue("screensaver_show_message")
      G_reader_settings:save("screensaver_message_position", "middle")
      G_reader_settings:save("screensaver_delay", "disable")
      Screensaver:setup()
      Screensaver:show()
      assert.is_not_nil(Screensaver.screensaver_widget)
      assert.is_true(Screensaver:close())

      -- Show with top message and overlay
      G_reader_settings:save("screensaver_message_position", "top")
      Screensaver:setup("poweroff", "Goodbye")
      Screensaver:show()
      assert.is_not_nil(Screensaver.screensaver_widget)
      Screensaver:cleanup()
      assert.is_nil(Screensaver.screensaver_widget)

      -- Show with bottom message
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
    end)
  end)
end)
