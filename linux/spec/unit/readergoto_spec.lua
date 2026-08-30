describe("ReaderGoto module", function()
  local ReaderGoto, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderGoto = require("apps/reader/modules/readergoto")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize goto page module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readergoto = readerui.readergoto or ReaderGoto:new({ ui = readerui })
    assert.is_table(readergoto)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle navigation to beginning, end, and random page", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local rgoto =
      ReaderGoto:new({ ui = readerui, document = readerui.document })
    assert.is_true(rgoto:onGoToBeginning())
    assert.is_true(rgoto:onGoToEnd())
    assert.is_true(rgoto:onGoToRandomPage())

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle goto dialog and percent/page jumps", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local rgoto =
      ReaderGoto:new({ ui = readerui, document = readerui.document })
    rgoto:onShowGotoDialog()
    assert.is_table(rgoto.goto_dialog)

    rgoto.goto_dialog.getInputValue = function()
      return 50
    end
    rgoto.goto_dialog.getInputText = function()
      return "3"
    end

    rgoto:gotoPercent()
    rgoto:gotoPage()

    readerui:onExit()
    readerui:onClose()
  end)
end)
