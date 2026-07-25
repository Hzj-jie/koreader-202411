describe("FootnoteWidget module", function()
  local FootnoteWidget, UIManager

  setup(function()
    require("commonrequire")
    FootnoteWidget = require("ui/widget/footnotewidget")
    UIManager = require("ui/uimanager")
  end)

  it(
    "should initialize with correct sizes and handle callbacks on exit and follow",
    function()
      local close_called = false
      local follow_called = false

      local footnote = FootnoteWidget:new({
        html = "<html><body><p>Test footnote content</p></body></html>",
        close_callback = function(h)
          close_called = true
        end,
        follow_callback = function()
          follow_called = true
        end,
      })

      assert.is_not_nil(footnote)
      local size = footnote:getSize()
      assert.is_not_nil(size)
      assert.is_true(size.w > 0)
      assert.is_true(size.h > 0)

      -- Test onFollow callback
      footnote:onFollow()
      assert.is_true(follow_called)
      assert.is_true(close_called)

      -- Test onExit callback
      close_called = false
      footnote:onExit()
      assert.is_true(close_called)
    end
  )
end)
