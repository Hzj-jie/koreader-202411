describe("ReaderHandmade module", function()
  local ReaderHandmade, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderHandmade = require("apps/reader/modules/readerhandmade")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize handmade TOC module and read/save settings", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local handmade = readerui.handmade
    assert.is_table(handmade)

    handmade:onReadSettings(readerui.doc_settings)
    assert.is_boolean(handmade:isHandmadeTocEnabled())
    assert.is_boolean(handmade:isHandmadeTocEditEnabled())

    handmade:onSaveSettings()

    readerui:onExit()
    readerui:onClose()
  end)

  it("should manage custom TOC items", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      doc_settings = {
        isTrue = function()
          return false
        end,
        nilOrTrue = function()
          return true
        end,
        readTableRef = function()
          return {}
        end,
        save = function() end,
        delete = function() end,
      },
    }
    local handmade = ReaderHandmade:new({ ui = mock_ui })
    handmade:onReadSettings(mock_ui.doc_settings)

    assert.is_table(handmade.toc)
    table.insert(handmade.toc, { title = "Chapter 1", page = 5 })

    assert.are.equal(1, #handmade.toc)

    if handmade.clearHandmadeToc then
      handmade:clearHandmadeToc()
      assert.are.equal(0, #handmade.toc)
    end
  end)

  it("should manage hidden flows and calculate doc flows correctly", function()
    local mock_doc = {
      getPageCount = function()
        return 100
      end,
      getPageFromXPointer = function(_, xp)
        return 10
      end,
      compareXPointers = function(_, a, b)
        return a == b and 0 or 1
      end,
      getPageXPointer = function(_, p)
        return "/page/" .. p
      end,
    }
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      document = mock_doc,
      annotation = { setNeedsUpdateFlag = function() end },
      highlight = {
        addToHighlightDialog = function() end,
        removeFromHighlightDialog = function() end,
      },
      doc_settings = {
        isTrue = function()
          return false
        end,
        nilOrTrue = function()
          return true
        end,
        readTableRef = function()
          return {}
        end,
        save = function() end,
        delete = function() end,
      },
    }
    local handmade = ReaderHandmade:new({
      ui = mock_ui,
      document = mock_doc,
    })
    handmade:onReadSettings(mock_ui.doc_settings)

    assert.is_false(handmade:isInHiddenFlow(10))
    assert.is_false(handmade:isHandmadeHiddenFlowsEnabled())
    assert.is_true(handmade:isHandmadeHiddenFlowsEditEnabled())

    -- Toggle hidden flow at page 10
    handmade:toggleHiddenFlow(10)
    assert.are.equal(1, #handmade.flow_points)
    assert.is_true(handmade.flow_points[1].hidden)
    assert.are.equal(10, handmade.flow_points[1].page)
    assert.is_true(handmade:isInHiddenFlow(15))
    assert.is_false(handmade:isInHiddenFlow(5))

    -- Toggle end of hidden flow at page 20 (restart regular flow)
    handmade:toggleHiddenFlow(20)
    assert.are.equal(2, #handmade.flow_points)
    assert.is_false(handmade.flow_points[2].hidden)
    assert.is_true(handmade:isInHiddenFlow(15))
    assert.is_false(handmade:isInHiddenFlow(25))

    -- Setup flows and check document overridden methods
    handmade.flows_enabled = true
    handmade:setupFlows(true)
    assert.is_true(mock_doc:hasHiddenFlows())
    assert.are.equal(1, mock_doc:getPageFlow(15))
    assert.are.equal(0, mock_doc:getPageFlow(5))
    assert.are.equal(0, mock_doc:getPageFlow(25))
    assert.are.equal(10, mock_doc:getFirstPageInFlow(1))
    assert.are.equal(10, mock_doc:getTotalPagesInFlow(1)) -- 20 - 10 = 10 pages hidden
    assert.are.equal(1, mock_doc:getPageNumberInFlow(1))
    assert.are.equal(6, mock_doc:getPageNumberInFlow(15)) -- 15 - 10 + 1 = 6 in flow
    assert.are.equal(15, mock_doc:getPageNumberInFlow(25)) -- 25 - 10 hidden = 15

    -- Disable flows
    handmade.flows_enabled = false
    handmade:setupFlows(true)
    assert.is_nil(mock_doc.hasHiddenFlows)

    -- Toggle again at page 10 to remove it
    handmade:toggleHiddenFlow(10)
    assert.are.equal(1, #handmade.flow_points)
  end)

  it("should handle _getItemIndex and hasPageTocItem correctly", function()
    local mock_doc = {
      getPageFromXPointer = function(_, xp)
        return xp == "xp2" and 20 or 10
      end,
      compareXPointers = function(_, a, b)
        if a == b then
          return 0
        end
        return a > b and 1 or -1
      end,
    }
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      document = mock_doc,
      annotation = { setNeedsUpdateFlag = function() end },
      highlight = {
        addToHighlightDialog = function() end,
        removeFromHighlightDialog = function() end,
      },
    }
    local handmade = ReaderHandmade:new({
      ui = mock_ui,
      document = mock_doc,
    })
    handmade.toc = {
      { title = "Ch1", page = 5 },
      { title = "Ch2", page = 15, xpointer = "xp_b" },
      { title = "Ch3", page = 30 },
    }

    assert.is_true(handmade:hasPageTocItem(5))
    assert.is_false(handmade:hasPageTocItem(10))
    local idx, match = handmade:_getItemIndex(handmade.toc, 10)
    assert.are.equal(2, idx)
    assert.is_false(match)

    local idx2, match2 = handmade:_getItemIndex(handmade.toc, 15, "xp_b")
    assert.are.equal(2, idx2)
    assert.is_true(match2)

    local idx3, match3 = handmade:_getItemIndex(handmade.toc, 40)
    assert.are.equal(4, idx3)
    assert.is_false(match3)
  end)

  it("should handle setupToc and document getToc override", function()
    local mock_doc = {}
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      document = mock_doc,
      highlight = {
        addToHighlightDialog = function() end,
        removeFromHighlightDialog = function() end,
      },
    }
    local handmade = ReaderHandmade:new({
      ui = mock_ui,
      document = mock_doc,
    })
    handmade.toc = { { title = "Section 1", page = 1 } }
    handmade.toc_enabled = true
    handmade:setupToc(true)

    assert.is_function(mock_doc.getToc)
    local fetched_toc = mock_doc:getToc()
    assert.are.equal(1, #fetched_toc)
    assert.are.equal("Section 1", fetched_toc[1].title)

    handmade.toc_enabled = false
    handmade:setupToc(true)
    assert.is_nil(mock_doc.getToc)
  end)

  it("should handle onToggleHandmadeToc and onToggleHandmadeFlows", function()
    local mock_doc = {
      getPageCount = function()
        return 50
      end,
    }
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      document = mock_doc,
      annotation = { setNeedsUpdateFlag = function() end },
      highlight = {
        addToHighlightDialog = function() end,
        removeFromHighlightDialog = function() end,
      },
    }
    local handmade = ReaderHandmade:new({
      ui = mock_ui,
      document = mock_doc,
    })
    handmade.toc = {}
    handmade.flow_points = {}
    handmade.inactive_flow_points = {}
    handmade.toc_enabled = false
    handmade.flows_enabled = false

    handmade:onToggleHandmadeToc()
    assert.is_true(handmade.toc_enabled)

    handmade:onToggleHandmadeFlows()
    assert.is_true(handmade.flows_enabled)
  end)

  it("should handle main menu items and submenus", function()
    local mock_doc = {
      getPageCount = function()
        return 50
      end,
      getPageXPointer = function(_, p)
        return "/xp/" .. p
      end,
      getPageFromXPointer = function(_, xp)
        return 1
      end,
      compareXPointers = function()
        return 0
      end,
    }
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      document = mock_doc,
      annotation = { setNeedsUpdateFlag = function() end },
      highlight = {
        addToHighlightDialog = function() end,
        removeFromHighlightDialog = function() end,
      },
    }
    local handmade = ReaderHandmade:new({
      ui = mock_ui,
      document = mock_doc,
    })
    handmade.toc = { { title = "Ch1", page = 1 } }
    handmade.flow_points = { { page = 10, hidden = true } }
    handmade.inactive_flow_points = {}
    handmade.toc_enabled = true
    handmade.flows_enabled = true

    local shown_widgets = {}
    handmade.showWidget = function(self, w)
      table.insert(shown_widgets, w)
    end

    local menu_items = {}
    handmade:addToMainMenu(menu_items)
    assert.is_table(menu_items.handmade_toc)
    assert.is_table(menu_items.handmade_hidden_flows)
    assert.is_table(menu_items.handmade_settings)

    menu_items.handmade_toc.checked_func()
    menu_items.handmade_toc.callback()

    menu_items.handmade_hidden_flows.checked_func()
    menu_items.handmade_hidden_flows.callback()

    -- Test submenus
    local settings_sub = menu_items.handmade_settings.sub_item_table_func()
    assert.is_table(settings_sub)
    for _, item in ipairs(settings_sub) do
      if item.checked_func then
        pcall(item.checked_func)
      end
      if item.enabled_func then
        pcall(item.enabled_func)
      end
      if item.callback then
        pcall(item.callback, { updateItems = function() end })
      end
    end

    -- Trigger callbacks on shown widgets (ConfirmBox / InfoMessage)
    for _, w in ipairs(shown_widgets) do
      if w.ok_callback then
        pcall(w.ok_callback)
      end
    end
  end)

  it("should handle settings migrations between rolling and paging", function()
    local mock_doc = { getPageCount = function() return 10 end }
    local mock_ui_rolling = {
      rolling = true,
      menu = { registerToMainMenu = function() end },
      document = mock_doc,
      highlight = { addToHighlightDialog = function() end, removeFromHighlightDialog = function() end },
      annotation = { setNeedsUpdateFlag = function() end },
    }
    local handmade = ReaderHandmade:new({ ui = mock_ui_rolling, document = mock_doc })

    local data = {
      handmade_toc = { { title = "PagingItem", page = 2 } },
      handmade_flow_points = { { page = 2, hidden = true } },
      handmade_toc_rolling = { { title = "RollingItem", page = 2, xpointer = "/xp/2" } },
      handmade_flow_points_rolling = { { page = 2, xpointer = "/xp/2", hidden = true } },
    }
    local config = {
      read = function(self, k) return data[k] end,
      readTableRef = function(self, k) return data[k] end,
      save = function(self, k, v) data[k] = v end,
      delete = function(self, k) data[k] = nil end,
      isTrue = function() return false end,
      nilOrTrue = function() return true end,
    }

    handmade:onReadSettings(config)
    assert.is_not_nil(handmade.toc)
    assert.is_not_nil(handmade.flow_points)
  end)
end)

