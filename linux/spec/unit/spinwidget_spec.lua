describe("SpinWidget", function()
  local SpinWidget
  local UIManager
  local Geom
  local Device

  local orig_setDirty
  local orig_show
  local orig_close

  setup(function()
    require("commonrequire")
    SpinWidget = require("ui/widget/spinwidget")
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

  describe("initialization and sizing", function()
    it("should instantiate with default settings", function()
      local spin = SpinWidget:new({
        title_text = "Volume",
        value = 5,
        value_min = 0,
        value_max = 10,
      })

      assert.are.equal("Volume", spin.title_text)
      assert.are.equal(5, spin.value)
      assert.are.equal(5, spin.original_value)
      assert.truthy(spin.width)
      assert.truthy(spin.key_events.Exit)
      if Device:isTouchDevice() then
        assert.truthy(spin.ges_events.TapClose)
      end
      assert.is_false(spin:hasMoved())
      assert.truthy(spin:getAddedWidgetAvailableWidth())
    end)

    it("should handle custom unit and precision", function()
      local spin = SpinWidget:new({
        title_text = "Temperature",
        value = 20,
        unit = "°",
      })

      assert.are.equal("%1d", spin.precision)
      assert.are.equal("°", spin.unit)
    end)

    it("should handle value_table initialization", function()
      local spin = SpinWidget:new({
        title_text = "Speed",
        value_table = { "Slow", "Normal", "Fast" },
        value_index = 2,
      })

      assert.are.equal("Normal", spin.original_value)
      assert.are.equal(2, spin.value_index)
    end)
  end)

  describe("buttons and callbacks", function()
    it("should handle default button with value and value_table", function()
      local spin_num = SpinWidget:new({
        title_text = "Number with Default",
        value = 8,
        default_value = 5,
        unit = "pt",
      })

      assert.truthy(spin_num.vgroup)
      -- Update picker value and reset to default
      spin_num:update(10)
      local ok_cancel_buttons = spin_num.vgroup[3][1]
      local default_btn = ok_cancel_buttons.buttons[1][1]
      assert.truthy(default_btn)
      default_btn.callback()

      -- Test default button with value_table and default_text
      local spin_tbl = SpinWidget:new({
        title_text = "Table with Default",
        value_table = { "Small", "Medium", "Large" },
        value_index = 3,
        default_value = 2,
        default_text = "Medium size",
      })
      local default_tbl_btn = spin_tbl.vgroup[3][1].buttons[1][1]
      default_tbl_btn.callback()
    end)

    it("should handle extra and option buttons", function()
      local extra_called = false
      local option_called = false

      local spin = SpinWidget:new({
        title_text = "Extra & Option",
        value = 5,
        extra_text = "Extra Action",
        extra_callback = function(self)
          extra_called = true
        end,
        option_text = "Option Action",
        option_callback = function(self)
          option_called = true
        end,
        keep_shown_on_apply = true,
      })

      local btn_table = spin.vgroup[3][1]
      -- Row 1: extra, option. Row 2: close, apply.
      local extra_btn = btn_table.buttons[1][1]
      local option_btn = btn_table.buttons[1][2]

      assert.are.equal("Extra Action", extra_btn.text)
      extra_btn.callback()
      assert.is_true(extra_called)

      assert.are.equal("Option Action", option_btn.text)
      option_btn.callback()
      assert.is_true(option_called)
    end)

    it("should handle single extra or single option button", function()
      local spin1 = SpinWidget:new({
        title_text = "Only Extra",
        value = 1,
        extra_text = "Extra",
        extra_callback = function() end,
      })
      assert.truthy(spin1.vgroup[3][1].buttons[1][1])

      local spin2 = SpinWidget:new({
        title_text = "Only Option",
        value = 1,
        option_text = "Option",
        option_callback = function() end,
      })
      assert.truthy(spin2.vgroup[3][1].buttons[1][1])
    end)

    it("should handle apply and cancel callbacks", function()
      local applied_val = nil
      local cancelled = false
      local closed = false

      local spin = SpinWidget:new({
        title_text = "Apply/Cancel",
        value = 3,
        callback = function(self)
          applied_val = self.value
        end,
        cancel_callback = function()
          cancelled = true
        end,
        close_callback = function()
          closed = true
        end,
      })

      -- Value changed to 7 -> Apply button enabled
      spin:update(7)
      local btn_table = spin.vgroup[3][1]
      local cancel_btn = btn_table.buttons[1][1]
      local apply_btn = btn_table.buttons[1][2]

      assert.is_true(apply_btn.enabled)
      apply_btn.callback()
      assert.are.equal(7, applied_val)
      assert.is_true(closed)

      -- Cancel callback
      cancel_btn.callback()
      assert.is_true(cancelled)
    end)

    it("should support ok_always_enabled and keep_shown_on_apply", function()
      local update_called = false
      local spin = SpinWidget:new({
        title_text = "Always Enabled",
        value = 5,
        ok_always_enabled = true,
        keep_shown_on_apply = true,
        callback = function() end,
      })

      local btn_table = spin.vgroup[3][1]
      local apply_btn = btn_table.buttons[1][2]
      assert.is_true(apply_btn.enabled)

      apply_btn.callback()
      assert.are.equal(5, spin.original_value)
    end)
  end)

  describe("widget extension and lifecycle", function()
    it("should add custom widgets and persist across updates", function()
      local TextWidget = require("ui/widget/textwidget")
      local custom_text = TextWidget:new({ text = "Custom Description" })

      local spin = SpinWidget:new({
        title_text = "AddWidget Test",
        value = 1,
      })

      spin:addWidget(custom_text)
      assert.truthy(spin._added_widgets)
      assert.are.equal(1, #spin._added_widgets)

      -- Update should re-add custom widget
      spin:update(2)
      assert.are.equal(1, #spin._added_widgets)
    end)

    it("should preserve movable offset and alpha", function()
      local spin = SpinWidget:new({
        title_text = "Movable Test",
        value = 1,
      })

      spin.movable.alpha = 0.8
      spin.movable:setMovedOffset(Geom:new({ x = 20, y = 30 }))
      assert.is_true(spin:hasMoved())

      spin:update(2)
      assert.are.equal(0.8, spin.movable.alpha)
      local offset = spin.movable:getMovedOffset()
      assert.are.equal(20, offset.x)
      assert.are.equal(30, offset.y)
    end)

    it("should handle onShow, onClose, and onTapClose", function()
      local dirty_called = false
      UIManager.setDirty = function()
        dirty_called = true
      end

      local spin = SpinWidget:new({
        title_text = "Lifecycle",
        value = 1,
      })

      assert.is_true(spin:onShow())
      assert.is_true(dirty_called)

      spin:onClose()

      -- Tap inside vs outside
      spin.spin_frame.dimen = Geom:new({ x = 100, y = 100, w = 200, h = 200 })

      local inside_ev = { pos = Geom:new({ x = 150, y = 150, w = 1, h = 1 }) }
      assert.is_true(spin:onTapClose(nil, inside_ev))

      local outside_ev = { pos = Geom:new({ x = 10, y = 10, w = 1, h = 1 }) }
      assert.is_true(spin:onTapClose(nil, outside_ev))
    end)
  end)
end)
