describe("Menu widget", function()
  local Menu, Blitbuffer, Geom

  setup(function()
    require("commonrequire")
    Menu = require("ui/widget/menu")
    Blitbuffer = require("ffi/blitbuffer")
    Geom = require("ui/geometry")
  end)

  describe("Static helper functions", function()
    it("should calculate item font size correctly based on perpage", function()
      assert.are.equal(24, Menu.getItemFontSize(6))
      assert.are.equal(19, Menu.getItemFontSize(14))
      assert.are.equal(14, Menu.getItemFontSize(24))
    end)

    it("should format menu text correctly", function()
      -- Plain text item
      local item1 = { text = "Option 1" }
      assert.are.equal("Option 1", Menu.getMenuText(item1))

      -- Text func item
      local item2 = {
        text_func = function()
          return "Dynamic Option"
        end,
      }
      assert.are.equal("Dynamic Option", Menu.getMenuText(item2))

      -- Item with submenu
      local item3 = { text = "Submenu", sub_item_table = {} }
      local formatted3 = Menu.getMenuText(item3)
      assert.is_not_nil(formatted3:find("Submenu"))
      assert.is_true(#formatted3 > #"Submenu")

      -- Item with sub_item_table_func
      local item4 = {
        text = "Submenu Func",
        sub_item_table_func = function()
          return {}
        end,
      }
      local formatted4 = Menu.getMenuText(item4)
      assert.is_not_nil(formatted4:find("Submenu Func"))
    end)

    it("should convert touch menu table into item array properly", function()
      local cb1 = function() end
      local cb2 = function() end
      local result = Menu.itemTableFromTouchMenu({
        navi = {
          icon = "foo/bar.png",
          { text = "foo", callback = cb1 },
          { text = "bar", callback = cb2 },
        },
        exit = {
          icon = "foo/bar2.png",
          callback = cb2,
        },
      })

      assert.are.equal(2, #result)
      local exit_item, navi_item
      for _, item in ipairs(result) do
        if item.text == "exit" then
          exit_item = item
        elseif item.text == "navi" then
          navi_item = item
        end
      end

      assert.is_not_nil(exit_item)
      assert.are.equal(cb2, exit_item.callback)
      assert.is_nil(exit_item.sub_item_table)

      assert.is_not_nil(navi_item)
      assert.is_nil(navi_item.callback)
      assert.is_not_nil(navi_item.sub_item_table)
      assert.are.equal("foo/bar.png", navi_item.sub_item_table.icon)
    end)
  end)

  describe("Menu instantiation and layout", function()
    it("should instantiate with default settings", function()
      local m = Menu:new({
        title = "Test Menu",
        item_table = {
          { text = "Item 1" },
          { text = "Item 2" },
        },
      })

      assert.is_true(m.modal)
      assert.are.equal("Test Menu", m.title)
      assert.are.equal(1, m.page)
      assert.are.equal(1, m.page_num)
      assert.is_not_nil(m.title_bar)
      assert.are.equal(2, #m.item_table)
      assert.are.equal(1, m:getFirstVisibleItemIndex())
    end)

    it("should handle no_title and borderless/popout configurations", function()
      local m = Menu:new({
        no_title = true,
        is_borderless = true,
        is_popout = false,
        width = 400,
        height = 300,
        item_table = { { text = "Item A" } },
      })

      assert.is_nil(m.title_bar)
      assert.are.equal(0, m.border_size)
      assert.are.equal(400, m.dimen.w)
      assert.are.equal(300, m.dimen.h)
    end)

    it(
      "should handle custom title bar and title bar left icon callbacks",
      function()
        local left_tapped = false
        local left_held = false
        local m = Menu:new({
          title = "Menu Title",
          subtitle = "Subtitle",
          title_bar_left_icon = "back",
          onLeftButtonTap = function()
            left_tapped = true
          end,
          onLeftButtonHold = function()
            left_held = true
          end,
          item_table = { { text = "Entry" } },
        })

        assert.is_not_nil(m.title_bar)
        m:onLeftButtonTap()
        assert.is_true(left_tapped)
        m:onLeftButtonHold()
        assert.is_true(left_held)

        m:setTitleBarLeftIcon("home")
      end
    )
  end)

  describe("Page calculation and navigation", function()
    local function createMultiPageMenu(total_items, per_page)
      local items = {}
      for i = 1, total_items do
        table.insert(items, { text = "Item " .. i, val = i })
      end
      return Menu:new({
        title = "Paging Test",
        items_per_page = per_page or 5,
        item_table = items,
      })
    end

    it("should calculate page numbers correctly", function()
      local m = createMultiPageMenu(12, 5)
      assert.are.equal(3, m.page_num)
      assert.are.equal(1, m:getPageNumber(1))
      assert.are.equal(1, m:getPageNumber(5))
      assert.are.equal(2, m:getPageNumber(6))
      assert.are.equal(3, m:getPageNumber(12))
      assert.are.equal(1, m:getPageNumber(0))
    end)

    it("should navigate pages (next, prev, first, last, goto)", function()
      local m = createMultiPageMenu(15, 5) -- 3 pages
      assert.are.equal(1, m.page)

      m:onNextPage()
      assert.are.equal(2, m.page)
      assert.are.equal(6, m:getFirstVisibleItemIndex())

      m:onNextPage()
      assert.are.equal(3, m.page)
      assert.are.equal(11, m:getFirstVisibleItemIndex())

      -- Next page wraps around
      m:onNextPage()
      assert.are.equal(1, m.page)

      m:onPrevPage()
      assert.are.equal(3, m.page)

      m:onFirstPage()
      assert.are.equal(1, m.page)

      m:onLastPage()
      assert.are.equal(3, m.page)

      m:onGotoPage(2)
      assert.are.equal(2, m.page)
    end)

    it("should update page info when empty or full", function()
      local m_empty = Menu:new({
        title = "Empty",
        item_table = {},
      })
      assert.are.equal(1, m_empty.page_num)

      local m_full = createMultiPageMenu(10, 5)
      m_full:updatePageInfo()
      assert.are.equal(2, m_full.page_num)
    end)

    it("should support setupItemHeights with items_max_lines", function()
      local items = {}
      for i = 1, 10 do
        table.insert(
          items,
          { text = "Long multiline item text " .. i, mandatory = "Tag " .. i }
        )
      end
      local m = Menu:new({
        title = "Flexible height",
        items_max_lines = 2,
        item_table = items,
      })
      assert.is_not_nil(m.page_items)
      assert.is_true(#m.page_items > 0)
    end)
  end)

  describe("Submenu switching and menu selection", function()
    it("should switch item tables correctly", function()
      local m = Menu:new({
        title = "Initial Title",
        item_table = {
          { text = "A", id = 1 },
          { text = "B", id = 2 },
        },
      })

      local new_table = {
        { text = "C", id = 3 },
        { text = "D", id = 4 },
      }
      m:switchItemTable("New Title", new_table)
      assert.are.equal("New Title", m.title_bar.title_widget.text)
      assert.are.equal(2, #m.item_table)
      assert.are.equal(3, m.item_table[1].id)

      -- Switch with itemmatch
      m:switchItemTable(nil, new_table, nil, { id = 4 })
      assert.are.equal(1, m.page)
    end)

    it(
      "should handle onMenuSelect for callbacks, disabled items, and submenus",
      function()
        local callback_called = false
        local closed = false

        local sub_table = {
          {
            text = "Sub Item 1",
            callback = function()
              callback_called = true
            end,
          },
        }

        local m
        m = Menu:new({
          title = "Root Menu",
          close_callback = function()
            closed = true
          end,
          item_table = {
            {
              text = "Disabled Item",
              select_enabled = false,
              callback = function() end,
            },
            {
              text = "Disabled Func Item",
              select_enabled_func = function()
                return false
              end,
              callback = function() end,
            },
            { text = "Submenu Item", sub_item_table = sub_table },
          },
        })

        -- Select disabled item
        m:onMenuSelect(m.item_table[1])
        assert.is_false(closed)

        -- Select disabled func item
        m:onMenuSelect(m.item_table[2])
        assert.is_false(closed)

        -- Select submenu item
        m:onMenuSelect(m.item_table[3])
        assert.are.equal(1, #m.item_table_stack)
        assert.are.equal("Submenu Item", m.title_bar.title_widget.text)
        assert.are.equal(1, #m.item_table)

        -- Select sub item
        m:onMenuSelect(m.item_table[1])
        assert.is_true(callback_called)
        assert.is_true(closed)

        -- Exit submenu
        m:onExit()
        assert.are.equal(0, #m.item_table_stack)
        assert.are.equal("Root Menu", m.title_bar.title_widget.text)
      end
    )
  end)

  describe("Event handling", function()
    it("should handle shortcut key selection", function()
      local selected_item = nil
      local m = Menu:new({
        title = "Shortcuts Test",
        items_per_page = 5,
        close_callback = function() end,
        onMenuChoice = function(self, item)
          selected_item = item
        end,
        item_table = {
          { text = "Item Q" },
          { text = "Item W" },
        },
      })

      -- Press 'Q' (shortcut for 1st item)
      local handled = m:onSelectByShortCut(nil, { key = "Q" })
      assert.is_true(handled)
      assert.is_not_nil(selected_item)
      assert.are.equal("Item Q", selected_item.text)

      -- Press invalid shortcut key
      local unhandled = m:onSelectByShortCut(nil, { key = "Z" })
      assert.is_false(unhandled)
    end)

    it("should handle swipe gestures", function()
      local m = Menu:new({
        title = "Swipe Test",
        items_per_page = 2,
        item_table = {
          { text = "1" },
          { text = "2" },
          { text = "3" },
          { text = "4" },
        },
      })

      m:onSwipe(nil, { direction = "west" })
      assert.are.equal(2, m.page)

      m:onSwipe(nil, { direction = "east" })
      assert.are.equal(1, m.page)

      local exited = false
      m._closeAllMenus = function()
        exited = true
      end
      m:onSwipe(nil, { direction = "south" })
      assert.is_true(exited)
    end)

    it("should handle pan (mousewheel) gestures", function()
      local m = Menu:new({
        title = "Pan Test",
        items_per_page = 2,
        item_table = {
          { text = "1" },
          { text = "2" },
          { text = "3" },
          { text = "4" },
        },
      })

      m:onPan(nil, { mousewheel_direction = true, direction = "north" })
      assert.are.equal(2, m.page)

      m:onPan(nil, { mousewheel_direction = true, direction = "south" })
      assert.are.equal(1, m.page)
    end)

    it("should handle tap outside popout menu to close", function()
      local closed = false
      local m = Menu:new({
        title = "Tap Close Test",
        is_popout = true,
        close_callback = function()
          closed = true
        end,
        item_table = { { text = "Entry" } },
      })

      -- Tap inside bounds
      m.dimen = Geom:new({ x = 50, y = 50, w = 100, h = 100 })
      m:onTapCloseAllMenus(nil, { pos = Geom:new({ x = 60, y = 60 }) })
      assert.is_false(closed)

      -- Tap outside bounds
      m:onTapCloseAllMenus(nil, { pos = Geom:new({ x = 10, y = 10 }) })
      assert.is_true(closed)
    end)

    it("should handle multiswipe and show goto dialog", function()
      local closed = false
      local m = Menu:new({
        title = "Misc Events",
        close_callback = function()
          closed = true
        end,
        item_table = { { text = "Entry" } },
      })

      m:onMultiSwipe()
      assert.is_true(closed)

      assert.is_true(m:onShowGotoDialog())
    end)

    it("should handle onScreenResize and onSetRotationMode", function()
      local recreated = false
      local rotation_set = false
      local m = Menu:new({
        title = "Resize Test",
        item_table = { { text = "Entry" } },
        _recreate_func = function()
          recreated = true
        end,
        _manager = {
          ui = {
            onSetRotationMode = function()
              rotation_set = true
            end,
          },
        },
      })

      m.perpage = nil
      m.font_size = nil
      m:onScreenResize()
      assert.are.equal(1, m.page)

      -- onSetRotationMode with target rotation different from current screen rotation
      local screen_rot = require("device").screen:getRotationMode()
      local new_rot = (screen_rot + 1) % 4
      m:onSetRotationMode(new_rot)
      assert.is_true(recreated)
      assert.is_true(rotation_set)
    end)
  end)

  describe("MenuItem details and state", function()
    it("should handle focus and unfocus state updates", function()
      local m = Menu:new({
        title = "MenuItem Focus Test",
        line_color = Blitbuffer.COLOR_GRAY,
        item_table = {
          { text = "Focus Item" },
        },
      })

      local item_widget = m.item_group[1]
      assert.is_not_nil(item_widget)

      item_widget:onFocus()
      assert.are.equal(
        Blitbuffer.COLOR_BLACK,
        item_widget._underline_container.color
      )

      item_widget:onUnfocus()
      assert.are.equal(
        Blitbuffer.COLOR_GRAY,
        item_widget._underline_container.color
      )
    end)

    it(
      "should render MenuItem options (single line, dots, baselines, mandatory, post_text)",
      function()
        local m = Menu:new({
          title = "MenuItem Render Options Test",
          single_line = true,
          align_baselines = true,
          with_dots = true,
          item_table = {
            {
              text = "Full item text",
              post_text = " (10p)",
              mandatory = "100 KB",
              mandatory_dim = true,
              bold = true,
              dim = true,
            },
          },
        })

        local item_widget = m.item_group[1]
        assert.is_not_nil(item_widget)
        assert.is_true(item_widget.single_line)
        assert.is_true(item_widget.with_dots)

        local dots_text, min_width =
          item_widget:getDotsText(item_widget.info_face)
        assert.is_not_nil(dots_text)
        assert.is_true(min_width > 0)
      end
    )

    it("should handle goto_letter and file search callbacks", function()
      local searched_file = nil
      local UIManager = require("ui/uimanager")
      local orig_broadcast = UIManager.broadcastEvent
      UIManager.broadcastEvent = function(_, ev)
        if ev and ev.name == "ShowFileSearch" then
          searched_file = ev.args[1]
        end
      end

      local items = {
        { text = "Alpha File", path = "/books/Alpha.epub" },
        { text = "Beta File", path = "/books/Beta.epub" },
        { text = "Gamma File", path = "/books/Gamma.epub" },
      }

      local m = Menu:new({
        title = "Letter Search",
        goto_letter = true,
        item_table = items,
      })

      local hold_input = m.page_info_text.hold_input
      assert.truthy(hold_input)
      assert.truthy(hold_input.buttons)

      -- File search button (row 1, button 1)
      m.page_info_text.input_dialog = {
        getInputText = function()
          return "query_test"
        end,
      }
      m.page_info_text.closeInputDialog = function() end

      local btn_file_search = hold_input.buttons[1][1]
      btn_file_search.callback()
      assert.are.equal("query_test", searched_file)

      -- Go to letter button (row 1, button 2)
      m.page_info_text.input_dialog = {
        getInputText = function()
          return "b"
        end,
      }
      local btn_goto_letter = hold_input.buttons[1][2]
      btn_goto_letter.callback()

      UIManager.broadcastEvent = orig_broadcast
    end)

    it("should handle chevron pagination callbacks and return arrow", function()
      local returned = false
      local hold_returned = false

      local items = {}
      for i = 1, 50 do
        table.insert(items, { text = "Item " .. i })
      end

      local m = Menu:new({
        title = "Pagination Menu",
        item_table = items,
        onReturn = function()
          returned = true
        end,
        onHoldReturn = function()
          hold_returned = true
        end,
      })

      assert.is_true(m.page_num > 1)

      -- Chevrons
      m.page_info_right_chev.callback()
      assert.are.equal(2, m.page)

      m.page_info_left_chev.callback()
      assert.are.equal(1, m.page)

      m.page_info_last_chev.callback()
      assert.are.equal(m.page_num, m.page)

      m.page_info_first_chev.callback()
      assert.are.equal(1, m.page)

      -- Return arrow
      m.page_return_arrow.callback()
      assert.is_true(returned)

      m.page_return_arrow.hold_callback()
      assert.is_true(hold_returned)
    end)

    it("should handle MenuItem onSelect and onHoldSelect", function()
      local selected_entry = nil
      local held_entry = nil

      local m = Menu:new({
        title = "Select Test",
        item_table = {
          { text = "Clickable Item", value = 42 },
        },
      })

      m.onMenuSelect = function(self, entry, pos)
        selected_entry = entry
      end
      m.onMenuHold = function(self, entry, pos)
        held_entry = entry
      end

      local item_widget = m.item_group[1]
      item_widget[1].dimen = Geom:new({ x = 0, y = 0, w = 100, h = 30 })

      item_widget:onSelect(nil, { pos = Geom:new({ x = 10, y = 10 }) })
      assert.truthy(selected_entry)
      assert.are.equal(42, selected_entry.value)

      item_widget:onHoldSelect(nil, { pos = Geom:new({ x = 10, y = 10 }) })
      assert.truthy(held_entry)
      assert.are.equal(42, held_entry.value)
    end)

    it("should support switchItemTable and updateItems", function()
      local m = Menu:new({
        title = "Original Table",
        item_table = {
          { text = "Old 1" },
          { text = "Old 2" },
        },
      })

      local new_table = {
        { text = "New A" },
        { text = "New B" },
        { text = "New C" },
      }

      m:switchItemTable("New Title", new_table, 1)
      assert.are.equal("New Title", m.title)
      assert.are.equal(3, #m.item_table)

      m:updateItems(2)
      assert.truthy(m.item_group)
    end)

    it("should support FM titlebar style and left icon", function()
      local m = Menu:new({
        title = "FM Style Menu",
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        subtitle = "Path info",
        item_table = {
          { text = "File 1" },
        },
      })

      assert.truthy(m.title_bar)
      assert.is_true(m.title_bar_fm_style)
    end)
  end)
end)
