describe("ConfirmBox", function()
  local ConfirmBox
  local UIManager
  local Geom
  local Device

  local orig_setDirty
  local orig_show
  local orig_close
  local orig_scheduleIn
  local orig_unschedule

  setup(function()
    require("commonrequire")
    ConfirmBox = require("ui/widget/confirmbox")
    UIManager = require("ui/uimanager")
    Geom = require("ui/geometry")
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
    UIManager.close = function() end
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
    it("should instantiate with default settings", function()
      local box = ConfirmBox:new({
        text = "Are you sure?",
      })

      assert.are.equal("Are you sure?", box.text)
      assert.is_true(box.modal)
      assert.is_true(box.dismissable)
      assert.truthy(box.key_events.Exit)
      if Device:isTouchDevice() then
        assert.truthy(box.ges_events.TapClose)
      end
      assert.truthy(box.movable)
    end)

    it("should handle non-dismissable configuration", function()
      local box = ConfirmBox:new({
        text = "Required confirmation",
        dismissable = false,
      })

      assert.is_false(box.dismissable)
      assert.is_nil(box.key_events.Exit)
      assert.is_nil(box.ges_events.TapClose)
    end)

    it("should handle no_ok_button configuration", function()
      local box = ConfirmBox:new({
        text = "Alert message",
        no_ok_button = true,
      })

      local btn_table = box[1][1][1][1][3]
      assert.are.equal(1, #btn_table.buttons[1])
      assert.are.equal(box.cancel_text, btn_table.buttons[1][1].text)
    end)
  end)

  describe("button callbacks and other_buttons", function()
    it("should execute ok_callback and close dialog", function()
      local ok_called = false
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local box = ConfirmBox:new({
        text = "Proceed?",
        ok_callback = function()
          ok_called = true
        end,
      })

      local btn_table = box[1][1][1][1][3]
      local ok_btn = btn_table.buttons[1][2]
      ok_btn.callback()

      assert.is_true(ok_called)
      assert.is_true(closed)
    end)

    it("should execute cancel_callback and close dialog", function()
      local cancel_called = false
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local box = ConfirmBox:new({
        text = "Cancel test",
        cancel_callback = function()
          cancel_called = true
        end,
      })

      local btn_table = box[1][1][1][1][3]
      local cancel_btn = btn_table.buttons[1][1]
      cancel_btn.callback()

      assert.is_true(cancel_called)
      assert.is_true(closed)
    end)

    it("should handle keep_dialog_open = true", function()
      local ok_called = false
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local box = ConfirmBox:new({
        text = "Keep open",
        keep_dialog_open = true,
        ok_callback = function()
          ok_called = true
        end,
      })

      local btn_table = box[1][1][1][1][3]
      local ok_btn = btn_table.buttons[1][2]
      ok_btn.callback()

      assert.is_true(ok_called)
      assert.is_false(closed)
    end)

    it("should support other_buttons rows placed before or after default buttons", function()
      local other1_called = false
      local other2_called = false

      -- other_buttons_first = false
      local box_after = ConfirmBox:new({
        text = "Other buttons after",
        other_buttons = {
          {
            { text = "Custom 1", callback = function() other1_called = true end },
          },
        },
      })
      local btn_table_after = box_after[1][1][1][1][3]
      assert.are.equal(2, #btn_table_after.buttons)
      btn_table_after.buttons[2][1].callback()
      assert.is_true(other1_called)

      -- other_buttons_first = true
      local box_before = ConfirmBox:new({
        text = "Other buttons before",
        other_buttons_first = true,
        other_buttons = {
          {
            { text = "Custom 2", callback = function() other2_called = true end },
          },
        },
      })
      local btn_table_before = box_before[1][1][1][1][3]
      assert.are.equal(2, #btn_table_before.buttons)
      btn_table_before.buttons[1][1].callback()
      assert.is_true(other2_called)
    end)
  end)

  describe("widget extension and lifecycle", function()
    it("should add custom widgets with addWidget", function()
      local TextWidget = require("ui/widget/textwidget")
      local custom_widget = TextWidget:new({ text = "Extra info row" })

      local box = ConfirmBox:new({
        text = "Base text",
      })

      box:addWidget(custom_widget)
      assert.truthy(box._added_widgets)
      assert.are.equal(1, #box._added_widgets)
      assert.truthy(box:getAddedWidgetAvailableWidth())
    end)

    it("should handle onShow and onClose with active instances tracking and timeouts", function()
      local scheduled_fn = nil
      UIManager.scheduleIn = function(_, delay, fn)
        scheduled_fn = fn
      end

      local box = ConfirmBox:new({
        text = "Timeout box",
        timeout = 3,
      })

      box:onShow()
      assert.truthy(box._timeout_func)

      box:onClose()
      assert.is_nil(box._timeout_func)
    end)

    it("should handle onExit and onTapClose", function()
      local cancel_called = false
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local box = ConfirmBox:new({
        text = "Tap test",
        cancel_callback = function()
          cancel_called = true
        end,
      })

      box.movable.dimen = Geom:new({ x = 100, y = 100, w = 200, h = 200 })

      -- Tap inside
      local inside_ev = { pos = Geom:new({ x = 150, y = 150, w = 1, h = 1 }) }
      assert.is_true(box:onTapClose(nil, inside_ev))
      assert.is_false(closed)

      -- Tap outside
      local outside_ev = { pos = Geom:new({ x = 10, y = 10, w = 1, h = 1 }) }
      assert.is_true(box:onTapClose(nil, outside_ev))
      assert.is_true(closed)
      assert.is_true(cancel_called)
    end)
  end)
end)
