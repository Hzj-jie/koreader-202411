describe("InfoMessage", function()
  local InfoMessage
  local UIManager
  local Device
  local Font

  local orig_setDirty
  local orig_show
  local orig_close
  local orig_scheduleIn
  local orig_unschedule

  setup(function()
    require("commonrequire")
    InfoMessage = require("ui/widget/infomessage")
    UIManager = require("ui/uimanager")
    Device = require("device")
    Font = require("ui/font")

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

  describe("initialization and widget layout", function()
    it("should instantiate with default settings", function()
      local msg = InfoMessage:new({
        text = "Hello informational message",
      })

      assert.are.equal("Hello informational message", msg.text)
      assert.is_true(msg.modal)
      assert.is_true(msg.dismissable)
      assert.is_true(msg.show_icon)
      assert.truthy(msg.key_events.AnyKeyPressed)
      if Device:isTouchDevice() then
        assert.truthy(msg.ges_events.TapClose)
      end
      assert.truthy(msg.movable)
    end)

    it("should support monospace font option", function()
      local msg = InfoMessage:new({
        text = "Code snippet",
        monospace_font = true,
      })

      assert.is_true(msg.monospace_font)
      assert.truthy(msg.face)
    end)

    it("should support hiding icon", function()
      local msg = InfoMessage:new({
        text = "No icon message",
        show_icon = false,
      })

      assert.is_false(msg.show_icon)
    end)

    it("should support custom image widget", function()
      local dummy_bb = setmetatable({
        free = function() end,
        getType = function() return "bb" end,
        getWidth = function() return 32 end,
        getHeight = function() return 32 end,
      }, {
        __index = function() return function() end end,
      })

      local msg = InfoMessage:new({
        text = "Custom image",
        image = dummy_bb,
        image_width = 32,
        image_height = 32,
      })

      assert.truthy(msg.image)
    end)

    it("should instantiate with explicit height using ScrollTextWidget", function()
      local msg = InfoMessage:new({
        text = "Long scrollable message",
        height = 300,
      })

      assert.are.equal(300, msg.height)
    end)

    it("should handle custom width", function()
      local msg = InfoMessage:new({
        text = "Width test",
        width = 250,
      })

      assert.are.equal(250, msg.width)
    end)

    it("should handle non-dismissable configuration", function()
      local msg = InfoMessage:new({
        text = "Non dismissable",
        dismissable = false,
      })

      assert.is_false(msg.dismissable)
      assert.is_nil(msg.key_events.AnyKeyPressed)
      assert.is_nil(msg.ges_events.TapClose)
    end)
  end)

  describe("lifecycle and timers", function()
    it("should handle onShow and schedule timeout callback", function()
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local scheduled_fn = nil
      UIManager.scheduleIn = function(_, delay, fn)
        scheduled_fn = fn
      end

      local msg = InfoMessage:new({
        text = "Auto closing message",
        timeout = 2,
      })

      assert.is_true(msg:onShow())
      assert.truthy(scheduled_fn)

      scheduled_fn()
      assert.is_true(closed)
    end)

    it("should unschedule timeout and execute dismiss_callback on onClose", function()
      local unscheduled = false
      local dismissed = false
      UIManager.unschedule = function(_, fn)
        unscheduled = true
      end
      UIManager.scheduleIn = function(_, delay, fn) end

      local msg = InfoMessage:new({
        text = "Early close message",
        timeout = 5,
        dismiss_callback = function()
          dismissed = true
        end,
      })

      msg:onShow()
      assert.truthy(msg._timeout_func)

      msg:onClose()
      assert.is_true(unscheduled)
      assert.is_nil(msg._timeout_func)
      assert.is_true(dismissed)
    end)

    it("should handle onTapClose and onAnyKeyPressed", function()
      local closed_count = 0
      UIManager.close = function(_, widget)
        closed_count = closed_count + 1
      end

      local msg = InfoMessage:new({
        text = "Tap to close",
      })

      assert.is_true(msg:onTapClose())
      assert.are.equal(1, closed_count)

      assert.is_true(msg:onAnyKeyPressed())
      assert.are.equal(2, closed_count)
    end)

    it("should handle readonly mode on tap close", function()
      local msg = InfoMessage:new({
        text = "Readonly",
        readonly = true,
      })

      assert.is_nil(msg:onTapClose())
    end)
  end)
end)
