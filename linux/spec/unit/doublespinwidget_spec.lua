describe("DoubleSpinWidget", function()
  local DoubleSpinWidget
  local UIManager
  local Geom
  local Device

  local orig_setDirty
  local orig_show
  local orig_close

  setup(function()
    require("commonrequire")
    DoubleSpinWidget = require("ui/widget/doublespinwidget")
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
      local dspin = DoubleSpinWidget:new({
        title_text = "Margins",
        left_value = 5,
        right_value = 10,
      })

      assert.are.equal("Margins", dspin.title_text)
      assert.are.equal(5, dspin.left_value)
      assert.are.equal(10, dspin.right_value)
      assert.truthy(dspin.width)
      assert.truthy(dspin.key_events.Exit)
      if Device:isTouchDevice() then
        assert.truthy(dspin.ges_events.TapClose)
      end
      assert.is_false(dspin:hasMoved())
    end)

    it("should handle custom unit and precision", function()
      local dspin = DoubleSpinWidget:new({
        title_text = "Angles",
        left_value = 45,
        right_value = 90,
        unit = "°",
      })

      assert.are.equal("%1d", dspin.left_precision)
      assert.are.equal("%1d", dspin.right_precision)
      assert.are.equal("°", dspin.unit)
    end)

    it("should handle is_range and default buttons formatting", function()
      local dspin_range = DoubleSpinWidget:new({
        title_text = "Page Range",
        left_value = 1,
        right_value = 10,
        left_default = 1,
        right_default = 100,
        is_range = true,
        unit = "p",
      })

      local btn_table = dspin_range.widget_frame[1][3][1]
      local default_btn = btn_table.buttons[1][1]
      assert.truthy(default_btn)
      default_btn.callback()

      -- Custom default_text
      local dspin_custom = DoubleSpinWidget:new({
        title_text = "Custom Defaults",
        left_default = 2,
        right_default = 4,
        default_text = "Reset to 2/4",
      })
      local default_custom_btn = dspin_custom.widget_frame[1][3][1].buttons[1][1]
      assert.are.equal("Reset to 2/4", default_custom_btn.text)
      default_custom_btn.callback()
    end)
  end)

  describe("buttons and callbacks", function()
    it("should handle extra button callback", function()
      local extra_left, extra_right = nil, nil

      local dspin = DoubleSpinWidget:new({
        title_text = "Extra Button",
        left_value = 10,
        right_value = 20,
        extra_text = "Swap",
        extra_callback = function(left, right)
          extra_left = left
          extra_right = right
        end,
        keep_shown_on_apply = true,
      })

      local btn_table = dspin.widget_frame[1][3][1]
      local extra_btn = btn_table.buttons[1][1]
      assert.are.equal("Swap", extra_btn.text)

      extra_btn.callback()
      assert.are.equal(10, extra_left)
      assert.are.equal(20, extra_right)
    end)

    it("should handle apply and cancel callbacks", function()
      local applied_left, applied_right = nil, nil
      local cancelled = false
      local closed = false

      local dspin = DoubleSpinWidget:new({
        title_text = "Apply/Cancel",
        left_value = 3,
        right_value = 7,
        callback = function(l, r)
          applied_left = l
          applied_right = r
        end,
        cancel_callback = function()
          cancelled = true
        end,
        close_callback = function()
          closed = true
        end,
      })

      -- Value changed -> Apply button enabled
      dspin:update(4, 8)
      local btn_table = dspin.widget_frame[1][3][1]
      local cancel_btn = btn_table.buttons[1][1]
      local apply_btn = btn_table.buttons[1][2]

      assert.is_true(apply_btn.enabled)
      apply_btn.callback()
      assert.are.equal(4, applied_left)
      assert.are.equal(8, applied_right)
      assert.is_true(closed)

      -- Cancel callback
      cancel_btn.callback()
      assert.is_true(cancelled)
    end)

    it("should support ok_always_enabled and keep_shown_on_apply", function()
      local dspin = DoubleSpinWidget:new({
        title_text = "Always Enabled",
        left_value = 5,
        right_value = 5,
        ok_always_enabled = true,
        keep_shown_on_apply = true,
        callback = function() end,
      })

      local btn_table = dspin.widget_frame[1][3][1]
      local apply_btn = btn_table.buttons[1][2]
      assert.is_true(apply_btn.enabled)

      apply_btn.callback()
      assert.are.equal(5, dspin.left_value)
    end)
  end)

  describe("lifecycle and movable state", function()
    it("should preserve movable offset and alpha across updates", function()
      local dspin = DoubleSpinWidget:new({
        title_text = "Movable",
        left_value = 1,
        right_value = 2,
      })

      dspin.movable.alpha = 0.75
      dspin.movable:setMovedOffset(Geom:new({ x = 15, y = 25 }))
      assert.is_true(dspin:hasMoved())

      dspin:update(3, 4)
      assert.are.equal(0.75, dspin.movable.alpha)
      local offset = dspin.movable:getMovedOffset()
      assert.are.equal(15, offset.x)
      assert.are.equal(25, offset.y)
    end)

    it("should handle onShow, onClose, and onTapClose", function()
      local dirty_called = false
      UIManager.setDirty = function()
        dirty_called = true
      end

      local dspin = DoubleSpinWidget:new({
        title_text = "Lifecycle",
        left_value = 1,
        right_value = 2,
      })

      assert.is_true(dspin:onShow())
      assert.is_true(dirty_called)

      dspin:onClose()

      -- Tap inside vs outside
      dspin.widget_frame.dimen = Geom:new({ x = 100, y = 100, w = 200, h = 200 })

      local inside_ev = { pos = Geom:new({ x = 150, y = 150, w = 1, h = 1 }) }
      assert.is_true(dspin:onTapClose(nil, inside_ev))

      local outside_ev = { pos = Geom:new({ x = 10, y = 10, w = 1, h = 1 }) }
      assert.is_true(dspin:onTapClose(nil, outside_ev))
    end)
  end)
end)
