local spy = require("luassert.spy")

describe("TextViewer", function()
  local TextViewer
  local UIManager
  local temp_file_small = "spec/unit/test_small.txt"
  local temp_file_large = "spec/unit/test_large.txt"

  setup(function()
    require("commonrequire")
    TextViewer = require("ui/widget/textviewer")
    UIManager = require("ui/uimanager")

    -- Create small file (10 bytes)
    local f = io.open(temp_file_small, "w")
    f:write("Small file")
    f:close()

    -- Create large file (> 400,000 bytes, e.g. 400,010 bytes)
    f = io.open(temp_file_large, "w")
    f:write(string.rep("A", 400010))
    f:close()
  end)

  teardown(function()
    os.remove(temp_file_small)
    os.remove(temp_file_large)
  end)

  it("opens small file directly", function()
    spy.on(UIManager, "show")

    TextViewer:openFile(temp_file_small)

    assert.spy(UIManager.show).was.called(1)
    local widget = UIManager.show.calls[1].refs[2]
    assert.is_not_nil(widget)
    assert.equal("Small file", widget.text)
    assert.equal(temp_file_small, widget.title)

    UIManager:close(widget)
    UIManager.show:revert()
  end)

  it("shows ConfirmBox for large file, and opens it after OK", function()
    spy.on(UIManager, "show")

    TextViewer:openFile(temp_file_large)

    -- Should show ConfirmBox first
    assert.spy(UIManager.show).was.called(1)
    local confirm_box = UIManager.show.calls[1].refs[2]
    assert.is_not_nil(confirm_box)

    -- We cannot easily check the class name, but we can check if it has ok_text and cancel_text
    assert.equal("Open", confirm_box.ok_text)

    -- Now trigger OK callback
    confirm_box.ok_callback()

    -- Should show TextViewer now (total 2 calls to UIManager.show)
    assert.spy(UIManager.show).was.called(2)
    local text_viewer = UIManager.show.calls[2].refs[2]
    assert.is_not_nil(text_viewer)
    assert.equal(temp_file_large, text_viewer.title)
    assert.equal(400010, #text_viewer.text)

    UIManager:close(confirm_box)
    UIManager:close(text_viewer)
    UIManager.show:revert()
  end)

  it(
    "should be placed above modal widgets in the UIManager window stack",
    function()
      local Widget = require("ui/widget/widget")
      local Geom = require("ui/geometry")
      local mock_modal = Widget:new({
        modal = true,
        dimen = Geom:new({ w = 100, h = 100 }),
      })
      local tv = TextViewer:new({ text = "test" })

      UIManager:show(mock_modal)
      UIManager:show(tv)

      local modal_idx, tv_idx
      for idx, win in ipairs(UIManager._window_stack) do
        if win.widget == mock_modal then
          modal_idx = idx
        elseif win.widget == tv then
          tv_idx = idx
        end
      end

      -- Clean up UIManager stack first
      UIManager:close(tv)
      UIManager:close(mock_modal)

      assert.is_true(
        tv_idx > modal_idx,
        "TextViewer should be above mock_modal in the stack"
      )
    end
  )

  it("handles gestures, search, menu, and text selection", function()
    local Geom = require("ui/geometry")
    local tv = TextViewer:new({
      text = "Line 1\nLine 2\nLine 3\nSearchTarget here\nLine 5",
      title = "Viewer Test",
    })

    UIManager:show(tv)
    UIManager:forceRepaint()

    -- Gestures
    tv:onTapClose(nil, { pos = Geom:new({ x = -100, y = -100 }) })
    tv:onSwipe(nil, { pos = tv.textw.dimen:copy(), direction = "west" })
    tv:onSwipe(nil, { pos = tv.textw.dimen:copy(), direction = "east" })
    tv:onMultiSwipe({})

    -- Forwarding
    tv:onHoldStartText(nil, { pos = tv.textw.dimen:copy() })
    tv:onHoldPanText(nil, { pos = tv.textw.dimen:copy() })
    tv:onHoldReleaseText(nil, { pos = tv.textw.dimen:copy() })
    tv:onForwardingTouch(nil, { pos = tv.textw.dimen:copy() })
    tv:onForwardingPan(nil, { pos = tv.textw.dimen:copy() })
    tv:onForwardingPanRelease(nil, { pos = tv.textw.dimen:copy() })

    -- Text Bold & Selection
    tv:setTextBold(1, 6)
    tv:handleTextSelection(nil, "Line", { 1, 4 }, { x = 50, y = 50 })

    -- Find Dialog & Search
    tv:findDialog()
    tv.search_value = "SearchTarget"
    tv:findCallback()

    -- Show Menu
    tv:onShowMenu()

    -- Register
    local mock_reg = {
      addAuxProvider = function(self, prov)
        if prov.enabled_func then prov.enabled_func("test.txt") end
      end,
      isTextFile = function() return true end,
    }
    tv:register(mock_reg)

    UIManager:close(tv)
  end)
end)

