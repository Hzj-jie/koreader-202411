describe("SortWidget widget", function()
  local SortWidget, UIManager, BD, Geom, Device

  local function showWidget(w)
    w._window = { x = 0, y = 0, widget = w }
    w.window = function(self)
      return self._window
    end
    UIManager:show(w)
    return w
  end

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    UIManager = require("ui/uimanager")
    BD = require("ui/bidi")
    Geom = require("ui/geometry")
    Device = require("device")
    SortWidget = require("ui/widget/sortwidget")
  end)

  after_each(function()
    UIManager._window_stack = {}
  end)

  local function createMockItems(count)
    local items = {}
    for i = 1, count do
      table.insert(items, {
        text = string.format("Item %02d", i),
        index = i,
      })
    end
    return items
  end

  it("should handle item selection, checkmarks, hold callbacks, and moveItem", function()
    local checked_state = false
    local callback_called = false
    local hold_called = false

    local items = {
      {
        text = "Item 1",
        checked_func = function() return checked_state end,
        callback = function() callback_called = true end,
      },
      {
        text = "Item 2",
        hold_callback = function(self, refresh) hold_called = true; refresh() end,
      },
      {
        text = "Item 3",
        callback = function() callback_called = true end,
      },
    }

    local widget = showWidget(SortWidget:new({
      title = "Test Sort",
      item_table = items,
      width = 400,
      height = 600,
    }))

    local item1 = widget.main_content[2]
    local item2 = widget.main_content[4]

    -- 1. Tap on checkmark area triggers item callback
    local checkmark_pos = item1.checkmark_widget.dimen:findCenter()
    item1:onTap({}, { pos = checkmark_pos })
    assert.is_true(callback_called)

    -- 2. Tap on item body marks item
    callback_called = false
    item1:onTap({}, { pos = Geom:new({ x = 300, y = item1.dimen.y + 10 }) })
    assert.are_equal(1, widget.marked)

    -- 3. Tap on marked item unmarks it
    item1:onTap({}, { pos = Geom:new({ x = 300, y = item1.dimen.y + 10 }) })
    assert.are_equal(0, widget.marked)

    -- 4. Hold callback on item2
    item2:onHold()
    assert.is_true(hold_called)

    -- 5. Hold on item3 (fallback to callback)
    local item3 = widget.main_content[6]
    item3:onHold()
    assert.is_true(callback_called)

    -- 6. Move item down and up
    widget.marked = 1
    widget:moveItem(1)
    assert.are_equal(2, widget.marked)
    assert.are_equal("Item 1", widget.item_table[2].text)

    widget:moveItem(-1)
    assert.are_equal(1, widget.marked)
    assert.are_equal("Item 1", widget.item_table[1].text)

    -- 7. Invalid move bounds
    widget:moveItem(-5)
    assert.are_equal(1, widget.marked)
  end)

  it("should handle pagination, page button hold input, and marked page jumps", function()
    local items = createMockItems(25)
    local widget = showWidget(SortWidget:new({
      title = "Paged Sort",
      item_table = items,
      width = 400,
      height = 400,
    }))

    assert.is_true(widget.pages > 1)

    -- nextPage / prevPage without marked item
    widget:nextPage()
    assert.are_equal(2, widget.show_page)
    widget:prevPage()
    assert.are_equal(1, widget.show_page)

    -- nextPage with marked item moves item to first on next page
    widget.marked = 1
    widget:nextPage()
    assert.are_equal(2, widget.show_page)
    assert.is_true(widget.marked > 1)

    -- prevPage with marked item
    widget:prevPage()
    assert.are_equal(1, widget.show_page)
    assert.are_equal(1, widget.marked)

    -- footer_page input callback
    widget.footer_page.hold_input.callback("2")
    assert.are_equal(2, widget.show_page)
    widget.footer_page.hold_input.callback("999") -- out of bounds ignored
    assert.are_equal(2, widget.show_page)
    assert.is_string(widget.footer_page.hold_input.hint_func())

    -- footer first/last buttons
    widget.marked = 0
    widget.footer_last_down.callback()
    assert.are_equal(widget.pages, widget.show_page)
    widget.footer_first_up.callback()
    assert.are_equal(1, widget.show_page)
  end)

  it("should handle sorting dialog options and auto-sorting", function()
    local items = {
      { text = "Banana" },
      { text = "Apple" },
      { text = "Cherry" },
    }
    local widget = showWidget(SortWidget:new({
      title = "Menu Sort",
      item_table = items,
      width = 400,
      height = 600,
    }))

    -- onShowWidgetMenu
    local menu_shown = false
    widget.showWidget = function(self, d)
      menu_shown = true
      -- Test callbacks of the 4 menu buttons
      d.buttons[1][1].callback() -- Sort A to Z
      assert.are_equal("Apple", widget.item_table[1].text)

      d.buttons[2][1].callback() -- Sort Z to A
      assert.are_equal("Cherry", widget.item_table[1].text)

      d.buttons[3][1].callback() -- Sort A to Z (natural)
      assert.are_equal("Apple", widget.item_table[1].text)

      d.buttons[4][1].callback() -- Sort Z to A (natural)
      assert.are_equal("Cherry", widget.item_table[1].text)
    end

    widget:onShowWidgetMenu()
    assert.is_true(menu_shown)
  end)

  it("should handle onCancel, onReturn, onExit, and sort_disabled mode", function()
    local returned = false
    local items = {
      { text = "First" },
      { text = "Second" },
    }
    local widget = showWidget(SortWidget:new({
      title = "Exit Sort",
      item_table = items,
      callback = function() returned = true end,
      width = 400,
      height = 600,
    }))

    -- Move item and cancel
    widget.marked = 1
    widget:moveItem(1)
    assert.are_equal("Second", widget.item_table[1].text)
    widget:onCancel()
    assert.are_equal("First", widget.item_table[1].text)
    assert.are_equal(0, widget.marked)

    -- onReturn when not marked (calls callback and onExit)
    widget:onReturn()
    assert.is_true(returned)

    -- onReturn when marked
    returned = false
    widget.marked = 1
    widget:onReturn()
    assert.is_true(returned)
    assert.are_equal(0, widget.marked)

    -- sort_disabled mode
    local disabled_item_called = false
    local widget_disabled = showWidget(SortWidget:new({
      title = "Disabled Sort",
      sort_disabled = true,
      item_table = {
        {
          text = "Disabled Item",
          callback = function() disabled_item_called = true end,
        },
      },
      width = 400,
      height = 600,
    }))

    local dis_item = widget_disabled.main_content[2]
    dis_item:onTap({}, { pos = Geom:new({ x = 100, y = 100 }) })
    assert.is_true(disabled_item_called)
  end)

  it("should handle swipe gestures in all directions", function()
    local items = createMockItems(20)
    local widget = showWidget(SortWidget:new({
      title = "Swipe Sort",
      item_table = items,
      width = 400,
      height = 400,
    }))

    -- West swipe -> next page
    widget:onSwipe(nil, { direction = "west" })
    assert.are_equal(2, widget.show_page)

    -- East swipe -> prev page
    widget:onSwipe(nil, { direction = "east" })
    assert.are_equal(1, widget.show_page)

    -- North swipe -> noop
    widget:onSwipe(nil, { direction = "north" })

    -- Diagonal swipe -> full refresh and return false
    assert.is_false(widget:onSwipe(nil, { direction = "northeast" }))

    -- South swipe -> onExit
    local exit_called = false
    widget.onExit = function() exit_called = true end
    widget:onSwipe(nil, { direction = "south" })
    assert.is_true(exit_called)
  end)
end)
