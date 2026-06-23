local spy = require("luassert.spy")
local mock = require("luassert.mock")

describe("TouchMenu", function()
  local TouchMenu
  local InfoMessage
  local UIManager

  setup(function()
    require("commonrequire")
    TouchMenu = require("ui/widget/touchmenu")
    InfoMessage = require("ui/widget/infomessage")
    UIManager = require("ui/uimanager")
  end)

  before_each(function()
    spy.on(UIManager, "show")
  end)

  after_each(function()
    if UIManager.show.revert then
      UIManager.show:revert()
    end
  end)

  it("shows help text on menu item hold", function()
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Test Tab",
          icon = "dummy",
          { text = "Item 1", help_text = "Help for Item 1" }
        }
      }
    })

    local item = { text = "Item 1", help_text = "Help for Item 1" }
    menu:onMenuHold(item)

    assert.spy(UIManager.show).was.called(1)
    local arg = UIManager.show.calls[1].refs[2]
    assert.is_not_nil(arg)
    assert.equal("Help for Item 1", arg.text)

    UIManager:close(arg)
  end)

  it("evaluates help_text_func if help_text is not a string", function()
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Test Tab",
          icon = "dummy",
          { text = "Item 2" }
        }
      }
    })

    local help_called = false
    local item = {
      text = "Item 2",
      help_text_func = function()
        help_called = true
        return "Dynamic Help"
      end
    }

    menu:onMenuHold(item)

    assert.is_true(help_called)
    assert.spy(UIManager.show).was.called(1)
    local arg = UIManager.show.calls[1].refs[2]
    assert.equal("Dynamic Help", arg.text)

    UIManager:close(arg)
  end)

  it("shows menu text as fallback if text is truncated and no help text is present", function()
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Test Tab",
          icon = "dummy",
          { text = "Item 3" }
        }
      }
    })

    local item = { text = "Item 3" }
    -- call with text_truncated = true
    menu:onMenuHold(item, true)

    assert.spy(UIManager.show).was.called(1)
    local arg = UIManager.show.calls[1].refs[2]
    assert.equal("Item 3", arg.text)

    UIManager:close(arg)
  end)

  it("does nothing if no help text and text is not truncated", function()
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Test Tab",
          icon = "dummy",
          { text = "Item 4" }
        }
      }
    })

    local item = { text = "Item 4" }
    menu:onMenuHold(item, false)

    assert.spy(UIManager.show).was.not_called()
  end)
end)
