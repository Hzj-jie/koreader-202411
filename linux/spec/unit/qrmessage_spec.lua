describe("QRMessage", function()
  local QRMessage
  local UIManager
  local Device

  local orig_setDirty
  local orig_show
  local orig_close
  local orig_scheduleIn
  local orig_unschedule

  setup(function()
    require("commonrequire")
    QRMessage = require("ui/widget/qrmessage")
    UIManager = require("ui/uimanager")
    Device = require("device")

    orig_setDirty = UIManager.setDirty
    orig_show = UIManager.show
    orig_close = UIManager.close
    orig_scheduleIn = UIManager.scheduleIn
    orig_unschedule = UIManager.unschedule
  end)

  before_each(function()
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

  describe("initialization and structure", function()
    it("should instantiate QRMessage widget", function()
      local qrmsg = QRMessage:new({
        text = "https://koreader.rocks",
        width = 300,
        height = 300,
      })

      assert.is_true(qrmsg.modal)
      assert.truthy(qrmsg.key_events.AnyKeyPressed)
      if Device:isTouchDevice() then
        assert.truthy(qrmsg.ges_events.TapClose)
      end
      assert.truthy(qrmsg[1])
    end)
  end)

  describe("lifecycle and timers", function()
    it("should handle onShow and auto-timeout", function()
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local scheduled_fn = nil
      UIManager.scheduleIn = function(_, delay, fn)
        scheduled_fn = fn
      end

      local qrmsg = QRMessage:new({
        text = "Timeout QR",
        timeout = 5,
      })

      assert.is_true(qrmsg:onShow())
      assert.truthy(scheduled_fn)

      scheduled_fn()
      assert.is_true(closed)
    end)

    it("should handle onClose with dismiss_callback and unschedule", function()
      local unscheduled = false
      local dismissed = false
      UIManager.unschedule = function(_, fn)
        unscheduled = true
      end
      UIManager.scheduleIn = function(_, delay, fn) end

      local qrmsg = QRMessage:new({
        text = "Early close QR",
        timeout = 5,
        dismiss_callback = function()
          dismissed = true
        end,
      })

      qrmsg:onShow()
      assert.truthy(qrmsg._timeout_func)

      qrmsg:onClose()
      assert.is_true(unscheduled)
      assert.is_nil(qrmsg._timeout_func)
      assert.is_true(dismissed)
    end)

    it("should handle onTapClose and onAnyKeyPressed", function()
      local closed_count = 0
      UIManager.close = function(_, widget)
        closed_count = closed_count + 1
      end

      local qrmsg = QRMessage:new({
        text = "Dismiss QR",
      })

      qrmsg:onTapClose()
      assert.are.equal(1, closed_count)

      qrmsg:onAnyKeyPressed()
      assert.are.equal(2, closed_count)
    end)
  end)
end)
