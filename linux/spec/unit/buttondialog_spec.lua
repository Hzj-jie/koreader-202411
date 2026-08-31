describe("ButtonDialog", function()
  local ButtonDialog
  local mock_device
  local UIManager

  setup(function()
    require("commonrequire")

    mock_device = {
      hasKeys = function()
        return true
      end,
      isAndroid = function()
        return false
      end,
      isKindle = function()
        return false
      end,
      isTouchDevice = function()
        return true
      end,
      hasDPad = function()
        return false
      end,
      hasKeyboard = function()
        return false
      end,
      input = {
        group = {
          Dismiss = { "MockDismissKey" },
        },
      },
      screen = {
        getSize = function()
          return { w = 600, h = 800 }
        end,
        getWidth = function()
          return 600
        end,
        getHeight = function()
          return 800
        end,
        scaleBySize = function(self, v)
          return v
        end,
        scaleByDPI = function(self, v)
          return v
        end,
      },
    }
    package.loaded["device"] = mock_device

    UIManager = {
      setDirty = spy.new(function() end),
    }
    package.loaded["ui/uimanager"] = UIManager

    package.loaded["ui/widget/buttondialog"] = nil
    ButtonDialog = require("ui/widget/buttondialog")
  end)

  teardown(function()
    package.loaded["device"] = nil
    package.loaded["ui/uimanager"] = nil
  end)

  it(
    "should map page buttons to Exit event when dismissable is true",
    function()
      local dialog = ButtonDialog:new({
        buttons = { { text = "Test", id = "test" } },
        dismissable = true,
      })

      local exit_keys = dialog.key_events.Exit[1][1]
      assert.truthy(exit_keys)

      assert.are.equal(mock_device.input.group.Dismiss, exit_keys)
    end
  )

  it(
    "should NOT map page buttons to Exit event when dismissable is false",
    function()
      local dialog = ButtonDialog:new({
        buttons = { { text = "Test", id = "test" } },
        dismissable = false,
      })

      assert.is_nil(dialog.key_events.Exit)
    end
  )

  it("should be modal by default", function()
    local dialog = ButtonDialog:new({
      buttons = { { { text = "Test", id = "test" } } },
    })
    assert.is_true(dialog.modal)
  end)

  describe("titles, button queries, and scrollable container", function()
    it("should instantiate with title and info style", function()
      local dialog = ButtonDialog:new({
        title = "Info Title",
        use_info_style = true,
        buttons = {
          {
            { text = "Btn 1", id = "btn1", callback = function() end },
            { text = "Btn 2", id = "btn2", callback = function() end },
          },
        },
      })

      assert.are.equal("Info Title", dialog.title)
      assert.truthy(dialog:getButtonById("btn1"))
      assert.truthy(dialog:getContentSize())
    end)

    it("should instantiate with title and bold title style", function()
      local dialog = ButtonDialog:new({
        title = "Bold Title",
        use_info_style = false,
        buttons = {
          {
            { text = "Action", id = "act" },
          },
        },
      })

      assert.are.equal("Bold Title", dialog.title)
    end)

    it("should wrap buttons in ScrollableContainer when height exceeds max_height", function()
      local many_rows = {}
      for i = 1, 30 do
        table.insert(many_rows, {
          { text = "Row " .. i, id = "row" .. i, callback = function() end },
        })
      end

      local dialog = ButtonDialog:new({
        title = "Scrollable Dialog",
        rows_per_page = { 10, 5 },
        buttons = many_rows,
      })

      assert.truthy(dialog.cropping_widget)
      assert.truthy(dialog:getScrolledOffset())

      -- Test setScrolledOffset
      dialog:setScrolledOffset({ x = 0, y = 100 })

      -- Test _onPageScrollToRow
      dialog:_onPageScrollToRow(5)
    end)

    it("should support numeric rows_per_page", function()
      local many_rows = {}
      for i = 1, 20 do
        table.insert(many_rows, {
          { text = "Item " .. i, id = "item" .. i },
        })
      end

      local dialog = ButtonDialog:new({
        rows_per_page = 8,
        buttons = many_rows,
      })

      assert.truthy(dialog.cropping_widget)
    end)

    it("should update title with setTitle", function()
      local dialog = ButtonDialog:new({
        title = "Original Title",
        buttons = { { { text = "Btn", id = "btn" } } },
      })

      dialog:setTitle("Updated Title")
      assert.are.equal("Updated Title", dialog.title)
    end)
  end)

  describe("lifecycle, tap close, and focus", function()
    it("should handle onShow and onClose tracking active instances", function()
      local dialog = ButtonDialog:new({
        buttons = { { { text = "Btn", id = "btn" } } },
      })

      dialog:onShow()
      dialog:onClose()
    end)

    it("should handle onExit and tap_close_callback", function()
      local tap_closed = false
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local dialog = ButtonDialog:new({
        buttons = { { { text = "Btn", id = "btn" } } },
        tap_close_callback = function()
          tap_closed = true
        end,
      })

      assert.is_true(dialog:onExit())
      assert.is_true(tap_closed)
      assert.is_true(closed)
    end)

    it("should handle onTapClose dismissing when tapped outside and ignoring inside", function()
      local Geom = require("ui/geometry")
      local closed = false
      UIManager.close = function(_, widget)
        closed = true
      end

      local dialog = ButtonDialog:new({
        buttons = { { { text = "Btn", id = "btn" } } },
      })
      dialog.movable.dimen = Geom:new({ x = 100, y = 100, w = 200, h = 200 })

      -- Tap inside
      local inside_ev = { pos = Geom:new({ x = 150, y = 150, w = 1, h = 1 }) }
      assert.is_true(dialog:onTapClose(nil, inside_ev))
      assert.is_false(closed)

      -- Tap outside
      local outside_ev = { pos = Geom:new({ x = 10, y = 10, w = 1, h = 1 }) }
      assert.is_true(dialog:onTapClose(nil, outside_ev))
      assert.is_true(closed)
    end)

    it("should handle onFocusMove with and without cropping_widget", function()
      local dialog_plain = ButtonDialog:new({
        buttons = { { { text = "Btn", id = "btn" } } },
      })
      dialog_plain:onFocusMove({ direction = "south" })

      local many_rows = {}
      for i = 1, 20 do
        table.insert(many_rows, {
          { text = "Row " .. i, id = "row" .. i },
        })
      end
      local dialog_scroll = ButtonDialog:new({
        buttons = many_rows,
      })
      dialog_scroll:onFocusMove({ direction = "south" })
    end)
  end)
end)
