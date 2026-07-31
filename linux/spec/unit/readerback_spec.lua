describe("ReaderBack module", function()
  local ReaderBack, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderBack = require("apps/reader/modules/readerback")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize back navigation module and reset location stack", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readerback = readerui.back or ReaderBack:new({ ui = readerui })
    assert.is_table(readerback)

    readerback:onReadSettings()
    assert.is_table(readerback.location_stack)
    assert.are.equal(0, #readerback.location_stack)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should compare locations for scrollable and paged documents", function()
    local mock_ui_scroll = {
      document = { info = { has_pages = false } },
      key_events = {},
    }
    local back_scroll = ReaderBack:new({ ui = mock_ui_scroll })
    assert.is_true(back_scroll:_areLocationsSimilar({ xpointer = "p1" }, { xpointer = "p1" }))
    assert.is_false(back_scroll:_areLocationsSimilar({ xpointer = "p1" }, { xpointer = "p2" }))
  end)

  it("should handle back navigation actions when stack has history", function()
    local mock_ui = {
      document = { info = { has_pages = true } },
      paging = { getBookLocation = function() return { { page = 1 } } end },
      link = { onGoBackLink = function() return true end },
      handleEvent = function() end,
      showWidget = function() end,
      key_events = {},
    }

    local readerback = ReaderBack:new({ ui = mock_ui })
    readerback:onReadSettings()

    table.insert(readerback.location_stack, { { page = 1 } })
    assert.is_true(readerback:onBack())
  end)
end)
