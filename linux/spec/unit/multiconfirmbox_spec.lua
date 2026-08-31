describe("MultiConfirmBox", function()
  local MultiConfirmBox
  local UIManager
  local Geom
  local Device

  local orig_setDirty
  local orig_show
  local orig_close

  setup(function()
    require("commonrequire")
    MultiConfirmBox = require("ui/widget/multiconfirmbox")
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

  describe("initialization and structure", function()
    it("should instantiate with default settings", function()
      local box = MultiConfirmBox:new({
        text = "Do you want to proceed?",
      })

      assert.are.equal("Do you want to proceed?", box.text)
      assert.is_true(box.modal)
      assert.is_true(box.dismissable)
      assert.truthy(box.key_events.Exit)
      if Device:isTouchDevice() then
        assert.truthy(box.ges_events.TapClose)
      end
      assert.truthy(box[1]) -- CenterContainer
      assert.truthy(box[1][1]) -- MovableContainer
    end)

    it("should handle non-dismissable configuration", function()
      local box = MultiConfirmBox:new({
        text = "Mandatory choice",
        dismissable = false,
      })

      assert.is_false(box.dismissable)
      assert.is_nil(box.key_events.Exit)
      assert.is_nil(box.ges_events.TapClose)
    end)
  end)

  describe("button callbacks and actions", function()
    it("should execute cancel button callback and close widget", function()
      local cancel_called = false
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local box = MultiConfirmBox:new({
        text = "Confirm action",
        cancel_callback = function()
          cancel_called = true
        end,
      })

      -- Button table is in VerticalGroup inside FrameContainer inside MovableContainer
      local button_table = box[1][1][1][1][3]
      assert.truthy(button_table)

      local cancel_btn = button_table.buttons[1][1]
      assert.are.equal(box.cancel_text, cancel_btn.text)
      cancel_btn.callback()

      assert.is_true(cancel_called)
      assert.is_true(closed)
    end)

    it("should execute choice1 and choice2 callbacks with custom labels", function()
      local choice1_called = false
      local choice2_called = false
      local closed_count = 0
      UIManager.close = function(_, widget)
        closed_count = closed_count + 1
      end

      local box = MultiConfirmBox:new({
        text = "Font selection",
        choice1_text = "Default Font",
        choice1_callback = function()
          choice1_called = true
        end,
        choice2_text = "Fallback Font",
        choice2_callback = function()
          choice2_called = true
        end,
      })

      local button_table = box[1][1][1][1][3]
      local choice1_btn = button_table.buttons[1][2]
      local choice2_btn = button_table.buttons[1][3]

      assert.are.equal("Default Font", choice1_btn.text)
      choice1_btn.callback()
      assert.is_true(choice1_called)
      assert.are.equal(1, closed_count)

      assert.are.equal("Fallback Font", choice2_btn.text)
      choice2_btn.callback()
      assert.is_true(choice2_called)
      assert.are.equal(2, closed_count)
    end)

    it("should support dynamic text functions and enabled states for choices", function()
      local box = MultiConfirmBox:new({
        text = "Dynamic test",
        choice1_text_func = function()
          return "Dynamic Choice 1"
        end,
        choice1_enabled = false,
        choice2_text_func = function()
          return "Dynamic Choice 2"
        end,
        choice2_enabled = true,
      })

      local button_table = box[1][1][1][1][3]
      local choice1_btn = button_table.buttons[1][2]
      local choice2_btn = button_table.buttons[1][3]

      assert.truthy(choice1_btn.text_func)
      assert.is_false(choice1_btn.enabled)
      assert.truthy(choice2_btn.text_func)
      assert.is_true(choice2_btn.enabled)
    end)
  end)

  describe("lifecycle and event handlers", function()
    it("should handle onShow and onClose setting dirty regions", function()
      local dirty_regions = {}
      UIManager.setDirty = function(_, fn)
        if fn then
          local _, region = fn()
          table.insert(dirty_regions, region)
        end
      end

      local box = MultiConfirmBox:new({
        text = "Lifecycle test",
      })

      box:onShow()
      assert.are.equal(1, #dirty_regions)

      box:onClose()
      assert.are.equal(2, #dirty_regions)
    end)

    it("should handle onExit", function()
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local box = MultiConfirmBox:new({
        text = "Exit test",
      })

      assert.is_true(box:onExit())
      assert.is_true(closed)
    end)

    it("should handle onTapClose dismissing when tapped outside and ignoring inside", function()
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local box = MultiConfirmBox:new({
        text = "Tap test",
      })

      box[1][1].dimen = Geom:new({ x = 100, y = 100, w = 200, h = 200 })

      -- Tap inside MovableContainer
      local inside_ev = { pos = Geom:new({ x = 150, y = 150, w = 1, h = 1 }) }
      assert.is_false(box:onTapClose(nil, inside_ev))
      assert.is_false(closed)

      -- Tap outside MovableContainer
      local outside_ev = { pos = Geom:new({ x = 10, y = 10, w = 1, h = 1 }) }
      assert.is_true(box:onTapClose(nil, outside_ev))
      assert.is_true(closed)
    end)
  end)
end)
