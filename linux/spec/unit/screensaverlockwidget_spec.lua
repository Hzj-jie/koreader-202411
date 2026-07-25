local spy = require("luassert.spy")
local stub = require("luassert.stub")

describe("ScreenSaverLockWidget", function()
  local ScreenSaverLockWidget
  local Device
  local UIManager
  local Screensaver
  local InfoMessage
  local old_screensaver_delay
  local old_touch_device
  local old_screensaver_widget

  setup(function()
    require("commonrequire")
    ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")
    Device = require("device")
    UIManager = require("ui/uimanager")
    Screensaver = require("ui/screensaver")
    InfoMessage = require("ui/widget/infomessage")
  end)

  before_each(function()
    old_screensaver_delay = G_reader_settings:read("screensaver_delay")
    old_touch_device = Device.isTouchDevice
    old_screensaver_widget = Screensaver.screensaver_widget
  end)

  after_each(function()
    G_reader_settings:save("screensaver_delay", old_screensaver_delay)
    Device.isTouchDevice = old_touch_device
    Screensaver.screensaver_widget = old_screensaver_widget
  end)

  it(
    "should initialize default tap gesture on touch device when gesture delay is not enabled",
    function()
      Device.isTouchDevice = function()
        return true
      end
      G_reader_settings:save("screensaver_delay", "off")

      local widget = ScreenSaverLockWidget:new({})
      assert.is_false(widget.is_infomessage_visible)
      assert.is_nil(widget.has_exit_screensaver_gesture)
      assert.is_not_nil(widget.ges_events.Tap)
    end
  )

  it("should not setup touch gestures on non-touch device", function()
    Device.isTouchDevice = function()
      return false
    end

    local widget = ScreenSaverLockWidget:new({})
    assert.is_false(widget.is_infomessage_visible)
    assert.is_nil(widget.ges_events.Tap)
  end)

  it(
    "should setup exit screensaver gestures when configured in ReaderUI",
    function()
      Device.isTouchDevice = function()
        return true
      end
      G_reader_settings:save("screensaver_delay", "gesture")

      local handler_called = false
      local dummy_handler = function(ev)
        handler_called = true
      end

      local ReaderUI = require("apps/reader/readerui")
      local old_instance = ReaderUI.instance
      ReaderUI.instance = {
        gestures = {
          gestures = {
            swipe_east = { exit_screensaver = true },
            multiswipe_nw = { exit_screensaver = true },
            multiswipe_se = { exit_screensaver = true },
            ignored_gesture = { other_action = true },
          },
        },
        _zones = {
          swipe_east = { gs_range = "range_east", handler = dummy_handler },
          multiswipe = { gs_range = "range_multi", handler = dummy_handler },
        },
      }

      local widget = ScreenSaverLockWidget:new({})
      assert.is_true(widget.has_exit_screensaver_gesture)
      assert.is_not_nil(widget.ges_events.swipe_east)
      assert.is_not_nil(widget.ges_events.multiswipe)

      -- Test event handler trigger
      local event_name = widget.ges_events.swipe_east.event
      assert.are.equal("TriggerExitScreensaver_swipe_east", event_name)
      assert.is_function(widget["on" .. event_name])
      local res = widget["on" .. event_name](widget, nil, {})
      assert.is_true(res)
      assert.is_true(handler_called)

      -- Test handleEvent override
      local event_handled = widget:handleEvent({ fake = "event" })
      assert.is_true(event_handled)

      ReaderUI.instance = old_instance
    end
  )

  it(
    "should setup exit screensaver gestures from FileManager when ReaderUI instance is nil",
    function()
      Device.isTouchDevice = function()
        return true
      end
      G_reader_settings:save("screensaver_delay", "gesture")

      local ReaderUI = require("apps/reader/readerui")
      local FileManager = require("apps/filemanager/filemanager")
      local old_rui_instance = ReaderUI.instance
      local old_fm_instance = FileManager.instance

      ReaderUI.instance = nil
      FileManager.instance = {
        gestures = {
          gestures = {
            tap_north = { exit_screensaver = true },
          },
        },
        _zones = {
          tap_north = {
            gs_range = "range_north",
            handler = function() end,
          },
        },
      }

      local widget = ScreenSaverLockWidget:new({})
      assert.is_true(widget.has_exit_screensaver_gesture)
      assert.is_not_nil(widget.ges_events.tap_north)

      ReaderUI.instance = old_rui_instance
      FileManager.instance = old_fm_instance
    end
  )

  it("should show wait for gesture message with appropriate text", function()
    stub(InfoMessage, "paintTo")
    stub(InfoMessage, "onShow")
    stub(InfoMessage, "free")

    local widget = ScreenSaverLockWidget:new({})

    -- Case A: with gesture configured
    widget.has_exit_screensaver_gesture = true
    widget:showWaitForGestureMessage()
    assert.is_true(widget.is_infomessage_visible)
    assert.stub(InfoMessage.paintTo).was_called()
    assert.stub(InfoMessage.onShow).was_called()
    assert.stub(InfoMessage.free).was_called()

    -- Case B: without gesture configured (tap to exit)
    widget.is_infomessage_visible = false
    widget.has_exit_screensaver_gesture = nil
    widget:showWaitForGestureMessage()
    assert.is_true(widget.is_infomessage_visible)

    InfoMessage.paintTo:revert()
    InfoMessage.onShow:revert()
    InfoMessage.free:revert()
  end)

  it("should handle onExit and close screensaver widget if present", function()
    stub(UIManager, "close")
    local mock_ss_widget = {
      onExit = spy.new(function() end),
    }
    Screensaver.screensaver_widget = mock_ss_widget

    local widget = ScreenSaverLockWidget:new({})
    local result = widget:onExit()

    assert.is_true(result)
    assert.stub(UIManager.close).was_called_with(UIManager, widget)
    assert.spy(mock_ss_widget.onExit).was_called()

    UIManager.close:revert()
  end)

  it("should handle onClose when screensaver widget is missing", function()
    stub(UIManager, "setDirty")
    stub(Screensaver, "cleanup")
    Screensaver.screensaver_widget = nil

    local widget = ScreenSaverLockWidget:new({})
    widget:onClose()

    assert.stub(UIManager.setDirty).was_called_with(UIManager, "all", "full")
    assert.stub(Screensaver.cleanup).was_called()

    UIManager.setDirty:revert()
    Screensaver.cleanup:revert()
  end)

  it("should handle onResume and onSuspend state changes", function()
    stub(UIManager, "setDirty")
    local widget = ScreenSaverLockWidget:new({})
    stub(widget, "showWaitForGestureMessage")

    widget:onResume()
    assert.is_true(Device.screen_saver_lock)
    assert.stub(widget.showWaitForGestureMessage).was_called()

    widget.is_infomessage_visible = true
    widget:onSuspend()
    assert.is_false(Device.screen_saver_lock)
    assert.is_false(widget.is_infomessage_visible)
    assert.stub(UIManager.setDirty).was_called_with(UIManager, "all", "full")

    UIManager.setDirty:revert()
  end)
end)
