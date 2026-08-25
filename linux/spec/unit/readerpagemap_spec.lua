describe("ReaderPageMap module", function()
  local ReaderPageMap, DocumentRegistry, ReaderUI, Screen, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    ReaderPageMap = require("apps/reader/modules/readerpagemap")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
  end)

  it("should initialize pagemap module and handle layout reset", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local pagemap = readerui.pagemap
    assert.is_table(pagemap)

    pagemap:resetLayout()

    readerui:onExit()
    readerui:onClose()
  end)

  describe("Settings and Toggles", function()
    it(
      "should handle reading settings and check pagemap availability",
      function()
        local mock_ui = {
          document = {
            configurable = { h_page_margins = { 10, 10 } },
            hasPageMap = function()
              return false
            end,
            info = { has_pages = false },
          },
          menu = { registerToMainMenu = function() end },
          view = { registerViewModule = function() end },
          doc_settings = {
            has = function()
              return false
            end,
            isTrue = function()
              return false
            end,
            save = function() end,
          },
        }
        local pagemap = ReaderPageMap:new({ ui = mock_ui })
        pagemap:init()

        pagemap:onReadSettings(mock_ui.doc_settings)
        assert.is_boolean(pagemap.has_pagemap)
      end
    )

    it("should test cleanPageLabel, label getters, and menu actions", function()
      local sample_epub = "spec/front/unit/data/leaves.epub"
      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      local pagemap = readerui.pagemap
      pagemap.has_pagemap = true

      assert.is.same("123", pagemap:cleanPageLabel("Page 123"))
      assert.is.same("iv", pagemap:cleanPageLabel("page iv"))

      pagemap.use_page_labels = true
      assert.is_true(pagemap:wantsPageLabels())

      -- Mock document pagemap methods for testing getters
      readerui.document.getPageMapCurrentPageLabel = function()
        return "Page 1", 1, 2
      end
      readerui.document.getPageMapFirstPageLabel = function()
        return "Page 1"
      end
      readerui.document.getPageMapLastPageLabel = function()
        return "Page 2"
      end
      readerui.document.getPageMapXPointerPageLabel = function()
        return "Page 1"
      end
      readerui.document.getPageMapSource = function()
        return "First Edition 1920"
      end
      readerui.document.getPageMap = function()
        return {
          { label = "Page 1", page = 1, xpointer = "/1" },
          { label = "Page 2", page = 2, xpointer = "/2" },
        }
      end

      assert.is.same("1", pagemap:getCurrentPageLabel(true))
      assert.is.same("Page 1", pagemap:getCurrentPageLabel(false))
      assert.is.same("1", pagemap:getFirstPageLabel(true))
      assert.is.same("Page 1", pagemap:getFirstPageLabel(false))
      assert.is.same("2", pagemap:getLastPageLabel(true))
      assert.is.same("Page 2", pagemap:getLastPageLabel(false))
      assert.is.same("1", pagemap:getXPointerPageLabel("/1", true))
      assert.is.same("Page 1", pagemap:getXPointerPageLabel("/1", false))
      assert.is.same(1, pagemap:getRenderedPageNumber("1", true))
      assert.is.same(2, pagemap:getRenderedPageNumber("Page 2", false))
      assert.is_nil(pagemap:getRenderedPageNumber("999", true))

      -- Test onSetPageMargins
      pagemap:onSetPageMargins({ 15, 10, 15, 10 })

      -- Test updateVisibleLabels in various configurations
      pagemap.show_page_labels = true
      pagemap.initialized = true
      pagemap.has_pagemap = true
      pagemap:resetLayout()

      readerui.document.getPageMapVisiblePageLabels = function()
        return {
          { label = "Page 1", screen_page = 1, screen_y = 50 },
          { label = "Page 2", screen_page = 1, screen_y = 60 }, -- consecutive overlap
          { label = "Page 3", screen_page = 2, screen_y = 700 }, -- near bottom
        }
      end
      readerui.document.getVisiblePageCount = function() return 2 end
      readerui.view.footer_visible = true
      readerui.view.footer.settings.reclaim_height = false
      pagemap:updateVisibleLabels()

      -- Test events triggering updateVisibleLabels
      pagemap:onPageUpdate()
      pagemap:onPosUpdate()
      pagemap:onChangeViewMode()
      pagemap:onSetStatusLine()

      -- Test addToMainMenu
      local menu_items = {}
      pagemap:addToMainMenu(menu_items)
      assert.truthy(menu_items.page_map)
      local mock_menu = { updateItems = function() end }
      for _, item in ipairs(menu_items.page_map.sub_item_table) do
        if item.text_func then item:text_func() end
        if item.enabled_func then item:enabled_func() end
        if item.checked_func then item:checked_func() end
        if item.callback then
          item.callback(mock_menu)
          local top = UIManager:getTopmostVisibleWidget()
          if top and top.ok_callback then
            top.ok_callback()
          end
          if top and top.callback then
            top.callback({ value = 12 })
          end
          UIManager:close(top)
        end
        if item.hold_callback then
          item.hold_callback(mock_menu)
          local confirm = UIManager:getTopmostVisibleWidget()
          if confirm and confirm.choice1_callback then
            confirm.choice1_callback()
          end
          if confirm and confirm.choice2_callback then
            confirm.choice2_callback()
          end
          UIManager:close(confirm)
        end
      end

      -- Test onShowPageList
      pagemap:onShowPageList()
      local list_container = pagemap.pagelist_menu
      assert.is_not_nil(list_container)
      local pl_menu = list_container[1]
      if pl_menu and pl_menu.onMenuChoice then
        pl_menu:onMenuChoice({ xpointer = "/1", page = 1 })
      end
      if pagemap.refresh then
        pagemap.refresh()
      end
      if pl_menu and pl_menu.close_callback then
        pl_menu.close_callback()
      end

      -- Test _postInit when has_pages is true or hasPageMap is false
      readerui.document.info.has_pages = true
      pagemap:_postInit()
      readerui.document.info.has_pages = false
      readerui.document.hasPageMap = function() return false end
      pagemap:_postInit()

      readerui:onExit()
      readerui:onClose()
    end)
  end)
end)
