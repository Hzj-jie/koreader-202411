describe("ReaderPageMap module", function()
  local ReaderPageMap, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    ReaderPageMap = require("apps/reader/modules/readerpagemap")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
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
      assert.is.same("1", pagemap:getFirstPageLabel(true))
      assert.is.same("2", pagemap:getLastPageLabel(true))
      assert.is.same("1", pagemap:getXPointerPageLabel("/1", true))
      assert.is.same(1, pagemap:getRenderedPageNumber("1", true))

      -- Test onSetPageMargins
      pagemap:onSetPageMargins({ 15, 10, 15, 10 })

      -- Test addToMainMenu
      local menu_items = {}
      pagemap:addToMainMenu(menu_items)
      assert.truthy(menu_items.page_map)
      for _, item in ipairs(menu_items.page_map.sub_item_table) do
        if item.callback then
          item.callback()
        end
        if item.hold_callback then
          item.hold_callback()
        end
      end

      -- Test onShowPageList
      pagemap:onShowPageList()

      readerui:onExit()
      readerui:onClose()
    end)
  end)
end)
