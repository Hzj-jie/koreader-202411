describe("ReaderPageMap module", function()
  local ReaderPageMap

  setup(function()
    require("commonrequire")
    ReaderPageMap = require("apps/reader/modules/readerpagemap")
  end)

  it("should initialize and register view module via self.ui.view", function()
    local registered_menu = false
    local registered_view = false

    local mock_ui = {
      menu = {
        registerToMainMenu = function()
          registered_menu = true
        end,
      },
      view = {
        registerViewModule = function(_self_view, _name, _module)
          registered_view = true
        end,
      },
      document = {
        info = { has_pages = false },
        hasPageMap = function()
          return true
        end,
      },
    }

    local pagemap = ReaderPageMap:new({
      ui = mock_ui,
    })

    assert.is_not_nil(pagemap)
    pagemap:_postInit()
    assert.is_true(registered_menu)
    assert.is_true(registered_view)
  end)
end)

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
  end)
end)
