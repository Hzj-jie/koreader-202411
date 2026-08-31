describe("Notification", function()
  local Notification
  local UIManager
  local Event
  local Device
  local time

  local orig_setDirty
  local orig_show
  local orig_close
  local orig_scheduleIn
  local orig_unschedule

  setup(function()
    require("commonrequire")
    Notification = require("ui/widget/notification")
    UIManager = require("ui/uimanager")
    Event = require("ui/event")
    Device = require("device")
    time = require("ui/time")

    orig_setDirty = UIManager.setDirty
    orig_show = UIManager.show
    orig_close = UIManager.close
    orig_scheduleIn = UIManager.scheduleIn
    orig_unschedule = UIManager.unschedule
  end)

  before_each(function()
    Notification._shown_list = {}
    UIManager.setDirty = function() end
    UIManager.show = function() end
    UIManager.close = function(_, widget)
      if widget and widget.onClose then
        widget:onClose()
      end
    end
    UIManager.scheduleIn = function(_, delay, fn)
      if fn then
        fn()
      end
    end
    UIManager.unschedule = function() end
  end)

  after_each(function()
    UIManager.setDirty = orig_setDirty
    UIManager.show = orig_show
    UIManager.close = orig_close
    UIManager.scheduleIn = orig_scheduleIn
    UIManager.unschedule = orig_unschedule
  end)

  describe("initialization and stacking", function()
    it("should instantiate toast notification by default", function()
      local notif = Notification:new({
        text = "Hello World",
      })

      assert.are.equal("Hello World", notif.text)
      assert.is_true(notif.toast)
      assert.are.equal(1, notif._shown_idx)
      assert.are.equal(1, #Notification._shown_list)
      assert.truthy(notif.frame)
      assert.is_true(notif:isAlwaysOnTop())

      notif:onClose()
      assert.are.equal(0, #Notification._shown_list)
    end)

    it("should stack multiple notifications vertically", function()
      local notif1 = Notification:new({ text = "First" })
      local notif2 = Notification:new({ text = "Second" })
      local notif3 = Notification:new({ text = "Third" })

      assert.are.equal(1, notif1._shown_idx)
      assert.are.equal(2, notif2._shown_idx)
      assert.are.equal(3, notif3._shown_idx)
      assert.are.equal(3, #Notification._shown_list)

      -- Closing middle notification sets slot to false
      notif2:onClose()
      assert.are.equal(3, #Notification._shown_list)
      assert.is_false(Notification._shown_list[2])

      -- Closing tail notification trims the tail
      notif3:onClose()
      assert.are.equal(1, #Notification._shown_list)

      notif1:onClose()
      assert.are.equal(0, #Notification._shown_list)
    end)

    it("should instantiate non-toast notification with key and tap events", function()
      local notif = Notification:new({
        text = "Non-toast message",
        toast = false,
      })

      assert.is_false(notif.toast)
      assert.truthy(notif.key_events.AnyKeyPressed)
      if Device:isTouchDevice() then
        assert.truthy(notif.ges_events.TapClose)
      end

      notif:onClose()
    end)

    it("should clean expired entries (> 30s) during stack cleanup", function()
      table.insert(Notification._shown_list, time.monotonic() - 35)
      table.insert(Notification._shown_list, time.monotonic() - 31)

      local notif = Notification:new({ text = "Fresh" })
      assert.are.equal(1, notif._shown_idx)
      assert.are.equal(1, #Notification._shown_list)
      notif:onClose()
    end)
  end)

  describe("lifecycle and timer events", function()
    it("should handle onShow and schedule timeout callback", function()
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local scheduled_fn = nil
      UIManager.scheduleIn = function(_, delay, fn)
        scheduled_fn = fn
      end

      local notif = Notification:new({
        text = "Timeout test",
        timeout = 3,
      })

      assert.is_true(notif:onShow())
      assert.truthy(scheduled_fn)

      scheduled_fn()
      assert.is_true(closed)
    end)

    it("should unschedule timeout when closed early", function()
      local unscheduled = false
      UIManager.unschedule = function(_, fn)
        unscheduled = true
      end
      UIManager.scheduleIn = function(_, delay, fn) end

      local notif = Notification:new({
        text = "Early close",
        timeout = 5,
      })
      notif:onShow()
      assert.truthy(notif._timeout_func)

      notif:onClose()
      assert.is_true(unscheduled)
      assert.is_nil(notif._timeout_func)
    end)

    it("should support notify helper method", function()
      local shown_widget = nil
      local notif = Notification:new({ text = "Parent" })
      notif.showWidget = function(self, widget)
        shown_widget = widget
      end

      notif:notify("Child popup")
      assert.truthy(shown_widget)
      assert.are.equal("Child popup", shown_widget.text)
    end)
  end)

  describe("event handling and toast interception", function()
    it("should dismiss toast on user input event and let event propagate", function()
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local notif = Notification:new({
        text = "Toast dismiss",
        toast = true,
      })

      local tap_ev = Event:new("Tap")
      tap_ev.isUserInput = function()
        return true
      end

      local handled = notif:handleEvent(tap_ev)
      assert.is_false(handled)
      assert.is_true(closed)
    end)

    it("should pass non-user input events to InputContainer for toast", function()
      local notif = Notification:new({
        text = "Toast pass",
        toast = true,
      })

      local dummy_ev = Event:new("DummyCustomEvent")
      dummy_ev.isUserInput = function()
        return false
      end

      local handled = notif:handleEvent(dummy_ev)
      assert.is_false(handled or false)
    end)

    it("should handle onTapClose and onAnyKeyPressed", function()
      local closed_count = 0
      UIManager.close = function(_, widget)
        closed_count = closed_count + 1
      end

      local notif = Notification:new({
        text = "Manual close",
        toast = false,
      })

      assert.is_true(notif:onTapClose())
      assert.are.equal(1, closed_count)

      assert.is_true(notif:onAnyKeyPressed())
      assert.are.equal(2, closed_count)
    end)

    it("should consume background events onIgnoreTouchInput and aliases", function()
      local notif = Notification:new({ text = "Ignore" })

      assert.is_true(notif:onIgnoreTouchInput())
      assert.is_true(notif:onResume())
      assert.is_true(notif:onPhysicalKeyboardDisconnected())
      assert.is_true(notif:onInput())
    end)
  end)
end)
