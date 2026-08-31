describe("RadioButtonWidget", function()
  local RadioButtonWidget
  local UIManager
  local Geom
  local Device

  local orig_setDirty
  local orig_show
  local orig_close

  setup(function()
    require("commonrequire")
    RadioButtonWidget = require("ui/widget/radiobuttonwidget")
    UIManager = require("ui/uimanager")
    Geom = require("ui/geometry")
    Device = require("device")

    orig_setDirty = UIManager.setDirty
    orig_show = UIManager.show
    orig_close = UIManager.close
  end)

  before_each(function()
    UIManager.setDirty = function() end
    UIManager.show = function() end
    UIManager.close = function(_, widget)
      if widget and widget.onClose then
        widget:onClose()
      end
    end
  end)

  after_each(function()
    UIManager.setDirty = orig_setDirty
    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  describe("initialization and default indicators", function()
    it("should instantiate with default settings and default_provider star", function()
      local buttons = {
        { { text = "Option 1", provider = "opt1" } },
        { { text = "Option 2", provider = "opt2", checked = true } },
      }

      local widget = RadioButtonWidget:new({
        title_text = "Select Option",
        radio_buttons = buttons,
        default_provider = "opt1",
      })

      assert.are.equal("Select Option", widget.title_text)
      assert.truthy(widget.width)
      assert.truthy(widget.key_events.Exit)
      assert.truthy(widget.ges_events.TapClose)

      local row, col = widget:getButtonIndex("opt2")
      assert.are.equal(2, row)
      assert.are.equal(1, col)
      assert.is_false(widget:hasMoved())
    end)
  end)

  describe("buttons and callbacks", function()
    it("should execute ok_callback with selected provider and indices", function()
      local result_radio = nil
      local closed = false

      local buttons = {
        { { text = "Option A", provider = "a" } },
        { { text = "Option B", provider = "b", checked = true } },
      }

      local widget = RadioButtonWidget:new({
        title_text = "Radio Test",
        radio_buttons = buttons,
        callback = function(self)
          result_radio = self
        end,
        close_callback = function()
          closed = true
        end,
      })

      local btn_table = widget.widget_frame[1][3][1]
      local ok_btn = btn_table.buttons[1][2]
      ok_btn.callback()

      assert.truthy(result_radio)
      assert.are.equal("b", result_radio.provider)
      assert.are.equal(2, result_radio.row)
      assert.are.equal(1, result_radio.col)
      assert.is_true(closed)
    end)

    it("should execute extra button callback and cancel callback", function()
      local extra_called = false
      local cancelled = false

      local buttons = {
        { { text = "Choice", provider = "c" } },
      }

      local widget = RadioButtonWidget:new({
        title_text = "Extra Button Test",
        radio_buttons = buttons,
        extra_text = "Custom Action",
        extra_callback = function(self)
          extra_called = true
        end,
        cancel_callback = function()
          cancelled = true
        end,
        keep_shown_on_apply = true,
      })

      local btn_table = widget.widget_frame[1][3][1]
      local cancel_btn = btn_table.buttons[1][1]
      local extra_btn = btn_table.buttons[2][1]

      extra_btn.callback()
      assert.is_true(extra_called)

      cancel_btn.callback()
      assert.is_true(cancelled)
    end)
  end)

  describe("lifecycle and tap close", function()
    it("should handle onShow, onClose, and onTapClose", function()
      local dirty_called = false
      UIManager.setDirty = function()
        dirty_called = true
      end

      local buttons = { { { text = "Choice", provider = "c" } } }
      local widget = RadioButtonWidget:new({
        title_text = "Lifecycle Test",
        radio_buttons = buttons,
      })

      assert.is_true(widget:onShow())
      assert.is_true(dirty_called)

      widget:onClose()

      -- Tap inside vs outside
      widget.widget_frame.dimen = Geom:new({ x = 100, y = 100, w = 200, h = 200 })

      local inside_ev = { pos = Geom:new({ x = 150, y = 150, w = 1, h = 1 }) }
      assert.is_true(widget:onTapClose(nil, inside_ev))

      local outside_ev = { pos = Geom:new({ x = 10, y = 10, w = 1, h = 1 }) }
      assert.is_true(widget:onTapClose(nil, outside_ev))
    end)
  end)
end)
