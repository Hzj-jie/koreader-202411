local spy = require("luassert.spy")

describe("TouchMenu", function()
  local TouchMenu
  local UIManager

  setup(function()
    require("commonrequire")
    TouchMenu = require("ui/widget/touchmenu")
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
          { text = "Item 1", help_text = "Help for Item 1" },
        },
      },
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
          { text = "Item 2" },
        },
      },
    })

    local help_called = false
    local item = {
      text = "Item 2",
      help_text_func = function()
        help_called = true
        return "Dynamic Help"
      end,
    }

    menu:onMenuHold(item)

    assert.is_true(help_called)
    assert.spy(UIManager.show).was.called(1)
    local arg = UIManager.show.calls[1].refs[2]
    assert.equal("Dynamic Help", arg.text)

    UIManager:close(arg)
  end)

  it(
    "shows menu text as fallback if text is truncated and no help text is present",
    function()
      local menu = TouchMenu:new({
        tab_item_table = {
          {
            text = "Test Tab",
            icon = "dummy",
            { text = "Item 3" },
          },
        },
      })

      local item = { text = "Item 3" }
      -- call with text_truncated = true
      menu:onMenuHold(item, true)

      assert.spy(UIManager.show).was.called(1)
      local arg = UIManager.show.calls[1].refs[2]
      assert.equal("Item 3", arg.text)

      UIManager:close(arg)
    end
  )

  it("does nothing if no help text and text is not truncated", function()
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Test Tab",
          icon = "dummy",
          { text = "Item 4" },
        },
      },
    })

    local item = { text = "Item 4" }
    menu:onMenuHold(item, false)

    assert.spy(UIManager.show).was.not_called()
  end)

  it("does not crash when an item has an integer key", function()
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Test Tab",
          icon = "dummy",
          {
            text = "Item 1",
            [1] = "some value",
          },
        },
      },
    })
    assert.is_not_nil(menu)
  end)

  it("handles submenu navigation and backToUpperMenu", function()
    local sub_item = { text = "Sub 1" }
    local root_item = {
      text = "Open Submenu",
      sub_item_table = {
        sub_item,
      },
    }
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Tab 1",
          icon = "dummy",
          root_item,
        },
      },
    })

    assert.are.equal(0, #menu.item_table_stack)
    menu:onMenuSelect(root_item)
    assert.are.equal(1, #menu.item_table_stack)
    assert.are.equal(sub_item, menu.item_table[1])

    -- Return to upper menu
    local returned = menu:backToUpperMenu()
    assert.is_true(returned)
    assert.are.equal(0, #menu.item_table_stack)
    assert.are.equal(root_item, menu.item_table[1])
  end)

  it("handles tab switching and pagination", function()
    local items_tab1 = {}
    for i = 1, 25 do
      table.insert(items_tab1, { text = "Tab1 Item " .. i })
    end
    local items_tab2 = {
      { text = "Tab2 Item 1" },
    }
    local tab_table = {
      items_tab1,
      items_tab2,
    }
    tab_table[1].icon = "icon1"
    tab_table[1].text = "Tab 1"
    tab_table[2].icon = "icon2"
    tab_table[2].text = "Tab 2"

    local menu = TouchMenu:new({
      tab_item_table = tab_table,
    })

    assert.are.equal(1, menu.cur_tab)
    assert.is_true(menu.page_num > 1)
    assert.are.equal(1, menu.page)

    -- Next page
    menu:onNextPage()
    assert.are.equal(2, menu.page)

    -- Prev page
    menu:onPrevPage()
    assert.are.equal(1, menu.page)

    -- Goto last and first page
    menu:onLastPage()
    assert.are.equal(menu.page_num, menu.page)
    menu:onFirstPage()
    assert.are.equal(1, menu.page)

    -- Switch tab
    menu:switchMenuTab(2)
    assert.are.equal(2, menu.cur_tab)
    assert.are.equal(1, menu.page)
  end)

  it("handles swipe gestures for page navigation and closing", function()
    local closed = false
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Tab 1",
          icon = "dummy",
          { text = "Item 1" },
        },
      },
      close_callback = function()
        closed = true
      end,
    })

    -- North swipe closes menu
    menu:onSwipe(nil, { direction = "north" })
    assert.is_true(closed)
  end)

  it("triggers item callback and checkmark_callback", function()
    local item_called = false
    local checkmark_called = false
    local item = {
      text = "Checkable Item",
      checked = false,
      callback = function()
        item_called = true
      end,
      checkmark_callback = function()
        checkmark_called = true
      end,
    }
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Tab 1",
          icon = "dummy",
          item,
        },
      },
    })

    menu:onMenuSelect(item, false)
    assert.is_true(item_called)

    menu:onMenuSelect(item, true)
    assert.is_true(checkmark_called)
  end)

  it("searches menu items recursively and opens a found item via openMenu", function()
    local sub_item = { text = "Target Sub Item" }
    local root_item = {
      text = "Parent Menu",
      sub_item_table = {
        sub_item,
      },
    }
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Tab 1",
          icon = "dummy",
          root_item,
        },
      },
    })

    local results = menu:search("target")
    assert.is_table(results)
    assert.are.equal(1, #results)
    assert.are.equal("Target Sub Item", results[1][1])
    local path = results[1][3]
    assert.are.equal("1.1.1", path)

    -- Open menu item path without animation
    assert.has_no.errors(function()
      menu:openMenu(path, false)
    end)
  end)

  it("handles onGotoPage and onTapCloseAllMenus", function()
    local Geom = require("ui/geometry")
    local closed = false
    local items = {}
    for i = 1, 30 do
      table.insert(items, { text = "Item " .. i })
    end
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Tab 1",
          icon = "dummy",
          unpack(items),
        },
      },
      close_callback = function()
        closed = true
      end,
    })

    -- Go to page 2
    menu:onGotoPage(2)
    assert.are.equal(2, menu.page)

    menu.dimen = Geom:new({ x = 0, y = 0, w = 600, h = 300 })
    -- Tap outside to close all menus
    menu:onTapCloseAllMenus(nil, { pos = Geom:new({ x = 0, y = 500, w = 1, h = 1 }) })
    assert.is_true(closed)
  end)

  it("handles custom tap_input and hold_input on items", function()
    local tapped_input
    local held_input
    local item = {
      text = "Input Item",
      tap_input = "CustomTap",
      hold_input = "CustomHold",
    }
    local menu = TouchMenu:new({
      tab_item_table = {
        {
          text = "Tab 1",
          icon = "dummy",
          item,
        },
      },
    })
    menu.onInput = function(self, input)
      if input == "CustomTap" then
        tapped_input = true
      elseif input == "CustomHold" then
        held_input = true
      end
    end

    local item_widget = menu.item_group[1]
    if item_widget and item_widget.onTap then
      item_widget:onTap()
      assert.is_true(tapped_input)
    end
    if item_widget and item_widget.onHold then
      item_widget:onHold()
      assert.is_true(held_input)
    end
  end)
end)
