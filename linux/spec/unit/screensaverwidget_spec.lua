describe("ScreenSaverWidget", function()
  local ScreenSaverWidget
  local Device
  local Geom
  local Screensaver
  local UIManager

  setup(function()
    require("commonrequire")
    ScreenSaverWidget = require("ui/widget/screensaverwidget")
    Device = require("device")
    Geom = require("ui/geometry")
    Screensaver = require("ui/screensaver")
    UIManager = require("ui/uimanager")
  end)

  it("should initialize ScreenSaverWidget and create frame", function()
    local orig_is_touch = Device.isTouchDevice
    Device.isTouchDevice = function() return true end

    local ssw = ScreenSaverWidget:new({
      background = 0,
    })

    assert.truthy(ssw.main_frame)
    assert.are.equal(ssw.main_frame, ssw[1])
    assert.is_true(ssw.dithered)
    assert.truthy(ssw.ges_events.Tap)

    Device.isTouchDevice = orig_is_touch
  end)

  it("should mark full dirty on show", function()
    local ssw = ScreenSaverWidget:new()

    local dirty_widget = nil
    local dirty_func = nil
    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, widget, func)
      dirty_widget = widget
      dirty_func = func
    end

    local res = ssw:onShow()
    assert.is_true(res)
    assert.are.equal(ssw, dirty_widget)
    assert.truthy(dirty_func)
    local mode, region = dirty_func()
    assert.are.equal("full", mode)
    assert.are.equal(ssw.main_frame.dimen, region)

    UIManager.setDirty = orig_setDirty
  end)

  it("should handle onTap when inside frame", function()
    local ssw = ScreenSaverWidget:new()
    local closed_widget = nil
    local orig_close = UIManager.close
    UIManager.close = function(self, widget)
      closed_widget = widget
    end

    local ges_inside = {
      pos = Geom:new({ x = 10, y = 10, w = 1, h = 1 }),
    }
    local res = ssw:onTap(nil, ges_inside)
    assert.is_true(res)
    assert.are.equal(ssw, closed_widget)

    closed_widget = nil
    local ges_outside = {
      pos = Geom:new({ x = 9999, y = 9999, w = 1, h = 1 }),
    }
    local res2 = ssw:onTap(nil, ges_outside)
    assert.is_true(res2)
    assert.is_nil(closed_widget)

    UIManager.close = orig_close
  end)

  it("should handle onExit, unscheduling delayed close if active", function()
    local ssw = ScreenSaverWidget:new()
    local unscheduled_task = nil
    local orig_unschedule = UIManager.unschedule
    UIManager.unschedule = function(self, task)
      unscheduled_task = task
    end

    local closed_widget = nil
    local orig_close = UIManager.close
    UIManager.close = function(self, widget)
      closed_widget = widget
    end

    Screensaver.delayed_close = true
    Screensaver.close_widget = function() end

    ssw:onExit()
    assert.are.equal(Screensaver.close_widget, unscheduled_task)
    assert.are.equal(ssw, closed_widget)

    Screensaver.delayed_close = nil
    Screensaver.close_widget = nil
    UIManager.unschedule = orig_unschedule
    UIManager.close = orig_close
  end)

  it("should handle onClose, restore rotation mode, refresh and broadcast event", function()
    local ssw = ScreenSaverWidget:new()

    local refreshed_mode = nil
    local orig_scheduleRefresh = UIManager.scheduleRefresh
    UIManager.scheduleRefresh = function(self, mode)
      refreshed_mode = mode
    end

    local broadcasted_event = nil
    local orig_broadcastEvent = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self, ev)
      broadcasted_event = ev
    end

    local cleanup_called = false
    local orig_cleanup = Screensaver.cleanup
    Screensaver.cleanup = function(self)
      cleanup_called = true
    end

    local restored_rotation = nil
    local orig_setRotationMode = Device.screen.setRotationMode
    Device.screen.setRotationMode = function(self, mode)
      restored_rotation = mode
    end

    Device.orig_rotation_mode = "portrait"

    ssw:onClose()

    assert.are.equal("portrait", restored_rotation)
    assert.is_nil(Device.orig_rotation_mode)
    assert.are.equal("full", refreshed_mode)
    assert.truthy(broadcasted_event)
    assert.are.equal("OutOfScreenSaver", broadcasted_event.type)
    assert.is_true(cleanup_called)

    UIManager.scheduleRefresh = orig_scheduleRefresh
    UIManager.broadcastEvent = orig_broadcastEvent
    Screensaver.cleanup = orig_cleanup
    Device.screen.setRotationMode = orig_setRotationMode
  end)

  it("should handle onResume and onSuspend flipping screen_saver_lock", function()
    local ssw = ScreenSaverWidget:new()

    ssw:onResume()
    assert.is_true(Device.screen_saver_lock)

    ssw:onSuspend()
    assert.is_false(Device.screen_saver_lock)
  end)
end)
