describe("ReaderScreenshot module", function()
  local DocumentRegistry, ReaderUI, lfs, UIManager, Event, Screen, Screenshoter, Device, filemanagerutil
  local sample_epub = "spec/front/unit/data/leaves.epub"
  local readerui

  setup(function()
    require("commonrequire")
    package.unloadAll()
    local dev = require("device")
    require("document/canvascontext"):init(dev)

    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    lfs = require("libs/libkoreader-lfs")
    UIManager = require("ui/uimanager")
    Event = require("ui/event")
    Screen = require("device").screen
    Screenshoter = require("ui/widget/screenshoter")
    Device = require("device")
    filemanagerutil = require("apps/filemanager/filemanagerutil")

    readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
  end)

  teardown(function()
    readerui:handleEvent(
      Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT)
    )
    readerui:onExit()
    readerui:onClose()
  end)

  it("should get screenshot in portrait", function()
    local name = "screenshots/reader_screenshot_portrait.png"
    readerui:handleEvent(
      Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT)
    )
    UIManager:quit()
    UIManager:show(readerui)
    UIManager:scheduleIn(1, function()
      UIManager:close(readerui)
      -- We haven't torn it down yet
      ReaderUI.instance = readerui
    end)
    UIManager:run()
    readerui.screenshot:onScreenshot(name)
    assert.truthy(lfs.attributes(name, "mode"))
    local dialog = UIManager._window_stack[#UIManager._window_stack].widget
    UIManager:close(dialog)
    UIManager:quit()
  end)

  it("should get screenshot in landscape", function()
    local name = "screenshots/reader_screenshot_landscape.png"
    readerui:handleEvent(
      Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE)
    )
    UIManager:quit()
    UIManager:show(readerui)
    UIManager:scheduleIn(2, function()
      UIManager:close(readerui)
      -- We haven't torn it down yet
      ReaderUI.instance = readerui
    end)
    UIManager:run()
    readerui.screenshot:onScreenshot(name)
    assert.truthy(lfs.attributes(name, "mode"))
    local dialog = UIManager._window_stack[#UIManager._window_stack].widget
    UIManager:close(dialog)
    UIManager:quit()
  end)

  it("should test key registration and gesture events across device types", function()
    -- Keyboard device
    local orig_hasKb = Device.hasKeyboard
    local orig_hasScreenKB = Device.hasScreenKB
    local orig_isTouch = Device.isTouchDevice

    Device.hasKeyboard = function() return true end
    Device.hasScreenKB = function() return false end
    Device.isTouchDevice = function() return true end

    local s_kb = Screenshoter:new({})
    assert.is_not_nil(s_kb.key_events.KeyPressShoot)
    assert.is_not_nil(s_kb.ges_events.TapDiagonal)
    assert.is_not_nil(s_kb.ges_events.SwipeDiagonal)

    -- ScreenKB device
    Device.hasKeyboard = function() return false end
    Device.hasScreenKB = function() return true end
    local s_screenkb = Screenshoter:new({})
    assert.is_not_nil(s_screenkb.key_events.KeyPressShoot)

    -- Non-touch device
    Device.hasKeyboard = function() return false end
    Device.hasScreenKB = function() return false end
    Device.isTouchDevice = function() return false end
    local s_nontouch = Screenshoter:new({})
    assert.is_nil(s_nontouch.ges_events)

    Device.hasKeyboard = orig_hasKb
    Device.hasScreenKB = orig_hasScreenKB
    Device.isTouchDevice = orig_isTouch
  end)

  it("should get custom screenshot dir and handle chooseFolder dialog", function()
    local s = Screenshoter:new({})
    assert.are_equal(s.default_dir, s:getScreenshotDir())

    G_reader_settings:save("screenshot_dir", "/custom/screenshots/")
    assert.are_equal("/custom/screenshots", s:getScreenshotDir())
    G_reader_settings:save("screenshot_dir", nil)

    -- chooseFolder
    local chosen_callback = nil
    local orig_showChoose = filemanagerutil.showChooseDialog
    filemanagerutil.showChooseDialog = function(title, cb, curr, def)
      chosen_callback = cb
    end

    s:chooseFolder()
    assert.is_not_nil(chosen_callback)
    chosen_callback("/new/screenshots")
    assert.are_equal("/new/screenshots", G_reader_settings:read("screenshot_dir"))
    G_reader_settings:save("screenshot_dir", nil)

    filemanagerutil.showChooseDialog = orig_showChoose
  end)

  it("should trigger all dialog button callbacks and event triggers", function()
    local shown_dialog = nil
    local custom_cover_set = false
    local image_viewer_shown = false

    local mock_ui = {
      document = { file = "book.epub" },
      bookinfo = {
        setCustomCoverFromImage = function(_, f, img)
          custom_cover_set = true
        end,
      },
      file_chooser = {
        path = "/tmp",
        refreshPath = function() end,
      },
    }

    local s = Screenshoter:new({
      ui = mock_ui,
      showWidget = function(self, w)
        if w.name == "ImageViewer" or w.file then
          image_viewer_shown = true
        else
          shown_dialog = w
        end
      end,
    })

    local shot_name = "/tmp/test_shot.png"
    local caller_called = false
    s:onScreenshot(shot_name, function() caller_called = true end)

    assert.is_not_nil(shown_dialog)
    local buttons = shown_dialog.buttons

    -- Button 1: "Delete"
    buttons[1][1].callback()

    -- Button 2: "Set as book cover"
    buttons[1][2].callback()
    assert.is_true(custom_cover_set)

    -- Button 3: "View"
    buttons[2][1].callback()
    assert.is_true(image_viewer_shown)

    -- Button 4: "Set as wallpaper"
    buttons[2][2].callback()
    assert.are_equal("image_file", G_reader_settings:read("screensaver_type"))
    assert.are_equal(shot_name, G_reader_settings:read("screensaver_image"))
    G_reader_settings:save("screensaver_type", nil)
    G_reader_settings:save("screensaver_image", nil)

    -- tap_close_callback
    shown_dialog.tap_close_callback()
    assert.is_true(caller_called)

    -- Event handlers
    assert.is_true(s:onKeyPressShoot())
    assert.is_true(s:onTapDiagonal())
    assert.is_true(s:onSwipeDiagonal())
    s:onPhysicalKeyboardConnected()
  end)
end)
